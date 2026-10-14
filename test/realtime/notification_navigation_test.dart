import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/config/nav_config.dart';
import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/models/chat_models.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/chat/chat_conversation_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:elly_mobile_app/screens/forms/form_submissions_screen.dart';
import 'package:elly_mobile_app/screens/notifications_screen.dart';
import 'package:elly_mobile_app/screens/users/users_screen.dart';
import 'package:elly_mobile_app/services/chat_format.dart';
import 'package:elly_mobile_app/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

const g1 = '11111111-1111-4111-8111-111111111111';
const g2 = '22222222-2222-4222-8222-222222222222';
const unavailable = 'Bu bildirimin mobilde açılacak bir ekranı yok ya da yetkiniz yok.';

class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route);
}

AppNotification notif({Object? link, Object? metadata, int id = 1}) => AppNotification.fromJson({
  'id': id,
  'type': 'SYSTEM',
  'title': 'Başlık',
  'message': 'mesaj',
  'link': link,
  'read': false,
  'metadata': metadata,
  'createdAt': '2026-10-14T09:00:00Z',
})!;

/// Where a tapped notification may lead (admin `router.push(n.link)` on mobile): only known admin paths, with the
/// permission of the target, never a URL — and nothing is requested or launched for anything else.
void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late _Pushes pushes;
  late List<MethodCall> launcherCalls;
  late AppNotification current;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    pushes = _Pushes();
    current = notif();
    launcherCalls = [];
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        launcherCalls.add(call);
        return null;
      },
    );
    backend.ok('/chat/tenant/t1/groups', [
      {'id': g1, 'name': 'Ekip', 'type': 'GROUP', 'visibilityLevel': 1, 'tenantId': 't1'},
    ]);
    backend.ok('/chat/tenant/t1/groups/$g1/access', {'canRead': true, 'canWrite': true});
    backend.ok('/chat/tenant/t1/groups/$g1/messages', []);
    backend.ok('/chat/tenant/t1/groups/$g1/bans', []);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
    live.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  /// A home screen whose button runs `openNotification(context, current)`.
  Future<void> pumpHarness(WidgetTester tester, List<String> perms, {List<String> roles = const ['ADMIN']}) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await backend.signIn(auth, perms, roles: roles, me: {'id': 7, 'username': 'ben'});
      live.realtime.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ...live.providers,
        ],
        child: MaterialApp(
          theme: appTheme,
          navigatorObservers: [pushes],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open'),
                onPressed: () => openNotification(context, current, api: backend.api),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    backend.requests.clear();
    pushes.routes.clear();
  }

  Future<void> open(WidgetTester tester, AppNotification n) async {
    current = n;
    await tester.tap(find.byKey(const ValueKey('open')));
    await settle(tester);
  }

  void expectNothingOpened(WidgetTester tester, {String reason = ''}) {
    expect(pushes.routes, isEmpty, reason: 'no route pushed $reason');
    expect(find.text(unavailable), findsOneWidget, reason: reason);
    expect(backend.requests, isEmpty, reason: 'no request $reason');
    expect(launcherCalls, isEmpty, reason: 'url_launcher untouched $reason');
  }

  group('malicious / unknown targets open nothing (all permissions granted, so it is not a permission denial)', () {
    const allPerms = [
      'chat:read',
      'forms:read',
      'users:manage',
      'mail:read',
      'emails:read',
      'rabbit:read',
      'email_templates:read',
      'posts:read',
    ];

    for (final link in <String?>[
      null,
      '',
      ' ',
      'https://evil.com',
      'http://evil.com/chat',
      'HTTPS://EVIL.COM',
      '//evil.com',
      '//evil.com/chat',
      'javascript:alert(1)',
      'data:text/html,<script>alert(1)</script>',
      'intent://scan/#Intent;scheme=zxing;end',
      'file:///etc/passwd',
      'tel:+905551112233',
      'mailto:a@b.co',
      'otpauth://totp/x?secret=ABC',
      'chat',
      '/chat\n',
      '/chat\u0000',
      ' /chat',
      '/chat ',
      '/CHAT',
      '/Chat',
      '/chаt', // Cyrillic а
      '/ｃｈａｔ',
      '/%63hat',
      '/chat/../users',
      '/users/..',
      '/users/',
      '/users/1',
      '/a/b',
      '/forms/abc/submissions',
      '/forms/-1/submissions',
      '/forms//submissions',
      '/forms/12345678901234567890/submissions',
      '/forms/1/submissions/../../users',
      '/forms/1/submissions/extra',
      '/forms/1/submissions\n',
      '/forms/１２/submissions',
      '/login',
      '/profile',
      '/dashboard',
      '/unknown-section',
      '/x' * 30,
      '/${'a' * 60}',
    ]) {
      testWidgets('link ${link == null ? 'null' : '"${link.replaceAll('\n', r'\n').replaceAll('\u0000', r'\0')}"'}', (
        tester,
      ) async {
        await pumpHarness(tester, allPerms);
        await open(tester, notif(link: link));
        expectNothingOpened(tester);
      });
    }

    test('the same set maps to no target at the format layer', () {
      for (final link in [
        'https://evil.com',
        '//evil.com',
        'javascript:alert(1)',
        '/chat/../users',
        '/CHAT',
        '/forms/x/submissions',
      ]) {
        expect(notificationTarget(link, const {}), isNull, reason: link);
      }
    });
  });

  group('a well-known section needs its permission', () {
    final gated = [
      for (final g in NavConfig.groups)
        for (final i in g.items)
          if (i.permission != null && navScreen(i) != null) i,
    ];

    test('the matrix is not empty', () {
      expect(gated.map((i) => i.id), containsAll(['chat', 'users', 'mail-accounts', 'email-logs', 'rabbitmq']));
    });

    for (final item in gated) {
      testWidgets('/${item.id} without ${item.permission}: nothing opens, nothing is requested', (tester) async {
        await pumpHarness(tester, const []);
        await open(tester, notif(link: '/${item.id}', metadata: {'groupId': g1}));
        expectNothingOpened(tester, reason: item.id);
      });
    }

    testWidgets('/users?next=https://evil.com WITH users:manage opens the Users screen; the URL is ignored', (
      tester,
    ) async {
      backend.ok('/users', <Object>[]);
      await pumpHarness(tester, ['users:manage']);
      await open(tester, notif(link: '/users?next=https://evil.com#https://evil.com'));
      expect(find.byType(UsersScreen), findsOneWidget);
      expect(launcherCalls, isEmpty);
      expect(backend.requests.every((r) => r.url.host == backend.requests.first.url.host), isTrue);
      expect(backend.requests.any((r) => r.url.toString().contains('evil')), isFalse);
    });

    testWidgets('/settings (every signed-in user) opens; no permission needed', (tester) async {
      await pumpHarness(tester, const []);
      await open(tester, notif(link: '/settings'));
      expect(pushes.routes, isNotEmpty);
      expect(find.text(unavailable), findsNothing);
      expect(launcherCalls, isEmpty);
    });
  });

  group('chat links', () {
    testWidgets('chat:read + a valid, accessible group: list → conversation', (tester) async {
      await pumpHarness(tester, ['chat:read']);
      await open(tester, notif(link: '/chat', metadata: {'groupId': g1}));
      expect(find.byType(ChatConversationScreen), findsOneWidget);
      expect(live.link.destinations, contains('/topic/tenant/t1/group/$g1/typing'));
      expect(launcherCalls, isEmpty);
    });

    testWidgets('chat:read missing: not even the list; nothing requested', (tester) async {
      await pumpHarness(tester, ['forms:read']);
      await open(tester, notif(link: '/chat', metadata: {'groupId': g1}));
      expectNothingOpened(tester);
      expect(live.link.destinations.where((d) => d.contains('/tenant/')), isEmpty);
    });

    for (final id in <Object?>[
      '../../users',
      '../x',
      '*',
      '>',
      '#',
      '',
      ' ',
      7,
      true,
      ['a'],
      {'a': 1},
      '$g1/members',
      '$g1?x=1',
      '$g1\n',
      'https://evil.com',
      'javascript:alert(1)',
      'g1',
    ]) {
      testWidgets(
        'metadata.groupId ${id.runtimeType} ${id.toString().replaceAll('\n', r'\n')}: opens the chat list only, the id never hits the network',
        (tester) async {
          await pumpHarness(tester, ['chat:read']);
          await open(tester, notif(link: '/chat', metadata: {'groupId': id}));
          expect(find.byType(ChatScreen), findsOneWidget);
          expect(find.byType(ChatConversationScreen), findsNothing);
          expect(
            backend.requests.every((r) => !r.url.path.contains('/groups/')),
            isTrue,
            reason: 'no per-group request',
          );
          expect(backend.requests.any((r) => r.url.toString().contains('evil') || r.url.path.contains('..')), isFalse);
          expect(launcherCalls, isEmpty);
        },
      );
    }

    testWidgets(
      'a group id of ANOTHER tenant (well-formed UUID, backend refuses): conversation shows "not found", no live channel',
      (tester) async {
        backend.routes['/chat/tenant/t1/groups/$g2'] = (_) =>
            http.Response('{"message":"Bu gruba erişiminiz yok"}', 403);
        await pumpHarness(tester, ['chat:read']);
        await open(tester, notif(link: '/chat', metadata: {'groupId': g2}));
        expect(find.text('Grup bulunamadı ya da erişiminiz yok.'), findsOneWidget);
        expect(backend.requestsTo('/groups/$g2').single.method, 'GET');
        expect(
          backend.requests.where((r) => r.url.path.contains('/groups/$g2/')),
          isEmpty,
          reason: 'no messages / access',
        );
        expect(live.link.destinations.any((d) => d.contains(g2)), isFalse);
        expect(live.link.sent, isEmpty);
        expect(launcherCalls, isEmpty);
      },
    );

    testWidgets('the backend returns a group of tenant t2 for the id: still no live channel and no signal', (
      tester,
    ) async {
      backend.routes['/chat/tenant/t1/groups/$g2'] = (_) =>
          okData({'id': g2, 'name': 'Yabancı', 'tenantId': 't2', 'type': 'GROUP'});
      backend.ok('/chat/tenant/t1/groups/$g2/access', {'canRead': true, 'canWrite': true});
      backend.ok('/chat/tenant/t1/groups/$g2/messages', []);
      backend.ok('/chat/tenant/t1/groups/$g2/bans', []);
      await pumpHarness(tester, ['chat:read']);
      await open(tester, notif(link: '/chat', metadata: {'groupId': g2}));
      expect(live.link.destinations.any((d) => d.contains(g2) || d.contains('/t2/')), isFalse);
      expect(live.link.sent, isEmpty);
    });
  });

  group('form links', () {
    testWidgets('without forms:read: nothing opens and /forms is never requested', (tester) async {
      await pumpHarness(tester, ['chat:read']);
      await open(tester, notif(link: '/forms/12/submissions'));
      expectNothingOpened(tester);
    });

    testWidgets('a form that does not exist (404): error message, no screen, no other request', (tester) async {
      backend.routes['/forms/777'] = (_) => http.Response('{"message":"Form bulunamadı"}', 404);
      await pumpHarness(tester, ['forms:read']);
      await open(tester, notif(link: '/forms/777/submissions'));
      expect(find.byType(FormSubmissionsScreen), findsNothing);
      expect(pushes.routes, isEmpty);
      expect(find.textContaining('Form bulunamadı'), findsOneWidget);
      expect(backend.requests.map((r) => r.url.path.split('/api/v1').last), ['/forms/777']);
      expect(launcherCalls, isEmpty);
    });

    for (final body in <Object?>[null, <Object>[], 'text', 5]) {
      testWidgets('form endpoint answers with ${body.runtimeType} ($body): nothing opens, no crash', (tester) async {
        backend.routes['/forms/12'] = (_) => okData(body ?? <String, dynamic>{}).statusCode == 200 && body == null
            ? http.Response('{"result":true,"data":null}', 200)
            : okData(body!);
        await pumpHarness(tester, ['forms:read']);
        await open(tester, notif(link: '/forms/12/submissions'));
        expect(find.byType(FormSubmissionsScreen), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an existing form: only /forms/{id} is fetched, the submissions screen opens', (tester) async {
      backend.ok('/forms/12', {
        'id': 12,
        'name': 'İletişim',
        'formSchema': {'fields': <Object>[]},
      });
      backend.ok('/forms/12/submissions/paged', {'content': <Object>[], 'last': true});
      backend.ok('/forms/12/submissions/count', 0);
      await pumpHarness(tester, ['forms:read']);
      await open(tester, notif(link: '/forms/12/submissions'));
      expect(find.byType(FormSubmissionsScreen), findsOneWidget);
      expect(backend.requestsTo('/forms/12').first.method, 'GET');
      expect(launcherCalls, isEmpty);
    });

    testWidgets('leading zeros are just digits: /forms/007/submissions → GET /forms/007 (no traversal possible)', (
      tester,
    ) async {
      backend.routes['/forms/007'] = (_) => http.Response('{"message":"yok"}', 404);
      await pumpHarness(tester, ['forms:read']);
      await open(tester, notif(link: '/forms/007/submissions'));
      expect(backend.requests.single.url.path.endsWith('/forms/007'), isTrue);
    });
  });

  group('through the real app: banner "Aç" and the list', () {
    late List<Map<String, dynamic>> items;

    Future<void> pumpApp(WidgetTester tester, List<String> perms) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      backend.routes['/notifications/unread-count'] = (_) => okData({'count': items.length});
      backend.routes['/notifications'] = (_) => okData({'content': items, 'last': true});
      backend.routes['/notifications/read-all'] = (_) => okData({'updated': 1});
      for (var i = 1; i <= 20; i++) {
        backend.routes['/notifications/$i/read'] = (_) => okData(<String, dynamic>{});
      }
      await tester.runAsync(
        () => backend.signIn(auth, perms, roles: const ['ADMIN'], me: const {'id': 7, 'username': 'ben'}),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ...live.providers,
          ],
          child: EllyMobileApp(apiService: backend.api),
        ),
      );
      await settle(tester);
    }

    Map<String, dynamic> row(
      int id, {
      String? link,
      Object? metadata,
      String title = 'Başlık',
      String message = 'mesaj',
    }) => {
      'id': id,
      'type': 'SYSTEM',
      'title': title,
      'message': message,
      'link': link,
      'read': false,
      'metadata': metadata,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
    };

    setUp(() => items = []);

    testWidgets(
      'a pushed notification with a hostile link: banner shows, "Aç" → "no screen" message, no launch, no route',
      (tester) async {
        await pumpApp(tester, ['chat:read']);
        live.push(
          '/user/queue/notifications',
          row(9, link: 'https://evil.com/login', title: 'Hesabınız', message: 'Giriş yapın'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Hesabınız: Giriş yapın'), findsOneWidget);
        final routesBefore = find.byType(DashboardScreen);
        expect(routesBefore, findsOneWidget);
        await tester.tap(find.text('Aç'));
        await settle(tester);
        expect(find.text(unavailable), findsOneWidget);
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(launcherCalls, isEmpty);
      },
    );

    testWidgets('banner text is clipped to 140 chars / 2 lines without breaking an emoji, and bidi is visible', (
      tester,
    ) async {
      await pumpApp(tester, ['chat:read']);
      live.push('/user/queue/notifications', row(9, title: '${'a' * 135}😀😀😀\u202E', message: 'b\nc\nd'));
      await tester.pumpAndSettle();
      final text = tester
          .widget<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)).first)
          .data!;
      expect(text.length, lessThanOrEqualTo(141));
      expect(text.split('\n').length, lessThanOrEqualTo(2));
      final units = text.codeUnits;
      for (var i = 0; i < units.length; i++) {
        final u = units[i];
        if (u >= 0xD800 && u <= 0xDBFF) {
          expect(
            i + 1 < units.length && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF,
            isTrue,
            reason: 'lone high surrogate at $i',
          );
          i++;
        } else {
          expect(u >= 0xDC00 && u <= 0xDFFF, isFalse, reason: 'lone low surrogate at $i');
        }
      }
      expect(RegExp('[\u202A-\u202E\u2066-\u2069]').hasMatch(text), isFalse);
    });

    testWidgets('list: a notification with a hostile link is still readable, tapping marks it read and opens nothing', (
      tester,
    ) async {
      items = [row(1, link: 'javascript:alert(1)', title: '<img src=x onerror=alert(1)>'), row(2, link: '//evil.com')];
      await pumpApp(tester, ['chat:read']);
      await tester.tap(find.byKey(const ValueKey('notification_bell')));
      await settle(tester);
      expect(find.text('<img src=x onerror=alert(1)>'), findsOneWidget);
      await tester.tap(find.text('<img src=x onerror=alert(1)>'));
      await settle(tester);
      expect(backend.requestsTo('/notifications/1/read').single.method, 'POST');
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text(unavailable), findsOneWidget);
      expect(launcherCalls, isEmpty);
    });
  });
}
