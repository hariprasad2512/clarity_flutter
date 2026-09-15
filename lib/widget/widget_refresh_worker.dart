import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import 'widget_service.dart';

/// Periodic widget freshness (Android only, 15-min OS cadence).
///
/// Freshness-only by design: re-renders all widget sizes from the last
/// prefs snapshot so overdue styling, strike-expiry and counts stay
/// correct while the app is closed. NO network, NO database, NO
/// notification code in this file — verifiable by its imports (only
/// home_widget + workmanager). Tasks created elsewhere surface on next
/// app open; a closed app cannot sync on any platform.
class WidgetRefreshWorker {
  static const taskName = 'clarity-widget-refresh';
  static const uniqueName = 'com.harry.Clarity.widgetRefresh';
}

/// Background entrypoint. Re-renders every registered size from prefs.
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

/// Registers the 15-min freshness worker once at startup. Android-only;
/// safe no-op elsewhere and in tests.
Future<void> registerWidgetRefreshWorker() async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    await Workmanager().initialize(widgetRefreshDispatcher);
    await Workmanager().registerPeriodicTask(
      WidgetRefreshWorker.uniqueName,
      WidgetRefreshWorker.taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // Best-effort.
  }
}
