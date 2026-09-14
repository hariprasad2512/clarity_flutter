import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_service.dart';

/// Background entrypoint for widget interactivity (Android only).
///
/// The header tap (Today ⇄ Inbox switch) flips display state that lives
/// entirely in widget prefs — no Hive, no Supabase — so it runs in the
/// background isolate WITHOUT opening the app. Toggle/open taps use
/// `actionStartActivity` deep links instead (handled in the main isolate,
/// which owns the database).
@pragma('vm:entry-point')
FutureOr<void> widgetInteractCallback(Uri? uri) async {
  if (uri == null) return;
  if (uri.toString() != WidgetService.switchUri) return;
  try {
    final current =
        await HomeWidget.getWidgetData<String>('selected_list',
            defaultValue: WidgetService.listToday);
    final next = current == WidgetService.listInbox
        ? WidgetService.listToday
        : WidgetService.listInbox;
    await HomeWidget.saveWidgetData<String>('selected_list', next);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: WidgetService.androidReceiver,
    );
  } catch (_) {
    // Best-effort.
  }
}

/// Registers [widgetInteractCallback] once at startup. Android-only;
/// safe no-op elsewhere and in tests.
Future<void> registerWidgetInteractivity() async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    await HomeWidget.registerInteractivityCallback(widgetInteractCallback);
  } catch (_) {
    // Best-effort.
  }
}
