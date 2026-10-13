import 'package:flutter/material.dart';

/// The app's only way to show a SnackBar: replaces the current one (no queue of stale messages), error →
/// `colorScheme.error` background. Text/action colors come from `appTheme.snackBarTheme`.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool error = false,
  SnackBarAction? action,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message.replaceFirst('Exception: ', '')),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        action: action,
        duration: duration ?? Duration(seconds: error ? 6 : 3),
      ),
    );
}

/// Failed `validateGranularly`: scrolls to the first invalid field and names it ("2 alan hatalı: Etiket").
/// [labelOf] maps a field state to its label (null → the field's error text is shown instead).
void reportInvalidFields(
  BuildContext context,
  Set<FormFieldState<Object?>> invalid, {
  String? Function(FormFieldState<Object?> field)? labelOf,
}) {
  final first = invalid.first;
  Scrollable.ensureVisible(first.context, alignment: 0.2, duration: const Duration(milliseconds: 250));
  final name = labelOf?.call(first) ?? first.errorText;
  showAppSnackBar(context, '${invalid.length} alan hatalı${name == null ? '' : ': $name'}', error: true);
}
