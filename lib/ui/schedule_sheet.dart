import 'package:flutter/material.dart';

import '../core/date_parser.dart';

/// Schedule picker result: picked date, cleared, or dismissed (null).
sealed class ScheduleResult {
  const ScheduleResult();
}

class SchedulePicked extends ScheduleResult {
  const SchedulePicked(this.date);
  final DateTime date;
}

class ScheduleCleared extends ScheduleResult {
  const ScheduleCleared();
}

/// Bottom-sheet schedule picker shared by the desktop capture bar and the
/// mobile composer: Today/Tomorrow/Weekend presets (day is set, draft
/// time-of-day kept — like native `applyPreset`), month calendar, time
/// row, Clear/Done. Returns picked/cleared, null when dismissed.
Future<ScheduleResult?> showScheduleSheet(
  BuildContext context,
  DateTime initial,
) =>
    showModalBottomSheet<ScheduleResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ScheduleSheet(initial: initial),
    );

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
                  onPressed: () => Navigator.of(context)
                      .pop(const ScheduleCleared()),
                  child: const Text('Clear'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(SchedulePicked(_draft)),
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
