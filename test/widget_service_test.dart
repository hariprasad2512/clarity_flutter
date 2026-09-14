import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/core/task_model.dart';
import 'package:clarity_flutter/widget/widget_service.dart';

TodoTask _task(String id, String title,
    {DateTime? due, bool done = false, DateTime? created}) {
  final now = created ?? DateTime.now();
  return TodoTask(
    id: id,
    title: title,
    dueDate: due,
    isCompleted: done,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('WidgetService.payloadFor (native widget parity)', () {
    test('open Today/overdue first, sorted, capped at 6', () {
      final now = DateTime.now();
      final tasks = [
        _task('done', 'Done today',
            due: now, done: true), // completed excluded
        _task('future', 'Next week',
            due: now.add(const Duration(days: 7))), // future excluded
        _task('plain', 'No date'), // undated excluded (not Today)
        _task('overdue', 'Overdue bill',
            due: now.subtract(const Duration(days: 1))),
        _task('today', 'Call mom', due: now),
        for (var i = 0; i < 10; i++)
          _task('extra-$i', 'Extra $i', due: now),
      ];
      final payload = WidgetService.payloadFor(tasks);
      expect(payload, hasLength(WidgetService.maxRows));
      final titles = payload.map((r) => r['title']).toList();
      expect(titles, isNot(contains('Done today')));
      expect(titles, isNot(contains('Next week')));
      expect(titles, isNot(contains('No date')));
      // Overdue first, then today (display sort).
      expect(titles.first, 'Overdue bill');
      for (final row in payload) {
        expect(row.keys, containsAll(['id', 'title', 'due']));
      }
    });

    test('empty input → empty payload', () {
      expect(WidgetService.payloadFor([]), isEmpty);
    });
  });

  group('WidgetService.parseToggleId', () {
    test('accepts widget-toggle URIs, rejects everything else', () {
      expect(
        WidgetService.parseToggleId(
            Uri.parse('com.harry.Clarity://widget-toggle?id=abc-123')),
        'abc-123',
      );
      expect(
        WidgetService.parseToggleId(
            Uri.parse('com.harry.Clarity://today')),
        isNull,
      );
      expect(
        WidgetService.parseToggleId(
            Uri.parse('com.harry.Clarity://widget-toggle')),
        isNull,
      );
      expect(
        WidgetService.parseToggleId(
            Uri.parse('com.harry.Clarity://oauth-callback?code=x')),
        isNull,
      );
      expect(
        WidgetService.parseToggleId(Uri.parse('https://example.com/x')),
        isNull,
      );
    });
  });

  group('widget deep-link contract', () {
    test('toggle/today URIs are well-formed', () {
      final toggle = Uri.parse(WidgetService.toggleUri('abc'));
      // Uri.parse lowercases scheme+host — parseToggleId compensates.
      expect(toggle.scheme, 'com.harry.clarity');
      expect(WidgetService.parseToggleId(toggle), 'abc');
      expect(
        Uri.parse(WidgetService.todayUri).host,
        'today',
      );
    });
  });
}
