import 'package:flutter/material.dart';

/// Yes/no dialog; true only when the user taps the confirm button.
/// [destructive]: confirm button in `colorScheme.error` (delete, purge, force delete...).
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
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        backgroundColor: scheme.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(cancelLabel)),
          ElevatedButton(
            key: confirmKey,
            style: ElevatedButton.styleFrom(
              backgroundColor: destructive ? scheme.error : scheme.primary,
              foregroundColor: destructive ? scheme.onError : scheme.onPrimary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result == true;
}

/// Form back-navigation guard: unsaved edits (or a save still running) → "Çık / Kal".
Future<bool> confirmLeaveForm(BuildContext context, {bool saving = false}) => showConfirmDialog(
  context,
  title: saving ? 'Kayıt sürüyor' : 'Kaydedilmemiş değişiklikler',
  message: saving
      ? 'Kayıt henüz tamamlanmadı. Çıkarsanız sonucu göremezsiniz.'
      : 'Değişiklikler kaydedilmedi ve kaybolacak. Çıkılsın mı?',
  confirmLabel: 'Çık',
  cancelLabel: 'Kal',
  destructive: true,
  confirmKey: const ValueKey('confirm_leave_button'),
);
