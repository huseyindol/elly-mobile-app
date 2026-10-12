import 'package:flutter/material.dart';

import '../widgets/state_views.dart';

/// Placeholder for admin areas not on mobile yet (filled by later phases).
class ComingSoonScreen extends StatelessWidget {
  final String title;
  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const EmptyView(
        icon: Icons.construction_rounded,
        message: 'Bu bölüm mobil uygulamada yakında. Şimdilik yönetim panelinden kullanabilirsiniz.',
      ),
    );
  }
}
