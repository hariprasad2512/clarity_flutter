import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clarity_flutter/core/app_store.dart';
import 'package:clarity_flutter/data/local_store.dart';
import 'package:clarity_flutter/main.dart';

// NOTE: Hive/SharedPreferences setup lives in setUpAll (real async zone).
// Inside testWidgets, FakeAsync is active: Hive's disk-flush futures only
// complete inside runAsync, so the test waits on notifier state there and
// pumps afterwards.
//
// NOTE: tests run with FLUTTER_TEST set, so `isDesktopApp` is false and the
// mobile UI is under test: + FAB → bottom-sheet composer (no capture bar).
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

  testWidgets('offline smoke: sidebar filters render, FAB composer adds',
      (tester) async {
    // Phone-sized surface → narrow layout with the + FAB.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClarityApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Workspace renders in the mobile default tab (Inbox).
    expect(find.text('Inbox'), findsWidgets);

    // Drawer holds the filter list on narrow screens.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.tapAt(const Offset(350, 450)); // scrim dismisses drawer
    await tester.pumpAndSettle();

    // Mobile flow: + FAB opens the bottom-sheet composer.
    await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.add));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'New task'), findsOneWidget);

    // "today" keeps it visible in the default Inbox tab. Save via the
    // button (keyboard actions are covered by the composer unit path).
    await tester.enterText(
      find.widgetWithText(TextField, 'New task'),
      'Smoke task today',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    // Let Hive's disk flush + the notifier continuation run in real time.
    await tester.runAsync(() async {
      for (var i = 0;
          i < 400 && container.read(taskListProvider).isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('Smoke task'), findsOneWidget);
  });
}
