import 'dart:convert';

import 'package:elly_mobile_app/models/chat_models.dart';
import 'package:elly_mobile_app/providers/chat_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

const g1 = '11111111-1111-4111-8111-111111111111';
const g2 = '22222222-2222-4222-8222-222222222222';
const g3 = '33333333-3333-4333-8333-333333333333';
const me = 7;

Map<String, dynamic> group(String id, {String? name, String tenant = 't1', int level = 1, int createdBy = 1}) => {
  'id': id,
  'name': name ?? 'Grup ${id.substring(0, 1)}',
  'description': null,
  'type': 'GROUP',
  'createdBy': createdBy,
  'visibilityLevel': level,
  'tenantId': tenant,
  'visitorAccess': false,
  'createdAt': '2026-10-01T09:00:00Z',
  'updatedAt': '2026-10-01T09:00:00Z',
};

int _seq = 0;
Map<String, dynamic> msg(
  String groupId, {
  String? id,
  int sender = 5,
  String content = 'merhaba',
  String type = 'ADMIN',
  String? sessionId,
  DateTime? at,
}) => {
  'id': id ?? 'm${_seq++}',
  'groupId': groupId,
  'senderType': type,
  'senderId': type == 'ADMIN' ? sender : null,
  'sessionId': sessionId,
  'senderUsername': 'user$sender',
  'content': content,
  'contentType': 'TEXT',
  'deleted': false,
  'createdAt': (at ?? DateTime.utc(2026, 10, 14, 9, 0, _seq)).toIso8601String(),
};

Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 5));

/// Admin `chat-ws-store` / `ChatSidebar` / `ChatWindow` behaviour of ChatProvider over fake STOMP + fake REST.
void main() {
  late FakeBackend backend;
  late FakeRealtime live;
  late ChatProvider chat;
  late List<Map<String, dynamic>> groups;

  setUp(() {
    backend = FakeBackend();
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    live = FakeRealtime(backend);
    chat = live.chat;
    groups = [
      group(g1),
      group(g2),
      group(g3, tenant: 't2'), // never happens in AC=TC — must not be subscribed
    ];
    backend.routes['/chat/tenant/t1/groups'] = (req) =>
        req.method == 'GET' ? okData(groups) : jsonResponse({'result': true, 'data': group(g3)}, 201);
  });

  tearDown(() => live.dispose());

  Future<void> opened({int level = 3}) async {
    live.realtime.start();
    await chat.open(myUserId: me, myLevel: level);
    await pumpEvents();
  }

  ChatGroup g(String id) => chat.groupById(id)!;

  test('open: global topics + one message topic per session-tenant group (admin allGroupSubs)', () async {
    await opened();
    expect(chat.groups.map((x) => x.id), [g1, g2, g3]);
    expect(live.link.destinations, {
      '/topic/presence',
      '/topic/groups/new',
      '/topic/groups/deleted',
      '/user/queue/chat-errors',
      '/topic/user/$me/membership',
      '/topic/tenant/t1/group/$g1',
      '/topic/tenant/t1/group/$g2',
    });
  });

  test('no session tenant → error, nothing requested', () async {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a'});
    await opened();
    expect(chat.groupsLoaded, isFalse);
    expect(chat.groupsError, contains('tenant'));
    expect(backend.requestsTo('/groups'), isEmpty);
  });

  test('live message: unread + last message on other groups; own message no unread; duplicates ignored', () async {
    await opened();
    live.push('/topic/tenant/t1/group/$g2', msg(g2, id: 'a', content: 'selam'));
    live.push('/topic/tenant/t1/group/$g2', msg(g2, id: 'a', content: 'selam'));
    live.push('/topic/tenant/t1/group/$g2', msg(g2, id: 'b', sender: me));
    expect(chat.unreadOf(g2), 1);
    expect(chat.lastMessageOf(g2)!.id, 'b');
    expect(chat.messagesOf(g2), hasLength(2));
    expect(chat.groups.first.id, g2, reason: 'recent activity moves the group up');

    live.push('/topic/tenant/t1/group/$g2', msg(g1, id: 'x')); // wrong group in payload
    live.push('/topic/tenant/t1/group/$g2', 'garbage');
    expect(chat.messagesOf(g2), hasLength(2));
  });

  test('enter: unread cleared, typing/read/bans subscribed for this group only; leave unsubscribes', () async {
    await opened();
    live.push('/topic/tenant/t1/group/$g1', msg(g1));
    chat.enterGroup(g(g1));
    expect(chat.unreadOf(g1), 0);
    expect(
      live.link.destinations,
      containsAll([
        '/topic/tenant/t1/group/$g1/typing',
        '/topic/tenant/t1/group/$g1/read',
        '/topic/tenant/t1/group/$g1/bans',
      ]),
    );
    chat.enterGroup(g(g2));
    expect(live.link.destinations.where((d) => d.contains(g1) && d != '/topic/tenant/t1/group/$g1'), isEmpty);
    chat.leaveGroup(g2);
    expect(live.link.destinations.where((d) => d.endsWith('/typing')), isEmpty);
    expect(chat.activeGroupId, isNull);
  });

  test('history: newest page, then older pages with ?before=<oldest id>; read receipt sent', () async {
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (req) {
      final before = req.url.queryParameters['before'];
      expect(req.url.queryParameters['limit'], '50');
      if (before == null) {
        return okData([for (var i = 50; i < 100; i++) msg(g1, id: 'h$i', at: DateTime.utc(2026, 1, 1, 0, 0, i))]);
      }
      expect(before, 'h50');
      return okData([for (var i = 0; i < 10; i++) msg(g1, id: 'h$i', at: DateTime.utc(2026, 1, 1, 0, 0, i))]);
    };
    await opened();
    chat.enterGroup(g(g1));
    await chat.loadLatest(g(g1));
    expect(chat.messagesOf(g1).first.id, 'h50');
    expect(chat.hasMore(g1), isTrue);
    expect(live.link.sent, [('/app/tenant-chat/t1/$g1/read', '')]);

    await chat.loadOlder(g(g1));
    expect(chat.messagesOf(g1), hasLength(60));
    expect(chat.messagesOf(g1).first.id, 'h0');
    expect(chat.hasMore(g1), isFalse);
    await chat.loadOlder(g(g1)); // nothing more → no request
    expect(backend.requestsTo('/messages').length, 2);
  });

  test('re-sync with a gap (none of the newest page cached) replaces the cache', () async {
    var page = [for (var i = 0; i < 50; i++) msg(g1, id: 'old$i', at: DateTime.utc(2026, 1, 1, 0, 0, i))];
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (_) => okData(page);
    await opened();
    await chat.loadLatest(g(g1));
    page = [for (var i = 0; i < 50; i++) msg(g1, id: 'new$i', at: DateTime.utc(2026, 2, 1, 0, 0, i))];
    await chat.loadLatest(g(g1));
    expect(chat.messagesOf(g1).map((m) => m.id).every((id) => id.startsWith('new')), isTrue);
    expect(chat.hasMore(g1), isTrue);
  });

  test('send: REST body, response shown at once, WS echo de-duplicated, typing/seen cleared', () async {
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (req) {
      if (req.method == 'GET') return okData([]);
      expect(jsonDecode(req.body), {'content': 'Merhaba dünya', 'contentType': 'TEXT'});
      return jsonResponse({'result': true, 'data': msg(g1, id: 'sent', sender: me, content: 'Merhaba dünya')}, 201);
    };
    await opened();
    chat.enterGroup(g(g1));
    await chat.send(g(g1), '  Merhaba dünya  ');
    expect(chat.messagesOf(g1).single.id, 'sent');
    live.push('/topic/tenant/t1/group/$g1', msg(g1, id: 'sent', sender: me, content: ''));
    expect(chat.messagesOf(g1).single.content, 'Merhaba dünya', reason: 'REST version kept');
    await chat.send(g(g1), '   ');
    expect(backend.requestsTo('/messages').where((r) => r.method == 'POST'), hasLength(1));
  });

  test('typing: at most one signal per 2 s; others typing shown, cleared after 3 s or by their message', () async {
    await opened();
    chat.enterGroup(g(g1));
    chat.typing(g(g1));
    chat.typing(g(g1));
    expect(live.link.sent.where((s) => s.$1 == '/app/tenant-chat/t1/$g1/typing'), hasLength(1));

    final typing = '/topic/tenant/t1/group/$g1/typing';
    live.push(typing, {'groupId': g1, 'userId': me, 'username': 'ben', 'typing': true});
    expect(chat.typingText(g1), isNull, reason: 'own typing is hidden');
    live.push(typing, {'groupId': g1, 'userId': 5, 'username': 'Ayşe', 'typing': true});
    expect(chat.typingText(g1), 'Ayşe yazıyor…');
    live.push(typing, {'groupId': g1, 'userId': null, 'sessionId': 's1', 'username': 'Misafir\u202E', 'typing': true});
    expect(chat.typingText(g1), '2 kişi yazıyor…');
    live.push('/topic/tenant/t1/group/$g1', msg(g1, sender: 5));
    expect(chat.typingText(g1), 'Misafir⟨U+202E⟩ yazıyor…');
    await Future<void>.delayed(ChatProvider.typingTimeout + const Duration(milliseconds: 50));
    expect(chat.typingText(g1), isNull);
  });

  test('read receipts: "Görüldü" lists readers after the own last message; reset by a new own message', () async {
    await opened();
    chat.enterGroup(g(g1));
    final read = '/topic/tenant/t1/group/$g1/read';
    live.push(read, {'groupId': g1, 'userId': 5, 'username': 'ayse'});
    expect(chat.seenBy(g1), isEmpty, reason: 'no own message yet');
    live.push('/topic/tenant/t1/group/$g1', msg(g1, sender: me));
    live.push(read, {'groupId': g1, 'userId': 5, 'username': 'ayse'});
    live.push(read, {'groupId': g1, 'userId': me, 'username': 'ben'});
    expect(chat.seenBy(g1), ['ayse']);
    live.push('/topic/tenant/t1/group/$g1', msg(g1, sender: me));
    expect(chat.seenBy(g1), isEmpty);
  });

  test('incoming message in the open group sends a (throttled) read receipt instead of counting unread', () async {
    await opened();
    chat.enterGroup(g(g1));
    live.push('/topic/tenant/t1/group/$g1', msg(g1));
    live.push('/topic/tenant/t1/group/$g1', msg(g1));
    expect(chat.unreadOf(g1), 0);
    expect(live.link.sent.where((s) => s.$1.endsWith('/read')), hasLength(1));
  });

  test('presence events', () async {
    await opened();
    expect(chat.isOnline(5), isNull);
    live.push('/topic/presence', {'userId': 5, 'username': 'a', 'status': 'ONLINE'});
    expect(chat.isOnline(5), isTrue);
    live.push('/topic/presence', {'userId': 5, 'username': 'a', 'status': 'OFFLINE'});
    expect(chat.isOnline(5), isFalse);
  });

  test('/topic/groups/new: other tenants ignored (broadcast to everyone); above own level → list re-fetched', () async {
    await opened(level: 2);
    final before = backend.requestsTo('/chat/tenant/t1/groups').length;
    const g4 = '44444444-4444-4444-8444-444444444444';
    live.push('/topic/groups/new', group(g4, tenant: 'baska'));
    expect(chat.groupById(g4), isNull);
    live.push('/topic/groups/new', group(g4, level: 2));
    expect(chat.groupById(g4), isNotNull);
    expect(live.link.destinations, contains('/topic/tenant/t1/group/$g4'));
    live.push('/topic/groups/new', group('55555555-5555-4555-8555-555555555555', level: 3));
    await pumpEvents();
    expect(backend.requestsTo('/chat/tenant/t1/groups').length, before + 1);
  });

  test('deleted group: removed and unsubscribed; the open conversation is told to close', () async {
    await opened();
    chat.enterGroup(g(g1));
    final notices = <ChatNotice>[];
    final sub = chat.notices.listen(notices.add);
    live.push('/topic/groups/deleted', g1);
    await pumpEvents();
    expect(chat.groupById(g1), isNull);
    expect(live.link.destinations.where((d) => d.contains(g1)), isEmpty);
    expect(notices.single.leave, isTrue);
    live.push('/topic/groups/deleted', 'not-a-uuid');
    await sub.cancel();
  });

  test('membership: JOINED adds the group; REMOVED drops it (or tells the open conversation)', () async {
    backend.routes['/chat/tenant/t1/groups/$g2/access'] = (_) => okData({'canRead': false, 'canWrite': false});
    await opened();
    const g4 = '44444444-4444-4444-8444-444444444444';
    final topic = '/topic/user/$me/membership';
    live.push(topic, {
      'action': 'JOINED',
      'groupId': g4,
      'userId': me,
      'group': group(g4),
      'message': 'Gruba dahil edildiniz.',
    });
    expect(chat.groupById(g4), isNotNull);
    live.push(topic, {'action': 'REMOVED', 'groupId': g1, 'userId': me, 'message': 'Gruptan çıkarıldınız.'});
    expect(chat.groupById(g1), isNull);

    chat.enterGroup(g(g2));
    final notices = <ChatNotice>[];
    final sub = chat.notices.listen(notices.add);
    live.push(topic, {'action': 'REMOVED', 'groupId': g2, 'userId': me, 'message': 'Gruptan çıkarıldınız.'});
    await pumpEvents();
    expect(chat.groupById(g2), isNotNull, reason: 'open conversation keeps its group, shows the banner');
    expect(notices.single.message, 'Gruptan çıkarıldınız.');
    expect(chat.accessOf(g2)!.canWrite, isFalse);
    await sub.cancel();
  });

  test('chat errors (/user/queue/chat-errors) become notices', () async {
    await opened();
    final notices = <ChatNotice>[];
    final sub = chat.notices.listen(notices.add);
    live.push('/user/queue/chat-errors', {
      'errorCode': 'CHAT_WRITE_FORBIDDEN',
      'message': 'Yazamazsınız',
      'groupId': g1,
    });
    await pumpEvents();
    expect((notices.single.groupId, notices.single.message), (g1, 'Yazamazsınız'));
    await sub.cancel();
  });

  test('reconnect re-syncs the list and the open conversation', () async {
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (_) => okData([msg(g1, id: 'z')]);
    backend.routes['/chat/tenant/t1/groups/$g1/access'] = (_) => okData({'canRead': true, 'canWrite': true});
    await opened();
    chat.enterGroup(g(g1));
    final lists = backend.requestsTo('/chat/tenant/t1/groups').length;
    live.link.drop();
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    await pumpEvents();
    expect(backend.requestsTo('/chat/tenant/t1/groups').length, lists + 1);
    expect(chat.messagesOf(g1).single.id, 'z');
    expect(live.link.destinations, contains('/topic/tenant/t1/group/$g1/typing'), reason: 're-subscribed');
  });

  test('group admin calls: create (Admin/Tenant chat), delete, DM, members, invite by id / e-mail, remove', () async {
    await opened();
    final created = await chat.createGroup(name: ' Destek ', description: '  ', tenantChat: true, visitorAccess: true);
    final create = backend.requestsTo('/chat/tenant/t1/groups').lastWhere((r) => r.method == 'POST');
    expect(jsonDecode(create.body), {'name': 'Destek', 'tenantId': 't1', 'visitorAccess': true});
    expect(chat.groupById(created.id), isNotNull);

    await chat.createGroup(name: 'Ekip', description: 'açıklama');
    expect(jsonDecode(backend.requestsTo('/chat/tenant/t1/groups').lastWhere((r) => r.method == 'POST').body), {
      'name': 'Ekip',
      'description': 'açıklama',
    });

    backend.routes['/chat/dm/12'] = (_) => okData({...group(g3), 'type': 'DM', 'name': null});
    expect((await chat.openDm(12)).isDm, isTrue);

    backend.routes['/chat/tenant/t1/groups/$g1/members/12'] = (req) => req.method == 'POST'
        ? jsonResponse({
            'result': true,
            'data': {'userId': 12, 'username': 'x'},
          }, 201)
        : http.Response('', 204);
    backend.routes['/chat/tenant/t1/groups/$g1/members/by-email'] = (req) {
      expect(jsonDecode(req.body), {'email': 'a@b.co'});
      return jsonResponse({
        'result': true,
        'data': {'userId': 13, 'username': 'y'},
      }, 201);
    };
    expect((await chat.invite(g(g1), ' 12 '))!.userId, 12);
    expect((await chat.invite(g(g1), 'a@b.co'))!.userId, 13);
    await chat.removeMember(g(g1), 12);
    expect(backend.requestsTo('/members/12').last.method, 'DELETE');

    backend.routes['/chat/tenant/t1/groups/$g1'] = (_) => http.Response('', 204);
    await chat.deleteGroup(g(g1));
    expect(chat.groupById(g1), isNull);
  });

  test('ban / unban tenant-side senders (guest sessionId, visitor visitorId) and live ban events', () async {
    backend.routes['/chat/tenant/t1/groups/$g1/bans'] = (req) => switch (req.method) {
      'GET' => okData([
        {'id': 'b1', 'groupId': g1, 'sessionId': 's-old', 'visitorId': null},
      ]),
      'POST' => jsonResponse({
        'result': true,
        'data': {'id': 'b2'},
      }, 201),
      _ => http.Response('', 204),
    };
    await opened();
    chat.enterGroup(g(g1));
    await chat.loadBans(g(g1));
    expect(chat.bannedKeys, {'s:s-old'});

    final guest = ChatMessage.fromJson(msg(g1, type: 'GUEST', sessionId: 's-1'))!;
    await chat.ban(g(g1), guest);
    expect(jsonDecode(backend.requestsTo('/bans').lastWhere((r) => r.method == 'POST').body), {'sessionId': 's-1'});
    expect(chat.bannedKeys, contains('s:s-1'));
    await chat.unban(g(g1), guest);
    expect(backend.requestsTo('/bans').last.url.query, 'sessionId=s-1');
    expect(chat.bannedKeys, isNot(contains('s:s-1')));

    live.push('/topic/tenant/t1/group/$g1/bans', {'action': 'BANNED', 'groupId': g1, 'visitorId': 9});
    expect(chat.bannedKeys, contains('v:9'));
    live.push('/topic/tenant/t1/group/$g1/bans', {'action': 'UNBANNED', 'groupId': g1, 'visitorId': 9});
    expect(chat.bannedKeys, isNot(contains('v:9')));
  });

  test('file message: upload, then the stored path is sent as FILE (admin ChatInput)', () async {
    backend.routes['/chat/tenant/t1/files'] = (_) => jsonResponse({'result': true, 'data': 'assets/chat/r.pdf'}, 201);
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (req) => jsonResponse({
      'result': true,
      'data': {...msg(g1, id: 'f', sender: me), 'contentType': 'FILE', 'content': 'assets/chat/r.pdf'},
    }, 201);
    await opened();
    await chat.sendFile(g(g1), 'pubspec.yaml');
    expect(backend.requestsTo('/files').single.method, 'POST');
    expect(jsonDecode(backend.requestsTo('/messages').last.body), {
      'content': 'assets/chat/r.pdf',
      'contentType': 'FILE',
    });
    expect(chat.messagesOf(g1).single.isFile, isTrue);
  });

  test('reset (sign-out): every subscription and all state gone', () async {
    await opened();
    chat.enterGroup(g(g1));
    live.push('/topic/tenant/t1/group/$g2', msg(g2));
    chat.reset();
    expect(live.link.destinations, isEmpty);
    expect(chat.groups, isEmpty);
    expect(chat.unreadOf(g2), 0);
    expect(chat.started, isFalse);
  });
}
