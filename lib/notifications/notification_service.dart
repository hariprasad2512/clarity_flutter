import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/task_model.dart';

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

  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
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
  }

  /// Schedules the due alert. No-op when unsupported, unready, completed,
  /// undated or in the past. Mirrors native `schedule(for:)`.
  /// [snoozeMinutes] bakes the dynamic action title.
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: task.id,
      );
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
  }

  void _onResponse(NotificationResponse response) {
    final taskId = response.payload;
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
