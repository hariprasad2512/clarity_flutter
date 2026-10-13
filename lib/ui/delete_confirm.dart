import 'package:flutter/material.dart';

/// Shared "Are you sure?" delete confirmation (v1.2.2). Used by both the
/// swipe-to-delete guard and the edit-sheet Delete button so the copy and
/// behavior stay identical. Returns true only for an explicit Delete tap;
/// dismiss/Cancel yields false.
Future<bool> showDeleteConfirm(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this task?'),
      content: Text(
        'Are you sure you want to delete "$title"?',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
