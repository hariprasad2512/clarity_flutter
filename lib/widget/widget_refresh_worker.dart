import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../notifications/notification_restore_worker.dart';
import 'widget_service.dart';

/// Periodic widget freshness (Android only, 15-min OS cadence).
///
/// Freshness-only by design: re-renders all widget sizes from the last
/// prefs snapshot so overdue styling, strike-expiry and counts stay
/// correct while the app is closed. NO network, NO database, NO
/// notification code in this file — verifiable by its imports (only
/// home_widget + workmanager + restore worker). Tasks created elsewhere
/// surface on next app open; a closed app cannot sync on any platform.
///
/// Notification reboot safety comes from two layers:
/// 1. `ScheduledNotificationBootReceiver` (manifest) — plugin restores OS
///    exact alarms after reboot/update.
/// 2. `NotificationRestoreWorker` (prefs cache, same dispatcher below) —
///    re-issues zoned schedules for known-future reminders without Hive.
class WidgetRefreshWorker {
  static const taskName = 'clarity-widget-refresh';
  static const uniqueName = 'com.harry.Clarity.widgetRefresh';
}

/// Unified background entrypoint (single Workmanager initialize).
/// Handles widget refresh + notification restore. Hive-free by design.
@pragma('vm:entry-point')
void clarityBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == WidgetRefreshWorker.taskName) {
      try {
        for (final receiver in WidgetService.androidReceivers) {
          await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
        }
        return true;
      } catch (_) {
        return false;
      }
    }
    if (task == NotificationRestoreWorker.taskName) {
      try {
        await restoreReminders();
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  });
}

/// Background entrypoint. Re-renders every registered size from prefs.
/// Kept for backward compat (already-registered workers); delegates to
/// the unified dispatcher logic for its task name.
@pragma('vm:entry-point')
void widgetRefreshDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != WidgetRefreshWorker.taskName) return true;
    try {
      for (final receiver in WidgetService.androidReceivers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Registers the 15-min freshness worker + notification restore worker
/// once at startup. Android-only; safe no-op elsewhere and in tests.
Future<void> registerWidgetRefreshWorker() async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    await Workmanager().initialize(clarityBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      WidgetRefreshWorker.uniqueName,
      WidgetRefreshWorker.taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    await Workmanager().registerPeriodicTask(
      NotificationRestoreWorker.uniqueName,
      NotificationRestoreWorker.taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // Best-effort.
  }
}
