import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// One reusable confirmation dialog (spec §19) — every "are you sure?"
/// moment (cancel a booking, remove a playing area, etc.) goes through this
/// instead of a bespoke AlertDialog per screen. Returns true if the user
/// confirmed, false/null otherwise.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.destructive) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}