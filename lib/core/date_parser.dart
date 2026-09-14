import 'package:intl/intl.dart';

/// Natural-language date extraction. Port of native `DateParser`
/// (Shared/DateParser.swift). No NSDataDetector on Flutter, so this is a
/// regex-based parser covering the documented cases:
///
/// "Pay rent tomorrow at 5pm", "Commit repo at 6.20 pm" (dotted time),
/// "Call mom tomorrow", weekday names, tonight/weekend/next week,
/// "in 2 hours", "Sep 12", ISO dates.
///
/// Rules mirrored from native:
/// * date-only matches default to 23:59
/// * detected date words are stripped Todoist-style; if stripping would
///   leave nothing ("tomorrow"), the original text is kept
/// * trailing prepositions ("repo at") are stripped
class DateParser {
  static final _dottedTime = RegExp(
    r'(\b\d{1,2})\.(\d{2})(?=\s*(?:am|pm|a\.m\.|p\.m\.))',
    caseSensitive: false,
  );
  static final _ws = RegExp(r'\s+');
  static final _trailingPrep =
      RegExp(r'\s+(at|on|by|for|in)$', caseSensitive: false);

  static const _months = {
    'jan': 1, 'january': 1,
    'feb': 2, 'february': 2,
    'mar': 3, 'march': 3,
    'apr': 4, 'april': 4,
    'may': 5,
    'jun': 6, 'june': 6,
    'jul': 7, 'july': 7,
    'aug': 8, 'august': 8,
    'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10,
    'nov': 11, 'november': 11,
    'dec': 12, 'december': 12,
  };

  static const _weekdays = {
    'monday': 1, 'mon': 1,
    'tuesday': 2, 'tue': 2, 'tues': 2,
    'wednesday': 3, 'wed': 3,
    'thursday': 4, 'thu': 4, 'thur': 4, 'thurs': 4,
    'friday': 5, 'fri': 5,
    'saturday': 6, 'sat': 6,
    'sunday': 7, 'sun': 7,
  };

  /// "Buy groceries tomorrow at 5 PM" -> Date. Date-only -> 23:59.
  static DateTime? extractDate(String text) => extractDateAndCleaned(text).date;

  /// Returns the detected date plus the title with date words stripped.
  static ({DateTime? date, String title}) extractDateAndCleaned(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return (date: null, title: trimmed);
    final normalized = _normalizeDottedTime(trimmed);
    final lower = normalized.toLowerCase();

    final now = DateTime.now();
    DateTime? day;
    final List<_Span> consumed = [];

    // -- day reference -------------------------------------------------------
    final dayMatch = _findDay(lower, now);
    if (dayMatch != null) {
      day = dayMatch.date;
      consumed.add(dayMatch.span);
      if (dayMatch.exact) {
        // Relative times ("in 2 hours") already carry their time.
        return _strip(normalized, trimmed, day, consumed);
      }
    } else {
      // Time-only ("6.20 pm", "at 5") implies today — like NSDataDetector.
      final timeOnly = _findTime(lower);
      if (timeOnly == null) return (date: null, title: trimmed);
      day = DateTime(
          now.year, now.month, now.day, timeOnly.hour, timeOnly.minute);
      consumed.add(timeOnly.span);
      return _strip(normalized, trimmed, day, consumed);
    }

    // -- time reference (search whole string; "at 5pm" etc.) -----------------
    final time = _findTime(lower);
    if (time != null) {
      consumed.add(time.span);
      day = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    } else {
      day = DateTime(day.year, day.month, day.day, 23, 59);
    }

    return _strip(normalized, trimmed, day, consumed);
  }

  /// Removes consumed spans, collapses whitespace, strips a dangling
  /// preposition. Empty result keeps the original text (native behavior).
  static ({DateTime? date, String title}) _strip(
    String normalized,
    String trimmed,
    DateTime date,
    List<_Span> consumed,
  ) {
    var cleaned = normalized;
    final sorted = [...consumed]..sort((a, b) => b.start.compareTo(a.start));
    for (final s in sorted) {
      cleaned = '${cleaned.substring(0, s.start)} ${cleaned.substring(s.end)}';
    }
    cleaned = _collapse(cleaned);
    cleaned = cleaned.replaceAll(_trailingPrep, '');
    cleaned = _collapse(cleaned);
    if (cleaned.isEmpty) return (date: date, title: trimmed);
    return (date: date, title: cleaned);
  }

  // -- day patterns ----------------------------------------------------------

  static ({DateTime date, _Span span, bool exact})? _findDay(
      String lower, DateTime now) {
    DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
    _R dayOnly(DateTime d, Match m) =>
        (date: dayStart(d), span: _Span(m.start, m.end), exact: false);
    _R exact(DateTime d, Match m) =>
        (date: d, span: _Span(m.start, m.end), exact: true);

    Match? m;
    // tonight / today
    m = RegExp(r'\b(tonight|today)\b').firstMatch(lower);
    if (m != null) {
      return dayOnly(now, m);
    }
    // tomorrow / tmw / tmrw
    m = RegExp(r'\b(tomorrow|tmrw|tmw)\b').firstMatch(lower);
    if (m != null) {
      final d = now.add(const Duration(days: 1));
      return dayOnly(d, m);
    }
    // yesterday (overdue styling exercises this path)
    m = RegExp(r'\byesterday\b').firstMatch(lower);
    if (m != null) {
      return dayOnly(now.subtract(const Duration(days: 1)), m);
    }
    // weekend -> upcoming Saturday (today if Saturday, like native)
    m = RegExp(r'\b(weekend|this weekend)\b').firstMatch(lower);
    if (m != null) {
      // Dart weekday: Mon=1..Sun=7, Saturday=6
      final offset = (6 - now.weekday + 7) % 7;
      final d = now.add(Duration(days: offset));
      return dayOnly(d, m);
    }
    // next week -> next Monday
    m = RegExp(r'\bnext week\b').firstMatch(lower);
    if (m != null) {
      var offset = (8 - now.weekday) % 7;
      if (offset == 0) offset = 7;
      final d = now.add(Duration(days: offset));
      return dayOnly(d, m);
    }
    // in N days/weeks/hours/minutes, "in an hour"
    m = RegExp(r'\bin\s+(an?\s+hour|(\d+)\s*(min(?:ute)?s?|hour?s?|day?s?|week?s?))\b')
        .firstMatch(lower);
    if (m != null) {
      final inner = m.group(1)!;
      if (inner.startsWith('an') || inner.startsWith('a ')) {
        return exact(now.add(const Duration(hours: 1)), m);
      }
      final count = int.parse(RegExp(r'\d+').firstMatch(inner)!.group(0)!);
      // NOTE: `inner` starts with the number ("2 hours"), so match the
      // unit keyword anywhere inside it.
      if (inner.contains('min')) {
        return exact(now.add(Duration(minutes: count)), m);
      }
      if (inner.contains('hour')) {
        return exact(now.add(Duration(hours: count)), m);
      }
      final d = inner.contains('day')
          ? now.add(Duration(days: count))
          : now.add(Duration(days: count * 7));
      return dayOnly(d, m);
    }
    // weekday names -> upcoming, including today
    m = RegExp(
            r'\b(monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat|sunday|sun)\b')
        .firstMatch(lower);
    if (m != null) {
      final target = _weekdays[m.group(1)!]!;
      final offset = (target - now.weekday + 7) % 7;
      final d = now.add(Duration(days: offset));
      return dayOnly(d, m);
    }
    // ISO: 2026-09-20
    m = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(lower);
    if (m != null) {
      final d = DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
      return dayOnly(d, m);
    }
    // numeric: 12/09, 12-09 (day/month; year = this or next)
    m = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})\b').firstMatch(lower);
    if (m != null) {
      var d = DateTime(now.year, int.parse(m.group(2)!), int.parse(m.group(1)!));
      if (d.isBefore(dayStart(now))) {
        d = DateTime(now.year + 1, d.month, d.day);
      }
      if (d.month <= 12 && d.day <= 31) {
        return dayOnly(d, m);
      }
    }
    // "Sep 12" / "12 Sep" / "September 12"
    m = RegExp(
            r'\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t)?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?\b')
        .firstMatch(lower);
    if (m == null) {
      m = RegExp(
              r'\b(\d{1,2})(?:st|nd|rd|th)?\s+of\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t)?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b')
          .firstMatch(lower);
      if (m != null) {
        final month = _months[m.group(2)!]!;
        final dayNum = int.parse(m.group(1)!);
        var d = DateTime(now.year, month, dayNum);
        if (d.isBefore(dayStart(now))) d = DateTime(now.year + 1, month, dayNum);
        return dayOnly(d, m);
      }
    } else {
      final month = _months[m.group(1)!]!;
      final dayNum = int.parse(m.group(2)!);
      var d = DateTime(now.year, month, dayNum);
      if (d.isBefore(dayStart(now))) d = DateTime(now.year + 1, month, dayNum);
      return dayOnly(d, m);
    }
    return null;
  }

  // -- time patterns ---------------------------------------------------------

  static ({int hour, int minute, _Span span})? _findTime(String lower) {
    Match? m;
    // "at 5pm", "at 6:20 pm", "5pm", "6:20pm", "17:30", "at 17"
    m = RegExp(
      r'(?:\bat\s+)?\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (m != null) {
      var hour = int.parse(m.group(1)!);
      final minute = m.group(2) != null ? int.parse(m.group(2)!) : 0;
      final pm = m.group(3)!.toLowerCase().startsWith('p');
      if (pm && hour < 12) hour += 12;
      if (!pm && hour == 12) hour = 0;
      if (hour <= 23 && minute <= 59) {
        return (hour: hour, minute: minute, span: _Span(m.start, m.end));
      }
    }
    // 24h "17:30" / "at 17:30"
    m = RegExp(r'(?:\bat\s+)?\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(lower);
    if (m != null) {
      return (
        hour: int.parse(m.group(1)!),
        minute: int.parse(m.group(2)!),
        span: _Span(m.start, m.end),
      );
    }
    // "at 17" (bare hour after 'at')
    m = RegExp(r'\bat\s+([01]?\d|2[0-3])\b').firstMatch(lower);
    if (m != null) {
      return (
        hour: int.parse(m.group(1)!),
        minute: 0,
        span: _Span(m.start, m.end),
      );
    }
    return null;
  }

  // -- helpers ---------------------------------------------------------------

  static String _normalizeDottedTime(String text) =>
      text.replaceAllMapped(_dottedTime, (m) => '${m.group(1)}:${m.group(2)}');

  static String _collapse(String s) =>
      s.split(_ws).where((w) => w.isNotEmpty).join(' ').trim();

  /// Human-friendly due label: "Today 5:00 PM", "Tomorrow", "Sep 12",
  /// "Overdue". Mirrors `displayString`.
  static String displayString(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final time = DateFormat.jm().format(date);
    if (day == today) return 'Today $time';
    if (day == today.add(const Duration(days: 1))) {
      return 'Tomorrow $time';
    }
    if (date.isBefore(now)) {
      return 'Overdue · ${DateFormat.MMMd().add_jm().format(date)}';
    }
    return DateFormat.MMMd().add_jm().format(date);
  }

  /// Chip labels for the capture bar. Mirrors dayLabel/timeLabel.
  static String dayLabel(DateTime? date) {
    if (date == null) return 'Date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Today';
    if (day == today.add(const Duration(days: 1))) return 'Tmrw';
    return DateFormat('EEE d').format(date);
  }

  static String timeLabel(DateTime? date) {
    if (date == null) return 'Time';
    return DateFormat.jm().format(date);
  }
}

typedef _R = ({DateTime date, _Span span, bool exact});

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}
