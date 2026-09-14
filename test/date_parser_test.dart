import 'package:flutter_test/flutter_test.dart';

import 'package:clarity_flutter/core/date_parser.dart';

void main() {
  DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  group('DateParser.extractDateAndCleaned', () {
    test('parses "tomorrow at 5pm" and strips date words', () {
      final r =
          DateParser.extractDateAndCleaned('Pay rent tomorrow at 5pm');
      expect(r.title, 'Pay rent');
      expect(r.date, isNotNull);
      final tomorrow = dayStart(DateTime.now().add(const Duration(days: 1)));
      expect(
        r.date,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17, 0),
      );
    });

    test('normalizes dotted time "6.20 pm"', () {
      final r = DateParser.extractDateAndCleaned(
          'Commit Clarity repo at 6.20 pm');
      expect(r.title, 'Commit Clarity repo');
      expect(r.date, isNotNull);
      expect(r.date!.hour, 18);
      expect(r.date!.minute, 20);
    });

    test('date-only defaults to 23:59 and strips the word', () {
      final r = DateParser.extractDateAndCleaned('Call mom tomorrow');
      expect(r.title, 'Call mom');
      expect(r.date, isNotNull);
      expect(r.date!.hour, 23);
      expect(r.date!.minute, 59);
    });

    test('keeps original text when stripping would leave nothing', () {
      final r = DateParser.extractDateAndCleaned('tomorrow');
      expect(r.title, 'tomorrow');
      expect(r.date, isNotNull);
    });

    test('returns null date for plain titles', () {
      final r = DateParser.extractDateAndCleaned('Buy milk');
      expect(r.date, isNull);
      expect(r.title, 'Buy milk');
    });

    test('returns null date for blank input', () {
      final r = DateParser.extractDateAndCleaned('   ');
      expect(r.date, isNull);
      expect(r.title, isEmpty);
    });

    test('strips trailing preposition left behind', () {
      final r = DateParser.extractDateAndCleaned('Finish report on Friday');
      expect(r.title, 'Finish report');
      expect(r.date, isNotNull);
      expect(r.date!.weekday, DateTime.friday);
    });

    test('parses "yesterday" for overdue tasks', () {
      final r = DateParser.extractDateAndCleaned('Overdue thing yesterday');
      expect(r.title, 'Overdue thing');
      expect(r.date, isNotNull);
      expect(r.date!.isBefore(DateTime.now()), isTrue);
    });

    test('parses weekday names as upcoming day', () {
      final r = DateParser.extractDateAndCleaned('Dentist Monday 10am');
      expect(r.title, 'Dentist');
      expect(r.date, isNotNull);
      expect(r.date!.weekday, DateTime.monday);
      expect(r.date!.hour, 10);
    });

    test('parses "tonight" as today', () {
      final r = DateParser.extractDateAndCleaned('Gym tonight');
      expect(r.title, 'Gym');
      expect(r.date, isNotNull);
      expect(dayStart(r.date!), dayStart(DateTime.now()));
    });

    test('parses "in 2 hours" as an exact datetime', () {
      final before = DateTime.now();
      final r = DateParser.extractDateAndCleaned('Check oven in 2 hours');
      expect(r.title, 'Check oven');
      expect(r.date, isNotNull);
      expect(
        r.date!.difference(before).inMinutes,
        inInclusiveRange(110, 130),
      );
    });

    test('parses month-day "Sep 12"', () {
      final r = DateParser.extractDateAndCleaned('Report on Sep 12');
      expect(r.title, 'Report');
      expect(r.date, isNotNull);
      expect(r.date!.month, 9);
      expect(r.date!.day, 12);
    });

    test('parses 24h time', () {
      final r = DateParser.extractDateAndCleaned('Standup today 17:30');
      expect(r.title, 'Standup');
      expect(r.date, isNotNull);
      expect(r.date!.hour, 17);
      expect(r.date!.minute, 30);
    });
  });

  group('DateParser.displayString', () {
    test('labels today, tomorrow, overdue and future', () {
      final now = DateTime.now();
      expect(DateParser.displayString(now), startsWith('Today'));
      expect(
        DateParser.displayString(now.add(const Duration(days: 1))),
        startsWith('Tomorrow'),
      );
      expect(
        DateParser.displayString(now.subtract(const Duration(days: 2))),
        startsWith('Overdue'),
      );
      expect(
        DateParser.displayString(now.add(const Duration(days: 10))),
        isNot(startsWith('Today')),
      );
    });

    test('chip labels fall back to Date/Time when null', () {
      expect(DateParser.dayLabel(null), 'Date');
      expect(DateParser.timeLabel(null), 'Time');
    });
  });
}
