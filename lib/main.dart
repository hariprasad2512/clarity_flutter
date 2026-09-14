import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'auth/auth_service.dart';
import 'core/app_config.dart';
import 'core/app_store.dart';
import 'data/local_store.dart';
import 'desktop/desktop.dart';
import 'desktop/hotkey_service.dart';
import 'desktop/quick_add_host.dart';
import 'desktop/quick_add_window.dart';
import 'desktop/tray_service.dart';
import 'notifications/notification_service.dart';
import 'sync/sync_engine.dart';
import 'sync/task_remote.dart';
import 'ui/app_shell.dart';
import 'widget/widget_background.dart';
import 'widget/widget_service.dart';

/// Clarity for Flutter — Phase 4: previous phases + floating Quick Add,
/// global hotkey, tray, launch-at-login.
///
/// Two entrypoints share this file (same pattern as the plugin example):
/// * main window (default): the full app below.
/// * `'quick_add'` sub-window: [quickAddWindowMain] — a dumb input panel in
///   its own isolate. It never touches Hive/Supabase; submits come back
///   over the multi-window channel and are created here.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopApp) {
    await windowManager.ensureInitialized();
    final self = await WindowController.fromCurrentEngine();
    if (parseWindowArguments(self.arguments).isPanel) {
      await quickAddWindowMain(self);
      return;
    }
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

  // Widget header switch (background isolate, Android only).
  await registerWidgetInteractivity();

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
      quickAddHostProvider.overrideWithValue(QuickAddHost()),
      widgetServiceProvider.overrideWithValue(WidgetService()),
    ],
  );

  if (isDesktopApp) {
    // Panel submits land here (main isolate owns Hive + sync + alerts).
    final self = await WindowController.fromCurrentEngine();
    container.read(quickAddHostProvider).mainWindowId = self.windowId;
    await self.setWindowMethodHandler((call) async {
      if (call.method == 'quick_add_submit') {
        final payload = parseQuickAddPayload(call.arguments);
        if (payload == null) return false;
        final task = await container
            .read(taskListProvider.notifier)
            .add(payload.text, manualDate: payload.due);
        return task != null;
      }
    });
  }

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
        await container
            .read(widgetServiceProvider)
            .refresh(container.read(taskListProvider));
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
      quickAddHostProvider
          .overrideWithValue(container.read(quickAddHostProvider)),
      widgetServiceProvider
          .overrideWithValue(container.read(widgetServiceProvider)),
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
  StreamSubscription<Uri?>? _widgetSub;

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
    _widgetSub?.cancel();
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
      await ref
          .read(widgetServiceProvider)
          .refresh(ref.read(taskListProvider));
      await _initDesktop();
      _listenWidgetTaps();
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

  /// Desktop integrations: floating Quick Add (hotkey/tray/buttons),
  /// tray (hide-on-close, Quit). No-ops on mobile/web/tests via guards.
  Future<void> _initDesktop() async {
    final tray = ref.read(trayServiceProvider);
    final summon = ref.read(quickAddHostProvider).summon;
    await ref.read(hotkeyServiceProvider).init(summon);
    await tray.init(
      quickAdd: summon,
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

  /// Widget taps land here as deep links (`widgetClicked`): circle taps
  /// toggle immediately in the main isolate (the widget never touches
  /// Hive itself — single-isolate box locks). Plain opens need no action.
  /// Android-only in Phase 5 (no iOS extension yet; no plugin elsewhere).
  void _listenWidgetTaps() {
    if (_widgetSub != null) return;
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      _widgetSub = HomeWidget.widgetClicked.listen(
        (uri) async {
          if (!mounted || uri == null) return;
          final id = WidgetService.parseToggleId(uri);
          if (id == null) return; // plain open (today) — nothing to apply
          await ref.read(taskListProvider.notifier).completeById(id);
        },
        onError: (_) {},
      );
    } catch (_) {
      // Best-effort (tests).
    }
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
