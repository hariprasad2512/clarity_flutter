import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/core/task_model.dart';
import 'package:clarity_flutter/widget/widget_service.dart';

TodoTask _task(String id, String title,
    {DateTime? due, bool done = false, DateTime? created, DateTime? updated}) {
  final now = created ?? DateTime.now();
  return TodoTask(
    id: id,
    title: title,
    dueDate: due,
    isCompleted: done,
    createdAt: now,
    updatedAt: updated ?? now,
  );
}

void main() {
  group('WidgetService.payloadFor (widget v2 contract)', () {
    List<Map<String, String>> listOf(
            Map<String, Object> payload, String key) =>
        (payload[key]! as List).cast<Map<String, String>>();

    test('today/inbox open + struck lists, flagged', () {
      final now = DateTime.now();
      final tasks = [
        _task('done-today', 'Did already',
            done: true, updated: now.subtract(const Duration(hours: 1))),
        _task('done-old', 'Did long ago',
            done: true,
            updated: now.subtract(const Duration(days: 2))),
        _task('overdue', 'Overdue bill',
            due: now.subtract(const Duration(days: 1))),
        _task('today', 'Call mom', due: now),
        _task('future', 'Next week',
            due: now.add(const Duration(days: 7))),
        _task('plain', 'No date'),
        _task('extra-0', 'Extra 0', due: now),
        _task('extra-1', 'Extra 1', due: now),
      ];
      final payload = WidgetService.payloadFor(tasks);
      final todayOpen = listOf(payload, 'today_open');
      final inboxOpen = listOf(payload, 'inbox_open');
      final struck = listOf(payload, 'struck');

      // Struck = completed today only.
      expect(struck.map((r) => r['title']), ['Did already']);
      expect(struck.single['done'], '1');
      // Overdue flagged for red paint.
      expect(
        todayOpen
            .firstWhere((r) => r['title'] == 'Overdue bill')['overdue'],
        '1',
      );
      expect(
        todayOpen
            .firstWhere((r) => r['title'] == 'Call mom')['overdue'],
        '',
      );
      // Today-open excludes undated/future/done; inbox carries all open.
      expect(todayOpen.map((r) => r['title']),
          containsAll(['Overdue bill', 'Call mom']));
      expect(todayOpen.map((r) => r['title']), isNot(contains('No date')));
      expect(inboxOpen.map((r) => r['title']), contains('Next week'));
      // Counts feed the header badges (uncapped totals).
      expect(payload['today_count'], 4); // overdue + today + 2 extras
      expect(payload['inbox_count'], 6); // all open incl. dated ones
    });

    test('struck reserve: done rows always survive the cap', () {
      final now = DateTime.now();
      final tasks = [
        _task('done-1', 'Struck one',
            done: true, updated: now.subtract(const Duration(minutes: 5))),
        _task('done-2', 'Struck two',
            done: true, updated: now.subtract(const Duration(minutes: 10))),
        for (var i = 0; i < 10; i++)
          _task('open-$i', 'Open $i', due: now),
      ];
      final payload = WidgetService.payloadFor(tasks);
      // Uncapped lists ship whole; Kotlin reserves struck space per size.
      expect(listOf(payload, 'struck'), hasLength(2));
      expect(listOf(payload, 'today_open'), hasLength(10));
    });

    test('empty input → empty lists, zero counts', () {
      final payload = WidgetService.payloadFor([]);
      expect(payload['today_open'], isEmpty);
      expect(payload['inbox_open'], isEmpty);
      expect(payload['struck'], isEmpty);
      expect(payload['today_count'], 0);
      expect(payload['inbox_count'], 0);
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
