import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';

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
              'Press ⌘⇧T (desktop, Phase 4) or the Quick Add button anywhere to capture. Actionable notifications arrive in Phase 2.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
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
