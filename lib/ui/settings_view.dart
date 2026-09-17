import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../desktop/desktop.dart';
import '../desktop/hotkey_service.dart';
import 'clarity_logo.dart';

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
      title: const Row(
        children: [
          ClarityMark(size: 28),
          SizedBox(width: 10),
          Text('Settings'),
        ],
      ),
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
            if (!kIsWeb && Platform.isAndroid) ...[
              const SizedBox(height: 12),
              const _AndroidNotificationStatus(),
            ],
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

/// Android 13+ notification health (same-account multi-device parity).
///
/// Shows POST_NOTIFICATIONS + exact-alarm state from
/// `NotificationService.refreshPermissionStatus`. Exact denied is not
/// fatal: scheduling falls back to inexact (OEM-dependent window).
/// Hidden on desktop/web/tests via the call-site guard.
class _AndroidNotificationStatus extends ConsumerStatefulWidget {
  const _AndroidNotificationStatus();

  @override
  ConsumerState<_AndroidNotificationStatus> createState() =>
      _AndroidNotificationStatusState();
}

class _AndroidNotificationStatusState
    extends ConsumerState<_AndroidNotificationStatus> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    Future(() async {
      await ref.read(notificationServiceProvider).refreshPermissionStatus();
      if (mounted) setState(() {});
    });
  }

  Future<void> _request() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(notificationServiceProvider).requestPermission();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(notificationServiceProvider);
    final enabled = svc.notificationsEnabled;
    final canExact = svc.canScheduleExact;
    final outline = Theme.of(context).colorScheme.outline;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Device alerts', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Notifications: ${enabled == null ? 'unknown' : enabled ? 'on' : 'off'} • '
          'Exact alarms: ${canExact ? 'allowed' : 'denied (inexact fallback)'}',
          style: small,
        ),
        const SizedBox(height: 4),
        Text(
          'Both devices fire locally after syncing the same Google account. '
          'If exact alarms are denied, alerts may arrive late. '
          'For Samsung/Xiaomi/Oppo also allow “Alarms & reminders” and unrestricted battery.',
          style: small,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              onPressed: _refreshing ? null : _request,
              child: Text(_refreshing ? 'Requesting…' : 'Enable alerts'),
            ),
          ],
        ),
      ],
    );
  }
}
