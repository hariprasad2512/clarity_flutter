import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clarity_flutter/core/app_store.dart';
import 'package:clarity_flutter/data/local_store.dart';
import 'package:clarity_flutter/desktop/desktop.dart';
import 'package:clarity_flutter/desktop/hotkey_service.dart';
import 'package:clarity_flutter/desktop/tray_service.dart';

Future<ProviderContainer> _container(LocalStore store) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('desktop guards', () {
    test('isDesktopApp is false under flutter test', () {
      // Tests run on the macOS host where Platform.isMacOS is true —
      // FLUTTER_TEST must still force local-only behavior.
      expect(isDesktopApp, isFalse);
    });

    test('HotkeyService.init is a safe no-op in tests', () async {
      final service = HotkeyService();
      var called = false;
      await service.init(() async => called = true);
      expect(called, isFalse);
      await service.dispose();
    });

    test('hotkey label falls back without platform hint in tests', () {
      expect(HotkeyService.label, 'Quick Add');
    });
  });

  group('HotkeyService.buildHotkey', () {
    test('system-scope T with shift + platform modifier', () {
      final hotkey = HotkeyService.buildHotkey();
      expect(hotkey.key, PhysicalKeyboardKey.keyT);
      expect(hotkey.scope, HotKeyScope.system);
      expect(hotkey.modifiers, contains(HotKeyModifier.shift));
      expect(hotkey.modifiers, hasLength(2));
    });
  });

  group('TrayService', () {
    test('icon asset lives under assets/tray', () {
      expect(TrayService.iconAsset, startsWith('assets/tray/'));
    });

    test('menu carries quick-add / show / quit actions', () {
      var quickAdd = 0, show = 0, quit = 0;
      final menu = TrayService.buildMenu(
        quickAdd: () => quickAdd++,
        show: () => show++,
        quit: () => quit++,
      );
      final keys = [
        for (final item in menu.items ?? []) item.key,
      ];
      expect(
        keys,
        containsAll([
          TrayService.quickAddKey,
          TrayService.showKey,
          TrayService.quitKey,
        ]),
      );
      // Callbacks route through the built items.
      for (final item in menu.items ?? []) {
        item.onClick?.call(item);
      }
      expect(quickAdd, 1);
      expect(show, 1);
      expect(quit, 1);
    });

    test('init is a safe no-op in tests', () async {
      final service = TrayService();
      await service.init(
        quickAdd: () async {},
        show: () async {},
        quit: () async {},
      );
      await service.dispose();
    });
  });

  group('launch-at-login setting', () {
    test('defaults off and stays off outside desktop', () async {
      final store = await LocalStore.openTest();
      addTearDown(() => store.closeAndDelete());
      final c = await _container(store);
      expect(c.read(settingsProvider).launchAtLogin, isFalse);
      await c.read(settingsProvider.notifier).setLaunchAtLogin(true);
      expect(c.read(settingsProvider).launchAtLogin, isFalse);
    });
  });
}
