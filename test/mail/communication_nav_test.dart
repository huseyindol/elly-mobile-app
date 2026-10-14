import 'package:elly_mobile_app/config/nav_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/chat/chat_screen.dart';
import 'package:elly_mobile_app/screens/coming_soon_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_logs_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_templates_screen.dart';
import 'package:elly_mobile_app/screens/mail/mail_accounts_screen.dart';
import 'package:elly_mobile_app/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

const _perms = ['mail:read', 'email_templates:read', 'emails:read'];

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend
      ..ok('/mail-accounts/active', [
        {'id': 1},
      ])
      ..ok('/emails', {
        'content': [
          {'id': 9, 'subject': 'Hoş geldiniz', 'recipient': 'a@b.com', 'status': 'SENT', 'createdAt': 1760259900000},
        ],
        'totalElements': 1,
      });
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, _perms));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: DashboardScreen(apiService: backend.api)),
      ),
    );
    await settle(tester);
  }

  test('İletişim items all have real screens (chat included)', () {
    final group = NavConfig.groups.firstWhere((g) => g.title == 'İletişim');
    expect(
      {for (final i in group.items) i.id: navScreen(i)?.runtimeType},
      {
        'mail-accounts': MailAccountsScreen,
        'email-templates': EmailTemplatesScreen,
        'email-logs': EmailLogsScreen,
        'chat': ChatScreen,
      },
    );
  });

  for (final (id, type) in [
    ('mail-accounts', MailAccountsScreen),
    ('email-templates', EmailTemplatesScreen),
    ('email-logs', EmailLogsScreen),
  ]) {
    testWidgets('drawer "$id": no "Yakında", opens its screen with the drawer selected', (tester) async {
      await pumpDashboard(tester);
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('nav_$id'));
      expect(find.descendant(of: tile, matching: find.text('Yakında')), findsNothing);

      await tester.tap(tile);
      await settle(tester);
      expect(find.byType(type), findsOneWidget);
      expect(find.byType(ComingSoonScreen), findsNothing);

      tester.state<ScaffoldState>(find.byType(Scaffold).last).openDrawer();
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(find.byKey(ValueKey('nav_$id'))).selected, isTrue);
    });
  }

  testWidgets('dashboard "Aktif Mail Hesabı" card → mail accounts', (tester) async {
    await pumpDashboard(tester);
    await tester.tap(find.byKey(const ValueKey('stat_mail-accounts')));
    await settle(tester);
    expect(find.byType(MailAccountsScreen), findsOneWidget);
  });

  testWidgets('dashboard "E-postalar" card → e-mail logs', (tester) async {
    await pumpDashboard(tester);
    await tester.tap(find.byKey(const ValueKey('stat_email-logs')));
    await settle(tester);
    expect(find.byType(EmailLogsScreen), findsOneWidget);
  });

  testWidgets('dashboard "Son E-postalar" → "Tümü" → e-mail logs', (tester) async {
    await pumpDashboard(tester);
    final all = find.descendant(
      of: find.ancestor(of: find.text('Son E-postalar'), matching: find.byType(Column)).first,
      matching: find.text('Tümü'),
    );
    await tester.ensureVisible(all);
    await tester.tap(all);
    await settle(tester);
    expect(find.byType(EmailLogsScreen), findsOneWidget);
  });
}
