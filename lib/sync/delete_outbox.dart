import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Pending hard-delete outbox (delete propagation without tombstones).
///
/// Swipe-delete removes the row locally immediately, but the server row
/// must also go — otherwise the next pull resurrects it on every device.
/// IDs land here at delete time and [SyncEngine] flushes them via
/// `TaskRemote.deleteByIds` during the push phase (before upserts).
/// Failures stay queued and retry on the next round; server rows whose
/// ID is still queued are shielded from the merge so a retrying delete
/// can never self-resurrect.
///
/// Pure codec below is unit-tested; prefs I/O is best-effort.
abstract final class DeleteOutbox {
  static const prefsKey = 'pending_task_deletes';

  static String encode(Set<String> ids) =>
      jsonEncode(ids.where((id) => id.isNotEmpty).toList());

  static Set<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return {
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      };
    } catch (_) {
      return {};
    }
  }
}

/// Reads the queued delete IDs. Never throws.
Future<Set<String>> loadDeleteOutbox([SharedPreferences? prefs]) async {
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    return DeleteOutbox.decode(p.getString(DeleteOutbox.prefsKey));
  } catch (_) {
    return {};
  }
}

/// Replaces the queued delete IDs. Never throws.
Future<void> saveDeleteOutbox(
  Set<String> ids, [
  SharedPreferences? prefs,
]) async {
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(DeleteOutbox.prefsKey, DeleteOutbox.encode(ids));
  } catch (_) {
    // Best-effort.
  }
}
