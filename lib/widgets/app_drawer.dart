import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/nav_config.dart';
import '../providers/auth_provider.dart';
import '../screens/assets_screen.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/crud/generic_crud_list_screen.dart';
import '../services/text_format.dart';

bool isNavItemVisible(AuthProvider auth, NavItem item) => item.permission == null || auth.has(item.permission!);

/// Opens [item]. Sections replace each other: the stack is always [dashboard] or [dashboard, section],
/// however long the user browses (system back from a section → dashboard).
void openNavItem(BuildContext context, NavItem item) {
  final navigator = Navigator.of(context);
  navigator.popUntil((route) => route.isFirst);
  if (item.id == NavConfig.dashboard.id) return;
  final module = item.module;
  navigator.push(
    MaterialPageRoute(
      settings: RouteSettings(name: item.id),
      builder: (_) => switch (module?.permissionKey) {
        null => ComingSoonScreen(title: item.label, navId: item.id),
        'assets' => const AssetsScreen(),
        _ => GenericCrudListScreen(module: module!),
      },
    ),
  );
}

/// "hüseyin" → "HÜ" (grapheme-safe, Turkish upper case).
String avatarInitials(String name) => name.trim().isEmpty ? 'U' : upperTr(name.trim().characters.take(2).toString());

/// Main navigation: admin sidebar groups filtered by permission, profile header, logout.
class AppDrawer extends StatelessWidget {
  /// `NavItem.id` of the screen hosting the drawer (highlighted; tapping it just closes the drawer).
  final String currentId;

  const AppDrawer({super.key, required this.currentId});

  void _open(BuildContext context, NavItem item) {
    Navigator.of(context).pop(); // close the drawer
    if (item.id != currentId) openNavItem(context, item);
  }

  /// Header + visible items of [group]; nothing when no item is visible (like the admin sidebar).
  List<Widget> _groupTiles(BuildContext context, AuthProvider auth, NavGroup group) {
    final items = group.items.where((item) => isNavItemVisible(auth, item)).toList();
    if (items.isEmpty) return const [];
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
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
          selected: item.id == currentId,
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
    final scheme = Theme.of(context).colorScheme;
    final name = auth.currentUser?.username ?? '';

    return Drawer(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              key: const ValueKey('drawer_profile'),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              leading: CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: Text(avatarInitials(name), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              title: Text(name.isEmpty ? 'Kullanıcı' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(auth.roleLabel, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
              trailing: const Icon(Icons.chevron_right_rounded, semanticLabel: 'Profil'),
              selected: currentId == NavConfig.profile.id,
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
              iconColor: scheme.onErrorContainer,
              textColor: scheme.onErrorContainer,
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Çıkış Yap'),
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
