import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_store.dart';
import '../core/date_parser.dart';
import 'schedule_sheet.dart';

/// Mobile task composer: Google-Tasks-style bottom sheet. Title field,
/// date/time chips sharing the schedule picker, parsed-date preview,
/// right-aligned Save. v1 scope: no details/star rows.
///
/// Smoothness: keystrokes update a [ValueNotifier] — only the preview
/// line and the Save button rebuild per keystroke. The icon row, date
/// highlight and sheet chrome rebuild only when the manual date changes
/// (picker result), keeping 60fps while typing with the keyboard up.
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

class _ComposerSheetState extends ConsumerState<_ComposerSheet>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _text = ValueNotifier<String>('');
  DateTime? _manualDate;
  bool _saving = false;
  Timer? _parseDebounce;
  DateTime? _previewDate;

  /// Keyboard was visible at least once (autofocus opens it). When it
  /// hides afterwards (system back / hide-keyboard button), the composer
  /// goes with it — matching Google Tasks behavior.
  bool _keyboardWasVisible = false;

  /// True while the schedule picker is on top (it also hides the
  /// keyboard — that must NOT dismiss the composer).
  bool _pickingDate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    _text.dispose();
    _parseDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding
        .instance.platformDispatcher.views.firstOrNull;
    if (view == null || !mounted || _saving || _pickingDate) return;
    final keyboardHeight =
        view.viewInsets.bottom / view.devicePixelRatio;
    if (keyboardHeight > 0) {
      _keyboardWasVisible = true;
    } else if (_keyboardWasVisible) {
      Navigator.of(context).maybePop();
    }
  }

  void _onChanged(String v) {
    _text.value = v;
    // Debounced NLP preview: regexes run at most ~7x/sec while typing.
    _parseDebounce?.cancel();
    _parseDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      final manual = _manualDate;
      setState(() {
        _previewDate =
            manual ?? DateParser.extractDate(_text.value);
      });
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    _pickingDate = true;
    final result = await showScheduleSheet(
      context,
      _manualDate ?? _previewDate ?? now,
    );
    _pickingDate = false;
    if (!mounted || result == null) return;
    final picked = result is SchedulePicked ? result.date : null;
    setState(() {
      _manualDate = picked;
      _previewDate = picked ?? DateParser.extractDate(_text.value);
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
    final manual = _manualDate;
    final highlight = manual != null
        ? Colors.green
        : Theme.of(context).colorScheme.outline;
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
              onChanged: _onChanged,
              onSubmitted: (_) => _save(),
            ),
            // Rebuilds debounced, isolated from the static icon row.
            ValueListenableBuilder<String>(
              valueListenable: _text,
              builder: (context, value, _) {
                final date = _previewDate;
                if (date == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        DateParser.displayString(date),
                        style: const TextStyle(color: Colors.green),
                      ),
                      if (manual != null) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => setState(() {
                            _manualDate = null;
                            _previewDate =
                                DateParser.extractDate(_text.value);
                          }),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Set date',
                  icon: const Icon(Icons.calendar_month_outlined),
                  color: highlight,
                  onPressed: _pickDate,
                ),
                IconButton(
                  tooltip: 'Set time',
                  icon: const Icon(Icons.access_time_outlined),
                  color: highlight,
                  onPressed: _pickDate,
                ),
                const Spacer(),
                ValueListenableBuilder<String>(
                  valueListenable: _text,
                  builder: (context, value, _) => TextButton(
                    onPressed:
                        value.trim().isNotEmpty && !_saving ? _save : null,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
