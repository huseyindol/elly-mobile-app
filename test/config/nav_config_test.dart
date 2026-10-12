import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/config/nav_config.dart';
import 'package:elly_mobile_app/widgets/app_drawer.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

/// Expected admin sidebar (`elly-admin/src/app/_components/Sidebar.tsx`):
/// group title → (id, label, permission). Update both sides together.
const _adminSidebar = <String, List<(String, String, String?)>>{
  '': [('dashboard', 'Gösterge Paneli', null)],
  'İçerik Yönetimi': [
    ('posts', 'Yazılar', 'posts:read'),
    ('pages', 'Sayfalar', 'pages:read'),
    ('contents', 'İçerikler', 'contents:read'),
  ],
  'Bileşenler': [
    ('components', 'Componentler', 'components:read'),
    ('widgets', 'Widgetlar', 'widgets:read'),
    ('banners', 'Bannerlar', 'banners:read'),
  ],
  'Medya': [('assets', 'Assetler', 'assets:read')],
  'Etkileşim': [('forms', 'Formlar', 'forms:read')],
  'İletişim': [
    ('mail-accounts', 'Mail Hesapları', 'mail:read'),
    ('email-templates', 'Email Templates', 'email_templates:read'),
    ('email-logs', 'Email Logları', 'emails:read'),
    ('chat', 'Chat', 'chat:read'),
  ],
  'Sistem': [
    ('users', 'Kullanıcılar', 'users:manage'),
    ('rabbitmq', 'RabbitMQ', 'rabbit:read'),
    ('settings', 'Ayarlar', null),
  ],
};

void main() {
  group('NavConfig matches the admin sidebar', () {
    test('groups appear in the same order with the same titles', () {
      expect([for (final g in NavConfig.groups) g.title], _adminSidebar.keys.toList());
    });

    test('every group has the same items in the same order (id, label, permission)', () {
      for (final group in NavConfig.groups) {
        final actual = [for (final i in group.items) (i.id, i.label, i.permission)];
        expect(actual, _adminSidebar[group.title], reason: 'group "${group.title}"');
      }
    });

    test('only the dashboard group has no header', () {
      expect(
        [
          for (final g in NavConfig.groups)
            if (g.title.isEmpty) g.title,
        ],
        [''],
      );
      expect(NavConfig.groups.first.title, isEmpty);
    });

    test('item ids are unique and byId resolves every item and the profile entry', () {
      final items = [for (final g in NavConfig.groups) ...g.items];
      expect({for (final i in items) i.id}, hasLength(items.length));
      for (final item in items) {
        expect(NavConfig.byId(item.id), same(item));
      }
      expect(NavConfig.byId('profile'), same(NavConfig.profile));
      expect(() => NavConfig.byId('does-not-exist'), throwsStateError);
    });

    test('profile is not a drawer-group item and has no permission', () {
      expect([for (final g in NavConfig.groups) ...g.items], isNot(contains(NavConfig.profile)));
      expect(NavConfig.profile.permission, isNull);
    });
  });

  group('NavItem.crud', () {
    test('derives id, label, icon and "<key>:read" from the module', () {
      final item = NavItem.crud('posts');
      final module = ModulesConfig.byKey('posts');

      expect(item.id, 'posts');
      expect(item.label, module.title);
      expect(item.icon, module.icon);
      expect(item.permission, 'posts:read');
      expect(item.module, same(module));
    });

    test('every CRUD nav item is wired to a module; the others are "yakında" placeholders', () {
      final crudIds = ModulesConfig.allModules.map((m) => m.permissionKey).toSet();
      for (final item in [for (final g in NavConfig.groups) ...g.items]) {
        if (crudIds.contains(item.id)) {
          expect(item.module, isNotNull, reason: item.id);
          expect(item.permission, '${item.id}:read', reason: item.id);
        } else {
          expect(item.module, isNull, reason: '${item.id} has no mobile screen yet');
        }
      }
    });

    test('every module is reachable from the drawer', () {
      final navModules = {
        for (final g in NavConfig.groups)
          for (final i in g.items) i.module?.permissionKey,
      };
      for (final module in ModulesConfig.allModules) {
        expect(navModules, contains(module.permissionKey));
      }
    });
  });

  group('drawer visibility (isNavItemVisible + group hiding)', () {
    late FakeBackend backend;

    setUp(() => backend = FakeBackend());

    /// Ids of the items a user holding exactly [keys] sees; group titles of non-empty groups.
    Future<({List<String> ids, List<String> groupTitles})> visibleFor(List<String> keys) async {
      final auth = backend.newAuth();
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
      backend.permissions(keys);
      await auth.checkAuthStatus();

      final ids = <String>[];
      final titles = <String>[];
      for (final group in NavConfig.groups) {
        final visible = group.items.where((i) => isNavItemVisible(auth, i)).toList();
        if (visible.isEmpty) continue; // AppDrawer renders nothing (not even the header) for these
        ids.addAll(visible.map((i) => i.id));
        if (group.title.isNotEmpty) titles.add(group.title);
      }
      return (ids: ids, groupTitles: titles);
    }

    test('no permissions: only items without a permission remain, so only "Sistem" keeps its header', () async {
      final v = await visibleFor([]);
      expect(v.ids, ['dashboard', 'settings']);
      expect(v.groupTitles, ['Sistem']);
    });

    test('a group whose items are all hidden disappears, including its header', () async {
      final v = await visibleFor(['mail:read']);
      expect(v.ids, ['dashboard', 'mail-accounts', 'settings']);
      expect(v.groupTitles, ['İletişim', 'Sistem']);
    });

    test('a single visible item is enough to keep the group', () async {
      final v = await visibleFor(['forms:read', 'rabbit:read']);
      expect(v.groupTitles, ['Etkileşim', 'Sistem']);
      expect(v.ids, ['dashboard', 'forms', 'rabbitmq', 'settings']);
    });

    test('create/update/delete and users:read do not reveal items; users:manage does', () async {
      final hidden = await visibleFor(['posts:create', 'posts:update', 'posts:delete', 'users:read']);
      expect(hidden.ids, ['dashboard', 'settings']);

      final shown = await visibleFor(['users:manage']);
      expect(shown.ids, ['dashboard', 'users', 'settings']);
    });

    test('all permissions: every item and every titled group is visible', () async {
      final all = [
        for (final g in NavConfig.groups)
          for (final i in g.items)
            if (i.permission != null) i.permission!,
      ];
      final v = await visibleFor(all);
      expect(v.ids, [for (final g in NavConfig.groups) ...g.items.map((i) => i.id)]);
      expect(v.groupTitles, [
        for (final g in NavConfig.groups)
          if (g.title.isNotEmpty) g.title,
      ]);
    });

    test('before permissions are loaded nothing gated is visible', () {
      final auth = backend.newAuth();
      for (final item in [for (final g in NavConfig.groups) ...g.items]) {
        expect(isNavItemVisible(auth, item), item.permission == null, reason: item.id);
      }
    });
  });
}
