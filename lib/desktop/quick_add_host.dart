import 'dart:async';

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
  DateTime? _createdAt;
  bool _creating = false;
  DateTime? _lastSummon;

  /// Channel methods shared with the panel isolate (see quick_add_window.dart)
  /// and the main-window handler in main.dart.
  static const submitMethod = 'quick_add_submit';
  static const closingMethod = 'quick_add_closing';
  static const pingMethod = 'window_ping';
  static const focusMethod = 'window_focus';

  /// Minimum gap between summons. Hotkey auto-repeat + near-simultaneous
  /// tray/button/hotkey presses must not stack panels.
  static const summonDebounce = Duration(milliseconds: 500);

  /// Grace period after creation during which a failed ping means "still
  /// booting", not "dead". The panel isolate takes ~1-3s before it answers;
  /// treating that as death spawns a replacement per keypress (the
  /// multi-spotlight bug). Must exceed [pingTimeout] with margin.
  static const bootGrace = Duration(seconds: 5);

  /// Upper bound for one panel ping. The channel has no reply until the
  /// panel registers its handler, so never wait unboundedly.
  static const pingTimeout = Duration(seconds: 1);

  /// Main window's controller id (learned at startup). Encoded into the
  /// panel's launch arguments so it can submit back without discovery.
  String? mainWindowId;

  /// Called when the panel reports it is closing (or was found dead):
  /// drops the controller so the next summon creates a fresh window instead
  /// of re-showing a destroyed (black) one. The panel closes its own
  /// native window; this plugin version has no remote close/destroy, and
  /// none is needed — the handle is all that lingers.
  void onPanelClosed() {
    _sub = null;
    _createdAt = null;
  }

  /// Show the panel, focusing it if already open. Safe no-op off-desktop.
  /// Creation is serialized: concurrent summons (e.g. hotkey repeats
  /// during launch) collapse onto the single in-flight window.
  /// Returns true when the panel is up; false when creation failed (or
  /// off-desktop) so callers can fall back to the in-window composer
  /// instead of failing silently.
  Future<bool> summon() async {
    if (!isDesktopApp) return false;
    if (_creating) return true; // panel is on its way — don't double up
    final now = DateTime.now();
    if (_lastSummon != null &&
        now.difference(_lastSummon!) < summonDebounce) {
      // Debounced repeat: the panel is either already up or coming up.
      return _sub != null;
    }
    _lastSummon = now;
    final existing = _sub;
    if (existing != null) {
      try {
        // Ping first: show() on a destroyed Windows window resurrects a
        // blank window instead of throwing. Only show a panel proven alive.
        await existing.invokeMethod(pingMethod).timeout(pingTimeout);
        await existing.show();
        await existing.invokeMethod(focusMethod);
        return true;
      } catch (_) {
        final born = _createdAt;
        if (born != null && now.difference(born) < bootGrace) {
          // Still booting (isolate not answering yet) — keep it. It shows
          // itself after its first frame. Creating a replacement here is
          // what stacked one spotlight per keypress.
          try {
            await existing.show();
          } catch (_) {
            // Best-effort: the panel shows itself when ready regardless.
          }
          return true;
        }
        onPanelClosed(); // genuinely dead — recreate below
      }
    }
    _creating = true;
    try {
      final created = await WindowController.create(
        WindowConfiguration(arguments: quickAddArguments(mainWindowId)),
      );
      _sub = created;
      _createdAt = DateTime.now();
      try {
        // Hide until the first frame: the native window is visible from
        // createWindow, before Flutter paints (white/black flash). The
        // panel shows itself from waitUntilReadyToShow when ready.
        await created.hide();
      } catch (_) {
        // Best-effort.
      }
      return true;
    } catch (e) {
      // Visible in debug runs: a dead hotkey/tray item is worse silent.
      assert(() {
        debugPrint('Clarity Quick Add panel failed: $e');
        return true;
      }());
      onPanelClosed();
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
