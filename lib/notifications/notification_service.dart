import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/task_model.dart';
import 'reminder_cache.dart';

/// All local-notification logic in one place. Port of native
/// `NotificationManager` (Shared/NotificationManager.swift).
///
/// * Action/category IDs mirror AGENTS §7 exactly: `CLARITY_TASK_DUE`,
///   `CLARITY_MARK_DONE`, `CLARITY_SNOOZE`.
/// * Title-only content: the app icon identifies Clarity, the task gets the
///   prominent slot. No subtitle/body.
/// * Past dates are never scheduled (native guard).
/// * Backends: Android / iOS / macOS / Windows / Linux via
///   flutter_local_notifications. Web is a no-op (plugin has no web
///   scheduler) — documented limitation.
///
/// Action taps are delivered to [onMarkDone]/[onSnooze] in the main isolate
/// (wired in main.dart). No background-isolate handler by design: Hive boxes
/// cannot be opened from two isolates, so actions always apply through the
/// running app (a tap cold-starts it first when killed).
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const categoryId = 'CLARITY_TASK_DUE';
  static const markDoneActionId = 'CLARITY_MARK_DONE';
  static const snoozeActionId = 'CLARITY_SNOOZE';
  static const androidChannelId = 'clarity_due';

  /// Stable COM identity for Windows toasts. Generated once, never changed
  /// (Windows uses it to route activation callbacks).
  static const windowsGuid = 'd4f5b0df-9fc7-48ff-9399-f0331db046b3';
  static const windowsAppId = 'Clarity.Clarity.Clarity.1';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  int _snoozeMinutes = 60;

  /// Last-known Android permission state (null = unknown / non-Android).
  /// Refreshed by [requestPermission] and [refreshPermissionStatus].
  /// When exact alarms are denied, [schedule] falls back to inexact so the
  /// alert still fires (OEM-dependent window) instead of throwing.
  bool? _notificationsEnabled;
  bool _canScheduleExact = true;

  bool? get notificationsEnabled => _notificationsEnabled;
  bool get canScheduleExact => _canScheduleExact;

  /// Set by main.dart. Invoked with the task UUID from the payload.
  Future<void> Function(String taskId)? onMarkDone;
  Future<void> Function(String taskId)? onSnooze;

  /// Whether this platform can schedule. Web has no scheduler backend.
  static bool get isSupported => !kIsWeb;

  /// Local notification int ID derived deterministically from the task UUID
  /// (same task re-scheduled replaces itself — mirrors native identifier).
  static int notificationIdFor(String taskId) =>
      taskId.hashCode & 0x7fffffff;

  /// Pure scheduling rule (unit-tested): incomplete + future due date.
  /// Native guard: `guard dueDate > Date()`.
  static bool shouldSchedule(TodoTask task, DateTime now) {
    final due = task.dueDate;
    return due != null && !task.isCompleted && due.isAfter(now);
  }

  /// Snooze target: now + delay. Native: `Date() + minutes*60`.
  static DateTime snoozedDate(DateTime now, int minutes) =>
      now.add(Duration(minutes: minutes));

  /// Dynamic "Remind me later" label. Mirrors native `snoozeLabel`.
  static String snoozeLabel(int minutes) {
    if (minutes < 60) return 'Remind me in $minutes min';
    final h = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) {
      return h == 1 ? 'Remind me in 1 hour' : 'Remind me in $h hours';
    }
    return 'Remind me in ${h}h ${rest}m';
  }

  Future<void> init({required int snoozeMinutes}) async {
    if (!isSupported) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
      _snoozeMinutes = snoozeMinutes;
      await _register();
      const channel = AndroidNotificationChannel(
        androidChannelId,
        'Task reminders',
        description: 'Due-task alerts with Mark Done and snooze actions',
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _ready = true;
    } catch (_) {
      // Notifications are best-effort: never break the app.
      _ready = false;
    }
  }

  /// (Re)registers init settings incl. the actionable Darwin category.
  /// Called at startup and whenever the snooze setting changes (the action
  /// title is dynamic — mirrors native `registerCategories`).
  Future<void> _register() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: _darwinCategories(_snoozeMinutes),
    );
    const linuxInit = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
    const windowsInit = WindowsInitializationSettings(
      appName: 'Clarity',
      appUserModelId: windowsAppId,
      guid: windowsGuid,
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
        linux: linuxInit,
        windows: windowsInit,
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
  }

  /// Refreshes the action button title after the snooze setting changes.
  Future<void> updateSnoozeLabel(int minutes) async {
    if (!_ready) return;
    try {
      _snoozeMinutes = minutes;
      await _register();
    } catch (_) {
      // Best-effort.
    }
  }

  /// Requests notification + exact-alarm permission, then refreshes status.
  /// Returns true when notifications are enabled afterwards. Never throws:
  /// unready plugin or denied permissions yield false so the Settings UI can
  /// show a SnackBar / open system settings instead of appearing dead.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // Best-effort.
    }
    await refreshPermissionStatus();
    return _notificationsEnabled ?? false;
  }

  /// Re-opens the system "Alarms & reminders" screen when exact alarms are
  /// still denied after [requestPermission]. No-op when unready.
  Future<void> openExactAlarmSettings() async {
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    } catch (_) {
      // Best-effort.
    }
    await refreshPermissionStatus();
  }

  /// Re-reads Android notification + exact-alarm state without prompting.
  /// Safe no-op on other platforms / in tests. Used by Settings UI and
  /// foreground-resume refresh.
  Future<void> refreshPermissionStatus() async {
    if (!_ready) return;
    try {
      final android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return;
      _notificationsEnabled = await android.areNotificationsEnabled();
      _canScheduleExact =
          await android.canScheduleExactNotifications() ?? true;
    } catch (_) {
      // Best-effort: keep previous values.
    }
  }

  /// Schedules the due alert. No-op when unsupported, unready, completed,
  /// undated or in the past. Mirrors native `schedule(for:)`.
  /// [snoozeMinutes] bakes the dynamic action title.
  /// On Android without exact-alarm permission, falls back to inexact
  /// (fires within an OEM-dependent window) instead of throwing.
  Future<void> schedule(TodoTask task, {int snoozeMinutes = 60}) async {
    if (!_ready || !shouldSchedule(task, DateTime.now())) return;
    try {
      final due = task.dueDate!;
      final scheduled = tz.TZDateTime.from(due, tz.local);
      await _plugin.zonedSchedule(
        id: notificationIdFor(task.id),
        title: task.title,
        scheduledDate: scheduled,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            androidChannelId,
            'Task reminders',
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            actions: <AndroidNotificationAction>[
              const AndroidNotificationAction(
                markDoneActionId,
                'Mark Done',
                showsUserInterface: true,
                cancelNotification: true,
              ),
              // Baked per schedule so the delay is always current.
              AndroidNotificationAction(
                snoozeActionId,
                snoozeLabel(snoozeMinutes),
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            categoryIdentifier: categoryId,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            categoryIdentifier: categoryId,
          ),
          linux: LinuxNotificationDetails(
            actions: <LinuxNotificationAction>[
              const LinuxNotificationAction(
                key: markDoneActionId,
                label: 'Mark Done',
              ),
              LinuxNotificationAction(
                key: snoozeActionId,
                label: snoozeLabel(snoozeMinutes),
              ),
            ],
          ),
          windows: WindowsNotificationDetails(
            actions: <WindowsAction>[
              const WindowsAction(
                content: 'Mark Done',
                arguments: markDoneActionId,
              ),
              WindowsAction(
                content: snoozeLabel(snoozeMinutes),
                arguments: snoozeActionId,
              ),
            ],
          ),
        ),
        androidScheduleMode: _canScheduleExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: task.id,
      );
      await _cacheUpsert(task, snoozeMinutes);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> cancel(String taskId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: notificationIdFor(taskId));
    } catch (_) {
      // Best-effort.
    }
    await _cacheRemove(taskId);
  }

  /// Startup reconcile: clear stale system state, then schedule every
  /// actionable task. Called on every launch (covers reboot).
  Future<void> rescheduleAll(
    Iterable<TodoTask> tasks, {
    int snoozeMinutes = 60,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Continue to (re)schedule regardless.
    }
    final now = DateTime.now();
    for (final task in tasks) {
      if (shouldSchedule(task, now)) {
        await schedule(task, snoozeMinutes: snoozeMinutes);
      }
    }
    // Rewrite the prefs mirror to drop stale ids (deleted/completed on
    // another device). Individual schedule() calls above already upserted,
    // so this is a prune pass.
    await _cacheReplaceAll(tasks, snoozeMinutes);
  }

  /// Prefs mirror writes. Best-effort; never throws; keeps the background
  /// restore worker (no Hive access) able to re-schedule after reboot.
  Future<void> _cacheUpsert(TodoTask task, int snoozeMinutes) async {
    try {
      final due = task.dueDate;
      if (due == null) return;
      final prefs = await SharedPreferences.getInstance();
      final current = ReminderCache.decode(
        prefs.getString(ReminderCache.prefsKey),
      );
      final updated = ReminderCache.upsert(
        current,
        ReminderEntry(
          id: task.id,
          title: task.title,
          dueMs: due.millisecondsSinceEpoch,
          snoozeMinutes: snoozeMinutes,
        ),
      );
      await saveReminderCache(updated, prefs);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _cacheRemove(String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = ReminderCache.decode(
        prefs.getString(ReminderCache.prefsKey),
      );
      await saveReminderCache(ReminderCache.remove(current, taskId), prefs);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _cacheReplaceAll(
    Iterable<TodoTask> tasks,
    int snoozeMinutes,
  ) async {
    try {
      final now = DateTime.now();
      final entries = <ReminderEntry>[];
      for (final task in tasks) {
        final due = task.dueDate;
        if (due != null &&
            !task.isCompleted &&
            due.isAfter(now)) {
          entries.add(
            ReminderEntry(
              id: task.id,
              title: task.title,
              dueMs: due.millisecondsSinceEpoch,
              snoozeMinutes: snoozeMinutes,
            ),
          );
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await saveReminderCache(entries, prefs);
    } catch (_) {
      // Best-effort.
    }
  }

  void _onResponse(NotificationResponse response) {    final taskId = response.payload;
    if (taskId == null || taskId.isEmpty) return;
    switch (response.actionId) {
      case markDoneActionId:
        onMarkDone?.call(taskId);
      case snoozeActionId:
        onSnooze?.call(taskId);
      default:
        // Default tap: the OS already foregrounds the app. Nothing to do.
        break;
    }
  }

  List<DarwinNotificationCategory> _darwinCategories(int snoozeMinutes) => [
        DarwinNotificationCategory(
          categoryId,
          actions: [
            DarwinNotificationAction.plain(
              markDoneActionId,
              'Mark Done',
              options: const {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              snoozeActionId,
              snoozeLabel(snoozeMinutes),
            ),
          ],
        ),
      ];
}
