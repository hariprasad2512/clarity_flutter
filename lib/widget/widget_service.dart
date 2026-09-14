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
/// Widget v2 contract:
/// * Two switchable lists — Today (open Today/overdue) and Inbox (open
///   incomplete) — toggled from the header without opening the app.
/// * Tasks completed today linger struck (● + dimmed) until midnight
///   instead of vanishing at once. Total rows capped at 6.
/// * Overdue due labels render red.
/// * Taps use deep links handled in the main isolate (`widgetClicked`):
///   circle → toggle, row/background → open. The widget never touches
///   Hive directly (single-isolate box locks) — it renders prefs JSON.
class WidgetService {
  /// Fully-qualified Glance receiver (must match AndroidManifest).
  static const androidReceiver = 'com.harry.Clarity.ClarityWidgetReceiver';

  /// Max rows, mirroring the native widget's cap.
  static const maxRows = 6;

  static const listToday = 'today';
  static const listInbox = 'inbox';

  static String toggleUri(String taskId) =>
      'com.harry.Clarity://widget-toggle?id=$taskId';
  static const String todayUri = 'com.harry.Clarity://today';

  /// Background-only switch URI (handled without opening the app).
  static const String switchUri = 'clarity-widget://switch-list';

  /// Pure payload builder (unit-tested).
  static Map<String, Object> payloadFor(List<TodoTask> tasks) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    Map<String, String> rowOf(TodoTask t, {required bool done}) => {
          'id': t.id,
          'title': t.title,
          'due': t.dueDate == null
              ? ''
              : DateParser.displayString(t.dueDate!),
          'done': done ? '1' : '',
          'overdue': (!done &&
                  t.dueDate != null &&
                  t.dueDate!.isBefore(todayStart))
              ? '1'
              : '',
        };

    final doneToday = tasks
        .where((t) =>
            t.isCompleted &&
            !t.updatedAt.isBefore(todayStart))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    List<Map<String, String>> capped(
      List<TodoTask> open,
      List<TodoTask> done,
    ) {
      // Struck rows reserve space first: a fresh tap must stay visible
      // instead of being capped out by a long open list.
      final room = (maxRows - done.length).clamp(0, maxRows);
      final rows = [
        ...open.take(room).map((t) => rowOf(t, done: false)),
        ...done.map((t) => rowOf(t, done: true)),
      ];
      return rows.take(maxRows).toList();
    }

    final todayOpen = tasks.where((t) => t.isDueTodayOrOverdue).toList()
      ..sort(TodoTask.sortForDisplay);
    final inboxOpen =
        tasks.where((t) => !t.isCompleted).toList()
          ..sort(TodoTask.sortForDisplay);

    final today = capped(todayOpen, doneToday);
    final inbox = capped(inboxOpen, doneToday);
    return {
      'today': today,
      'inbox': inbox,
      'today_count': tasks.where((t) => t.isDueTodayOrOverdue).length,
      'inbox_count': tasks.where((t) => !t.isCompleted).length,
    };
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
  /// Preserves the header's selected list (owned by the background
  /// switch callback).
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
        payload['today_count']! as int,
      );
      await HomeWidget.saveWidgetData<int>(
        'inbox_count',
        payload['inbox_count']! as int,
      );
      await HomeWidget.updateWidget(
        qualifiedAndroidName: androidReceiver,
      );
      // Rollover: re-render at next midnight so "Today" stays correct
      // and struck rows drop off.
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
