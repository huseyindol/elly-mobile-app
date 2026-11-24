import 'package:flutter/material.dart';

import '../models/crud_module.dart';
import 'modules_config.dart';

/// A drawer entry. Mirrors an elly-admin sidebar link (`elly-admin/src/app/_components/Sidebar.tsx`).
class NavItem {
  /// Admin route without the leading slash (`posts`, `mail-accounts`, ...).
  final String id;
  final String label;
  final IconData icon;

  /// `<module>:<action>` from PermissionConstants.java; null = every signed-in user (like the admin).
  final String? permission;

  /// Usernames allowed to see this item (null = not user-specific). Both [permission] AND this must pass —
  /// e.g. Mac Kamerası is a personal-device page: users:manage admins other than the owner must not see it.
  /// Unknown username (profile not loaded, login data missing) hides the item (fail-closed).
  final Set<String>? visibleUsernames;

  /// CRUD screen; null = custom screen (`navScreen` in app_drawer.dart) or not on mobile yet → "yakında".
  final CrudModule? module;

  const NavItem({required this.id, required this.label, required this.icon, this.permission, this.module, this.visibleUsernames});

  NavItem.crud(String permissionKey) : this._fromModule(ModulesConfig.byKey(permissionKey));

  NavItem._fromModule(CrudModule m)
    : this(id: m.permissionKey, label: m.title, icon: m.icon, permission: '${m.permissionKey}:read', module: m);
}

class NavGroup {
  /// Empty = no header (dashboard).
  final String title;
  final List<NavItem> items;
  const NavGroup(this.title, this.items);
}

class NavConfig {
  /// Kişisel "Hızlı Arama" sayfasını görebilen yetkili kullanıcı adları.
  static const quickCallUsernames = {'huseyindol', 'zehradol'};

  static const dashboard = NavItem(id: 'dashboard', label: 'Gösterge Paneli', icon: Icons.home_rounded);
  static const profile = NavItem(id: 'profile', label: 'Profil', icon: Icons.person_rounded);

  /// Same groups, order and permissions as the admin sidebar.
  static final List<NavGroup> groups = [
    const NavGroup('', [dashboard]),
    NavGroup('İçerik Yönetimi', [NavItem.crud('posts'), NavItem.crud('pages'), NavItem.crud('contents')]),
    NavGroup('Bileşenler', [NavItem.crud('components'), NavItem.crud('widgets'), NavItem.crud('banners')]),
    NavGroup('Medya', [NavItem.crud('assets')]),
    NavGroup('Etkileşim', [NavItem.crud('forms')]),
    const NavGroup('İletişim', [
      NavItem(
        id: 'mail-accounts',
        label: 'Mail Hesapları',
        icon: Icons.alternate_email_rounded,
        permission: 'mail:read',
      ),
      NavItem(
        id: 'email-templates',
        label: 'Email Templates',
        icon: Icons.mail_outline_rounded,
        permission: 'email_templates:read',
      ),
      NavItem(id: 'email-logs', label: 'Email Logları', icon: Icons.inbox_rounded, permission: 'emails:read'),
      NavItem(id: 'chat', label: 'Chat', icon: Icons.chat_bubble_outline_rounded, permission: 'chat:read'),
    ]),
    const NavGroup('Sistem', [
      NavItem(id: 'users', label: 'Kullanıcılar', icon: Icons.people_rounded, permission: 'users:manage'),
      NavItem(
        id: 'mac-camera',
        label: 'Hızlı Arama',
        icon: Icons.phone_in_talk_rounded,
        permission: 'users:manage',
        visibleUsernames: quickCallUsernames, // kişisel hızlı arama sayfası — yalnız huseyindol ve zehradol
      ),
      NavItem(id: 'rabbitmq', label: 'RabbitMQ', icon: Icons.monitor_heart_rounded, permission: 'rabbit:read'),
      NavItem(id: 'ai-logs', label: 'AI Logları', icon: Icons.auto_awesome_rounded),
      NavItem(id: 'settings', label: 'Ayarlar', icon: Icons.settings_rounded),
    ]),
  ];

  static NavItem byId(String id) => [profile, for (final g in groups) ...g.items].firstWhere((item) => item.id == id);
}
