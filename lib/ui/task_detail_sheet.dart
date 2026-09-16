import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../core/date_parser.dart';
import '../core/task_model.dart';
import 'schedule_sheet.dart';

/// Task detail sheet: opened by tapping a task tile (both platforms).
/// Plain-text title (no NLP re-parse), due date/time chips sharing the
/// schedule picker, quick presets (In 1 hour / Tomorrow 9 AM / Next week /
/// Clear), Save + Delete. Completion stays on the row's circle only.
Future<void> showTaskDetailSheet(BuildContext context, TodoTask task) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetailSheet(task: task),
    );

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet({required this.task});
  final TodoTask task;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  late final TextEditingController _titleCtrl;
  DateTime? _due;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _due = widget.task.dueDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final result = await showScheduleSheet(
      context,
      _due ?? DateTime.now(),
    );
    if (!mounted || result == null) return;
    setState(() {
      _due = result is SchedulePicked ? result.date : null;
    });
  }

  void _presetInOneHour() {
    setState(() {
      _due = DateTime.now().add(const Duration(hours: 1));
    });
  }

  void _presetTomorrowMorning() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    setState(() {
      _due = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
    });
  }

  void _presetNextWeek() {
    setState(() {
      _due = (_due ?? DateTime.now()).add(const Duration(days: 7));
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _titleCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(taskListProvider.notifier).updateTask(
          widget.task.id,
          title: text,
          dueDate: _due,
          clearDue: _due == null,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_saving) return;
    setState(() => _saving = true);
    await ref
        .read(taskListProvider.notifier)
        .deleteByIds([widget.task.id]);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Task title',
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: due != null
                          ? Colors.green
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      due != null
                          ? DateParser.displayString(due)
                          : 'No due date',
                      style: TextStyle(
                        color: due != null
                            ? Colors.green
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const Spacer(),
                    if (due != null)
                      InkWell(
                        onTap: () => setState(() => _due = null),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 16, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PresetChip(
                    label: 'In 1 hour', onTap: _presetInOneHour),
                _PresetChip(
                    label: 'Tomorrow 9 AM',
                    onTap: _presetTomorrowMorning),
                _PresetChip(
                    label: 'Next week', onTap: _presetNextWeek),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red),
                  label: const Text('Delete',
                      style: TextStyle(color: Colors.red)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _titleCtrl.text.trim().isNotEmpty && !_saving
                      ? _save
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
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
