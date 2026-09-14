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
    test('today/inbox lists, capped, flagged', () {
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
      final today =
          (payload['today']! as List).cast<Map<String, String>>();
      final inbox =
          (payload['inbox']! as List).cast<Map<String, String>>();

      // Short fixture fits uncapped: 4 open + 1 struck.
      expect(today.length, 5);
      // Done-today lingers struck; long-ago done is gone.
      expect(today.map((r) => r['title']), contains('Did already'));
      expect(today.map((r) => r['title']), isNot(contains('Did long ago')));
      expect(
        today.firstWhere((r) => r['title'] == 'Did already')['done'],
        '1',
      );
      // Overdue flagged for red paint.
      expect(
        today.firstWhere((r) => r['title'] == 'Overdue bill')['overdue'],
        '1',
      );
      expect(
        today.firstWhere((r) => r['title'] == 'Call mom')['overdue'],
        '',
      );
      // Inbox carries dated + future rows (undated sorts last per
      // sortForDisplay, so it caps out here — covered by model tests).
      expect(inbox.map((r) => r['title']), contains('Next week'));
      expect(inbox.map((r) => r['title']), contains('Did already'));
      expect(inbox.map((r) => r['title']), isNot(contains('Did long ago')));
      // Counts feed the header badges (uncapped totals).
      expect(payload['today_count'], 4); // overdue + today + 2 extras
      expect(payload['inbox_count'], 6); // all open incl. dated ones
    });

    test('cap reserves struck rows first', () {
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
      final today =
          (payload['today']! as List).cast<Map<String, String>>();
      expect(today.length, WidgetService.maxRows);
      // Both struck rows survive the cap (4 open + 2 struck).
      expect(today.where((r) => r['done'] == '1'), hasLength(2));
      expect(today.map((r) => r['title']), contains('Struck one'));
    });

    test('empty input → empty lists, zero counts', () {
      final payload = WidgetService.payloadFor([]);
      expect(payload['today'], isEmpty);
      expect(payload['inbox'], isEmpty);
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
