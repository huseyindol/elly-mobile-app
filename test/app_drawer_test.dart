import 'package:elly_mobile_app/config/nav_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/coming_soon_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
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
    await openDrawer(tester, ['mail:read']);
    expect(find.descendant(of: nav('mail-accounts'), matching: find.text('Yakında')), findsOneWidget);

    await tester.tap(nav('mail-accounts'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Mail Hesapları')), findsOneWidget);
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
}
