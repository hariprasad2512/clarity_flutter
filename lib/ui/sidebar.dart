import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../core/app_config.dart';
import '../core/app_store.dart';
import '../core/task_model.dart';
import '../desktop/desktop.dart';
import '../desktop/hotkey_service.dart';
import '../sync/sync_engine.dart';
import 'clarity_logo.dart';

/// Slim Todoist-style sidebar: Quick Add entry, Today/Inbox/Done rows with
/// badges, account + sync footer. Mirrors native `SidebarView`.
class Sidebar extends ConsumerWidget {
  const Sidebar({
    super.key,
    required this.onQuickAdd,
    this.onNavigate,
  });

  final VoidCallback onQuickAdd;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final counts = ref.watch(countsProvider);
    final theme = Theme.of(context);
    // Mobile drawer gets bigger type + padding; desktop stays dense.
    final roomy = !isDesktopApp;

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                roomy ? 20 : 16, roomy ? 20 : 16, roomy ? 20 : 16, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClarityMark(size: roomy ? 28 : 24),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Clarity',
                    overflow: TextOverflow.ellipsis,
                    style: (roomy
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(roomy ? 20 : 16),
            child: FilledButton.icon(
              onPressed: onQuickAdd,
              icon: Icon(Icons.bolt, size: roomy ? 22 : 18),
              label: Text(HotkeyService.label,
                  style: TextStyle(fontSize: roomy ? 17 : 14)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    EdgeInsets.symmetric(vertical: roomy ? 16 : 12),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: roomy ? 20 : 16),
            child: Text(
              'Tasks',
              style: (roomy
                      ? theme.textTheme.labelLarge
                      : theme.textTheme.labelSmall)
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          for (final f in TaskFilter.values)
            _FilterRow(
              filter: f,
              selected: f == filter,
              badge: _badge(f, counts),
              onTap: () {
                ref.read(filterProvider.notifier).set(f);
                onNavigate?.call();
              },
            ),
          const Spacer(),
          const Divider(height: 1),
          _AccountFooter(onNavigate: onNavigate),
        ],
      ),
    );
  }

  String? _badge(TaskFilter f, ({int inbox, int today}) counts) {
    switch (f) {
      case TaskFilter.today:
        return counts.today > 0 ? '${counts.today}' : null;
      case TaskFilter.inbox:
        return counts.inbox > 0 ? '${counts.inbox}' : null;
      case TaskFilter.done:
        return null;
    }
  }
}

/// Account row + sync status. Mirrors native `SidebarView` footer
/// (avatar, sync dot, launch-at-login lives in Settings on Flutter).
class _AccountFooter extends ConsumerWidget {
  const _AccountFooter({this.onNavigate});
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = AppConfig.isConfigured
        ? ref.watch(authUserProvider).maybeWhen(
              data: (u) => u,
              orElse: () => null,
            )
        : null;
    final status = ref.watch(syncStatusProvider);

    final (dotColor, label) = switch (status) {
      SyncStatus.synced => (Colors.green, 'Synced'),
      SyncStatus.syncing => (Colors.orange, 'Syncing…'),
      SyncStatus.localOnly => (Colors.grey, 'Local only'),
      SyncStatus.error => (Colors.red, 'Sync error'),
    };
    final headline = user?.email ?? 'Local only';

    return Padding(
      padding: EdgeInsets.all(isDesktopApp ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.green.withValues(alpha: 0.2),
                child: Text(
                  headline.isEmpty ? '○' : headline[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.green, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500)),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (user != null)
            TextButton(
              onPressed: () async {
                await ref.read(authServiceProvider).signOut(ref);
                onNavigate?.call();
              },
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Sign out'),
            )
          else if (AppConfig.isConfigured)
            TextButton(
              onPressed: () async {
                // Leave offline mode → AppShell shows the sign-in gate.
                await ref
                    .read(settingsProvider.notifier)
                    .setOfflineMode(false);
                onNavigate?.call();
              },
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Sign in with Google'),
            )
          else
            Text(
              'Cloud sync not set up in this build',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final TaskFilter filter;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  IconData get _icon {
    switch (filter) {
      case TaskFilter.today:
        return Icons.wb_sunny_outlined;
      case TaskFilter.inbox:
        return Icons.inbox_outlined;
      case TaskFilter.done:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Roomier rows in the mobile drawer; desktop unchanged.
    final roomy = !isDesktopApp;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: roomy ? 12 : 8, vertical: roomy ? 3 : 1),
      child: Material(
        color: selected
            ? Colors.green.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 12, vertical: roomy ? 14 : 9),
            child: Row(
              children: [
                Icon(_icon, size: roomy ? 24 : 19),
                SizedBox(width: roomy ? 14 : 10),
                Text(filter.label,
                    style: TextStyle(fontSize: roomy ? 17 : 14)),
                const Spacer(),
                if (badge != null)
                  Text(
                    badge!,
                    style: TextStyle(
                      fontSize: roomy ? 15 : 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
