import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/core/task_model.dart';
import 'package:clarity_flutter/sync/sync_engine.dart';
import 'package:clarity_flutter/sync/task_remote.dart';

/// In-memory stand-in for Supabase PostgREST.
class FakeRemote implements TaskRemote {
  final Map<String, Map<String, dynamic>> server = {};
  int upsertCalls = 0;
  int fetchCalls = 0;
  bool failNext = false;

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
      );
    }

    setUp(() {
      remote = FakeRemote();
      local = [];
      writes = [];
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
}
