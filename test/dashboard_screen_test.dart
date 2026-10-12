import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/coming_soon_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

const _allCardPermissions = [
  'posts:read',
  'forms:read',
  'users:manage',
  'mail:read',
  'chat:read',
  'emails:read',
  'banners:read',
  'assets:read',
];

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend
      ..ok('/posts/list/summary', [
        {'id': 1, 'title': 'Birinci Yazı', 'slug': 'birinci', 'status': true},
        {'id': 2, 'title': 'Taslak Yazı', 'slug': 'taslak', 'status': false},
      ])
      ..ok('/forms/list', [
        {'id': 1},
      ])
      ..ok('/users', [
        {'id': 1},
        {'id': 2},
        {'id': 3},
      ])
      ..ok('/mail-accounts/active', [
        {'id': 1},
      ])
      ..ok('/chat/groups', [])
      ..ok('/emails', {
        'content': [
          {
            'id': 9,
            'subject': 'Hoş geldiniz',
            'recipient': 'a@b.com',
            'status': 'SENT',
            'createdAt': '2026-10-12T09:05:00Z',
          },
          {'id': 8, 'subject': '', 'recipient': 'c@d.com', 'status': 'FAILED', 'createdAt': 1760259900000},
        ],
        'totalElements': 1234,
      })
      ..ok('/banners/list/summary', [
        {'id': 1},
        {'id': 2},
      ])
      ..ok('/assets/list/paged', {'content': [], 'totalElements': 5, 'last': true});
  });

  /// Lets the fake backend / mock storage futures complete, then rebuilds.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> pumpDashboard(
    WidgetTester tester,
    List<String>? permissions, {
    Size size = const Size(800, 3000),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      if (permissions != null) return backend.signIn(auth, permissions);
      // null: keep the test's own /users/me/permissions route.
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
      await auth.checkAuthStatus();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: DashboardScreen(apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
  }

  Finder card(String id) => find.byKey(ValueKey('stat_$id'));
  Finder inCard(String id, String text) => find.descendant(of: card(id), matching: find.text(text));

  testWidgets('cards follow permissions and show real counts; unpermitted endpoints are never requested', (
    tester,
  ) async {
    await pumpDashboard(tester, ['posts:read', 'users:manage', 'emails:read', 'assets:read', 'pages:read']);

    expect(inCard('posts', '2'), findsOneWidget);
    expect(inCard('users', '3'), findsOneWidget);
    expect(inCard('email-logs', '1.234'), findsOneWidget, reason: 'page totalElements, tr-TR grouping');
    expect(inCard('assets', '5'), findsOneWidget);
    for (final hidden in ['forms', 'mail-accounts', 'chat', 'banners']) {
      expect(card(hidden), findsNothing, reason: '$hidden card needs its permission');
    }
    for (final path in ['/forms/list', '/mail-accounts/active', '/chat/groups', '/banners/list/summary']) {
      expect(backend.requestsTo(path), isEmpty, reason: '$path must not be requested without permission');
    }
    expect(backend.requestsTo('/emails').single.url.queryParameters['size'], '8');
    expect(backend.requestsTo('/assets/list/paged').single.url.queryParameters, containsPair('size', '1'));
    // Fake stats of the old dashboard are gone.
    expect(find.text('Total Users'), findsNothing);
    expect(find.text('Revenue'), findsNothing);
  });

  testWidgets('users card needs users:manage (users:read is not enough, same as the admin)', (tester) async {
    await pumpDashboard(tester, ['users:read', 'posts:read']);

    expect(card('users'), findsNothing);
    expect(backend.requestsTo('/users'), isEmpty);
  });

  testWidgets('recent posts and e-mails reuse the card requests', (tester) async {
    await pumpDashboard(tester, ['posts:read', 'emails:read']);

    expect(find.text('Son Yazılar'), findsOneWidget);
    expect(find.text('Birinci Yazı'), findsOneWidget);
    expect(find.text('Yayında'), findsOneWidget);
    expect(find.text('Taslak'), findsOneWidget);
    expect(find.text('Son E-postalar'), findsOneWidget);
    expect(find.text('Hoş geldiniz'), findsOneWidget);
    expect(find.text('(konu yok)'), findsOneWidget);
    expect(find.text('Gönderildi'), findsOneWidget);
    expect(find.text('Başarısız'), findsOneWidget);
    expect(backend.requestsTo('/posts/list/summary'), hasLength(1));
    expect(backend.requestsTo('/emails'), hasLength(1));
  });

  testWidgets('a failing card shows its own error, retries on tap, other cards unaffected', (tester) async {
    backend.routes['/forms/list'] = (_) => http.Response('', 500);
    await pumpDashboard(tester, ['posts:read', 'forms:read']);

    expect(inCard('forms', 'Yüklenemedi · tekrar dene'), findsOneWidget);
    expect(inCard('posts', '2'), findsOneWidget);

    backend.ok('/forms/list', [
      {'id': 1},
      {'id': 2},
      {'id': 3},
      {'id': 4},
    ]);
    await tester.tap(card('forms'));
    await tester.pump();
    await settle(tester);

    expect(inCard('forms', '4'), findsOneWidget);
    expect(backend.requestsTo('/forms/list'), hasLength(2));
    expect(backend.requestsTo('/posts/list/summary'), hasLength(1), reason: 'other cards are not refetched');
  });

  testWidgets('pull-to-refresh reloads permissions and every visible card', (tester) async {
    // Phone-sized view: the refresh threshold is a fraction of the viewport height.
    await pumpDashboard(tester, ['posts:read', 'banners:read'], size: const Size(400, 900));
    expect(inCard('banners', '2'), findsOneWidget);

    backend.ok('/banners/list/summary', [
      {'id': 1},
      {'id': 2},
      {'id': 3},
    ]);
    await tester.fling(find.text('Tekrar hoş geldin,'), const Offset(0, 500), 1000);
    await tester.pump(); // start the refresh
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1)); // indicator hide animation

    expect(backend.requestsTo('/users/me/permissions'), hasLength(2));
    expect(backend.requestsTo('/posts/list/summary'), hasLength(2));
    expect(backend.requestsTo('/banners/list/summary'), hasLength(2));
    expect(inCard('banners', '3'), findsOneWidget);
  });

  testWidgets('large text on a narrow screen: cards do not overflow', (tester) async {
    await pumpDashboard(tester, _allCardPermissions, size: const Size(320, 4000), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(inCard('email-logs', '1.234'), findsOneWidget);
    expect(inCard('mail-accounts', '1'), findsOneWidget);
  });

  testWidgets('tapping a card of an area not on mobile yet opens the "yakında" screen', (tester) async {
    await pumpDashboard(tester, ['users:manage']);

    await tester.tap(card('users'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Kullanıcılar')), findsOneWidget);
  });

  testWidgets('no module permission shows the empty-access message; "Yenile" reveals the dashboard', (tester) async {
    await pumpDashboard(tester, ['posts:create']);

    expect(find.text('Erişim yetkiniz olan modül yok.'), findsOneWidget);
    expect(card('posts'), findsNothing);

    backend.permissions(['posts:read']);
    await tester.tap(find.text('Yenile'));
    await settle(tester);
    await settle(tester);

    expect(find.text('Erişim yetkiniz olan modül yok.'), findsNothing);
    expect(inCard('posts', '2'), findsOneWidget);
  });

  testWidgets('modules without a dashboard card still count as access (no empty-access message)', (tester) async {
    await pumpDashboard(tester, ['pages:read']);

    expect(find.text('Erişim yetkiniz olan modül yok.'), findsNothing);
    expect(find.text('Tekrar hoş geldin,'), findsOneWidget);
  });

  testWidgets('permission load failure shows error + "Tekrar Dene"; retry reveals the cards', (tester) async {
    backend.routes['/users/me/permissions'] = (_) => http.Response('', 500);
    await pumpDashboard(tester, null);

    expect(find.textContaining('Yetkiler yüklenemedi'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
    expect(card('posts'), findsNothing);

    backend.permissions(['posts:read']);
    await tester.tap(find.text('Tekrar Dene'));
    // Retry clears the error synchronously → back to the spinner while loading.
    expect(auth.permissionsError, isNull);
    expect(auth.permissionsLoaded, isFalse);
    await settle(tester);
    await settle(tester);

    expect(find.text('Tekrar Dene'), findsNothing);
    expect(inCard('posts', '2'), findsOneWidget);
    expect(card('forms'), findsNothing);
  });
}
