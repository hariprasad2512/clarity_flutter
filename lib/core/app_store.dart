import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/date_parser.dart';
import '../core/task_model.dart';
import '../data/local_store.dart';
import '../desktop/desktop.dart';
import '../notifications/notification_service.dart';
import '../sync/sync_engine.dart';
import '../widget/widget_service.dart';

// -- bootstrap overrides (set in main) ---------------------------------------

/// Resolved in main() before runApp. Overridden with the opened Hive store.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider not overridden'),
);

/// Resolved in main() before runApp.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider not overridden'),
);

/// Initialized service, overridden in main(). The default instance is never
/// initialized, so every call is a safe no-op (unit tests rely on this).
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

// -- settings ----------------------------------------------------------------

class SettingsState {
  const SettingsState({
    required this.snoozeMinutes,
    required this.offlineMode,
    required this.launchAtLogin,
  });
  final int snoozeMinutes;
  final bool offlineMode;

  /// Desktop-only; always false on mobile/web. Default off (opt-in).
  final bool launchAtLogin;

  SettingsState copyWith({
    int? snoozeMinutes,
    bool? offlineMode,
    bool? launchAtLogin,
  }) =>
      SettingsState(
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        offlineMode: offlineMode ?? this.offlineMode,
        launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      );
}

/// Mirrors native `@AppStorage("snoozeMinutes")` + `AuthService.offlineMode`.
/// Default snooze 60 min (SettingsView options 15/30/60/120/180).
class SettingsNotifier extends Notifier<SettingsState> {
  static const snoozeKey = 'snoozeMinutes';
  static const offlineKey = 'offlineMode';
  static const launchKey = 'launchAtLogin';
  static const snoozeOptions = [15, 30, 60, 120, 180];

  @override
  SettingsState build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return SettingsState(
      snoozeMinutes: prefs.getInt(snoozeKey).let((v) =>
          (v != null && v > 0) ? v : 60),
      offlineMode: prefs.getBool(offlineKey) ?? false,
      launchAtLogin: isDesktopApp &&
          (prefs.getBool(launchKey) ?? false),
    );
  }

  Future<void> setSnoozeMinutes(int minutes) async {
    state = state.copyWith(snoozeMinutes: minutes);
    await ref.read(sharedPrefsProvider).setInt(snoozeKey, minutes);
    // Refresh the action button title on pending UI (native parity).
    await ref.read(notificationServiceProvider).updateSnoozeLabel(minutes);
  }

  Future<void> setOfflineMode(bool value) async {
    state = state.copyWith(offlineMode: value);
    await ref.read(sharedPrefsProvider).setBool(offlineKey, value);
  }

  /// Opt-in launch at login (desktop only, default off). Applies via the
  /// OS startup entry immediately; the choice persists across launches.
  /// Mirrors native `LaunchAtLogin`.
  Future<void> setLaunchAtLogin(bool value) async {
    if (!isDesktopApp) return;
    state = state.copyWith(launchAtLogin: value);
    await ref.read(sharedPrefsProvider).setBool(launchKey, value);
    try {
      launchAtStartup.setup(
        appName: 'Clarity',
        appPath: Platform.resolvedExecutable,
      );
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (_) {
      // Best-effort: the preference stays, the OS entry may not.
    }
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

// -- task list ---------------------------------------------------------------

/// Local-first task state. Mirrors native `TaskService` (add/toggle/delete).
/// Every mutation stamps updatedAt/needsSync via [TodoTask.touch].
///
/// Source of truth is this notifier's state; [LocalStore] is persistence.
/// The store listener only picks up *external* writes (Phase 2 notification
/// actions, Phase 3 sync) — own mutations update state explicitly so UI
/// never depends on listener round-trip timing.
/// Phase 2 hooks: schedule/cancel notifications. Phase 3 hooks: pushSoon().
class TaskListNotifier extends Notifier<List<TodoTask>> {
  @override
  List<TodoTask> build() =>
      [...ref.watch(localStoreProvider).all];

  /// Re-reads the store. Called after *outside* writes only (Phase 2
  /// notification actions, Phase 3 sync pull). Own mutations below set
  /// state explicitly.
  void refreshFromStore() {
    state = [...ref.read(localStoreProvider).all];
  }

  /// Extract natural date (or use manual override), insert, persist.
  /// Returns null when input is blank. Mirrors `TaskService.add`
  /// (insert + save + schedule + widget refresh + push).
  Future<TodoTask?> add(String rawInput, {DateTime? manualDate}) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;
    final String title;
    final DateTime? dueDate;
    if (manualDate != null) {
      title = trimmed;
      dueDate = manualDate;
    } else {
      final parsed = DateParser.extractDateAndCleaned(trimmed);
      title = parsed.title;
      dueDate = parsed.date;
    }
    final task = TodoTask.create(title: title, dueDate: dueDate);
    await ref.read(localStoreProvider).put(task);
    state = [...state, task];
    await _notifications().schedule(task, snoozeMinutes: _snooze());
    _syncSoon();
    await _refreshWidget();
    return task;
  }

  Future<void> toggle(TodoTask task) async {
    task.isCompleted = !task.isCompleted;
    task.touch();
    await ref.read(localStoreProvider).put(task);
    state = [
      for (final t in state)
        if (t.id == task.id) task else t,
    ];
    if (task.isCompleted) {
      await _notifications().cancel(task.id);
    } else {
      await _notifications().schedule(task, snoozeMinutes: _snooze());
    }
    _syncSoon();
    await _refreshWidget();
  }

  Future<void> deleteByIds(Iterable<String> ids) async {
    final gone = ids.toSet();
    await ref.read(localStoreProvider).deleteByIds(gone);
    state = state.where((t) => !gone.contains(t.id)).toList();
    for (final id in gone) {
      await _notifications().cancel(id);
    }
    _syncSoon();
    await _refreshWidget();
  }

  /// Privacy wipe on sign-out (Phase 3). Mirrors `AuthService.signOut`.
  /// Also clears system notifications for the wiped tasks.
  Future<void> clearAll() async {
    final ids = state.map((t) => t.id).toList();
    await ref.read(localStoreProvider).clear();
    state = const [];
    for (final id in ids) {
      await _notifications().cancel(id);
    }
    await _refreshWidget();
  }

  // -- notification-action handlers (main-isolate callbacks) -----------------
  // Mirror native NotificationDelegate.complete / snooze.

  /// Idempotent completion for the Mark Done action. Returns false when the
  /// task is unknown (e.g. deleted on another device).
  Future<bool> completeById(String id) async {
    final task = _byId(id);
    if (task == null || task.isCompleted) return task != null;
    task.isCompleted = true;
    task.touch();
    await ref.read(localStoreProvider).put(task);
    state = [
      for (final t in state)
        if (t.id == id) task else t,
    ];
    await _notifications().cancel(id);
    _syncSoon();
    await _refreshWidget();
    return true;
  }

  /// Pushes the due date out by [minutes] and reschedules. Returns false
  /// when the task is unknown or already completed.
  Future<bool> snoozeById(String id, int minutes) async {
    final task = _byId(id);
    if (task == null || task.isCompleted) return false;
    task.dueDate = NotificationService.snoozedDate(DateTime.now(), minutes);
    task.touch();
    await ref.read(localStoreProvider).put(task);
    state = [
      for (final t in state)
        if (t.id == id) task else t,
    ];
    await _notifications().schedule(task, snoozeMinutes: minutes);
    _syncSoon();
    await _refreshWidget();
    return true;
  }

  TodoTask? _byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  NotificationService _notifications() =>
      ref.read(notificationServiceProvider);

  int _snooze() => ref.read(settingsProvider).snoozeMinutes;

  /// Debounced cloud push. No-op when unconfigured (engine is null).
  /// Mirrors native `SyncEngine.pushSoon`.
  void _syncSoon() => ref.read(syncEngineProvider)?.pushSoon();

  /// Re-renders the home-screen widget. No-op off Android / in tests.
  Future<void> _refreshWidget() =>
      ref.read(widgetServiceProvider).refresh(state);
}

final taskListProvider =
    NotifierProvider<TaskListNotifier, List<TodoTask>>(TaskListNotifier.new);

// -- filtering ---------------------------------------------------------------

class FilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => TaskFilter.today;
  void set(TaskFilter f) => state = f;
}

final filterProvider =
    NotifierProvider<FilterNotifier, TaskFilter>(FilterNotifier.new);

class SearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final searchProvider =
    NotifierProvider<SearchNotifier, String>(SearchNotifier.new);

/// Mirrors `TaskListView.filtered`: filter tab + search + display sort.
final filteredTasksProvider = Provider<List<TodoTask>>((ref) {
  final tasks = ref.watch(taskListProvider);
  final filter = ref.watch(filterProvider);
  final q = ref.watch(searchProvider).trim().toLowerCase();
  List<TodoTask> base;
  switch (filter) {
    case TaskFilter.today:
      base = tasks.where((t) => t.isDueTodayOrOverdue).toList();
      break;
    case TaskFilter.inbox:
      base = tasks.where((t) => !t.isCompleted).toList();
      break;
    case TaskFilter.done:
      base = tasks.where((t) => t.isCompleted).toList();
      break;
  }
  if (q.isNotEmpty) {
    base = base.where((t) => t.title.toLowerCase().contains(q)).toList();
  }
  base.sort(TodoTask.sortForDisplay);
  return base;
});

/// Sidebar badges. Mirrors `todayCount` / `inboxCount` in ContentView.
final countsProvider = Provider<({int today, int inbox})>((ref) {
  final tasks = ref.watch(taskListProvider);
  return (
    today: tasks.where((t) => t.isDueTodayOrOverdue).length,
    inbox: tasks.where((t) => !t.isCompleted).length,
  );
});

// -- tiny helper --------------------------------------------------------------

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
