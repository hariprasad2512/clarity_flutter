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
import 'core/app_badge.dart';
import 'core/app_config.dart';
import 'core/app_store.dart';
import 'data/local_store.dart';
import 'desktop/desktop.dart';
import 'desktop/hotkey_service.dart';
import 'desktop/quick_add_host.dart';
import 'desktop/quick_add_window.dart';
import 'desktop/tray_service.dart';
import 'notifications/notification_service.dart';
import 'sync/delete_outbox.dart';
import 'sync/sync_engine.dart';
import 'sync/task_remote.dart';
import 'ui/app_shell.dart';
import 'ui/task_composer_sheet.dart';
import 'widget/widget_background.dart';
import 'widget/widget_refresh_worker.dart';
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
    // Shared desktop default. Main window only — the panel sizes itself.
    try {
      await windowManager.setMinimumSize(const Size(360, 520));
      await windowManager.setSize(const Size(900, 620));
      await windowManager.center();
    } catch (_) {
      // Best-effort (headless).
    }
  }
  LocalStore store;
  try {
    store = await LocalStore.open();
  } catch (_) {
    // A second Clarity window (e.g. a stale shortcut launching another
    // copy) can't share Hive's single-isolate boxes — without this guard
    // it sits at a blank white window. Say so and get out of the way.
    runApp(const _AlreadyRunningApp());
    return;
  }
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
  // Widget freshness worker (re-render only, Android only).
  await registerWidgetRefreshWorker();

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
      if (call.method == QuickAddHost.submitMethod) {
        final payload = parseQuickAddPayload(call.arguments);
        if (payload == null) return false;
        final task = await container
            .read(taskListProvider.notifier)
            .add(payload.text, manualDate: payload.due);
        return task != null;
      }
      if (call.method == QuickAddHost.closingMethod) {
        container.read(quickAddHostProvider).onPanelClosed();
        return true;
      }
    });
  }

  if (AppConfig.isConfigured) {
    // Shared post-write refresh: persist-side effects after any sync
    // write (puts or delete-prunes) — UI, notifications, widgets.
    Future<void> afterSyncWrite() async {
      final notifier = container.read(taskListProvider.notifier);
      notifier.refreshFromStore();
      await notifications.rescheduleAll(
        container.read(taskListProvider),
        snoozeMinutes: container.read(settingsProvider).snoozeMinutes,
      );
      await container
          .read(widgetServiceProvider)
          .refresh(container.read(taskListProvider));
      await reconcileWidgetStrikes(
        notifier.completeById,
        after: () => container
            .read(widgetServiceProvider)
            .refresh(container.read(taskListProvider)),
      );
    }

    final engine = SyncEngine(
      remote: SupabaseTaskRemote(),
      readLocal: () async => store.all,
      writeLocal: (tasks) async {
        for (final t in tasks) {
          await store.put(t);
        }
        await afterSyncWrite();
      },
      readUserId: () => Supabase.instance.client.auth.currentUser?.id,
      readPendingDeletes: loadDeleteOutbox,
      writePendingDeletes: saveDeleteOutbox,
      deleteLocal: (ids) async {
        await store.deleteByIds(ids);
        await afterSyncWrite();
      },
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

/// Global navigator for context-free routing (widget compose taps).
final appNavigatorKey = GlobalKey<NavigatorState>();

class ClarityApp extends StatelessWidget {
  const ClarityApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clarity',
      navigatorKey: appNavigatorKey,
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

/// Foreground pull cadence shared by all platforms (was 60s).
/// 15s keeps two devices on the same account within ~15–20s of each other
/// while open, in either direction. Overlap-safe via SyncEngine's busy
/// guard; error pacing via [SyncBackoff].
const syncPollInterval = Duration(seconds: 15);

/// Single coalesced fast retry after a failed poll (reconnect recovery).
const syncRetryDelay = Duration(seconds: 5);

/// One-time startup wiring that needs a live container: notification action
/// callbacks, permission request, alarm reconcile, auth-state reactions,
/// foreground-resume + 15s/backoff sync triggers. Mirrors native `ClarityApp.init`
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
  Timer? _syncRetryTimer;
  Timer? _midnightTimer;
  final SyncBackoff _backoff = SyncBackoff();
  WindowListener? _windowListener;
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
    _syncRetryTimer?.cancel();
    _midnightTimer?.cancel();
    final listener = _windowListener;
    _windowListener = null;
    if (listener != null) {
      try {
        windowManager.removeListener(listener);
      } catch (_) {
        // Best-effort.
      }
    }
    _authSub?.cancel();
    _widgetSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final engine = ref.read(syncEngineProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        // Foreground pull (native: onReceive foreground notification)
        // plus widget outbox reconcile. Permission refresh keeps the
        // exact-alarm fallback + Settings status accurate (user may flip
        // it in Settings).
        engine?.syncNow();
        ref.read(notificationServiceProvider).refreshPermissionStatus();
        reconcileWidgetStrikesRef(ref);
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Best-effort flush of local edits before the OS suspends us.
        // Without this the 1.2s debounced push may never run on
        // edit-then-background/kill, and the other device sees nothing
        // until this app reopens. Fire-and-forget on purpose.
        if (engine != null) {
          unawaited(engine.syncNow(pushOnly: true));
        }
      case AppLifecycleState.detached:
        break;
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
    // Replay a notification-button tap that launched the app before the
    // handlers above were assigned (cold start); otherwise the tap is lost
    // and it looks like the button "just opens the app".
    unawaited(notifications.drainPendingActions());
    // Red overdue badge follows every task change (mutations, sync,
    // sign-out wipe) without touching any other wiring.
    _scheduleMidnightRefresh();
    Future(() async {
      await notifications.requestPermission();
      if (!mounted) return;
      await notifications.rescheduleAll(
        ref.read(taskListProvider),
        snoozeMinutes: ref.read(settingsProvider).snoozeMinutes,
      );
      // Initial badge paint (listener covers later changes).
      unawaited(
          AppBadgeService.updateBadge(ref.read(overdueCountProvider)));
      await ref
          .read(widgetServiceProvider)
          .refresh(ref.read(taskListProvider));
      await reconcileWidgetStrikesRef(ref);
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
      // Foreground pull (was 60s): 15s shared cadence so phone ↔ macOS
      // stay within ~15–20s in either direction while open. Backoff +
      // single retry keep offline flakiness from hammering or stalling.
      _syncTimer = Timer.periodic(
        syncPollInterval,
        (_) => _pollOnce(engine),
      );
    });
  }

  /// One paced poll tick: backoff-gated full pull, result noted, single
  /// coalesced fast retry scheduled on failure.
  void _pollOnce(SyncEngine engine) {
    if (!_backoff.shouldSyncNow()) return;
    unawaited(engine.syncNow().then((s) {
      if (!mounted) return;
      _backoff.noteResult(s);
      if (s == SyncStatus.error) _scheduleSyncRetry(engine);
    }));
  }

  /// Single-shot reconnect retry. Coalesced: at most one pending.
  void _scheduleSyncRetry(SyncEngine engine) {
    if (_syncRetryTimer != null) return;
    _syncRetryTimer = Timer(syncRetryDelay, () {
      _syncRetryTimer = null;
      if (!mounted) return;
      _pollOnce(engine);
    });
  }

  /// Desktop integrations: floating Quick Add (hotkey/tray/buttons),
  /// tray (hide-on-close, Quit), window focus → pull / blur → push flush.
  /// No-ops on mobile/web/tests via guards.
  Future<void> _initDesktop() async {
    final tray = ref.read(trayServiceProvider);
    // Panel failure is never silent: when the floating window can't be
    // created (e.g. multi-window hiccup on Windows), fall back to the
    // in-window composer so hotkey/tray always do SOMETHING visible.
    Future<void> summonQuickAdd() async {
      final ok = await ref.read(quickAddHostProvider).summon();
      if (ok || !mounted) return;
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) showTaskComposer(ctx);
    }

    await ref.read(hotkeyServiceProvider).init(summonQuickAdd);
    await tray.init(
      quickAdd: summonQuickAdd,
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
    // Pull-on-focus: clicking back into the window after editing on the
    // phone pulls immediately instead of waiting for the next poll tick.
    // Blur flushes local edits — covers hide-to-tray (hide triggers a
    // blur but no app-lifecycle event on desktop).
    if (isDesktopApp && _windowListener == null) {
      final listener = _SyncWindowListener(
        onFocus: () => ref.read(syncEngineProvider)?.syncNow(),
        onBlur: () =>
            ref.read(syncEngineProvider)?.syncNow(pushOnly: true),
      );
      try {
        windowManager.addListener(listener);
        _windowListener = listener;
      } catch (_) {
        // Best-effort (tests / headless).
      }
    }
  }

  /// Widget taps land here as deep links (`widgetClicked`): circle taps
  /// toggle immediately in the main isolate (the widget never touches
  /// Hive itself — single-isolate box locks). Plain opens need no action.
  /// QuickAdd-tile taps open the composer. Android-only in Phase 5
  /// (no iOS extension yet; no plugin elsewhere).
  void _listenWidgetTaps() {
    if (_widgetSub != null) return;
    if (kIsWeb || !Platform.isAndroid) return;
    _handleInitialWidgetUri();
    try {
      _widgetSub = HomeWidget.widgetClicked.listen(
        (uri) async {
          if (!mounted || uri == null) return;
          if (WidgetService.isComposeUri(uri)) {
            _openComposer();
            return;
          }
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

  /// Day-boundary refresh: overdue/Today/badge/widget state is derived
  /// from wall-clock dates, so re-read the store just past midnight.
  /// Single-shot, rescheduled each fire; no-op when unmounted.
  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1)
        .add(const Duration(minutes: 1));
    _midnightTimer = Timer(next.difference(now), () {
      if (!mounted) return;
      try {
        ref.read(taskListProvider.notifier).refreshFromStore();
      } catch (_) {
        // Best-effort.
      }
      _scheduleMidnightRefresh();
    });
  }

  /// Cold-start via widget (e.g. QuickAdd tile while the app was dead).
  Future<void> _handleInitialWidgetUri() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (!mounted || uri == null) return;
      if (WidgetService.isComposeUri(uri)) {
        // Wait a frame so the navigator exists.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openComposer();
        });
      }
    } catch (_) {
      // Best-effort.
    }
  }

  void _openComposer() {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    showTaskComposer(ctx);
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen is build-only; the badge then tracks every task change.
    ref.listen<int>(overdueCountProvider, (_, count) {
      unawaited(AppBadgeService.updateBadge(count));
    });
    return widget.child;
  }
}

/// Window focus → full pull, blur → push-only flush. Desktop-only;
/// registered in `_initDesktop` behind `isDesktopApp` (false in tests).
class _SyncWindowListener extends WindowListener {
  _SyncWindowListener({required this.onFocus, required this.onBlur});
  final void Function() onFocus;
  final void Function() onBlur;

  @override
  void onWindowFocus() {
    try {
      onFocus();
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  void onWindowBlur() {
    try {
      onBlur();
    } catch (_) {
      // Best-effort.
    }
  }
}

/// Duplicate-instance screen: Hive boxes open in exactly one process, so a
/// second Clarity copy can never boot its store. Shown instead of a blank
/// white window; closing it ends the duplicate process.
class _AlreadyRunningApp extends StatelessWidget {
  const _AlreadyRunningApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Clarity is already running',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'This extra window cannot open your tasks while the first '
                  'copy is running. Close it and use the original window '
                  '(check the system tray).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    try {
                      if (isDesktopApp) {
                        await windowManager.destroy();
                        return;
                      }
                    } catch (_) {
                      // Fall through to exit.
                    }
                    exit(0);
                  },
                  child: const Text('Close this window'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
