import 'dart:io';

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
  static const showKey = 'show';
  static const quitKey = 'quit';

  bool _ready = false;
  bool _quitting = false;

  Future<void> Function()? onQuickAdd;
  Future<void> Function()? onShow;
  Future<void> Function()? onQuit;

  /// Asset key resolved by the plugin to `data/flutter_assets/<key>`.
  static String get iconAsset {
    if (Platform.isWindows) return 'assets/tray/tray_icon.ico';
    if (Platform.isLinux) return 'assets/tray/tray_icon_linux.png';
    return 'assets/tray/tray_icon@2x.png';
  }

  static Menu buildMenu({
    required void Function() quickAdd,
    required void Function() show,
    required void Function() quit,
  }) =>
      Menu(items: [
        MenuItem(
          key: quickAddKey,
          label: 'Quick Add (${HotkeyService.label.replaceFirst('Quick Add  ', '')})',
          onClick: (_) => quickAdd(),
        ),
        MenuItem.separator(),
        MenuItem(key: showKey, label: 'Show window', onClick: (_) => show()),
        MenuItem(key: quitKey, label: 'Quit Clarity', onClick: (_) => quit()),
      ]);

  Future<void> init({
    required Future<void> Function() quickAdd,
    required Future<void> Function() show,
    required Future<void> Function() quit,
  }) async {
    if (!isDesktopApp || _ready) return;
    onQuickAdd = quickAdd;
    onShow = show;
    onQuit = quit;
    try {
      _tray.addListener(this);
      await _tray.setIcon(
        iconAsset,
        isTemplate: Platform.isMacOS,
      );
      await _tray.setToolTip('Clarity — minimal todo');
      await _tray.setContextMenu(buildMenu(
        quickAdd: () => onQuickAdd?.call(),
        show: () => onShow?.call(),
        quit: () => onQuit?.call(),
      ));
      await _windows.setPreventClose(true);
      _windows.addListener(_WindowCloseListener(() async {
        if (_quitting) return;
        await _windows.hide();
      }));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// True quit: allow close, then destroy. Called from the tray menu.
  Future<void> quit() async {
    _quitting = true;
    try {
      await _windows.setPreventClose(false);
      await _windows.destroy();
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  void onTrayIconMouseDown() {
    // Left-click toggles the window (native menu-bar behavior).
    () async {
      try {
        if (await _windows.isVisible()) {
          await _windows.hide();
        } else {
          await _windows.show();
          await _windows.focus();
        }
      } catch (_) {
        // Best-effort.
      }
    }();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case quickAddKey:
        onQuickAdd?.call();
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
