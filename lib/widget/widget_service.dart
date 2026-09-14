import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../core/date_parser.dart';
import '../core/task_model.dart';

/// Home-screen widget data bridge (Android Glance in Phase 5; iOS WidgetKit
/// deferred — needs a paid Apple Developer account).
///
/// Mirrors the native widget contract (ClarityWidget): incomplete
/// Today/overdue tasks first, max 6. Taps use deep links handled in the
/// main isolate (`widgetClicked`): circle → toggle + stay current,
/// row/background → open Today. The widget never touches Hive directly
/// (single-isolate box locks) — it renders prefs JSON written here.
class WidgetService {
  /// Fully-qualified Glance receiver (must match AndroidManifest).
  static const androidReceiver = 'com.harry.Clarity.ClarityWidgetReceiver';

  /// Max rows, mirroring the native widget's cap.
  static const maxRows = 6;

  static String toggleUri(String taskId) =>
      'com.harry.Clarity://widget-toggle?id=$taskId';
  static const String todayUri = 'com.harry.Clarity://today';

  /// Pure payload builder (unit-tested): open Today/overdue tasks,
  /// display-sorted, capped — the exact rows the widget renders.
  static List<Map<String, String>> payloadFor(List<TodoTask> tasks) {
    final open = tasks.where((t) => t.isDueTodayOrOverdue).toList()
      ..sort(TodoTask.sortForDisplay);
    return [
      for (final t in open.take(maxRows))
        {
          'id': t.id,
          'title': t.title,
          'due': t.dueDate == null
              ? ''
              : DateParser.displayString(t.dueDate!),
        },
    ];
  }

  /// Extracts a toggle target from a widget tap URI. Null = not ours.
  /// NOTE: [Uri.parse] lowercases scheme+host, so compare case-insensitively
  /// (the canonical `com.harry.Clarity` scheme keeps its case on the wire
  /// for Android/iOS matching).
  static String? parseToggleId(Uri uri) {
    if (uri.scheme.toLowerCase() != 'com.harry.clarity') return null;
    if (uri.host.toLowerCase() != 'widget-toggle') return null;
    final id = uri.queryParameters['id'];
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Writes prefs JSON + asks the OS to re-render. Android-only in
  /// Phase 5; safe no-op elsewhere and in tests. Best-effort throughout.
  Future<void> refresh(List<TodoTask> tasks) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final payload = payloadFor(tasks);
      await HomeWidget.saveWidgetData<String>(
        'tasks_json',
        jsonEncode(payload),
      );
      await HomeWidget.saveWidgetData<int>(
        'today_count',
        payload.length,
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: androidReceiver,
      );
      // Rollover: re-render at next midnight so "Today" stays correct.
      final now = DateTime.now();
      final midnight =
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      await HomeWidget.scheduleWidgetUpdates([midnight]);
    } catch (_) {
      // Best-effort: widget must never break the app.
    }
  }
}

final widgetServiceProvider =
    Provider<WidgetService>((ref) => WidgetService());
