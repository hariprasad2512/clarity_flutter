import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_service.dart';
import 'reminder_cache.dart';

/// Background re-scheduler for Android (no Hive, no network).
///
/// Reads the prefs mirror written by [NotificationService] on every
/// schedule/cancel/reschedule and re-issues `zonedSchedule` for future
/// dues. Idempotent by notification id (same task replaces itself).
/// Runs from the unified Workmanager dispatcher — never touches Hive or
/// Supabase (single-isolate box lock).
class NotificationRestoreWorker {
  static const taskName = 'clarity-notif-restore';
  static const uniqueName = 'com.harry.Clarity.notifRestore';
}

/// Entry-point-safe restore. Returns count of re-scheduled alerts.
/// [plugin] and [nowMs] are injectable for tests.
Future<int> restoreReminders({
  FlutterLocalNotificationsPlugin? plugin,
  int? nowMs,
  Future<List<ReminderEntry>> Function()? load,
}) async {
  try {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.UTC);
    } catch (_) {
      // Fall through with default location.
    }
    final entries = await (load?.call() ?? loadReminderCache());
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final future = ReminderCache.futureOnly(entries, now);
    if (future.isEmpty) return 0;

    final p = plugin ?? FlutterLocalNotificationsPlugin();
    if (plugin == null) {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await p.initialize(
        settings: const InitializationSettings(android: androidInit),
      );
      const channel = AndroidNotificationChannel(
        NotificationService.androidChannelId,
        'Task reminders',
        description: 'Due-task alerts with Mark Done and snooze actions',
        importance: Importance.high,
      );
      await p
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
    final android = p.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact =
        await android?.canScheduleExactNotifications() ?? true;

    var count = 0;
    for (final e in future) {
      try {
        final due = DateTime.fromMillisecondsSinceEpoch(e.dueMs);
        final scheduled = tz.TZDateTime.from(due, tz.local);
        await p.zonedSchedule(
          id: NotificationService.notificationIdFor(e.id),
          title: e.title,
          scheduledDate: scheduled,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              NotificationService.androidChannelId,
              'Task reminders',
              category: AndroidNotificationCategory.reminder,
              visibility: NotificationVisibility.public,
              actions: <AndroidNotificationAction>[
                const AndroidNotificationAction(
                  NotificationService.markDoneActionId,
                  'Mark Done',
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
                AndroidNotificationAction(
                  NotificationService.snoozeActionId,
                  NotificationService.snoozeLabel(e.snoozeMinutes),
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
              ],
            ),
          ),
          androidScheduleMode: canExact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: e.id,
        );
        count++;
      } catch (_) {
        // Per-entry best-effort.
      }
    }
    return count;
  } catch (_) {
    return 0;
  }
}
