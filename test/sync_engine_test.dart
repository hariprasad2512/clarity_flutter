import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/core/task_model.dart';
import 'package:clarity_flutter/sync/sync_engine.dart';
import 'package:clarity_flutter/sync/task_remote.dart';

/// In-memory stand-in for Supabase PostgREST.
class FakeRemote implements TaskRemote {
  final Map<String, Map<String, dynamic>> server = {};
  int upsertCalls = 0;
  int fetchCalls = 0;
  int deleteCalls = 0;
  final List<String> deletedIds = [];
  bool failNext = false;
  bool failDeleteNext = false;

  @override
  Future<List<Map<String, dynamic>>> upsert(
      List<Map<String, dynamic>> rows) async {
    upsertCalls++;
    if (failNext) {
      failNext = false;
      throw Exception('network down');
    }
    for (final r in rows) {
      server[r['id'] as String] = Map.of(r);
    }
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String userId) async {
    fetchCalls++;
    if (failNext) {
      failNext = false;
      throw Exception('network down');
    }
    final rows = server.values
        .where((r) => r['user_id'] == userId)
        .toList()
      ..sort((a, b) => (b['updated_at'] as String)
          .compareTo(a['updated_at'] as String));
    return rows;
  }

  @override
  Future<void> deleteByIds(Set<String> ids) async {
    deleteCalls++;
    if (failDeleteNext) {
      failDeleteNext = false;
      throw Exception('delete denied');
    }
    deletedIds.addAll(ids);
    for (final id in ids) {
      server.remove(id);
    }
  }
}

TodoTask _local(String id, String title,
    {bool pending = false, DateTime? updated}) {
  final now = updated ?? DateTime.now();
  return TodoTask(
    id: id,
    title: title,
    createdAt: now,
    updatedAt: now,
    needsSync: pending,
  );
}

void main() {
  group('SyncEngine (native SyncEngine parity)', () {
    late FakeRemote remote;
    late List<TodoTask> local;
    late List<List<TodoTask>> writes;
    late Set<String> outbox;
    late List<Set<String>> outboxWrites;
    late List<Set<String>> localDeletes;
    late SyncEngine engine;

    SyncEngine build({String? userId}) {
      return SyncEngine(
        remote: remote,
        readLocal: () async => local,
        writeLocal: (tasks) async {
          writes.add(tasks);
          final byId = {for (final t in tasks) t.id: t};
          local = [
            for (final t in local)
              if (byId.containsKey(t.id)) byId[t.id]! else t,
            for (final t in tasks)
              if (!local.any((l) => l.id == t.id)) t,
          ];
        },
        readUserId: () => userId,
        readPendingDeletes: () async => Set.of(outbox),
        writePendingDeletes: (ids) async {
          outboxWrites.add(Set.of(ids));
          outbox = Set.of(ids);
        },
        deleteLocal: (ids) async {
          localDeletes.add(Set.of(ids));
          local = local.where((t) => !ids.contains(t.id)).toList();
        },
      );
    }

    setUp(() {
      remote = FakeRemote();
      local = [];
      writes = [];
      outbox = {};
      outboxWrites = [];
      localDeletes = [];
      engine = build(userId: 'user-1');
      addTearDown(engine.dispose);
    });

    test('pushes pending rows with user_id, clears needsSync', () async {
      local = [_local('a', 'Task A', pending: true)];
      final status = await engine.syncNow();
      expect(status, SyncStatus.synced);
      expect(remote.upsertCalls, 1);
      expect(remote.server['a']!['user_id'], 'user-1');
      expect(remote.server['a']!['title'], 'Task A');
      expect(local.single.needsSync, isFalse);
    });

    test('no user → localOnly without touching the network', () async {
      engine.dispose();
      engine = build();
      addTearDown(engine.dispose);
      local = [_local('a', 'Task A', pending: true)];
      expect(await engine.syncNow(), SyncStatus.localOnly);
      expect(remote.upsertCalls, 0);
      expect(remote.fetchCalls, 0);
    });

    test('pull adds server-only rows', () async {
      final serverTask = TodoTask.create(title: 'From cloud');
      remote.server[serverTask.id] =
          serverTask.toServerRow('user-1');
      await engine.syncNow();
      expect(local.map((t) => t.id), contains(serverTask.id));
      expect(local.single.needsSync, isFalse);
    });

    test('last-write-wins: newer server row replaces local', () async {
      final old = DateTime.now().subtract(const Duration(hours: 2));
      final now = DateTime.now();
      local = [_local('a', 'Local title', updated: old)];
      local.single.needsSync = false;
      final server = TodoTask(
        id: 'a',
        title: 'Server title',
        createdAt: old,
        updatedAt: now,
      );
      remote.server['a'] = server.toServerRow('user-1');
      await engine.syncNow();
      expect(local.single.title, 'Server title');
    });

    test('equal timestamps → local kept (no flip-flop)', () async {
      final stamp = DateTime.now().subtract(const Duration(hours: 1));
      local = [_local('a', 'Local title', updated: stamp)];
      local.single.needsSync = false;
      final server = TodoTask(
        id: 'a',
        title: 'Same-stamp server title',
        createdAt: stamp,
        updatedAt: stamp,
      );
      remote.server['a'] = server.toServerRow('user-1');
      await engine.syncNow();
      // Same stamp means "not newer": local wins. This is exactly why
      // dashboard edits need the auto-touch trigger (which bumps the
      // stamp) to become visible — pinned here by design.
      expect(local.single.title, 'Local title');
    });

    test('unpushed local edits survive the pull', () async {
      final base = DateTime.now().subtract(const Duration(hours: 3));
      local = [_local('a', 'Local edit', pending: true, updated: base)];
      final server = TodoTask(
        id: 'a',
        title: 'Stale server',
        createdAt: base,
        updatedAt: base.add(const Duration(hours: 1)),
      );
      remote.server['a'] = server.toServerRow('user-1');
      await engine.syncNow();
      // Push runs first, so the server now holds the local edit…
      expect(remote.server['a']!['title'], 'Local edit');
      expect(local.single.title, 'Local edit');
      expect(local.single.needsSync, isFalse);
    });

    test('pushSoon debounces rapid mutations', () async {
      local = [_local('a', 'Task A', pending: true)];
      engine.pushSoon(delay: const Duration(milliseconds: 20));
      engine.pushSoon(delay: const Duration(milliseconds: 20));
      engine.pushSoon(delay: const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(remote.upsertCalls, 1);
    });

    test('remote failure → error status, local untouched', () async {
      local = [_local('a', 'Task A', pending: true)];
      remote.failNext = true;
      expect(await engine.syncNow(), SyncStatus.error);
      expect(local.single.needsSync, isTrue);
    });

    test('lastError records the failure and clears on success', () async {
      expect(engine.lastError, isNull);
      local = [_local('a', 'Task A', pending: true)];
      remote.failNext = true;
      expect(await engine.syncNow(), SyncStatus.error);
      expect(engine.lastError, isNotNull);
      expect(await engine.syncNow(), SyncStatus.synced);
      expect(engine.lastError, isNull);
    });

    test('status stream emits syncing then synced', () async {
      local = [_local('a', 'Task A', pending: true)];
      final expectation = expectLater(
        engine.status,
        emitsInOrder([SyncStatus.syncing, SyncStatus.synced]),
      );
      await engine.syncNow();
      await expectation;
    });
  });

  group('SyncEngine delete propagation (hard delete)', () {
    late FakeRemote remote;
    late List<TodoTask> local;
    late Set<String> outbox;
    late List<Set<String>> localDeletes;
    late SyncEngine engine;

    SyncEngine build({String? userId}) {
      return SyncEngine(
        remote: remote,
        readLocal: () async => local,
        writeLocal: (tasks) async {
          final byId = {for (final t in tasks) t.id: t};
          local = [
            for (final t in local)
              if (byId.containsKey(t.id)) byId[t.id]! else t,
            for (final t in tasks)
              if (!local.any((l) => l.id == t.id)) t,
          ];
        },
        readUserId: () => userId,
        readPendingDeletes: () async => Set.of(outbox),
        writePendingDeletes: (ids) async => outbox = Set.of(ids),
        deleteLocal: (ids) async {
          localDeletes.add(Set.of(ids));
          local = local.where((t) => !ids.contains(t.id)).toList();
        },
      );
    }

    setUp(() {
      remote = FakeRemote();
      local = [];
      outbox = {};
      localDeletes = [];
      engine = build(userId: 'user-1');
      addTearDown(engine.dispose);
    });

    test('queued delete is flushed to the server and dequeued', () async {
      final gone = TodoTask.create(title: 'Gone');
      remote.server[gone.id] = gone.toServerRow('user-1');
      outbox = {gone.id};
      expect(await engine.syncNow(), SyncStatus.synced);
      expect(remote.deletedIds, contains(gone.id));
      expect(remote.server, isNot(contains(gone.id)));
      expect(outbox, isEmpty);
    });

    test('failed delete stays queued, reports error, no resurrection', () async {
      final gone = TodoTask.create(title: 'Gone');
      remote.server[gone.id] = gone.toServerRow('user-1');
      outbox = {gone.id};
      remote.failDeleteNext = true;
      expect(await engine.syncNow(), SyncStatus.error);
      // Still queued for the next round…
      expect(outbox, {gone.id});
      // …and the shielded server row did not resurrect locally.
      expect(local.map((t) => t.id), isNot(contains(gone.id)));
      // Retry succeeds and clears the queue.
      expect(await engine.syncNow(), SyncStatus.synced);
      expect(outbox, isEmpty);
      expect(remote.server, isNot(contains(gone.id)));
    });

    test('empty outbox never calls delete', () async {
      await engine.syncNow();
      expect(remote.deleteCalls, 0);
    });

    test('cross-device delete prunes the local copy', () async {
      // Other device deleted 'a' on the server; we still hold a synced copy.
      final shared = TodoTask.create(title: 'Shared');
      local = [
        TodoTask(
          id: shared.id,
          title: 'Shared',
          createdAt: shared.createdAt,
          updatedAt: shared.updatedAt,
        ),
      ];
      local.single.needsSync = false;
      // Server no longer has it (deleted elsewhere).
      expect(await engine.syncNow(), SyncStatus.synced);
      expect(local.map((t) => t.id), isNot(contains(shared.id)));
      expect(localDeletes.single, contains(shared.id));
    });

    test('failed flush keeps the shield: nothing pruned, queue kept', () async {
      final offline = _local('offline', 'Offline edit', pending: true);
      final queued = _local('queued', 'Queued delete');
      queued.needsSync = false;
      local = [offline, queued];
      outbox = {'queued'};
      remote.failDeleteNext = true;
      // Server knows neither row.
      expect(await engine.syncNow(), SyncStatus.error);
      expect(local.map((t) => t.id), containsAll(['offline', 'queued']));
      expect(localDeletes, isEmpty);
      expect(outbox, {'queued'});
    });

    test('pushOnly still flushes the delete outbox', () async {
      final gone = TodoTask.create(title: 'Gone');
      remote.server[gone.id] = gone.toServerRow('user-1');
      outbox = {gone.id};
      expect(await engine.syncNow(pushOnly: true), SyncStatus.synced);
      expect(remote.deletedIds, contains(gone.id));
      expect(outbox, isEmpty);
    });
  });

  group('SyncBackoff (poll pacing)', () {
    test('syncs every tick when healthy', () {
      final backoff = SyncBackoff();
      for (var i = 0; i < 10; i++) {
        expect(backoff.shouldSyncNow(), isTrue);
      }
      expect(backoff.inBackoff, isFalse);
    });

    test('backs off after 3 consecutive errors', () {
      final backoff = SyncBackoff(backoffAfter: 3, backoffEvery: 4);
      backoff.noteResult(SyncStatus.error);
      backoff.noteResult(SyncStatus.error);
      expect(backoff.inBackoff, isFalse);
      backoff.noteResult(SyncStatus.error);
      expect(backoff.inBackoff, isTrue);
      // 4 ticks → only the 4th syncs (≈60s at 15s cadence).
      expect(backoff.shouldSyncNow(), isFalse); // tick 1
      expect(backoff.shouldSyncNow(), isFalse); // tick 2
      expect(backoff.shouldSyncNow(), isFalse); // tick 3
      expect(backoff.shouldSyncNow(), isTrue); // tick 4
    });

    test('success resets the failure count', () {
      final backoff = SyncBackoff();
      backoff.noteResult(SyncStatus.error);
      backoff.noteResult(SyncStatus.error);
      backoff.noteResult(SyncStatus.error);
      expect(backoff.inBackoff, isTrue);
      backoff.noteResult(SyncStatus.synced);
      expect(backoff.inBackoff, isFalse);
      expect(backoff.failures, 0);
      expect(backoff.shouldSyncNow(), isTrue);
    });

    test('localOnly/syncing leave the count unchanged', () {
      final backoff = SyncBackoff();
      backoff.noteResult(SyncStatus.error);
      backoff.noteResult(SyncStatus.localOnly);
      backoff.noteResult(SyncStatus.syncing);
      expect(backoff.failures, 1);
      expect(backoff.inBackoff, isFalse);
    });
  });
}
