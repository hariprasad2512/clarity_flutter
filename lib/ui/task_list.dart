import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../core/date_parser.dart';
import '../core/task_model.dart';
import '../desktop/desktop.dart';
import 'schedule_sheet.dart';

/// Detail column: capture bar, search, task list. Mirrors native
/// `TaskListView` (header + count, capture bar with calendar/clock chips,
/// schedule popover with Today/Tomorrow/Weekend presets, rows, empty
/// states, widget footer).
class TaskList extends ConsumerStatefulWidget {
  const TaskList({super.key});

  @override
  ConsumerState<TaskList> createState() => _TaskListState();
}

class _TaskListState extends ConsumerState<TaskList> {
  final _captureCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _captureFocus = FocusNode();
  DateTime? _manualDate;

  @override
  void dispose() {
    _captureCtrl.dispose();
    _searchCtrl.dispose();
    _captureFocus.dispose();
    super.dispose();
  }

  DateTime? get _effectiveDate =>
      _manualDate ?? DateParser.extractDate(_captureCtrl.text);

  Future<void> _addTask() async {
    final task = await ref
        .read(taskListProvider.notifier)
        .add(_captureCtrl.text, manualDate: _manualDate);
    if (task == null || !mounted) return;
    _captureCtrl.clear();
    setState(() => _manualDate = null);
    _captureFocus.requestFocus();
    ref.read(searchProvider.notifier).set(_searchCtrl.text);
  }

  Future<void> _openSchedule() async {
    final now = DateTime.now();
    DateTime draft = _manualDate ?? _effectiveDate ?? now;
    final picked = await showScheduleSheet(context, draft);
    if (!mounted || picked == null) return; // dismissed
    setState(() {
      _manualDate = picked is SchedulePicked ? picked.date : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(filterProvider);
    final tasks = ref.watch(filteredTasksProvider);
    final doneToday = ref.watch(completedTodayProvider);
    final theme = Theme.of(context);
    final showDoneSection =
        (filter == TaskFilter.today || filter == TaskFilter.inbox) &&
            doneToday.isNotEmpty;

    // Re-evaluate chips as the user types.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                filter.label,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${tasks.length}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Spacer(),
              // Flexible (not fixed) so narrow phones never overflow.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (q) =>
                        ref.read(searchProvider.notifier).set(q),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Capture bar (desktop only — mobile creates via the + composer).
        if (isDesktopApp)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Colors.green.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_circle,
                    color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _captureCtrl,
                    focusNode: _captureFocus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Add a task — try "Finish Report"',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _addTask(),
                  ),
                ),
                _ScheduleChip(
                  icon: Icons.calendar_today,
                  label: DateParser.dayLabel(_effectiveDate),
                  active: _effectiveDate != null,
                  onTap: _openSchedule,
                ),
                const SizedBox(width: 6),
                _ScheduleChip(
                  icon: Icons.access_time,
                  label: DateParser.timeLabel(_effectiveDate),
                  active: _effectiveDate != null,
                  onTap: _openSchedule,
                ),
                if (_captureCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _addTask,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: const Text('Add'),
                  ),
                ],
              ],
            ),
          ),
        ),
        // List / empty state
        Expanded(
          child: tasks.isEmpty && !showDoneSection
              ? _EmptyState(filter: filter)
              : ListView.builder(
                  itemCount:
                      tasks.length + (showDoneSection ? doneToday.length + 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i < tasks.length) {
                      return _TaskRow(task: tasks[i]);
                    }
                    if (showDoneSection && i == tasks.length) {
                      return _SectionHeader(
                          label:
                              'Completed today (${doneToday.length})');
                    }
                    return _TaskRow(
                        task: doneToday[i - tasks.length - 1]);
                  },
                ),
        ),
        // Store footer (desktop only; mobile stays uncluttered).
        if (isDesktopApp)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Local store · Hive',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

class _ScheduleChip extends StatelessWidget {
  const _ScheduleChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: active ? 0.14 : 0.06),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: active ? Colors.green : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});
  final TodoTask task;

  Color _dueColor(BuildContext context, DateTime due) {
    if (task.isCompleted) return Colors.grey;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    if (day.isBefore(today)) return Colors.red;
    if (day == today) return Colors.green;
    return Theme.of(context).colorScheme.outline;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mobile gets roomier touch targets; desktop keeps dense rows.
    final roomy = !isDesktopApp;
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) =>
          ref.read(taskListProvider.notifier).deleteByIds([task.id]),
      child: InkWell(
        onTap: () => ref.read(taskListProvider.notifier).toggle(task),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 20, vertical: roomy ? 14 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: roomy ? 2 : 0),
                child: Icon(
                  task.isCompleted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: task.isCompleted ? Colors.grey : Colors.green,
                  size: roomy ? 28 : 22,
                ),
              ),
              SizedBox(width: roomy ? 14 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.isCompleted
                            ? Colors.grey
                            : null,
                        fontSize: roomy ? 17 : 15,
                      ),
                    ),
                    if (task.dueDate != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: roomy ? 14 : 12,
                            color: _dueColor(context, task.dueDate!),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateParser.displayString(task.dueDate!),
                            style: TextStyle(
                              fontSize: roomy ? 13 : 12,
                              color:
                                  _dueColor(context, task.dueDate!),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final TaskFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (filter) {
      TaskFilter.today => (
          Icons.wb_sunny_outlined,
          'Nothing due today. Enjoy the calm.'
        ),
      TaskFilter.inbox => (
          Icons.inbox_outlined,
          'Inbox zero. Press Quick Add anywhere to capture.'
        ),
      TaskFilter.done => (
          Icons.check_circle_outline,
          'No completed tasks yet.'
        ),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 44, color: Colors.green.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text(text,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}
