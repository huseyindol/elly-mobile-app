import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/chat/chat_conversation_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:elly_mobile_app/screens/login_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_logs_screen.dart';
import 'package:elly_mobile_app/screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

const gid = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> n(int id, {String? link, Map<String, dynamic>? metadata, bool read = false, String? title}) => {
  'id': id,
  'type': 'SYSTEM',
  'title': title ?? 'Bildirim $id',
  'message': 'açıklama $id',
  'link': link,
  'read': read,
  'metadata': metadata,
  'createdAt': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
};

/// Bell, notification list (open / read / delete), in-app banner and the realtime lifecycle owned by AuthWrapper.
void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late List<Map<String, dynamic>> items;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    items = [
      n(3, link: '/chat', metadata: {'groupId': gid}, title: 'Yeni chat mesajı'),
      n(2, link: '/email-logs', title: 'E-posta gönderimi başarısız'),
      n(1, link: 'https://evil.com', read: true, title: 'Garip'),
    ];
    backend.routes['/notifications/unread-count'] = (_) =>
        okData({'count': items.where((x) => x['read'] != true).length});
    backend.routes['/notifications'] = (_) => okData({'content': items, 'last': true});
    for (final id in [1, 2, 3]) {
      backend.routes['/notifications/$id/read'] = (_) {
        items = [
          for (final x in items) x['id'] == id ? {...x, 'read': true} : x,
        ];
        return okData(items.firstWhere((x) => x['id'] == id));
      };
    }
    backend.ok('/notifications/read-all', {'updated': 2});
    backend.ok('/chat/tenant/t1/groups', [
      {'id': gid, 'name': 'Destek', 'type': 'GROUP', 'visibilityLevel': 1, 'tenantId': 't1'},
    ]);
    backend.ok('/chat/tenant/t1/groups/$gid/access', {'canRead': true, 'canWrite': true});
    backend.ok('/chat/tenant/t1/groups/$gid/messages', []);
    backend.ok('/chat/tenant/t1/groups/$gid/bans', []);
  });

  tearDown(() => live.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  /// Signed-in app through AuthWrapper (starts realtime + notifications itself).
  Future<void> pumpApp(WidgetTester tester, List<String> perms) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

  Finder bell() =>
      find.descendant(of: find.byType(DashboardScreen), matching: find.byKey(const ValueKey('notification_bell')));

  testWidgets('sign-in starts the live connection (Bearer) and the bell shows the unread count', (tester) async {
    await pumpApp(tester, ['chat:read']);
    expect(live.links.single.headers, {'Authorization': 'Bearer a'});
    expect(
      live.link.destinations,
      containsAll(['/user/queue/notifications', '/user/queue/notifications/unread-count']),
    );
    expect(find.descendant(of: bell(), matching: find.text('2')), findsOneWidget);
    expect(tester.widget<IconButton>(bell()).tooltip, 'Bildirimler, 2 okunmamış');

    live.push('/user/queue/notifications/unread-count', {'count': 120});
    await tester.pump();
    expect(find.descendant(of: bell(), matching: find.text('99+')), findsOneWidget);
  });

  testWidgets('list: unread first styling, untrusted text plain; chat notification opens its conversation', (
    tester,
  ) async {
    items.insert(0, n(4, title: '<b>x</b> &amp; \u202Ey', read: true));
    await pumpApp(tester, ['chat:read']);
    await tester.tap(bell());
    await settle(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('<b>x</b> & ⟨U+202E⟩y'), findsOneWidget);
    expect(find.text('5 dk önce'), findsWidgets);

    await tester.tap(find.text('Yeni chat mesajı'));
    await settle(tester);
    expect(backend.requestsTo('/notifications/3/read').single.method, 'POST');
    expect(find.byType(ChatConversationScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Destek')), findsOneWidget);
    Navigator.of(tester.element(find.byType(ChatConversationScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget, reason: 'stack: dashboard → chat → conversation');
  });

  testWidgets('section link without permission or an unknown link opens nothing', (tester) async {
    await pumpApp(tester, ['chat:read']);
    await tester.tap(bell());
    await settle(tester);
    await tester.tap(find.text('E-posta gönderimi başarısız'));
    await settle(tester);
    expect(find.byType(EmailLogsScreen), findsNothing);
    expect(find.textContaining('yetkiniz yok'), findsOneWidget);

    await tester.tap(find.text('Garip'));
    await settle(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('section link with permission opens the section', (tester) async {
    backend.ok('/emails', {'content': [], 'last': true});
    await pumpApp(tester, ['chat:read', 'emails:read']);
    await tester.tap(bell());
    await settle(tester);
    await tester.tap(find.text('E-posta gönderimi başarısız'));
    await settle(tester);
    expect(find.byType(EmailLogsScreen), findsOneWidget);
  });

  testWidgets('"Tümünü okundu" and delete', (tester) async {
    backend.routes['/notifications/2'] = (_) {
      items.removeWhere((x) => x['id'] == 2);
      return okData(<String, dynamic>{});
    };
    await pumpApp(tester, ['chat:read']);
    await tester.tap(bell());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('notification_delete_2')));
    await settle(tester);
    expect(find.text('E-posta gönderimi başarısız'), findsNothing, reason: 'hidden at once');
    expect(backend.requestsTo('/notifications/2'), isEmpty, reason: 'sent only after the undo window');
    await tester.pumpAndSettle(); // SnackBar in
    await tester.pump(const Duration(seconds: 5)); // its 4 s timer
    await tester.pumpAndSettle(); // SnackBar out → closed
    await settle(tester);
    expect(backend.requestsTo('/notifications/2').single.method, 'DELETE');
    expect(find.text('E-posta gönderimi başarısız'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('notifications_read_all')));
    await settle(tester);
    expect(backend.requestsTo('/notifications/read-all').single.method, 'POST');
    expect(find.byKey(const ValueKey('notifications_read_all')), findsNothing);
  });

  testWidgets('delete → "Geri al" restores it and sends nothing', (tester) async {
    await pumpApp(tester, ['chat:read']);
    await tester.tap(bell());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('notification_delete_2')));
    await tester.pumpAndSettle();
    expect(find.text('E-posta gönderimi başarısız'), findsNothing);
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle(); // SnackBar in
    await tester.pump(const Duration(seconds: 5)); // its 4 s timer
    await tester.pumpAndSettle(); // SnackBar out → closed
    await settle(tester);
    expect(find.text('E-posta gönderimi başarısız'), findsOneWidget);
    expect(backend.requestsTo('/notifications/2'), isEmpty);
  });

  testWidgets('next page fails: inline "Tekrar dene", no automatic retries; retry loads it', (tester) async {
    var fail = true;
    items = [for (var i = 30; i > 0; i--) n(i, title: 'B$i')];
    backend.routes['/notifications'] = (req) {
      final page = int.parse(req.url.queryParameters['page'] ?? '0');
      if (page > 0 && fail) return jsonResponse({'message': 'Sunucu hatası'}, 500);
      final slice = items.skip(page * 20).take(20).toList();
      return okData({'content': slice, 'last': page > 0});
    };
    await pumpApp(tester, ['chat:read']);
    await tester.tap(bell());
    await settle(tester);
    await tester.drag(find.byType(ListView).last, const Offset(0, -4000));
    await settle(tester);
    expect(find.byKey(const ValueKey('notifications_load_more_retry')), findsOneWidget);
    final calls = backend.requestsTo('/notifications').length;
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await settle(tester);
    expect(backend.requestsTo('/notifications').length, calls, reason: 'scrolling does not retry by itself');
    fail = false;
    await tester.tap(find.byKey(const ValueKey('notifications_load_more_retry')));
    await settle(tester);
    expect(live.notifications.items, hasLength(30));
    expect(find.byKey(const ValueKey('notifications_load_more_retry')), findsNothing);
  });

  testWidgets('a pushed notification shows an in-app banner; "Aç" opens it — not while the list is open', (
    tester,
  ) async {
    await pumpApp(tester, ['chat:read']);
    live.push('/user/queue/notifications', n(9, link: '/chat', metadata: {'groupId': gid}, title: 'Yeni chat mesajı'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni chat mesajı: açıklama 9'), findsOneWidget);
    expect(find.descendant(of: bell(), matching: find.text('3')), findsOneWidget);
    await tester.tap(find.text('Aç'));
    await settle(tester);
    expect(find.byType(ChatConversationScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(ChatConversationScreen))).popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    await tester.tap(bell());
    await settle(tester);
    live.push('/user/queue/notifications', n(10, title: 'Liste açıkken'));
    await tester.pump();
    expect(find.text('Liste açıkken: açıklama 10'), findsNothing, reason: 'no banner over the list');
    expect(find.text('Liste açıkken'), findsOneWidget, reason: 'the list itself shows it');
  });

  testWidgets('app lifecycle: background closes the socket, foreground reconnects', (tester) async {
    await pumpApp(tester, ['chat:read']);
    expect(live.links, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(live.links.single.closed, isTrue);
    expect(live.realtime.connected, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(live.links, hasLength(2));
    expect(live.realtime.connected, isTrue);
    expect(live.link.destinations, contains('/user/queue/notifications'));
  });

  testWidgets('sign-out closes the socket and clears chat/notification state; sign-in again reconnects', (
    tester,
  ) async {
    await pumpApp(tester, ['chat:read']);
    await tester.runAsync(() => live.chat.open(myUserId: 7, myLevel: 3));
    expect(live.chat.groups, isNotEmpty);

    await tester.runAsync(() => auth.logout());
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(live.links.single.closed, isTrue);
    expect(live.realtime.started, isFalse);
    expect(live.chat.groups, isEmpty);
    expect(live.notifications.unreadCount, 0);

    backend.ok('/auth/login', {'token': 'b2', 'refreshToken': 'r2', 'username': 'baska'});
    await tester.runAsync(() => auth.login(usernameOrEmail: 'baska', password: 'p', tenantId: 't1'));
    await settle(tester);
    expect(live.links, hasLength(2));
    expect(live.link.headers['Authorization'], 'Bearer b2');
  });

  testWidgets('drawer screens show the bell; sub-screens do not', (tester) async {
    await pumpApp(tester, ['chat:read']);
    expect(bell(), findsOneWidget);
    await tester.tap(bell());
    await settle(tester);
    expect(
      find.descendant(of: find.byType(NotificationsScreen), matching: find.byKey(const ValueKey('notification_bell'))),
      findsNothing,
    );
  });

  testWidgets('without the realtime providers (older harnesses) the app still works, no bell', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, ['chat:read']));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: appTheme,
          home: DashboardScreen(apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('notification_bell')), findsNothing);
  });
}
