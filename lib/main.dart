import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_store.dart';
import 'data/local_store.dart';
import 'notifications/notification_service.dart';
import 'ui/app_shell.dart';

/// Clarity for Flutter — Phase 2: local-first core + actionable local
/// notifications.
///
/// Bootstrap: open Hive store + SharedPreferences, init notifications,
/// then inject via ProviderScope overrides. Cloud (Supabase), hotkey and
/// widgets arrive in Phases 3–5.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  final prefs = await SharedPreferences.getInstance();
  final notifications = NotificationService();
  final snoozeMinutes = prefs.getInt(SettingsNotifier.snoozeKey);
  await notifications.init(
    snoozeMinutes: (snoozeMinutes != null && snoozeMinutes > 0)
        ? snoozeMinutes
        : 60,
  );
  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        sharedPrefsProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const ClarityApp(),
    ),
  );
}

class ClarityApp extends StatelessWidget {
  const ClarityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clarity',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _Bootstrap(child: AppShell()),
    );
  }
}

/// One-time startup wiring that needs a live container: notification action
/// callbacks, permission request, and alarm reconcile. Mirrors the native
/// `ClarityApp.init` (delegate install) + `ContentView.onAppear`
/// (`NotificationManager.requestPermission`) split.
class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap> {
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final notifications = ref.read(notificationServiceProvider);
    notifications.onMarkDone = (id) =>
        ref.read(taskListProvider.notifier).completeById(id);
    notifications.onSnooze = (id) => ref
        .read(taskListProvider.notifier)
        .snoozeById(id, ref.read(settingsProvider).snoozeMinutes);
    // Best-effort, never blocks first frame.
    Future(() async {
      await notifications.requestPermission();
      if (!mounted) return;
      await notifications.rescheduleAll(
        ref.read(taskListProvider),
        snoozeMinutes: ref.read(settingsProvider).snoozeMinutes,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
