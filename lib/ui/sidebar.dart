import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../core/task_model.dart';

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

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: onQuickAdd,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text('Quick Add  ⌘⇧T'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tasks',
              style: theme.textTheme.labelSmall
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.green.withValues(alpha: 0.2),
                      child: const Text(
                        '○',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Local only',
                              style: TextStyle(fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Local only',
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
                Text(
                  'Cloud sync not set up — arrives in Phase 3',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? Colors.green.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(_icon, size: 19),
                const SizedBox(width: 10),
                Text(filter.label),
                const Spacer(),
                if (badge != null)
                  Text(
                    badge!,
                    style: TextStyle(
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
