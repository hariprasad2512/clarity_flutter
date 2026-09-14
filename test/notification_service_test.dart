import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/core/task_model.dart';
import 'package:clarity_flutter/notifications/notification_service.dart';

TodoTask _task({DateTime? due, bool done = false}) {
  final now = DateTime.now();
  return TodoTask(
    id: 'id-${now.microsecondsSinceEpoch}',
    title: 't',
    dueDate: due,
    isCompleted: done,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('NotificationService.shouldSchedule (native guard parity)', () {
    test('schedules incomplete future tasks only', () {
      final now = DateTime.now();
      expect(
        NotificationService.shouldSchedule(
          _task(due: now.add(const Duration(minutes: 5))),
          now,
        ),
        isTrue,
      );
      // Completed, undated, past, and exactly-now are never scheduled.
      expect(
        NotificationService.shouldSchedule(
          _task(due: now.add(const Duration(minutes: 5)), done: true),
          now,
        ),
        isFalse,
      );
      expect(NotificationService.shouldSchedule(_task(), now), isFalse);
      expect(
        NotificationService.shouldSchedule(
          _task(due: now.subtract(const Duration(minutes: 1))),
          now,
        ),
        isFalse,
      );
      expect(NotificationService.shouldSchedule(_task(due: now), now), isFalse);
    });
  });

  group('NotificationService.snoozedDate', () {
    test('pushes due date out by the configured delay', () {
      final now = DateTime(2026, 9, 14, 12, 0);
      expect(
        NotificationService.snoozedDate(now, 60),
        DateTime(2026, 9, 14, 13, 0),
      );
      expect(
        NotificationService.snoozedDate(now, 15),
        DateTime(2026, 9, 14, 12, 15),
      );
    });
  });

  group('NotificationService.snoozeLabel (native parity)', () {
    test('matches native label strings', () {
      expect(NotificationService.snoozeLabel(15), 'Remind me in 15 min');
      expect(NotificationService.snoozeLabel(30), 'Remind me in 30 min');
      expect(NotificationService.snoozeLabel(60), 'Remind me in 1 hour');
      expect(NotificationService.snoozeLabel(120), 'Remind me in 2 hours');
      expect(NotificationService.snoozeLabel(180), 'Remind me in 3 hours');
      expect(NotificationService.snoozeLabel(90), 'Remind me in 1h 30m');
    });
  });

  group('NotificationService.notificationIdFor', () {
    test('is deterministic, non-negative 31-bit', () {
      const id = 'some-task-uuid';
      final a = NotificationService.notificationIdFor(id);
      final b = NotificationService.notificationIdFor(id);
      expect(a, b);
      expect(a, greaterThanOrEqualTo(0));
      expect(a, lessThan(0x80000000));
    });
  });

  group('action/category contract (AGENTS §7)', () {
    test('IDs match the native contract', () {
      expect(NotificationService.categoryId, 'CLARITY_TASK_DUE');
      expect(NotificationService.markDoneActionId, 'CLARITY_MARK_DONE');
      expect(NotificationService.snoozeActionId, 'CLARITY_SNOOZE');
    });
  });
}
