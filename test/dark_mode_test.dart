import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clarity_flutter/core/app_store.dart';
import 'package:clarity_flutter/data/local_store.dart';
import 'package:clarity_flutter/desktop/quick_add_window.dart';
import 'package:clarity_flutter/main.dart';

// The floating panel and the app shell must both follow the system theme:
// light card on light mode, dark surface on dark mode (no black slabs,
// no unreadable hard-coded colors).
void main() {
  late LocalStore store;
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.openTest();
    prefs = await SharedPreferences.getInstance();
  });

  tearDownAll(() async {
    await store.closeAndDelete();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const ClarityApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Brightness appBrightness(WidgetTester tester) {
    final ctx = tester.element(find.byType(Scaffold).first);
    return Theme.of(ctx).brightness;
  }

  group('dark mode', () {
    testWidgets('app shell follows system brightness', (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(() => tester.binding.platformDispatcher
          .clearPlatformBrightnessTestValue());
      await pumpShell(tester);
      expect(find.text('Inbox'), findsWidgets);
      expect(appBrightness(tester), Brightness.light);

      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expect(find.text('Inbox'), findsWidgets);
      expect(appBrightness(tester), Brightness.dark);
    });

    testWidgets('floating panel follows system brightness', (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(() => tester.binding.platformDispatcher
          .clearPlatformBrightnessTestValue());
      await tester.pumpWidget(const QuickAddPanel(mainWindowId: null));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'What needs to be done?'),
        findsOneWidget,
      );
      final ctx = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(ctx).brightness, Brightness.dark);
      // Opaque full-bleed theme surface (no transparency tricks).
      final scaffold =
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, Theme.of(ctx).colorScheme.surface);
    });
  });
}
