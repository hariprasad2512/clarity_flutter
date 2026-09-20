import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop.dart';

/// Owns the floating Quick Add window: summon-or-focus on hotkey/tray/
/// button, and the submit payload contract with the main isolate.
///
/// The panel is a transient sub-window (created on demand, destroyed on
/// submit/dismiss — no idle cost, and stacking is structurally impossible).
class QuickAddHost {
  WindowController? _sub;
  bool _creating = false;

  /// Main window's controller id (learned at startup). Encoded into the
  /// panel's launch arguments so it can submit back without discovery.
  String? mainWindowId;

  /// Show the panel, focusing it if already open. Safe no-op off-desktop.
  /// Creation is serialized: concurrent summons (e.g. hotkey repeats
  /// during launch) collapse onto the single in-flight window.
  /// Returns true when the panel is up; false when creation failed (or
  /// off-desktop) so callers can fall back to the in-window composer
  /// instead of failing silently.
  Future<bool> summon() async {
    if (!isDesktopApp || _creating) return false;
    final existing = _sub;
    if (existing != null) {
      try {
        await existing.show();
        await existing.invokeMethod('window_focus');
        return true;
      } catch (_) {
        _sub = null; // dead window — recreate below
      }
    }
    _creating = true;
    try {
      _sub = await WindowController.create(
        WindowConfiguration(arguments: quickAddArguments(mainWindowId)),
      );
      await _sub!.show();
      return true;
    } catch (e) {
      // Visible in debug runs: a dead hotkey/tray item is worse silent.
      assert(() {
        debugPrint('Clarity Quick Add panel failed: $e');
        return true;
      }());
      _sub = null;
      return false;
    } finally {
      _creating = false;
    }
  }
}

final quickAddHostProvider =
    Provider<QuickAddHost>((ref) => QuickAddHost());

/// Launch arguments for the panel, carrying the main window id for the
/// submit trip back. [mainWindowId] is null only if summon runs before
/// startup wiring (never in practice).
String quickAddArguments(String? mainWindowId) =>
    mainWindowId == null ? 'quick_add' : 'quick_add:$mainWindowId';

/// Splits launch arguments into (isPanel, mainWindowId).
({bool isPanel, String? mainWindowId}) parseWindowArguments(String args) {
  if (args == 'quick_add') return (isPanel: true, mainWindowId: null);
  if (args.startsWith('quick_add:')) {
    return (isPanel: true, mainWindowId: args.substring('quick_add:'.length));
  }
  return (isPanel: false, mainWindowId: null);
}

/// Submit payload from the panel: `{text, dueMillis?}`.
/// Returns null when malformed (main isolate ignores it).
({String text, DateTime? due})? parseQuickAddPayload(Object? args) {
  if (args is! Map) return null;
  final text = args['text'];
  if (text is! String || text.trim().isEmpty) return null;
  DateTime? due;
  final millis = args['dueMillis'];
  if (millis is int) {
    due = DateTime.fromMillisecondsSinceEpoch(millis);
  }
  return (text: text, due: due);
}
