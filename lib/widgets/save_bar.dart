import 'package:flutter/material.dart';

/// Form save button pinned under the scrolling form (stays reachable on long forms).
class SaveBar extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;
  final Key buttonKey;

  const SaveBar({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.label = 'Kaydet',
    this.buttonKey = const ValueKey('crud_save_button'),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            key: buttonKey,
            onPressed: loading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: loading
                ? CircularProgressIndicator(color: scheme.onPrimary, semanticsLabel: 'Kaydediliyor')
                : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}
