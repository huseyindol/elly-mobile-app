import 'package:flutter/material.dart';

import '../widgets/app_scaffold.dart';
import '../widgets/state_views.dart';

/// Placeholder for admin areas not on mobile yet (filled by later phases).
class ComingSoonScreen extends StatelessWidget {
  final String title;

  /// Drawer item of this section (keeps the drawer available here).
  final String? navId;

  const ComingSoonScreen({super.key, required this.title, this.navId});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: title,
      navId: navId,
      body: const EmptyView(
        icon: Icons.construction_rounded,
        message: 'Bu bölüm mobil uygulamada yakında. Şimdilik yönetim panelinden kullanabilirsiniz.',
      ),
    );
  }
}
