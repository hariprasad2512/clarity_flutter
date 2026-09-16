import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Prefs-backed mirror of scheduled due alerts (Android reboot safety net).
///
/// Why this exists: `flutter_local_notifications` persists exact alarms and
/// restores them via `ScheduledNotificationBootReceiver`, but OEMs / Doze /
/// update edge cases can still drop them. This cache lets a background
/// Workmanager task re-schedule known-future reminders without touching
/// Hive (Hive boxes cannot be opened from two isolates — see
/// `NotificationService`). Foreground code is source of truth; the cache
/// is best-effort and pruned of past dues on every write/read.
///
/// Entry shape: `{id, title, dueMs, snooze}`. `dueMs` is local
/// millisecondsSinceEpoch (matches `TodoTask.dueDate` semantics).
class ReminderEntry {
  const ReminderEntry({
    required this.id,
    required this.title,
    required this.dueMs,
    required this.snoozeMinutes,
  });

  final String id;
  final String title;
  final int dueMs;
  final int snoozeMinutes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dueMs': dueMs,
        'snooze': snoozeMinutes,
      };

  static ReminderEntry? fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'];
      final title = json['title'];
      final dueMs = json['dueMs'];
      if (id is! String || id.isEmpty) return null;
      if (title is! String || title.isEmpty) return null;
      if (dueMs is! int) return null;
      final snooze = json['snooze'];
      return ReminderEntry(
        id: id,
        title: title,
        dueMs: dueMs,
        snoozeMinutes: snooze is int && snooze > 0 ? snooze : 60,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Pure encode/decode + filtering (unit-tested, no plugin calls).
abstract final class ReminderCache {
  static const prefsKey = 'pending_reminders';

  static String encode(List<ReminderEntry> entries) =>
      jsonEncode([for (final e in entries) e.toJson()]);

  static List<ReminderEntry> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <ReminderEntry>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final e = ReminderEntry.fromJson(item);
          if (e != null) out.add(e);
        } else if (item is Map) {
          final e = ReminderEntry.fromJson(
            item.map((k, v) => MapEntry(k.toString(), v)),
          );
          if (e != null) out.add(e);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Drops past-due entries relative to [nowMs].
  static List<ReminderEntry> futureOnly(
    List<ReminderEntry> entries,
    int nowMs,
  ) =>
      entries.where((e) => e.dueMs > nowMs).toList();

  static List<ReminderEntry> upsert(
    List<ReminderEntry> entries,
    ReminderEntry entry,
  ) {
    final out = entries.where((e) => e.id != entry.id).toList();
    out.add(entry);
    return out;
  }

  static List<ReminderEntry> remove(
    List<ReminderEntry> entries,
    String id,
  ) =>
      entries.where((e) => e.id != id).toList();
}

/// SharedPreferences I/O. All best-effort (never throws).
Future<List<ReminderEntry>> loadReminderCache([SharedPreferences? prefs]) async {
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    return ReminderCache.decode(p.getString(ReminderCache.prefsKey));
  } catch (_) {
    return const [];
  }
}

Future<void> saveReminderCache(
  List<ReminderEntry> entries, [
  SharedPreferences? prefs,
]) async {
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    final pruned = ReminderCache.futureOnly(
      entries,
      DateTime.now().millisecondsSinceEpoch,
    );
    await p.setString(ReminderCache.prefsKey, ReminderCache.encode(pruned));
  } catch (_) {
    // Best-effort.
  }
}
