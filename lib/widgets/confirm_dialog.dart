import 'package:flutter/material.dart';

/// Yes/no dialog; true only when the user taps the confirm button.
/// [destructive]: red confirm button (delete, purge, force delete...).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Onayla',
  String cancelLabel = 'Vazgeç',
  bool destructive = false,
  Key confirmKey = const ValueKey('confirm_dialog_button'),
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C22),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel, style: const TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          key: confirmKey,
          style: ElevatedButton.styleFrom(
            backgroundColor: destructive ? Colors.redAccent : const Color(0xFF6366F1),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}
