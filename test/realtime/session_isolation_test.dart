import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';
import '../helpers/gated_backend.dart';

/// `--dart-define=VERIFY_FINDINGS=true` runs the skipped BULGU tests (they fail today, proving the finding).
const _verify = bool.fromEnvironment('VERIFY_FINDINGS');

const gA = '11111111-1111-4111-8111-111111111111';
const gB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> grp(String id, String tenant) => {
  'id': id,
  'name': 'Grup ${id.substring(0, 1)}',
  'type': 'GROUP',
  'createdBy': 1,
  'visibilityLevel': 1,
  'tenantId': tenant,
  'visitorAccess': false,
  'updatedAt': '2026-10-01T09:00:00Z',
};

Map<String, dynamic> message(String groupId, String id, {int sender = 5}) => {
  'id': id,
  'groupId': groupId,
  'senderType': 'ADMIN',
  'senderId': sender,
  'senderUsername': 'u$sender',
  'content': 'gizli $id',
  'contentType': 'TEXT',
  'deleted': false,
  'createdAt': '2026-10-14T09:00:00Z',
};

Map<String, dynamic> notif(int id) => {
  'id': id,
  'type': 'SYSTEM',
  'title': 'Bildirim $id',
  'message': 'm',
  'read': false,
  'createdAt': '2026-10-14T09:00:00Z',
};

Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 10));

/// Sign-out → another user signs in (same app process, same providers): nothing of the previous user's
/// subscriptions, destinations, state or late responses may reach the next one. SECURITY.
void main() {
  late GatedBackend backend;
  late FakeRealtime live;
  late int unread;

  setUp(() {
    backend = GatedBackend();
    live = FakeRealtime(backend);
    unread = 2;
    backend.ok('/chat/tenant/t1/groups', [grp(gA, 't1')]);
    backend.ok('/chat/tenant/t2/groups', [grp(gB, 't2')]);
    backend.routes['/notifications/unread-count'] = (_) => okData({'count': unread});
    backend.routes['/notifications'] = (_) => okData({
      'content': [notif(unread * 100)],
      'last': true,
    });
    backend.ok('/chat/tenant/t1/groups/$gA/access', {'canRead': true, 'canWrite': true});
    backend.ok('/chat/tenant/t1/groups/$gA/messages', [message(gA, 'a1')]);
  });

  tearDown(() => live.dispose());

  /// What AuthWrapper does on sign-in / sign-out (same order).
  Future<void> signIn(String token, String tenant, int userId) async {
    FlutterSecureStorage.setMockInitialValues({'accessToken': token, 'refreshToken': 'r', 'tenantId': tenant});
    live.realtime.start();
    live.notifications.start();
    await live.chat.open(myUserId: userId, myLevel: 3);
    await pumpEvents();
  }

  void signOut() {
    live.chat.reset();
    live.notifications.reset();
    live.realtime.stop();
  }

  bool mentions(FakeStompLink link, Pattern p) => link.destinations.any((d) => d.contains(p));

  test(
    'user A (id 7, t1, conversation open) → user B (id 9, t2): B connects with B\'s token and only B\'s destinations',
    () async {
      await signIn('tok-a', 't1', 7);
      live.chat.enterGroup(live.chat.groupById(gA)!);
      final a = live.link;
      expect(a.destinations, contains('/topic/user/7/membership'));
      expect(a.destinations, contains('/topic/tenant/t1/group/$gA/typing'));

      signOut();
      expect(a.closed, isTrue);
      expect(a.destinations, isEmpty, reason: 'every handler of A is gone from A\'s link');

      await signIn('tok-b', 't2', 9);
      final b = live.link;
      expect(identical(a, b), isFalse);
      expect(b.headers, {'Authorization': 'Bearer tok-b'});
      expect(b.destinations, {
        '/topic/presence',
        '/topic/groups/new',
        '/topic/groups/deleted',
        '/user/queue/chat-errors',
        '/topic/user/9/membership',
        '/user/queue/notifications',
        '/user/queue/notifications/unread-count',
        '/topic/tenant/t2/group/$gB',
      });
      expect(mentions(b, '/7/'), isFalse, reason: 'previous user id');
      expect(mentions(b, '/t1/'), isFalse, reason: 'previous tenant');
      expect(mentions(b, gA), isFalse, reason: 'previous user group');
      expect(live.chat.tenantId, 't2');
      expect(live.chat.myUserId, 9);
      expect(live.chat.groups.map((g) => g.id), [gB]);
      expect(live.chat.activeGroupId, isNull);
    },
  );

  test('reconnects of user B never bring back user A\'s destinations', () async {
    await signIn('tok-a', 't1', 7);
    signOut();
    await signIn('tok-b', 't2', 9);
    for (var i = 0; i < 3; i++) {
      live.link.drop();
      await Future<void>.delayed(Duration(milliseconds: 1000 * (1 << i) + 400));
      await pumpEvents();
      expect(mentions(live.link, '/7/'), isFalse);
      expect(mentions(live.link, '/t1/'), isFalse);
      expect(live.link.headers['Authorization'], 'Bearer tok-b');
      expect(live.link.destinations, contains('/topic/user/9/membership'));
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('frames addressed to A\'s old destinations after sign-out change nothing for B', () async {
    await signIn('tok-a', 't1', 7);
    final a = live.link;
    signOut();
    unread = 4;
    await signIn('tok-b', 't2', 9);

    a.deliver('/topic/tenant/t1/group/$gA', message(gA, 'late'));
    a.deliver('/user/queue/notifications', notif(999));
    a.deliver('/user/queue/notifications/unread-count', {'count': 0});
    a.deliver('/topic/user/7/membership', {'action': 'JOINED', 'groupId': gA, 'group': grp(gA, 't1')});
    a.deliver('/topic/groups/new', grp(gA, 't1'));
    await pumpEvents();

    expect(live.chat.messagesOf(gA), isEmpty);
    expect(live.chat.unreadOf(gA), 0);
    expect(live.chat.groupById(gA), isNull);
    expect(live.notifications.unreadCount, 4);
    expect(live.notifications.items, isEmpty);
  });

  test(
    'no reset between the users (a missed sign-out hook): realtime.stop alone still leaves nothing subscribed',
    () async {
      await signIn('tok-a', 't1', 7);
      live.realtime.stop(); // chat / notifications NOT reset
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'tok-b', 'tenantId': 't2'});
      live.realtime.start();
      await pumpEvents();
      expect(live.link.headers['Authorization'], 'Bearer tok-b');
      expect(live.link.destinations, isEmpty, reason: 'A\'s subscriptions are not re-created for B');
    },
  );

  group('late responses of the previous session', () {
    test('A\'s group list arrives after B signed in: B sees only B\'s groups, nothing of A is subscribed', () async {
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'tok-a', 'tenantId': 't1'});
      live.realtime.start();
      final gate = backend.hold('/chat/tenant/t1/groups');
      final openA = live.chat.open(myUserId: 7, myLevel: 3);
      await pumpEvents();
      expect(backend.requestsTo('/chat/tenant/t1/groups'), hasLength(1));

      signOut();
      await signIn('tok-b', 't2', 9);
      gate.complete();
      await openA;
      await pumpEvents();

      expect(live.chat.groups.map((g) => g.id), [gB]);
      expect(live.chat.groupsError, isNull);
      expect(mentions(live.link, gA), isFalse);
      expect(live.chat.tenantId, 't2');
    });

    test('A\'s conversation history / send response arrive after reset: not stored, no read receipt sent', () async {
      await signIn('tok-a', 't1', 7);
      final groupA = live.chat.groupById(gA)!;
      final historyGate = backend.hold('/chat/tenant/t1/groups/$gA/messages');
      final history = live.chat.loadLatest(groupA);
      await pumpEvents();
      final sendGate = backend.hold('/chat/tenant/t1/groups/$gA/messages');
      backend.routes['/chat/tenant/t1/groups/$gA/messages'] = (req) => req.method == 'POST'
          ? jsonResponse({'result': true, 'data': message(gA, 'sent', sender: 7)}, 201)
          : okData([message(gA, 'a1')]);
      final send = live.chat.send(groupA, 'merhaba');
      await pumpEvents();

      final a = live.link;
      signOut();
      await signIn('tok-b', 't2', 9);
      historyGate.complete();
      sendGate.complete();
      await Future.wait([history, send]);
      await pumpEvents();

      expect(live.chat.messagesOf(gA), isEmpty);
      expect(a.sent, isEmpty, reason: 'no read receipt for A\'s group');
      expect(live.link.sent, isEmpty);
    });

    test('A\'s notification list and unread count arrive after B signed in: B\'s state is untouched', () async {
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'tok-a', 'tenantId': 't1'});
      unread = 99;
      final countGate = backend.hold('/notifications/unread-count');
      live.realtime.start();
      live.notifications.start(); // A: GET /unread-count (99), held
      await pumpEvents();
      final listGate = backend.hold('/notifications');
      final loadA = live.notifications.load();
      await pumpEvents();

      signOut();
      unread = 4;
      await signIn('tok-b', 't2', 9);
      expect(live.notifications.unreadCount, 4);

      countGate.complete();
      listGate.complete();
      await loadA;
      await pumpEvents();
      expect(live.notifications.unreadCount, 4, reason: 'A\'s 99 dropped');
      expect(live.notifications.items, isEmpty, reason: 'A\'s list dropped');
      expect(live.notifications.loaded, isFalse);
    });

    for (final action in ['markAllRead', 'markRead', 'remove']) {
      test(
        'A\'s "$action" completes after B signed in: B\'s unread badge is not changed',
        () async {
          FlutterSecureStorage.setMockInitialValues({'accessToken': 'tok-a', 'tenantId': 't1'});
          live.realtime.start();
          live.notifications.start();
          await pumpEvents();
          await live.notifications.load();
          final n = live.notifications.items.single;
          final gate = backend.hold(switch (action) {
            'markAllRead' => '/notifications/read-all',
            'markRead' => '/notifications/${n.id}/read',
            _ => '/notifications/${n.id}',
          });
          backend.routes['/notifications/read-all'] = (_) => okData({'updated': 1});
          backend.routes['/notifications/${n.id}/read'] = (_) => okData(notif(n.id));
          backend.routes['/notifications/${n.id}'] = (_) => okData(<String, dynamic>{});
          final inFlight = switch (action) {
            'markAllRead' => live.notifications.markAllRead(),
            'markRead' => live.notifications.markRead(n),
            _ => live.notifications.remove(n),
          };
          await pumpEvents();

          signOut();
          unread = 4;
          await signIn('tok-b', 't2', 9);
          expect(live.notifications.unreadCount, 4);
          gate.complete();
          await inFlight;
          await pumpEvents();
          expect(live.notifications.unreadCount, 4);
        },
        skip: _verify
            ? null
            : 'BULGU (düşük): NotificationsProvider.markRead/markAllRead/remove '
                  '`await` sonrası epoch kontrolü yapmıyor — önceki oturumun geç tamamlanan isteği yeni kullanıcının rozet '
                  'sayısını değiştirir (markAllRead → 0, markRead/remove → bir eksik). Veri sızıntısı yok, yalnız yanlış sayaç.',
      );
    }
  });

  testWidgets('real AuthWrapper: A (conversation open) logs out, B (t2) logs in → B\'s connection is B\'s alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final auth = backend.newAuth();
    backend.ok('/auth/logout', <String, dynamic>{});
    await tester.runAsync(
      () => backend.signIn(auth, ['chat:read'], roles: const ['ADMIN'], me: const {'id': 7, 'username': 'a'}),
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
    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    await settle();
    await tester.runAsync(() => live.chat.open(myUserId: auth.userId, myLevel: auth.roleLevel));
    live.chat.enterGroup(live.chat.groupById(gA)!);
    final a = live.link;
    expect(a.headers, {'Authorization': 'Bearer a'});
    expect(a.destinations, contains('/topic/user/7/membership'));

    await tester.runAsync(() => auth.logout());
    await tester.pumpAndSettle();
    expect(a.closed, isTrue);
    expect(a.destinations, isEmpty);
    expect(live.chat.tenantId, isNull);
    expect(live.chat.activeGroupId, isNull);

    backend.ok('/auth/login', {'token': 'tok-b', 'refreshToken': 'r2', 'username': 'bob'});
    backend.ok('/users/me', {'id': 9, 'username': 'bob'});
    backend.permissions(['chat:read'], roles: ['ADMIN']);
    await tester.runAsync(() => auth.login(usernameOrEmail: 'bob', password: 'p', tenantId: 't2'));
    await settle();
    await tester.runAsync(() => live.chat.open(myUserId: auth.userId, myLevel: auth.roleLevel));
    await settle();

    final b = live.link;
    expect(identical(a, b), isFalse);
    expect(b.headers, {'Authorization': 'Bearer tok-b'});
    expect(b.destinations, contains('/topic/user/9/membership'));
    expect(b.destinations, contains('/topic/tenant/t2/group/$gB'));
    expect(mentions(b, '/7/'), isFalse);
    expect(mentions(b, '/t1/'), isFalse);
    expect(mentions(b, gA), isFalse);
    expect(live.chat.groups.map((g) => g.id), [gB]);
  });
}
