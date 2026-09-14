import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/task_model.dart';

/// Thin Hive persistence layer. Mirrors native `SharedStore` (one `clarity`
/// box shared by the whole app).
///
/// Dumb by design: no change notifications. The Riverpod notifier
/// (`app_store.dart`) owns state and updates it explicitly on every
/// mutation; outside writers (Phase 2 notification actions, Phase 3 sync)
/// call `TaskListNotifier.refreshFromStore()` when done.
class LocalStore {
  LocalStore._(this._box);

  final Box<TodoTask> _box;
  static const boxName = 'clarity_tasks';

  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(TodoTaskAdapter());
    }
    final box = await Hive.openBox<TodoTask>(boxName);
    return LocalStore._(box);
  }

  static bool _testInitDone = false;

  /// For tests: temp-dir Hive backend, no path_provider needed.
  /// Init runs once per test isolate; each call opens a fresh box.
  @visibleForTesting
  static Future<LocalStore> openTest() async {
    if (!_testInitDone) {
      final dir =
          await Directory.systemTemp.createTemp('clarity_test_hive');
      Hive.init(dir.path);
      _testInitDone = true;
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(TodoTaskAdapter());
    }
    final box = await Hive.openBox<TodoTask>(
      'test_${DateTime.now().microsecondsSinceEpoch}',
    );
    return LocalStore._(box);
  }

  List<TodoTask> get all => _box.values.toList();

  Future<void> put(TodoTask task) => _box.put(task.id, task);

  Future<void> deleteByIds(Iterable<String> ids) => _box.deleteAll(ids);

  Future<void> clear() => _box.clear();

  @visibleForTesting
  Future<void> closeAndDelete() async {
    final name = _box.name;
    await _box.close();
    await Hive.deleteBoxFromDisk(name);
  }
}
