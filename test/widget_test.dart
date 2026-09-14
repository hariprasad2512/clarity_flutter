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

  testWidgets('offline smoke: sidebar filters render, capture adds a task',
      (tester) async {
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

    // Workspace renders (offlineMode defaults true -> no auth gate).
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // Capture a task through the capture bar ("today" so it lands in the
    // default Today tab).
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a task — try "Finish Report"'),
      'Smoke task today',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
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
