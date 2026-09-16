import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/task_model.dart';
import 'task_remote.dart';

// ignore_for_file: prefer_initializing_formals
// (Constructor params intentionally differ from private field names.)

/// Sync status for the sidebar dot. Mirrors native `SyncEngine.status`.
enum SyncStatus { synced, syncing, localOnly, error }

/// Offline-first cloud sync. Port of native `SyncEngine`
/// (Supabase/SyncEngine.swift) — same algorithm:
///
/// flush pending deletes → push pending upserts → pull all →
/// last-write-wins on `updated_at` → persist → refresh UI + notifications.
///
/// Deletes propagate as hard deletes: swipe-delete removes the row locally
/// and queues its ID in the delete outbox; the push phase deletes it from
/// the server, and other devices prune their local copy on the next pull
/// (local rows absent from the server that aren't pending or outboxed).
/// Conflict policy: whoever wrote last wins; local rows keep `needsSync`
/// until the server confirms them; a concurrent local edit beats a remote
/// delete (the edit re-pushes and the row comes back).
class SyncEngine {
  SyncEngine({
    required TaskRemote remote,
    required Future<List<TodoTask>> Function() readLocal,
    required Future<void> Function(List<TodoTask> tasks) writeLocal,
    required String? Function() readUserId,
    required Future<Set<String>> Function() readPendingDeletes,
    required Future<void> Function(Set<String> ids) writePendingDeletes,
    required Future<void> Function(Set<String> ids) deleteLocal,
  })  : _remote = remote,
        _readLocal = readLocal,
        _writeLocal = writeLocal,
        _readUserId = readUserId,
        _readPendingDeletes = readPendingDeletes,
        _writePendingDeletes = writePendingDeletes,
        _deleteLocal = deleteLocal;

  final TaskRemote _remote;
  final Future<List<TodoTask>> Function() _readLocal;
  final Future<void> Function(List<TodoTask>) _writeLocal;
  final String? Function() _readUserId;
  final Future<Set<String>> Function() _readPendingDeletes;
  final Future<void> Function(Set<String>) _writePendingDeletes;
  final Future<void> Function(Set<String>) _deleteLocal;

  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get status => _status.stream;

  /// Last sync failure, if any. Reset to null on the next success.
  /// Surfaced for diagnosis (sidebar dot shows the status; logs carry
  /// the cause) so a failing poll can never look like a silent stall.
  Object? _lastError;
  Object? get lastError => _lastError;

  Timer? _pushTimer;
  bool _busy = false;

  /// Debounced push trigger (native: 1.2s). Call after every local mutation.
  void pushSoon({Duration delay = const Duration(milliseconds: 1200)}) {
    _pushTimer?.cancel();
    _pushTimer = Timer(delay, () => syncNow(pushOnly: true));
  }

  Future<SyncStatus> syncNow({bool pushOnly = false}) {
    if (_busy) return Future.value(SyncStatus.syncing);
    return _run(pushOnly: pushOnly);
  }

  Future<SyncStatus> _run({required bool pushOnly}) async {
    _busy = true;
    _emit(SyncStatus.syncing);
    try {
      final local = await _readLocal();
      final userId = _readUserId();
      if (userId == null) {
        _emit(SyncStatus.localOnly);
        return SyncStatus.localOnly;
      }
      // 1. Flush queued hard deletes first. A failure keeps the IDs
      // queued for the next round (every sync retries) and surfaces as
      // an error — otherwise the row would resurrect on the next pull.
      var pendingDeletes = await _readPendingDeletes();
      var deletesFlushed = true;
      if (pendingDeletes.isNotEmpty) {
        try {
          await _remote.deleteByIds(pendingDeletes);
          pendingDeletes = {};
          await _writePendingDeletes(pendingDeletes);
        } catch (e) {
          deletesFlushed = false;
          _lastError = e;
          debugPrint('Clarity sync delete flush failed: $e');
        }
      }
      final pending = local.where((t) => t.needsSync).toList();
      if (pending.isNotEmpty) {
        final rows =
            pending.map((t) => t.toServerRow(userId)).toList();
        final stored = await _remote.upsert(rows);
        final confirmed = {
          for (final r in stored) (r['id'] as String): true,
        };
        for (final t in pending) {
          if (confirmed.containsKey(t.id)) t.needsSync = false;
        }
        await _writeLocal(pending);
      }
      if (!pushOnly) {
        final serverRows = await _remote.fetchAll(userId);
        final serverIds = {for (final r in serverRows) r['id'] as String};
        final merged = _merge(local, serverRows, pendingDeletes);
        await _writeLocal(merged);
        // Cross-device deletes: drop local copies that are gone from the
        // server. Never prune unpushed edits (they re-push next round)
        // or IDs still queued for deletion (shielded above).
        final prune = {
          for (final t in local)
            if (!t.needsSync &&
                !pendingDeletes.contains(t.id) &&
                !serverIds.contains(t.id))
              t.id,
        };
        if (prune.isNotEmpty) {
          await _deleteLocal(prune);
        }
      }
      if (!deletesFlushed) {
        _emit(SyncStatus.error);
        return SyncStatus.error;
      }
      _emit(SyncStatus.synced);
      _lastError = null;
      return SyncStatus.synced;
    } catch (e) {
      _lastError = e;
      // Visible in debug runs — a silent stall (looks like "sync only
      // works after restart") is worse than a log line.
      debugPrint('Clarity sync failed: $e');
      _emit(SyncStatus.error);
      return SyncStatus.error;
    } finally {
      _busy = false;
    }
  }

  /// Last-write-wins merge. Server rows win ties and newer stamps; local
  /// rows not yet pushed keep their content (they'll push next round).
  /// Server rows whose ID is still queued for deletion are skipped so a
  /// retrying delete can never self-resurrect.
  List<TodoTask> _merge(
    List<TodoTask> local,
    List<Map<String, dynamic>> serverRows,
    Set<String> pendingDeletes,
  ) {
    final byId = {for (final t in local) t.id: t};
    final out = <TodoTask>[];
    for (final row in serverRows) {
      if (pendingDeletes.contains(row['id'] as String)) continue;
      final server = TodoTask.fromServerRow(row);
      final existing = byId.remove(server.id);
      if (existing == null) {
        out.add(server);
      } else if (existing.needsSync) {
        out.add(existing); // unpushed local edit wins this round
      } else if (!server.updatedAt.isAfter(existing.updatedAt)) {
        out.add(existing);
      } else {
        out.add(server);
      }
    }
    out.addAll(byId.values); // local-only rows (incl. pending)
    return out;
  }

  void _emit(SyncStatus s) {
    if (!_status.isClosed) _status.add(s);
  }

  void dispose() {
    _pushTimer?.cancel();
    _status.close();
  }
}

/// Poll pacing for the foreground pull timer (see `_Bootstrap` in main).
///
/// Normal operation syncs every tick; after [backoffAfter] consecutive
/// errors it syncs every [backoffEvery]-th tick so an offline device
/// doesn't hammer the network, while a single coalesced retry (scheduled
/// by the caller) still recovers quickly on reconnect. Any success
/// resets to full cadence. Pure logic — unit-tested.
class SyncBackoff {
  SyncBackoff({
    this.backoffAfter = 3,
    this.backoffEvery = 4,
  });

  final int backoffAfter;
  final int backoffEvery;

  int _tick = 0;
  int _failures = 0;

  int get failures => _failures;
  bool get inBackoff => _failures >= backoffAfter;

  /// Called on every poll tick. Returns true when a sync should run.
  bool shouldSyncNow() {
    _tick++;
    if (!inBackoff) return true;
    return _tick % backoffEvery == 0;
  }

  /// Feed back each poll result. `localOnly`/`syncing` leave the count
  /// unchanged (neither success nor failure).
  void noteResult(SyncStatus status) {
    switch (status) {
      case SyncStatus.error:
        _failures++;
      case SyncStatus.synced:
        _failures = 0;
      case SyncStatus.syncing:
      case SyncStatus.localOnly:
        break;
    }
  }
}

/// Riverpod glue. The engine is created in main (needs store + notifier
/// callbacks) and overridden here; absent engine = local-only.
final syncEngineProvider = Provider<SyncEngine?>((ref) => null);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.localOnly;
  void set(SyncStatus s) => state = s;
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatus>(
        SyncStatusNotifier.new);
