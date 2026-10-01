import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop.dart';
import 'hotkey_service.dart';

/// Menu-bar / system-tray presence. Port of native `MenuBarExtra`
/// (ClarityApp.swift: Quick Add / Show window / Quit).
///
/// * macOS: template icon (recolored for light/dark), left-click toggles.
/// * Windows: green `.ico`. Linux: 22px PNG.
/// * Close button hides to tray; **Quit** (or Cmd+Q, which macOS routes
///   through close) is the only exit — standard tray-app behavior.
/// Desktop-only; [init] is a safe no-op elsewhere (incl. tests).
class TrayService with TrayListener {
  TrayService({TrayManager? tray, WindowManager? windows})
      : _trayOverride = tray,
        _windowsOverride = windows;

  // Resolved lazily (see HotkeyService): plugin singletons need a binding.
  final TrayManager? _trayOverride;
  final WindowManager? _windowsOverride;
  TrayManager? __tray;
  WindowManager? __windows;
  TrayManager get _tray => __tray ??= _trayOverride ?? trayManager;
  WindowManager get _windows =>
      __windows ??= _windowsOverride ?? windowManager;

  static const quickAddKey = 'quick_add';
  static const todayKey = 'show_today';
  static const inboxKey = 'show_inbox';
  static const showKey = 'show';
  static const quitKey = 'quit';

  bool _ready = false;
  bool _quitting = false;
  bool _popupOpen = false;
  int _todayCount = 0;
  int _inboxCount = 0;

  Future<void> Function()? onQuickAdd;
  Future<void> Function()? onShowToday;
  Future<void> Function()? onShowInbox;
  Future<void> Function()? onShow;
  Future<void> Function()? onQuit;

  /// Asset key resolved by the plugin to `data/flutter_assets/<key>`.
  /// Full-color green check everywhere (user choice over monochrome
  /// template — the black template rendered invisibly on dark menu bars).
  static String get iconAsset {
    if (Platform.isWindows) return 'assets/tray/tray_icon.ico';
    if (Platform.isLinux) return 'assets/tray/tray_icon_linux.png';
    return 'assets/tray/tray_icon_color@2x.png';
  }

  static Menu buildMenu({
    required void Function() quickAdd,
    required void Function() showToday,
    required void Function() showInbox,
    required void Function() show,
    required void Function() quit,
    int todayCount = 0,
    int inboxCount = 0,
  }) =>
      Menu(items: [
        MenuItem(
          key: quickAddKey,
          label: 'Quick Add (${HotkeyService.label.replaceFirst('Quick Add  ', '')})',
          onClick: (_) => quickAdd(),
        ),
        MenuItem.separator(),
        MenuItem(
          key: todayKey,
          label: 'Show Today ($todayCount)',
          onClick: (_) => showToday(),
        ),
        MenuItem(
          key: inboxKey,
          label: 'Show Inbox ($inboxCount)',
          onClick: (_) => showInbox(),
        ),
        MenuItem.separator(),
        MenuItem(key: showKey, label: 'Show window', onClick: (_) => show()),
        MenuItem(key: quitKey, label: 'Quit Clarity', onClick: (_) => quit()),
      ]);

  Future<void> init({
    required Future<void> Function() quickAdd,
    required Future<void> Function() showToday,
    required Future<void> Function() showInbox,
    required Future<void> Function() show,
    required Future<void> Function() quit,
    int todayCount = 0,
    int inboxCount = 0,
  }) async {
    if (!isDesktopApp || _ready) return;
    onQuickAdd = quickAdd;
    onShowToday = showToday;
    onShowInbox = showInbox;
    onShow = show;
    onQuit = quit;
    _todayCount = todayCount;
    _inboxCount = inboxCount;
    try {
      _tray.addListener(this);
      await _tray.setIcon(iconAsset);
      await _tray.setToolTip('Clarity — minimal todo');
      await _applyMenu();
      await _windows.setPreventClose(true);
      _windows.addListener(_WindowCloseListener(() async {
        if (_quitting) return;
        await _windows.hide();
      }));
      _ready = true;
    } catch (e) {
      // Visible in debug runs — a silent tray is worse than a log line.
      debugPrint('Clarity tray init failed: $e');
      _ready = false;
    }
  }

  Menu _currentMenu() => buildMenu(
        quickAdd: () => onQuickAdd?.call(),
        showToday: () => onShowToday?.call(),
        showInbox: () => onShowInbox?.call(),
        show: () => onShow?.call(),
        quit: () => onQuit?.call(),
        todayCount: _todayCount,
        inboxCount: _inboxCount,
      );

  Future<void> _applyMenu() => _tray.setContextMenu(_currentMenu());

  /// Live Today/Inbox counts in the menu (Today (n) / Inbox (n)).
  /// No-op until [init] succeeds and in tests; failures never propagate.
  Future<void> refreshMenu({required int todayCount, required int inboxCount}) async {
    if (!_ready) return;
    _todayCount = todayCount;
    _inboxCount = inboxCount;
    try {
      await _applyMenu();
    } catch (e) {
      debugPrint('Clarity tray menu refresh failed: $e');
    }
  }

  /// True quit: allow close, then destroy. Called ONLY from the tray
  /// menu's Quit item (never from icon clicks — those only pop the menu
  /// on macOS or toggle visibility elsewhere). Re-entrancy guarded so a
  /// double-click on Quit can't wedge the shutdown path.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await _windows.setPreventClose(false);
      await _windows.destroy();
    } catch (e) {
      debugPrint('Clarity tray quit failed: $e');
    }
  }

  /// macOS menu popup, serialized: overlapping left/right clicks used to
  /// race `popUpContextMenu` and could tear down the menu (seen as the
  /// app "quitting" when tapping the menu-bar icon). Never touches the
  /// window or the quit path.
  Future<void> _popUpMenu() async {
    if (_popupOpen) return;
    _popupOpen = true;
    try {
      await _tray.popUpContextMenu();
    } catch (e) {
      debugPrint('Clarity tray popup failed: $e');
    } finally {
      _popupOpen = false;
    }
  }

  @override
  void onTrayIconMouseDown() {
    // macOS parity with native MenuBarExtra: click shows the menu.
    // Windows/Linux keep click-to-toggle (platform convention).
    () async {
      try {
        if (Platform.isMacOS) {
          await _popUpMenu();
          return;
        }
        if (await _windows.isVisible()) {
          await _windows.hide();
        } else {
          await _windows.show();
          await _windows.focus();
        }
      } catch (e) {
        debugPrint('Clarity tray click failed: $e');
      }
    }();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Right-click always pops the menu (macOS convention; harmless
    // elsewhere). Previously unhandled — the OS default could dismiss
    // the icon interaction and look like a quit.
    _popUpMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case quickAddKey:
        onQuickAdd?.call();
      case todayKey:
        onShowToday?.call();
      case inboxKey:
        onShowInbox?.call();
      case showKey:
        onShow?.call();
      case quitKey:
        onQuit?.call();
    }
  }

  Future<void> dispose() async {
    if (!_ready) return;
    try {
      _tray.removeListener(this);
    } catch (_) {
      // Best-effort.
    }
    _ready = false;
  }
}

class _WindowCloseListener extends WindowListener {
  _WindowCloseListener(this.onClose);
  final Future<void> Function() onClose;

  @override
  void onWindowClose() => onClose();
}

final trayServiceProvider =
    Provider<TrayService>((ref) => TrayService());
