import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../desktop/desktop.dart';
import '../desktop/hotkey_service.dart';

/// Native Settings window equivalent (⌘,). Home of the "Remind me later"
/// delay. Mirrors native `SettingsView`.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  String _label(int m) {
    if (m < 60) return '$m minutes';
    if (m == 60) return '1 hour';
    return '${m ~/ 60} hours';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: settings.snoozeMinutes,
              decoration: const InputDecoration(
                labelText: 'Remind me later waits',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in SettingsNotifier.snoozeOptions)
                  DropdownMenuItem(value: m, child: Text(_label(m))),
              ],
              onChanged: (m) {
                if (m != null) {
                  ref.read(settingsProvider.notifier).setSnoozeMinutes(m);
                }
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Tapping "Remind me later" on a due alert moves the task out by this long.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 16),
            Text('Capture', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              isDesktopApp
                  ? 'Press ${HotkeyService.label.replaceFirst('Quick Add  ', '')} anywhere to capture, or use the Quick Add button and the menu-bar icon.'
                  : 'Tap + to capture a task. Title, date and time live in the composer.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            if (isDesktopApp) ...[
              const SizedBox(height: 16),
              Text('System',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Launch at login'),
                subtitle: Text(
                  'Start Clarity when you sign in.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                value: settings.launchAtLogin,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setLaunchAtLogin(v),
              ),
              Text(
                'Closing the window hides Clarity to the menu bar — Quit from the menu-bar icon to exit.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
