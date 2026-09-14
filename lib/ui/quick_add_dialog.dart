import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../core/date_parser.dart';

/// Spotlight-style quick-add. Fresh state on every open so focus always
/// lands in the field — mirrors native `QuickAddView`.
/// Enter = save (stays open for rapid entry), Esc = dismiss.
class QuickAddDialog extends ConsumerStatefulWidget {
  const QuickAddDialog({super.key});

  @override
  ConsumerState<QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends ConsumerState<QuickAddDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _showDatePicker = false;
  DateTime _manualDate = DateTime.now();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime? get _parsedDate =>
      _showDatePicker ? _manualDate : DateParser.extractDate(_ctrl.text);

  /// Enter (or Add) saves and closes — matching the floating panel.
  /// Rapid entry = summon again (hotkey/FAB).
  Future<void> _save({bool close = true}) async {
    final task = await ref.read(taskListProvider.notifier).add(
          _ctrl.text,
          manualDate: _showDatePicker ? _manualDate : null,
        );
    if (task == null || !mounted) return;
    if (close) {
      Navigator.of(context).pop();
      return;
    }
    _ctrl.clear();
    setState(() {
      _showDatePicker = false;
      _manualDate = DateTime.now();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final date = _parsedDate;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => Navigator.of(context).pop(),
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.green.withValues(alpha: 0.5),
          ),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt,
                      color: Colors.green, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: true,
                      style: const TextStyle(fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'What needs to be done?',
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                  if (_ctrl.text.trim().isNotEmpty)
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Add'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: date != null
                        ? Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 15, color: Colors.green),
                              const SizedBox(width: 6),
                              Text(
                                DateParser.displayString(date),
                                style: const TextStyle(
                                    color: Colors.green),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Icon(
                                _ctrl.text.isEmpty
                                    ? Icons.keyboard
                                    : Icons.inbox_outlined,
                                size: 15,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _ctrl.text.isEmpty
                                    ? '⏎ save & close · esc dismiss'
                                    : 'No date — goes to Inbox',
                                style: const TextStyle(
                                    color: Colors.grey),
                              ),
                            ],
                          ),
                  ),
                  IconButton(
                    tooltip: 'Set date manually',
                    icon: const Icon(Icons.calendar_month),
                    color: _showDatePicker ? Colors.green : Colors.grey,
                    onPressed: () => setState(
                        () => _showDatePicker = !_showDatePicker),
                  ),
                ],
              ),
              if (_showDatePicker)
                CalendarDatePicker(
                  initialDate: _manualDate,
                  firstDate: DateTime(2020),
                  lastDate:
                      DateTime.now().add(const Duration(days: 365 * 3)),
                  onDateChanged: (d) => setState(() {
                    _manualDate = DateTime(d.year, d.month, d.day,
                        _manualDate.hour, _manualDate.minute);
                  }),
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
      ),
    );
  }
}

/// Shows the Quick-Add dialog on any platform.
Future<void> showQuickAdd(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const QuickAddDialog(),
    );
