import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clarity_flutter/core/app_store.dart';
import 'package:clarity_flutter/core/task_model.dart';
import 'package:clarity_flutter/data/local_store.dart';

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
  group('TaskListNotifier (TaskService parity)', () {
    late LocalStore store;

    setUp(() async {
      store = await LocalStore.openTest();
    });

    tearDown(() async {
      await store.closeAndDelete();
    });

    test('add parses date, strips title, persists', () async {
      final c = await _container(store);
      final task = await c
          .read(taskListProvider.notifier)
          .add('Pay rent tomorrow at 5pm');
      expect(task, isNotNull);
      expect(task!.title, 'Pay rent');
      expect(task.dueDate, isNotNull);
      expect(task.needsSync, isTrue);
      expect(c.read(taskListProvider), hasLength(1));
      expect(store.all, hasLength(1));
    });

    test('add with manualDate keeps title verbatim', () async {
      final c = await _container(store);
      final when = DateTime.now().add(const Duration(days: 3));
      final task = await c.read(taskListProvider.notifier).add(
            'Call mom tomorrow',
            manualDate: when,
          );
      expect(task!.title, 'Call mom tomorrow');
      expect(task.dueDate, when);
    });

    test('add returns null for blank input', () async {
      final c = await _container(store);
      expect(await c.read(taskListProvider.notifier).add('   '), isNull);
      expect(c.read(taskListProvider), isEmpty);
    });

    test('toggle flips completion and stamps sync', () async {
      final c = await _container(store);
      final task =
          await c.read(taskListProvider.notifier).add('Buy milk');
      await c.read(taskListProvider.notifier).toggle(task!);
      expect(store.all.single.isCompleted, isTrue);
      expect(store.all.single.needsSync, isTrue);
    });

    test('deleteByIds removes tasks', () async {
      final c = await _container(store);
      final a = await c.read(taskListProvider.notifier).add('A');
      await c.read(taskListProvider.notifier).add('B');
      await c.read(taskListProvider.notifier).deleteByIds([a!.id]);
      expect(
        c.read(taskListProvider).map((t) => t.title),
        ['B'],
      );
    });

    test('filteredTasks: today tab, search and sort', () async {
      final c = await _container(store);
      final notifier = c.read(taskListProvider.notifier);
      await notifier.add('Overdue thing yesterday');
      await notifier.add('Future thing next week');
      await notifier.add('Plain thing');

      c.read(filterProvider.notifier).set(TaskFilter.today);
      final today =
          c.read(filteredTasksProvider).map((t) => t.title).toList();
      expect(today, contains('Overdue thing'));
      expect(today, isNot(contains('Future thing')));
      expect(today, isNot(contains('Plain thing')));

      c.read(filterProvider.notifier).set(TaskFilter.inbox);
      c.read(searchProvider.notifier).set('plain');
      expect(
        c.read(filteredTasksProvider).map((t) => t.title),
        ['Plain thing'],
      );
    });

    test('counts feed sidebar badges', () async {
      final c = await _container(store);
      final notifier = c.read(taskListProvider.notifier);
      await notifier.add('Due today');
      final done =
          await notifier.add('Done thing today');
      await notifier.toggle(done!);
      final counts = c.read(countsProvider);
      expect(counts.today, 1);
      expect(counts.inbox, 1);
    });
  });

  group('notification-action handlers (NotificationDelegate parity)', () {
    late LocalStore store;

    setUp(() async {
      store = await LocalStore.openTest();
    });

    tearDown(() async {
      await store.closeAndDelete();
    });

    test('completeById completes idempotently, false when unknown', () async {
      final c = await _container(store);
      final notifier = c.read(taskListProvider.notifier);
      final task = await notifier.add('Action task today');
      expect(await notifier.completeById(task!.id), isTrue);
      expect(store.all.single.isCompleted, isTrue);
      // Second call: already done, still true (idempotent Mark Done).
      expect(await notifier.completeById(task.id), isTrue);
      expect(await notifier.completeById('nope'), isFalse);
    });

    test('snoozeById pushes due date out and touches sync', () async {
      final c = await _container(store);
      final notifier = c.read(taskListProvider.notifier);
      final task = await notifier.add('Snooze task today');
      final before = DateTime.now();
      expect(await notifier.snoozeById(task!.id, 60), isTrue);
      final updated = store.all.single;
      expect(
        updated.dueDate!.difference(before).inMinutes,
        inInclusiveRange(55, 65),
      );
      expect(updated.needsSync, isTrue);
      expect(await notifier.snoozeById('nope', 60), isFalse);
    });

    test('snoozeById refuses completed tasks', () async {
      final c = await _container(store);
      final notifier = c.read(taskListProvider.notifier);
      final task = await notifier.add('Done task today');
      await notifier.toggle(task!);
      expect(await notifier.snoozeById(task.id, 60), isFalse);
    });
  });

  group('SettingsNotifier', () {
    test('defaults to 60 min snooze and persists changes', () async {
      final store = await LocalStore.openTest();
      addTearDown(() => store.closeAndDelete());
      final c = await _container(store);
      expect(c.read(settingsProvider).snoozeMinutes, 60);
      await c.read(settingsProvider.notifier).setSnoozeMinutes(15);
      expect(c.read(settingsProvider).snoozeMinutes, 15);
    });
  });

  group('mobile defaults + Completed-today section', () {
    test('filter defaults to Inbox outside desktop', () async {
      final store = await LocalStore.openTest();
      addTearDown(() => store.closeAndDelete());
      final c = await _container(store);
      expect(c.read(filterProvider), TaskFilter.inbox);
    });

    test('completed-today tracks done-today and undoes via toggle',
        () async {
      final store = await LocalStore.openTest();
      addTearDown(() => store.closeAndDelete());
      final c = await _container(store);
      final notifier = c.read(taskListProvider.notifier);
      final task = await notifier.add('Section task today');
      expect(c.read(completedTodayProvider), isEmpty);
      await notifier.toggle(task!);
      expect(
        c.read(completedTodayProvider).map((t) => t.id),
        [task.id],
      );
      // Undo: un-complete removes it from the section.
      await notifier.toggle(task);
      expect(c.read(completedTodayProvider), isEmpty);
    });

    test('yesterday completions stay out of the section', () async {
      final store = await LocalStore.openTest();
      addTearDown(() => store.closeAndDelete());
      final c = await _container(store);
      final notifier = c.read(taskListProvider.notifier);
      final task = await notifier.add('Old task');
      await notifier.toggle(task!);
      // Backdate the completion past midnight.
      task.updatedAt =
          DateTime.now().subtract(const Duration(days: 1));
      await store.put(task);
      notifier.refreshFromStore();
      expect(c.read(completedTodayProvider), isEmpty);
    });
  });
}
