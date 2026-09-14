import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'desktop.dart';

/// System-wide Quick-Add hotkey. Port of native `HotKeyManager`
/// (QuickAdd/HotKeyManager.swift: Cmd+Shift+T).
///
/// Combos are per-platform (user choice: Ctrl+Shift+T on Windows to avoid
/// the Alt+Shift input-language switcher):
/// * macOS: ⌘⇧T · Windows/Linux: Ctrl+Shift+T.
/// Carbon-level on macOS — no Accessibility permission needed, like native.
/// Desktop-only; [init] is a safe no-op elsewhere (incl. tests).
class HotkeyService {
  HotkeyService({HotKeyManager? manager}) : _managerOverride = manager;

  // Injected (tests) or plugin singleton, resolved lazily: the singleton
  // touches the binary messenger at construction, which doesn't exist
  // under `flutter test`. The guard in [init]/[dispose] always runs first,
  // so [_m] is only read on desktop.
  final HotKeyManager? _managerOverride;
  HotKeyManager? _manager;
  HotKeyManager get _m => _manager ??= _managerOverride ?? hotKeyManager;
  HotKey? _hotkey;
  bool _ready = false;

  /// Human label for buttons/menus. Mirrors the native menu hint.
  static String get label {
    if (!isDesktopApp) return 'Quick Add';
    if (Platform.isMacOS) return 'Quick Add  ⌘⇧T';
    return 'Quick Add  Ctrl+Shift+T';
  }

  static HotKey buildHotkey() {
    final meta = Platform.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control;
    return HotKey(
      key: PhysicalKeyboardKey.keyT,
      modifiers: [meta, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
  }

  Future<void> init(Future<void> Function() onQuickAdd) async {
    if (!isDesktopApp || _ready) return;
    try {
      _hotkey = buildHotkey();
      await _m.register(
        _hotkey!,
        keyDownHandler: (_) => onQuickAdd(),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> dispose() async {
    if (!_ready) return;
    try {
      if (_hotkey != null) await _m.unregister(_hotkey!);
    } catch (_) {
      // Best-effort.
    }
    _ready = false;
  }
}

final hotkeyServiceProvider =
    Provider<HotkeyService>((ref) => HotkeyService());
