import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/account/settings_screen.dart';
import 'package:elly_mobile_app/screens/coming_soon_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:elly_mobile_app/screens/users/users_screen.dart';
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
      ..ok('/assets/list/paged', {'content': [], 'totalElements': 5, 'last': true})
      ..ok('/storage/tenant/t1/quota', {
        'tenantId': 't1',
        'usedBytes': 805306368, // 768 MB
        'limitBytes': 1073741824, // 1 GB
        'usedPercent': 75.0,
      });
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
    String? tenantId = 't1',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      // null permissions: keep the test's own /users/me/permissions route.
      if (permissions != null) backend.permissions(permissions);
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': ?tenantId});
      await auth.checkAuthStatus();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: appTheme,
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
    await pumpDashboard(tester, ['chat:read']);

    await tester.tap(card('chat'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Chat')), findsOneWidget);
  });

  testWidgets('"Kullanıcılar" card opens the users screen', (tester) async {
    await pumpDashboard(tester, ['users:manage']);

    await tester.tap(card('users'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byType(UsersScreen), findsOneWidget);
    expect(find.byType(ComingSoonScreen), findsNothing);
  });

  testWidgets('storage "Yönet" opens the settings screen', (tester) async {
    await pumpDashboard(tester, ['posts:read']);

    await settle(tester);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('storage_card')), matching: find.text('Yönet')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
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

  group('storage usage card', () {
    Finder inStorage(String text) =>
        find.descendant(of: find.byKey(const ValueKey('storage_card')), matching: find.text(text));

    testWidgets('uses the session tenant URL like the admin and shows usage', (tester) async {
      await pumpDashboard(tester, ['pages:read']);

      expect(backend.requestsTo('/storage/tenant/t1/quota'), hasLength(1));
      expect(inStorage('Depolama Kullanımı'), findsOneWidget);
      expect(inStorage('%75,0'), findsOneWidget);
      expect(inStorage('768 MB'), findsOneWidget);
      expect(inStorage('1 GB'), findsOneWidget);
      expect(inStorage('256 MB'), findsOneWidget);
      expect(inStorage('Kota dolmak üzere.'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('storage_percent'))).style?.color, AppColors.warning);
    });

    testWidgets('no tenant in the session → /storage/quota', (tester) async {
      backend.ok('/storage/quota', {'usedBytes': 0, 'limitBytes': 1024, 'usedPercent': 0.0});
      await pumpDashboard(tester, ['pages:read'], tenantId: null);

      expect(backend.requestsTo('/storage/quota'), hasLength(1));
      expect(inStorage('Genel / Admin'), findsOneWidget);
      expect(inStorage('Kota dolmak üzere.'), findsNothing);
    });

    testWidgets('failure shows an inline error; "Tekrar Dene" reloads only the quota', (tester) async {
      backend.routes['/storage/tenant/t1/quota'] = (_) => http.Response('', 500);
      await pumpDashboard(tester, ['posts:read']);
      expect(inStorage('Depolama bilgisi yüklenemedi.'), findsOneWidget);

      backend.ok('/storage/tenant/t1/quota', {'usedBytes': 950, 'limitBytes': 1000, 'usedPercent': 95.0});
      await tester.tap(inStorage('Tekrar Dene'));
      await tester.pump();
      await settle(tester);

      expect(inStorage('%95,0'), findsOneWidget);
      expect(inStorage('Kota neredeyse dolu — yeni yüklemeler reddedilebilir.'), findsOneWidget);
      expect(backend.requestsTo('/posts/list/summary'), hasLength(1));
    });

    test('thresholds: <70 success, 70–90 warning, ≥90 error (admin StorageUsageWidget)', () {
      final scheme = appTheme.colorScheme;
      expect(quotaColor(0, scheme), AppColors.success);
      expect(quotaColor(69.9, scheme), AppColors.success);
      expect(quotaColor(70, scheme), AppColors.warning);
      expect(quotaColor(89.9, scheme), AppColors.warning);
      expect(quotaColor(90, scheme), scheme.onErrorContainer);
      expect(quotaColor(100, scheme), scheme.onErrorContainer);
    });
  });

  group('stat grid columns', () {
    Future<bool> sideBySide(WidgetTester tester, double width, double textScale) async {
      await pumpDashboard(tester, ['posts:read', 'forms:read'], size: Size(width, 2400), textScale: textScale);
      expect(tester.takeException(), isNull);
      return tester.getTopLeft(card('posts')).dy == tester.getTopLeft(card('forms')).dy;
    }

    for (final width in [320.0, 360.0, 393.0, 430.0]) {
      testWidgets('$width dp phone, normal text → two columns', (tester) async {
        expect(await sideBySide(tester, width, 1.0), isTrue);
      });
    }

    for (final (width, scale) in [(360.0, 1.5), (393.0, 2.0)]) {
      testWidgets('$width dp phone, text ×$scale → one column', (tester) async {
        expect(await sideBySide(tester, width, scale), isFalse);
      });
    }
  });

  testWidgets('refresh button is locked while refreshing (one reload per tap burst)', (tester) async {
    await pumpDashboard(tester, ['posts:read']);
    final refresh = find.byTooltip('Yenile');

    // Second tap lands before the first refresh finishes (no frame in between).
    await tester.tap(refresh);
    await tester.tap(refresh);
    await settle(tester);
    await settle(tester);
    expect(backend.requestsTo('/users/me/permissions'), hasLength(2), reason: 'initial + one refresh');
    expect(backend.requestsTo('/posts/list/summary'), hasLength(2), reason: 'cards reloaded once, not twice');
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh_rounded)).onPressed, isNotNull);
  });

  testWidgets('a failed permission refresh keeps the dashboard and shows a SnackBar', (tester) async {
    await pumpDashboard(tester, ['posts:read']);
    backend.routes['/users/me/permissions'] = (_) => http.Response('', 500);

    await tester.tap(find.byTooltip('Yenile'));
    await settle(tester);
    await settle(tester);

    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.textContaining('Yetkiler yenilenemedi')),
      findsOneWidget,
    );
    expect(inCard('posts', '2'), findsOneWidget, reason: 'last known permissions stay in effect');
  });
}
