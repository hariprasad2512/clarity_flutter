import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/core/task_model.dart';

TodoTask _task({DateTime? due, DateTime? created, bool done = false}) {
  final now = DateTime.now();
  return TodoTask(
    id: 'id-${created?.microsecondsSinceEpoch ?? now.microsecondsSinceEpoch}-${due?.day}',
    title: 't',
    dueDate: due,
    isCompleted: done,
    createdAt: created ?? now,
    updatedAt: created ?? now,
  );
}

void main() {
  group('TodoTask.sortForDisplay', () {
    test('earliest due first, undated last, ties by createdAt', () {
      final now = DateTime.now();
      final undated = _task(created: now);
      final late =
          _task(due: now.add(const Duration(days: 2)), created: now);
      final early =
          _task(due: now.add(const Duration(days: 1)), created: now);
      final list = [undated, late, early]..sort(TodoTask.sortForDisplay);
      expect(list, [early, late, undated]);
    });
  });

  group('TodoTask.isDueTodayOrOverdue', () {
    test('today and overdue count, future/completed/undated do not', () {
      final now = DateTime.now();
      expect(_task(due: now).isDueTodayOrOverdue, isTrue);
      expect(
        _task(due: now.subtract(const Duration(days: 1)))
            .isDueTodayOrOverdue,
        isTrue,
      );
      expect(
        _task(due: now.add(const Duration(days: 1)))
            .isDueTodayOrOverdue,
        isFalse,
      );
      expect(_task(due: now, done: true).isDueTodayOrOverdue, isFalse);
      expect(_task().isDueTodayOrOverdue, isFalse);
    });
  });

  group('TodoTask.touch', () {
    test('stamps updatedAt and needsSync', () async {
      final t = _task()..needsSync = false;
      final before = t.updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      t.touch();
      expect(t.needsSync, isTrue);
      expect(t.updatedAt.isAfter(before), isTrue);
    });
  });

  group('wire mapping (§3 contract)', () {
    test('toServerRow/fromServerRow round-trips', () {
      final original = TodoTask.create(
        title: 'Pay rent',
        dueDate: DateTime(2026, 9, 15, 17, 0),
      );
      final row = original.toServerRow('user-123');
      expect(row['id'], original.id);
      expect(row['user_id'], 'user-123');
      expect(row['title'], 'Pay rent');
      expect(row['is_completed'], isFalse);
      expect(row['due_at'], isA<String>());
      expect(row['updated_at'], isA<String>());

      final restored = TodoTask.fromServerRow(row);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.needsSync, isFalse);
      expect(
        restored.dueDate?.millisecondsSinceEpoch,
        original.dueDate?.millisecondsSinceEpoch,
      );
    });

    test('fromServerRow tolerates null dates', () {
      final restored = TodoTask.fromServerRow({
        'id': 'x',
        'title': 'y',
        'due_at': null,
        'is_completed': false,
        'created_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      expect(restored.dueDate, isNull);
      expect(restored.createdAt, isNotNull);
    });
  });

  group('TodoTask.isOverdue (badge rule: strictly before today)', () {
    test('yesterday counts, today and tomorrow do not', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(_task(due: today.subtract(const Duration(days: 1))).isOverdue,
          isTrue);
      expect(_task(due: today).isOverdue, isFalse);
      expect(
          _task(due: today.add(const Duration(days: 1))).isOverdue, isFalse);
    });

    test('completed, undated and late-today tasks never count', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(
          _task(due: today.subtract(const Duration(days: 1)), done: true)
              .isOverdue,
          isFalse);
      expect(_task().isOverdue, isFalse);
      // 23:59 today is Today-tab territory, not overdue.
      expect(
          _task(
                  due: today.add(
                      const Duration(hours: 23, minutes: 59)))
              .isOverdue,
          isFalse);
    });
  });
}
