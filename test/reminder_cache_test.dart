import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/notifications/reminder_cache.dart';

void main() {
  group('ReminderCache encode/decode', () {
    test('round-trips entries', () {
      final entries = [
        const ReminderEntry(
          id: 'a',
          title: 'Buy milk',
          dueMs: 123,
          snoozeMinutes: 15,
        ),
        const ReminderEntry(
          id: 'b',
          title: 'Call',
          dueMs: 456,
          snoozeMinutes: 60,
        ),
      ];
      final decoded = ReminderCache.decode(ReminderCache.encode(entries));
      expect(decoded.length, 2);
      expect(decoded.first.id, 'a');
      expect(decoded.first.snoozeMinutes, 15);
    });

    test('drops malformed input', () {
      expect(ReminderCache.decode(null), isEmpty);
      expect(ReminderCache.decode(''), isEmpty);
      expect(ReminderCache.decode('not-json'), isEmpty);
      expect(ReminderCache.decode('{"a":1}'), isEmpty);
      expect(
        ReminderCache.decode('[{"id":"","title":"x","dueMs":1}]'),
        isEmpty,
      );
    });

    test('defaults bad snooze to 60', () {
      final decoded = ReminderCache.decode(
        '[{"id":"a","title":"t","dueMs":99,"snooze":-5}]',
      );
      expect(decoded.single.snoozeMinutes, 60);
    });
  });

  group('ReminderCache filtering', () {
    test('futureOnly drops past dues', () {
      final entries = [
        const ReminderEntry(id: 'past', title: 'p', dueMs: 100, snoozeMinutes: 60),
        const ReminderEntry(id: 'now', title: 'n', dueMs: 200, snoozeMinutes: 60),
        const ReminderEntry(id: 'fut', title: 'f', dueMs: 300, snoozeMinutes: 60),
      ];
      final out = ReminderCache.futureOnly(entries, 200);
      expect(out.map((e) => e.id), ['fut']);
    });

    test('upsert replaces same id', () {
      const a1 = ReminderEntry(id: 'a', title: 'old', dueMs: 1, snoozeMinutes: 60);
      const a2 = ReminderEntry(id: 'a', title: 'new', dueMs: 2, snoozeMinutes: 15);
      const b = ReminderEntry(id: 'b', title: 'b', dueMs: 3, snoozeMinutes: 60);
      final out = ReminderCache.upsert([a1, b], a2);
      expect(out.length, 2);
      expect(out.last.title, 'new');
    });

    test('remove drops id', () {
      const a = ReminderEntry(id: 'a', title: 'a', dueMs: 1, snoozeMinutes: 60);
      const b = ReminderEntry(id: 'b', title: 'b', dueMs: 2, snoozeMinutes: 60);
      expect(ReminderCache.remove([a, b], 'a').map((e) => e.id), ['b']);
    });
  });
}
