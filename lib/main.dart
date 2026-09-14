import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'auth/auth_service.dart';
import 'core/app_config.dart';
import 'core/app_store.dart';
import 'data/local_store.dart';
import 'desktop/desktop.dart';
import 'desktop/hotkey_service.dart';
import 'desktop/tray_service.dart';
import 'notifications/notification_service.dart';
import 'sync/sync_engine.dart';
import 'sync/task_remote.dart';
import 'ui/app_shell.dart';
import 'ui/quick_add_dialog.dart';

/// Clarity for Flutter — Phase 3: local-first core + actionable
/// notifications + Supabase Auth (Google) + Postgres sync.
///
/// Bootstrap: open Hive store + SharedPreferences, init notifications and
/// (when configured) Supabase, build the sync engine bound to a live
/// container, then inject everything via overrides. Hotkey and widgets
/// arrive in Phases 4–5.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopApp) {
    // Window controls (show/focus/hide) for tray + hotkey summoning.
    await windowManager.ensureInitialized();
  }
  final store = await LocalStore.open();
  final prefs = await SharedPreferences.getInstance();
  final notifications = NotificationService();
  final snoozeMinutes = prefs.getInt(SettingsNotifier.snoozeKey);
  await notifications.init(
    snoozeMinutes: (snoozeMinutes != null && snoozeMinutes > 0)
        ? snoozeMinutes
        : 60,
  );

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      sharedPrefsProvider.overrideWithValue(prefs),
      notificationServiceProvider.overrideWithValue(notifications),
      // Pre-registered (null = local-only) so the engine can be swapped in
      // below without changing the override count (Riverpod forbids that).
      syncEngineProvider.overrideWithValue(null),
      hotkeyServiceProvider.overrideWithValue(HotkeyService()),
      trayServiceProvider.overrideWithValue(TrayService()),
    ],
  );

  if (AppConfig.isConfigured) {
    final engine = SyncEngine(
      remote: SupabaseTaskRemote(),
      readLocal: () async => store.all,
      writeLocal: (tasks) async {
        for (final t in tasks) {
          await store.put(t);
        }
        container.read(taskListProvider.notifier).refreshFromStore();
        await notifications.rescheduleAll(
          container.read(taskListProvider),
          snoozeMinutes: container.read(settingsProvider).snoozeMinutes,
        );
      },
      readUserId: () => Supabase.instance.client.auth.currentUser?.id,
    );
    container.updateOverrides([
      localStoreProvider.overrideWithValue(store),
      sharedPrefsProvider.overrideWithValue(prefs),
      notificationServiceProvider.overrideWithValue(notifications),
      syncEngineProvider.overrideWithValue(engine),
      hotkeyServiceProvider
          .overrideWithValue(container.read(hotkeyServiceProvider)),
      trayServiceProvider
          .overrideWithValue(container.read(trayServiceProvider)),
    ]);
    engine.status.listen((s) {
      container.read(syncStatusProvider.notifier).set(s);
    });
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
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
/// callbacks, permission request, alarm reconcile, auth-state reactions,
/// foreground-resume + 60s sync triggers. Mirrors native `ClarityApp.init`
/// + `ContentView.onAppear` + `SyncEngine` timers.
class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap>
    with WidgetsBindingObserver {
  bool _wired = false;
  Timer? _syncTimer;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground pull (native: onReceive foreground notification).
    if (state == AppLifecycleState.resumed) {
      ref.read(syncEngineProvider)?.syncNow();
    }
  }

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
    Future(() async {
      await notifications.requestPermission();
      if (!mounted) return;
      await notifications.rescheduleAll(
        ref.read(taskListProvider),
        snoozeMinutes: ref.read(settingsProvider).snoozeMinutes,
      );
      await _initDesktop();
      if (!mounted || !AppConfig.isConfigured) return;
      final engine = ref.read(syncEngineProvider);
      if (engine == null) return;
      // Signed-in launch: initial pull. Signed-out launch: stay local.
      if (Supabase.instance.client.auth.currentSession != null) {
        await engine.syncNow();
      }
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) async {
          if (!mounted) return;
          if (data.session != null) {
            ref.read(authErrorProvider.notifier).set(null);
            await ref.read(settingsProvider.notifier).setOfflineMode(false);
            await engine.syncNow();
          } else {
            // Remote expiry/sign-out elsewhere: surface the gate, keep data.
            ref.read(syncStatusProvider.notifier).set(SyncStatus.localOnly);
          }
        },
        onError: (Object e) {
          // Auth stream failures (refresh, exchange) must never crash the
          // run loop — and must be visible, not log-only.
          ref
              .read(authErrorProvider.notifier)
              .set('Sign-in sync error: ${_shortError(e)}');
        },
      );
      // Periodic pull (native: 60s timer).
      _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        engine.syncNow();
      });
    });
  }

  /// Desktop integrations: global hotkey + tray (hide-on-close, Quit).
  /// No-ops on mobile/web/tests via the services' own guards.
  Future<void> _initDesktop() async {
    final tray = ref.read(trayServiceProvider);
    await ref.read(hotkeyServiceProvider).init(_summonQuickAdd);
    await tray.init(
      quickAdd: _summonQuickAdd,
      show: () async {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {
          // Best-effort.
        }
      },
      quit: () => tray.quit(),
    );
  }

  /// Brings the window forward and opens Quick Add — the shared target of
  /// the global hotkey and the tray menu (native QuickAddPanel behavior).
  Future<void> _summonQuickAdd() async {
    if (!mounted) return;
    if (isDesktopApp) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {
        // Best-effort: still open the dialog wherever we are.
      }
    }
    if (!mounted) return;
    await showQuickAdd(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One-line error summary without leaking tokens or URLs.
String _shortError(Object e) {
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Connection failed')) {
    return 'could not reach the server — check your connection';
  }
  final first = s.split('\n').first;
  return first.length > 140 ? '${first.substring(0, 140)}…' : first;
}
