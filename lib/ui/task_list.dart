import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../core/date_parser.dart';
import '../core/task_model.dart';

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
    final picked = await showModalBottomSheet<DateTime?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ScheduleSheet(initial: draft),
    );
    // null return = dismissed; _ScheduleSheet returns _Sentinel.clear for Clear
    if (!mounted) return;
    if (picked == null) return; // dismissed
    setState(() {
      _manualDate = picked.year == 1 ? null : picked; // year 1 = Clear sentinel
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(filterProvider);
    final tasks = ref.watch(filteredTasksProvider);
    final theme = Theme.of(context);

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
              SizedBox(
                width: 220,
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
            ],
          ),
        ),
        // Capture bar
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
          child: tasks.isEmpty
              ? _EmptyState(filter: filter)
              : ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (ctx, i) =>
                      _TaskRow(task: tasks[i]),
                ),
        ),
        // Store footer
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text(
                'Local store · Hive',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const Spacer(),
              Text(
                'Widget arrives in Phase 5',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
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
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.isCompleted
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color:
                    task.isCompleted ? Colors.grey : Colors.green,
                size: 22,
              ),
              const SizedBox(width: 12),
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
                        fontSize: 15,
                      ),
                    ),
                    if (task.dueDate != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 12,
                            color: _dueColor(context, task.dueDate!),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateParser.displayString(task.dueDate!),
                            style: TextStyle(
                              fontSize: 12,
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

/// Bottom-sheet schedule picker: Today/Tomorrow/Weekend presets (day is
/// set, draft time-of-day kept — like native `applyPreset`), month
/// calendar, time row, Clear/Done. Returns picked date, year-1 sentinel
/// for Clear, null when dismissed.
class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.initial});
  final DateTime initial;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late DateTime _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  void _applyPreset(int dayOffset) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day)
        .add(Duration(days: dayOffset));
    setState(() {
      _draft = DateTime(
          day.year, day.month, day.day, _draft.hour, _draft.minute);
    });
  }

  void _applyWeekend() {
    final weekday = DateTime.now().weekday; // Mon=1..Sun=7
    _applyPreset((6 - weekday + 7) % 7);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PresetChip(label: 'Today', onTap: () => _applyPreset(0)),
                _PresetChip(
                    label: 'Tomorrow', onTap: () => _applyPreset(1)),
                _PresetChip(label: 'Weekend', onTap: _applyWeekend),
              ],
            ),
            CalendarDatePicker(
              initialDate: _draft,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
              onDateChanged: (d) => setState(() {
                _draft = DateTime(
                    d.year, d.month, d.day, _draft.hour, _draft.minute);
              }),
            ),
            Row(
              children: [
                const Icon(Icons.access_time,
                    color: Colors.green, size: 20),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_draft),
                    );
                    if (t != null) {
                      setState(() {
                        _draft = DateTime(_draft.year, _draft.month,
                            _draft.day, t.hour, t.minute);
                      });
                    }
                  },
                  child: Text(DateParser.timeLabel(_draft)),
                ),
                const Spacer(),
                TextButton(
                  // Clear sentinel: year 1 (handled by caller).
                  onPressed: () => Navigator.of(context)
                      .pop(DateTime(1, 1, 1)),
                  child: const Text('Clear'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_draft),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.green.withValues(alpha: 0.12),
      labelStyle: const TextStyle(color: Colors.green),
      side: BorderSide.none,
    );
  }
}
