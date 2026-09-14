import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../core/app_store.dart';
import 'widget_service.dart';

/// Background entrypoint for widget interactivity (Android only).
///
/// Two background-safe actions (prefs only — never Hive/Supabase, which
/// live in the main isolate):
/// * header tap (`switchUri`): flips the selected list, re-renders.
///   No app open.
/// * circle tap (toggle URI): strike/undo outbox. Flips the id in the
///   `pending_strikes` list and re-renders optimistically — the row shows
///   struck instantly, and tapping again undoes it. The main isolate
///   applies pending ids via [reconcileWidgetStrikes] on start/resume/pull.
@pragma('vm:entry-point')
FutureOr<void> widgetInteractCallback(Uri? uri) async {
  if (uri == null) return;
  try {
    if (uri.toString() == WidgetService.switchUri) {
      final current =
          await HomeWidget.getWidgetData<String>('selected_list',
              defaultValue: WidgetService.listToday);
      final next = current == WidgetService.listInbox
          ? WidgetService.listToday
          : WidgetService.listInbox;
      await HomeWidget.saveWidgetData<String>('selected_list', next);
      for (final receiver in WidgetService.androidReceivers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
      }
      return;
    }
    final id = WidgetService.parseToggleId(uri);
    if (id == null) return;
    final pending = await _pendingStrikes();
    if (pending.contains(id)) {
      pending.remove(id); // undo
    } else {
      pending.add(id); // strike
    }
    await HomeWidget.saveWidgetData<String>(
      'pending_strikes',
      jsonEncode(pending),
    );
    for (final receiver in WidgetService.androidReceivers) {
      await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
    }
  } catch (_) {
    // Best-effort.
  }
}

Future<List<String>> _pendingStrikes() async {
  try {
    final raw = await HomeWidget.getWidgetData<String>('pending_strikes',
        defaultValue: '[]');
    final decoded = jsonDecode(raw ?? '[]');
    if (decoded is List) {
      return decoded.whereType<String>().toList();
    }
  } catch (_) {
    // Fall through to empty.
  }
  return [];
}

/// Applies widget-struck ids (main isolate): completes each known task,
/// skips unknown/deleted ones, clears the outbox, refreshes the widget.
/// Called on startup, foreground resume, and after every sync pull.
Future<void> reconcileWidgetStrikes(
  Future<bool> Function(String id) complete, {
  Future<void> Function()? after,
}) async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    final pending = await _pendingStrikes();
    if (pending.isEmpty) return;
    for (final id in pending) {
      await complete(id);
    }
    await HomeWidget.saveWidgetData<String>('pending_strikes', '[]');
    await after?.call();
  } catch (_) {
    // Best-effort.
  }
}

/// WidgetRef convenience for UI call sites.
Future<void> reconcileWidgetStrikesRef(WidgetRef ref) =>
    reconcileWidgetStrikes(
      ref.read(taskListProvider.notifier).completeById,
      after: () => ref
          .read(widgetServiceProvider)
          .refresh(ref.read(taskListProvider)),
    );

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
