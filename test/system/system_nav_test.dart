import 'package:elly_mobile_app/config/nav_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/account/profile_screen.dart';
import 'package:elly_mobile_app/screens/account/settings_screen.dart';
import 'package:elly_mobile_app/screens/ai/ai_logs_screen.dart';
import 'package:elly_mobile_app/screens/coming_soon_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:elly_mobile_app/screens/rabbit/rabbit_screen.dart';
import 'package:elly_mobile_app/screens/users/users_screen.dart';
import 'package:elly_mobile_app/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
  });

  test('Sistem items and the profile have real screens; no drawer item is "yakında" any more', () {
    final system = NavConfig.groups.firstWhere((g) => g.title == 'Sistem');
    expect(
      {for (final i in system.items) i.id: navScreen(i).runtimeType},
      {'users': UsersScreen, 'rabbitmq': RabbitScreen, 'ai-logs': AiLogsScreen, 'settings': SettingsScreen},
    );
    expect(navScreen(NavConfig.profile), isA<ProfileScreen>());
    final placeholders = [
      for (final g in NavConfig.groups)
        for (final i in g.items)
          if (i.id != NavConfig.dashboard.id && navScreen(i) == null) i.id,
    ];
    expect(placeholders, isEmpty);
  });

  for (final (id, type, permission) in [
    ('users', UsersScreen, 'users:manage'),
    ('rabbitmq', RabbitScreen, 'rabbit:read'),
    ('ai-logs', AiLogsScreen, null),
    ('settings', SettingsScreen, null),
  ]) {
    testWidgets('drawer "$id": no "Yakında", opens $type with the drawer selected', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => backend.signIn(auth, ['posts:read', ?permission]));
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(home: DashboardScreen(apiService: backend.api)),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('nav_$id'));
      expect(find.descendant(of: tile, matching: find.text('Yakında')), findsNothing);

      await tester.tap(tile);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byType(type), findsOneWidget);
      expect(find.byType(ComingSoonScreen), findsNothing);

      tester.state<ScaffoldState>(find.byType(Scaffold).last).openDrawer();
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(find.byKey(ValueKey('nav_$id'))).selected, isTrue);
    });
  }
}
