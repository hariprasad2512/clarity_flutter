import 'dart:async';

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
/// push pending upserts → pull all → last-write-wins on `updated_at` →
/// persist → refresh UI + notifications.
///
/// Deletes don't propagate (no tombstones in the schema — same as native).
/// Conflict policy: whoever wrote last wins; local rows keep `needsSync`
/// until the server confirms them.
class SyncEngine {
  SyncEngine({
    required TaskRemote remote,
    required Future<List<TodoTask>> Function() readLocal,
    required Future<void> Function(List<TodoTask> tasks) writeLocal,
    required String? Function() readUserId,
  })  : _remote = remote,
        _readLocal = readLocal,
        _writeLocal = writeLocal,
        _readUserId = readUserId;

  final TaskRemote _remote;
  final Future<List<TodoTask>> Function() _readLocal;
  final Future<void> Function(List<TodoTask>) _writeLocal;
  final String? Function() _readUserId;

  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get status => _status.stream;

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
        final merged = _merge(local, serverRows);
        await _writeLocal(merged);
      }
      _emit(SyncStatus.synced);
      return SyncStatus.synced;
    } catch (_) {
      _emit(SyncStatus.error);
      return SyncStatus.error;
    } finally {
      _busy = false;
    }
  }

  /// Last-write-wins merge. Server rows win ties and newer stamps; local
  /// rows not yet pushed keep their content (they'll push next round).
  List<TodoTask> _merge(
    List<TodoTask> local,
    List<Map<String, dynamic>> serverRows,
  ) {
    final byId = {for (final t in local) t.id: t};
    final out = <TodoTask>[];
    for (final row in serverRows) {
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
