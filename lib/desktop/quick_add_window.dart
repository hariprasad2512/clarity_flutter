import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/date_parser.dart';
import 'quick_add_host.dart';

/// Floating Spotlight-style Quick Add panel. Runs in its OWN window +
/// isolate, independent of the main app window (port of native
/// `QuickAddPanel`: `Enter` saves + closes, `Esc` dismisses).
///
/// Deliberately dumb: it never touches Hive/Supabase (box locks are
/// single-isolate). Submit ships `{text}` to window 0 over the
/// multi-window channel; the main isolate parses + creates + schedules.
/// Only `DateParser` (pure Dart) is shared, for the live date preview.
Future<void> quickAddWindowMain(WindowController self) async {
  const options = WindowOptions(
    size: Size(520, 170),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    alwaysOnTop: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await self.setWindowMethodHandler((call) async {
    if (call.method == 'window_focus') {
      await windowManager.focus();
    }
  });
  final mainWindowId =
      parseWindowArguments(self.arguments).mainWindowId;
  runApp(QuickAddPanel(mainWindowId: mainWindowId));
}

class QuickAddPanel extends StatefulWidget {
  const QuickAddPanel({super.key, required this.mainWindowId});

  /// Main window id for the submit trip back (null = cannot submit).
  final String? mainWindowId;

  @override
  State<QuickAddPanel> createState() => _QuickAddPanelState();
}

class _QuickAddPanelState extends State<QuickAddPanel> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    final target = widget.mainWindowId;
    if (text.isEmpty || _sending || target == null) return;
    setState(() => _sending = true);
    try {
      await WindowController.fromWindowId(target)
          .invokeMethod('quick_add_submit', {'text': text});
    } catch (_) {
      // Main window unreachable (quitting?) — nothing to do.
    }
    await windowManager.close();
  }

  Future<void> _dismiss() => windowManager.close();

  @override
  Widget build(BuildContext context) {
    final date = DateParser.extractDate(_ctrl.text);
    return MaterialApp(
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
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
        },
        child: Builder(
          builder: (context) {
          // Full-bleed theme surface: the window is opaque (AppKit
          // transparency isn't reachable from plugins), so the panel
          // paints its own background edge-to-edge. Follows light/dark.
          final surface = Theme.of(context).colorScheme.surface;
          return Scaffold(
            backgroundColor: surface,
            body: Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt,
                          color: Colors.green, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          enabled: !_sending,
                          style: const TextStyle(fontSize: 18),
                          decoration: const InputDecoration(
                            hintText: 'What needs to be done?',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: date != null
                            ? Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 14, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateParser.displayString(date),
                                    style: const TextStyle(
                                        color: Colors.green),
                                  ),
                                ],
                              )
                            : const Row(
                                children: [
                                  Icon(Icons.keyboard,
                                      size: 14, color: Colors.grey),
                                  SizedBox(width: 6),
                                  Text(
                                    '⏎ save & close · esc dismiss',
                                    style:
                                        TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                      ),
                      if (_sending)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
        ),
      ),
    );
  }
}
