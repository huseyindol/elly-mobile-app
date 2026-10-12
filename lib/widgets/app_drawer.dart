import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/nav_config.dart';
import '../providers/auth_provider.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/crud/generic_crud_list_screen.dart';

bool isNavItemVisible(AuthProvider auth, NavItem item) => item.permission == null || auth.has(item.permission!);

/// Opens [item] on top of the dashboard (CRUD list or "yakında" placeholder).
void openNavItem(BuildContext context, NavItem item) {
  if (item.id == NavConfig.dashboard.id) return;
  final module = item.module;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => module != null ? GenericCrudListScreen(module: module) : ComingSoonScreen(title: item.label),
    ),
  );
}

/// Main navigation: admin sidebar groups, filtered by permission; profile + logout.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _open(BuildContext context, NavItem item) {
    Navigator.of(context).pop(); // close the drawer first
    openNavItem(context, item);
  }

  /// Header + visible items of [group]; nothing when no item is visible (like the admin sidebar).
  List<Widget> _groupTiles(BuildContext context, AuthProvider auth, NavGroup group) {
    final items = group.items.where((item) => isNavItemVisible(auth, item)).toList();
    if (items.isEmpty) return const [];
    final muted = Colors.white.withValues(alpha: 0.5);
    return [
      if (group.title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Semantics(
            header: true,
            // No toUpperCase(): Dart maps Turkish i → I (İletişim → ILETIŞIM).
            child: Text(
              group.title,
              style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      for (final item in items)
        ListTile(
          key: ValueKey('nav_${item.id}'),
          leading: Icon(item.icon),
          title: Text(item.label),
          selected: item.id == NavConfig.dashboard.id,
          trailing: item.module == null && item.id != NavConfig.dashboard.id
              ? Text('Yakında', style: TextStyle(color: muted, fontSize: 12))
              : null,
          onTap: () => _open(context, item),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.currentUser?.username ?? '';
    final initials = name.isEmpty ? 'U' : name.substring(0, name.length < 2 ? name.length : 2).toUpperCase();
    final muted = Colors.white.withValues(alpha: 0.5);

    return Drawer(
      backgroundColor: const Color(0xFF111116),
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              key: const ValueKey('drawer_profile'),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(name.isEmpty ? 'Kullanıcı' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('Profil', style: TextStyle(color: muted)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(context, NavConfig.profile),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [for (final group in NavConfig.groups) ..._groupTiles(context, auth, group)],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('drawer_logout'),
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Çıkış Yap', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.of(context).pop();
                auth.logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
