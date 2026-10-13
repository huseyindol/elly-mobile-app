import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Small pill label in a list row / detail header (Aktif / Pasif, Ana Hesap, e-mail status, …).
class StatusBadge extends StatelessWidget {
  final String label;

  /// null → muted (inactive look).
  final Color? color;

  const StatusBadge({super.key, required this.label, this.color});

  const StatusBadge.active(bool active, {super.key})
    : label = active ? 'Aktif' : 'Pasif',
      color = active ? AppColors.success : null;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
