import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Boxed hint under/above form fields (admin's blue ℹ️ / amber ⚠️ notes). [warning] → amber border.
class InfoNote extends StatelessWidget {
  final String text;
  final bool warning;

  const InfoNote(this.text, {super.key, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = warning ? AppColors.warning : AppColors.primaryLight;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded, size: 18, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.85))),
          ),
        ],
      ),
    );
  }
}
