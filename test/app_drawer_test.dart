import 'package:elly_mobile_app/config/nav_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/coming_soon_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:elly_mobile_app/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
  });

  List<NavItem> allItems() => [for (final g in NavConfig.groups) ...g.items];

  /// Dashboard as a user holding exactly [permissions], with the drawer open.
  Future<void> openDrawer(WidgetTester tester, List<String> permissions) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, permissions));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: DashboardScreen(apiService: backend.api)),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  Finder nav(String id) => find.byKey(ValueKey('nav_$id'));

  testWidgets('shows only items whose permission the user has; other actions or users:read do not reveal', (
    tester,
  ) async {
    await openDrawer(tester, [
      'posts:read',
      'pages:read',
      'pages:update',
      'forms:create',
      'assets:delete',
      'users:read',
    ]);

    for (final visible in ['dashboard', 'posts', 'pages', 'settings']) {
      expect(nav(visible), findsOneWidget, reason: '$visible must be visible');
    }
    for (final item in allItems().where((i) => !['dashboard', 'posts', 'pages', 'settings'].contains(i.id))) {
      expect(nav(item.id), findsNothing, reason: '${item.id} must be hidden without ${item.permission}');
    }
    // Groups without a visible item are hidden entirely, like the admin sidebar.
    expect(find.text('İçerik Yönetimi'), findsOneWidget);
    expect(find.text('Sistem'), findsOneWidget); // Ayarlar has no permission
    for (final hidden in ['Bileşenler', 'Medya', 'Etkileşim', 'İletişim']) {
      expect(find.text(hidden), findsNothing, reason: 'group $hidden must be hidden');
    }
  });

  testWidgets('every permission shows every admin sidebar item in order', (tester) async {
    await openDrawer(tester, [
      for (final i in allItems())
        if (i.permission != null) i.permission!,
    ]);

    final items = allItems();
    for (final item in items) {
      expect(nav(item.id), findsOneWidget, reason: item.id);
    }
    final ys = [for (final item in items) tester.getTopLeft(nav(item.id)).dy];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'drawer order = admin sidebar order');
  });

  testWidgets('admin areas not on mobile yet open the "yakında" placeholder', (tester) async {
    await openDrawer(tester, ['chat:read']);
    expect(find.descendant(of: nav('chat'), matching: find.text('Yakında')), findsOneWidget);

    await tester.tap(nav('chat'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Chat')), findsOneWidget);
    expect(find.textContaining('yakında'), findsOneWidget);
  });

  testWidgets('profile header opens the profile placeholder', (tester) async {
    await openDrawer(tester, ['posts:read']);

    await tester.tap(find.byKey(const ValueKey('drawer_profile')));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Profil')), findsOneWidget);
  });

  testWidgets('"Çıkış Yap" signs out', (tester) async {
    await openDrawer(tester, ['posts:read']);
    expect(auth.isAuthenticated, isTrue);

    await tester.tap(find.byKey(const ValueKey('drawer_logout')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500)); // no settle: the dashboard spinner keeps animating

    expect(auth.isAuthenticated, isFalse);
    expect(auth.permissionsLoaded, isFalse);
  });

  ListTile tile(WidgetTester tester, String id) => tester.widget<ListTile>(nav(id));

  Future<void> openSectionDrawer(WidgetTester tester) async {
    tester.state<ScaffoldState>(find.byType(Scaffold).last).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('sections have the drawer too; current item is highlighted; sections replace each other', (tester) async {
    await openDrawer(tester, ['mail:read', 'chat:read']);
    expect(tile(tester, 'dashboard').selected, isTrue);

    await tester.tap(nav('mail-accounts'));
    await tester.pumpAndSettle();
    await openSectionDrawer(tester);
    expect(tile(tester, 'mail-accounts').selected, isTrue);
    expect(tile(tester, 'dashboard').selected, isFalse);

    await tester.tap(nav('chat'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Chat')), findsOneWidget);

    // Stack is [dashboard, chat]: one back press returns to the dashboard.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ComingSoonScreen), findsNothing);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Gösterge Paneli')), findsOneWidget);
  });

  testWidgets('"Gösterge Paneli" from a section pops back to the dashboard', (tester) async {
    await openDrawer(tester, ['mail:read']);
    await tester.tap(nav('mail-accounts'));
    await tester.pumpAndSettle();
    await openSectionDrawer(tester);

    await tester.tap(nav('dashboard'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('profile header: Turkish initials and role label', (tester) async {
    backend.ok('/auth/login', {'token': 'a', 'refreshToken': 'r', 'username': 'ilker'});
    backend.ok('/users/me/permissions', {
      'roles': ['ADMIN'],
      'permissions': ['posts:read'],
    });
    await tester.runAsync(() => auth.login(usernameOrEmail: 'ilker', password: 'p', tenantId: 't1'));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(
          home: Scaffold(drawer: AppDrawer(currentId: 'dashboard')),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('drawer_profile'));
    expect(find.descendant(of: header, matching: find.text('İL')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('ilker')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('Admin')), findsOneWidget);
  });

  test('avatarInitials: Turkish upper case, grapheme-safe, fallback', () {
    expect(avatarInitials('ilker'), 'İL');
    expect(avatarInitials('ışık'), 'IŞ');
    expect(avatarInitials('  ömer '), 'ÖM');
    expect(avatarInitials('👩‍💻dev'), '👩‍💻D');
    expect(avatarInitials('a'), 'A');
    expect(avatarInitials(''), 'U');
  });
}
