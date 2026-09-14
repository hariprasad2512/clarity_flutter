import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../core/date_parser.dart';
import 'schedule_sheet.dart';

/// Mobile task composer: Google-Tasks-style bottom sheet. Title field,
/// date/time chips sharing the schedule picker, parsed-date preview,
/// right-aligned Save. v1 scope: no details/star rows.
Future<void> showTaskComposer(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ComposerSheet(),
    );

class _ComposerSheet extends ConsumerStatefulWidget {
  const _ComposerSheet();

  @override
  ConsumerState<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends ConsumerState<_ComposerSheet> {
  final _ctrl = TextEditingController();
  DateTime? _manualDate;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  DateTime? get _effectiveDate =>
      _manualDate ?? DateParser.extractDate(_ctrl.text);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final result = await showScheduleSheet(
      context,
      _manualDate ?? _effectiveDate ?? now,
    );
    if (!mounted || result == null) return;
    setState(() {
      _manualDate = result is SchedulePicked ? result.date : null;
    });
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    await ref
        .read(taskListProvider.notifier)
        .add(text, manualDate: _manualDate);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final date = _effectiveDate;
    final canSave = _ctrl.text.trim().isNotEmpty && !_saving;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 12,
          top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'New task',
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            if (date != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      DateParser.displayString(date),
                      style:
                          const TextStyle(color: Colors.green),
                    ),
                    if (_manualDate != null) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () =>
                            setState(() => _manualDate = null),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Set date',
                  icon: const Icon(Icons.calendar_month_outlined),
                  color: _manualDate != null
                      ? Colors.green
                      : Theme.of(context).colorScheme.outline,
                  onPressed: _pickDate,
                ),
                IconButton(
                  tooltip: 'Set time',
                  icon: const Icon(Icons.access_time_outlined),
                  color: _manualDate != null
                      ? Colors.green
                      : Theme.of(context).colorScheme.outline,
                  onPressed: _pickDate,
                ),
                const Spacer(),
                TextButton(
                  onPressed: canSave ? _save : null,
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
