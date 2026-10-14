import 'dart:convert';

import 'package:elly_mobile_app/models/chat_models.dart';
import 'package:elly_mobile_app/providers/chat_provider.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

const g1 = '11111111-1111-4111-8111-111111111111';
const g2 = '22222222-2222-4222-8222-222222222222';
const g3 = '33333333-3333-4333-8333-333333333333';
const g4 = '44444444-4444-4444-8444-444444444444';
const me = 7;

Map<String, dynamic> grp(String id, {Object? tenant = 't1', int level = 1, String type = 'GROUP', String? name}) => {
  'id': id,
  'name': name ?? 'Grup',
  'type': type,
  'createdBy': 1,
  'visibilityLevel': level,
  'tenantId': tenant,
  'visitorAccess': false,
  'updatedAt': '2026-10-01T09:00:00Z',
};

Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 5));

/// ChatProvider fail-closed rules: which groups may get a WebSocket destination, what hostile ids / tenants / events
/// do, the new-group / membership broadcast filters, DM, invite hierarchy at the provider level.
void main() {
  late FakeBackend backend;
  late FakeRealtime live;
  late ChatProvider chat;
  late List<Object> groups;

  setUp(() {
    backend = FakeBackend();
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    live = FakeRealtime(backend);
    chat = live.chat;
    groups = [grp(g1)];
    backend.routes['/chat/tenant/t1/groups'] = (_) => okData(groups);
  });

  tearDown(() => live.dispose());

  Future<void> opened({int level = 3}) async {
    live.realtime.start();
    await chat.open(myUserId: me, myLevel: level);
    await pumpEvents();
  }

  Set<String> scoped() => live.link.destinations.where((d) => d.contains('/tenant/') || d.startsWith('/app/')).toSet();

  /// Everything a conversation could do over STOMP for [g]: enter (typing/read/bans), typing and read signals.
  void exercise(ChatGroup g) {
    chat.enterGroup(g);
    chat.typing(g);
    chat.sendRead(g, force: true);
  }

  group('a group gets a destination only with a UUID id AND the session tenant', () {
    test(
      'control: a valid group is subscribed, and entering it adds typing / read / bans and lets signals out',
      () async {
        await opened();
        expect(scoped(), {'/topic/tenant/t1/group/$g1'});
        exercise(chat.groupById(g1)!);
        expect(scoped(), {
          '/topic/tenant/t1/group/$g1',
          '/topic/tenant/t1/group/$g1/typing',
          '/topic/tenant/t1/group/$g1/read',
          '/topic/tenant/t1/group/$g1/bans',
        });
        expect(live.link.sent.map((s) => s.$1), ['/app/tenant-chat/t1/$g1/typing', '/app/tenant-chat/t1/$g1/read']);
      },
    );

    for (final badId in [
      '../x',
      '../../t2/group/$g2',
      '*',
      '>',
      '#',
      '+',
      'abc',
      '$g2/typing',
      '$g2/../$g3',
      ' $g2',
      '$g2 ',
      '$g2\n',
      '$g2%2F..',
      '\u202E$g2',
      '${g2.substring(0, 35)}а',
      'ｇ',
    ]) {
      test(
        'REST group with hostile id ${jsonEncode(badId)}: no subscription, no typing / read / bans, no signal',
        () async {
          groups = [grp(g1), grp(badId)];
          await opened();
          final hostile = chat.groupById(badId);
          expect(hostile, isNotNull, reason: 'the backend list is shown as is; only the live channel is fail-closed');
          expect(scoped(), {'/topic/tenant/t1/group/$g1'});
          exercise(hostile!);
          expect(scoped(), {'/topic/tenant/t1/group/$g1'}, reason: 'nothing added by entering it');
          expect(live.link.sent, isEmpty);
          chat.leaveGroup(badId);
        },
      );
    }

    for (final tenant in <Object?>[
      't2',
      null,
      'T1',
      't1 ',
      ' t1',
      't1\n',
      't1/../t2',
      't1/group/x',
      '*',
      '>',
      '',
      't１',
    ]) {
      test('REST group with tenantId ${jsonEncode(tenant)} ≠ session tenant "t1": fail-closed', () async {
        groups = [grp(g1), grp(g2, tenant: tenant)];
        await opened();
        final foreign = chat.groupById(g2)!;
        expect(scoped(), {'/topic/tenant/t1/group/$g1'});
        exercise(foreign);
        expect(scoped(), {'/topic/tenant/t1/group/$g1'});
        expect(live.link.sent, isEmpty);
      });
    }

    for (final tenant in ['t1/../t2', 't1/group', '*', '>', '#', 't 1', 'a' * 65, '']) {
      test('hostile SESSION tenant ${jsonEncode(tenant)}: no REST call, no tenant destination, calls refuse', () async {
        FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': tenant});
        groups = [grp(g1, tenant: tenant)];
        await opened();
        expect(chat.groupsLoaded, isFalse);
        expect(chat.groupsError, isNotNull);
        expect(backend.requests.where((r) => r.url.path.contains('/chat/')), isEmpty);
        expect(scoped(), isEmpty);
        await expectLater(chat.createGroup(name: 'x'), throwsA(isA<ApiException>()));
        await expectLater(chat.members(ChatGroup(id: g1, tenantId: tenant)), throwsA(isA<ApiException>()));
        exercise(ChatGroup(id: g1, tenantId: tenant));
        expect(scoped(), isEmpty);
        expect(live.link.sent, isEmpty);
      });
    }

    test('a DM without a tenant (legacy row) is listed but has no live channel (fail-closed)', () async {
      groups = [grp(g1), grp(g2, type: 'DM', tenant: null, name: '')];
      await opened();
      final dm = chat.groupById(g2)!;
      expect(dm.isDm, isTrue);
      expect(dm.title, 'Direkt mesaj');
      expect(scoped(), {'/topic/tenant/t1/group/$g1'});
      exercise(dm);
      expect(live.link.sent, isEmpty);
    });

    test('a DM of the session tenant is live like any group; a DM of another tenant is not', () async {
      groups = [grp(g1)];
      backend.routes['/chat/dm/12'] = (_) => okData(grp(g2, type: 'DM', name: ''));
      backend.routes['/chat/dm/13'] = (_) => okData(grp(g3, type: 'DM', name: '', tenant: 't2'));
      await opened();
      final own = await chat.openDm(12);
      final foreign = await chat.openDm(13);
      expect(own.isDm, isTrue);
      expect(live.link.destinations, contains('/topic/tenant/t1/group/$g2'));
      expect(live.link.destinations, isNot(contains('/topic/tenant/t2/group/$g3')));
      expect(live.link.destinations.any((d) => d.contains(g3)), isFalse);
      exercise(foreign);
      expect(live.link.sent, isEmpty);
    });

    test('DM response without an id is an error, not a group', () async {
      backend.routes['/chat/dm/12'] = (_) => okData(<String, dynamic>{'name': 'x'});
      await opened();
      await expectLater(chat.openDm(12), throwsA(isA<ApiException>()));
      expect(chat.groups.map((g) => g.id), [g1]);
    });
  });

  group('deep link (resolveGroup)', () {
    test('hostile ids never reach the network', () async {
      await opened();
      final before = backend.requests.length;
      for (final id in ['../x', '*', '$g2/members', '', ' ', 'abc', '$g2\n', '..']) {
        expect(await chat.resolveGroup(id), isNull, reason: id);
      }
      expect(backend.requests.length, before);
    });

    test('unknown UUID: exactly GET /chat/tenant/t1/groups/{uuid}; 403 / 404 → null and nothing is added', () async {
      await opened();
      backend.routes['/chat/tenant/t1/groups/$g2'] = (_) => http.Response('{"message":"yok"}', 404);
      expect(await chat.resolveGroup(g2), isNull);
      backend.routes['/chat/tenant/t1/groups/$g3'] = (_) => http.Response('{"message":"yasak"}', 403);
      expect(await chat.resolveGroup(g3), isNull);
      expect(backend.requestsTo('/groups/$g2').single.method, 'GET');
      expect(chat.groups.map((g) => g.id), [g1]);
    });

    test('a group of ANOTHER tenant that the backend returned is still never given a live channel', () async {
      backend.routes['/chat/tenant/t1/groups/$g2'] = (_) => okData(grp(g2, tenant: 't2'));
      await opened();
      final resolved = await chat.resolveGroup(g2);
      expect(resolved, isNotNull);
      exercise(resolved!);
      expect(scoped(), {'/topic/tenant/t1/group/$g1'});
      expect(live.link.destinations.any((d) => d.contains('t2')), isFalse);
      expect(live.link.sent, isEmpty);
    });
  });

  group('/topic/groups/new is broadcast to everyone', () {
    test('other tenants, unknown tenant, hostile tenant strings: never added', () async {
      await opened();
      var n = 0;
      for (final tenant in <Object?>['t2', null, 'T1', 't1 ', 't1/../t2', '*', '']) {
        live.push(
          '/topic/groups/new',
          grp('aaaaaaaa-aaaa-4aaa-8aaa-${(n++).toString().padLeft(12, '0')}', tenant: tenant),
        );
      }
      await pumpEvents();
      expect(chat.groups.map((g) => g.id), [g1]);
      expect(scoped(), {'/topic/tenant/t1/group/$g1'});
    });

    test('before the list is loaded the broadcast is ignored (the list fetch will have it)', () async {
      backend.routes['/chat/tenant/t1/groups'] = (_) => http.Response('{"message":"hata"}', 500);
      await opened();
      expect(chat.groupsLoaded, isFalse);
      live.push('/topic/groups/new', grp(g4));
      expect(chat.groupById(g4), isNull);
    });

    test('same tenant but a hostile id: listed (backend data) yet fail-closed on the live channel', () async {
      await opened();
      live.push('/topic/groups/new', grp('../../t2/group/$g2'));
      expect(chat.groupById('../../t2/group/$g2'), isNotNull);
      expect(scoped(), {'/topic/tenant/t1/group/$g1'});
    });

    test('a repeated event for a known group updates it in place (no duplicate row, no second subscription)', () async {
      await opened();
      live.push('/topic/groups/new', grp(g1, name: 'Yeni ad'));
      live.push('/topic/groups/new', grp(g1, name: 'Yeni ad'));
      expect(chat.groups.where((g) => g.id == g1), hasLength(1));
      expect(chat.groupById(g1)!.name, 'Yeni ad');
      expect(live.link.subscriptions['/topic/tenant/t1/group/$g1'], hasLength(1));
    });

    for (final (mine, theirs, refetch) in [
      (1, 1, false),
      (1, 2, true),
      (2, 2, false),
      (2, 3, true),
      (3, 3, false),
      (3, 4, true),
      (4, 4, false),
      (4, 1, false),
      (2, 1, false),
    ]) {
      test(
        'invite hierarchy: my level $mine, new group visible from level $theirs → ${refetch ? 're-fetch the list' : 'added directly'}',
        () async {
          await opened(level: mine);
          final lists = backend.requestsTo('/chat/tenant/t1/groups').length;
          live.push('/topic/groups/new', grp(g4, level: theirs));
          await pumpEvents();
          expect(backend.requestsTo('/chat/tenant/t1/groups').length, lists + (refetch ? 1 : 0));
          expect(chat.groupById(g4) != null, !refetch, reason: 'the re-fetched list is the authority');
        },
      );
    }
  });

  group('/topic/user/{me}/membership', () {
    final topic = '/topic/user/$me/membership';

    test(
      'JOINED with a group of another tenant, or whose id differs from groupId, is not inserted (list re-fetched)',
      () async {
        await opened();
        final lists = backend.requestsTo('/chat/tenant/t1/groups').length;
        live.push(topic, {'action': 'JOINED', 'groupId': g2, 'group': grp(g2, tenant: 't2')});
        live.push(topic, {'action': 'JOINED', 'groupId': g3, 'group': grp(g4)});
        live.push(topic, {'action': 'JOINED', 'groupId': g3, 'group': 'not a map'});
        await pumpEvents();
        expect(chat.groups.map((g) => g.id), [g1]);
        expect(backend.requestsTo('/chat/tenant/t1/groups').length, greaterThan(lists));
      },
    );

    test('hostile / missing groupId: ignored without any side effect', () async {
      await opened();
      final lists = backend.requestsTo('/chat/tenant/t1/groups').length;
      for (final id in <Object?>[null, '', '../x', '*', '$g1/typing', 7]) {
        live.push(topic, {'action': 'REMOVED', 'groupId': id, 'message': 'x'});
        live.push(topic, {'action': 'JOINED', 'groupId': id, 'group': grp(g4)});
      }
      await pumpEvents();
      expect(chat.groups.map((g) => g.id), [g1]);
      expect(backend.requestsTo('/chat/tenant/t1/groups').length, lists);
    });

    test('REMOVED from a group that is not open: dropped with its live channel; unknown group: harmless', () async {
      await opened();
      live.push(topic, {'action': 'REMOVED', 'groupId': g2});
      expect(chat.groups.map((g) => g.id), [g1]);
      live.push(topic, {'action': 'REMOVED', 'groupId': g1});
      expect(chat.groups, isEmpty);
      expect(scoped(), isEmpty);
    });

    test('the notice text is untrusted: bidi shown, entities decoded', () async {
      await opened();
      chat.enterGroup(chat.groupById(g1)!);
      backend.ok('/chat/tenant/t1/groups/$g1/access', {'canRead': false, 'canWrite': false});
      final notices = <ChatNotice>[];
      final sub = chat.notices.listen(notices.add);
      live.push(topic, {'action': 'REMOVED', 'groupId': g1, 'message': 'Çıkarıldınız\u202E &lt;b&gt;'});
      await pumpEvents();
      expect(notices.single.message, 'Çıkarıldınız⟨U+202E⟩ <b>');
      await sub.cancel();
    });
  });

  group('malformed frames never break the provider', () {
    const bodies = ['garbage', '', 'null', '[]', '42', '"str"', '{}', '{"id":1}', '{"userId":"x"}', '[{"id":"a"}]'];

    String snapshot() => [
      chat.groups.map((g) => '${g.id}:${g.name}:${chat.unreadOf(g.id)}:${chat.lastMessageOf(g.id)?.id}').join('|'),
      chat.activeGroupId,
      chat.bannedKeys.join(','),
      chat.isOnline(5),
      chat.typingText(g1),
      chat.seenBy(g1).join(','),
    ].join('#');

    test('every subscribed topic survives every body, state unchanged (chat-errors only raises a notice)', () async {
      await opened();
      chat.enterGroup(chat.groupById(g1)!);
      final before = snapshot();
      for (final topic in live.link.destinations.toList()) {
        for (final body in bodies) {
          live.link.deliver(topic, body);
        }
      }
      await pumpEvents();
      expect(snapshot(), before);
      expect(chat.started, isTrue);
      expect(live.realtime.connected, isTrue);
      // the connection and every handler still work afterwards
      live.push('/topic/presence', {'userId': 5, 'status': 'ONLINE'});
      expect(chat.isOnline(5), isTrue);
    });

    test('group deleted: only an exact known UUID removes a group', () async {
      await opened();
      for (final body in ['', ' ', '*', '..', g2, '${g1.substring(0, 35)}2', '$g1/x', '{"id":"$g1"}', 'null']) {
        live.push('/topic/groups/deleted', body);
      }
      await pumpEvents();
      expect(chat.groupById(g1), isNotNull);
      live.push('/topic/groups/deleted', '  $g1\n');
      await pumpEvents();
      expect(chat.groupById(g1), isNull, reason: 'surrounding whitespace is the transport\'s, the id is exact');
    });

    test('a message frame whose groupId is another group is not stored; the right one is', () async {
      groups = [grp(g1), grp(g2)];
      await opened();
      Map<String, dynamic> m(String gid, String id) => {
        'id': id,
        'groupId': gid,
        'senderType': 'ADMIN',
        'senderId': 5,
        'content': 'x',
        'contentType': 'TEXT',
        'createdAt': '2026-10-14T09:00:00Z',
      };
      live.push('/topic/tenant/t1/group/$g1', m(g2, 'spoof'));
      live.push('/topic/tenant/t1/group/$g1', m('../x', 'spoof2'));
      expect(chat.messagesOf(g1), isEmpty);
      expect(chat.messagesOf(g2), isEmpty);
      expect(chat.unreadOf(g1) + chat.unreadOf(g2), 0);
      live.push('/topic/tenant/t1/group/$g1', m(g1, 'ok'));
      expect(chat.messagesOf(g1).single.id, 'ok');
      expect(chat.unreadOf(g1), 1);
    });
  });

  group('invite at the provider level', () {
    test('by id: trimmed, POST /members/{int}; by e-mail: trimmed, POST /members/by-email', () async {
      backend.routes['/chat/tenant/t1/groups/$g1/members/12'] = (_) => jsonResponse({
        'result': true,
        'data': {'userId': 12, 'username': 'x'},
      }, 201);
      backend.routes['/chat/tenant/t1/groups/$g1/members/by-email'] = (req) {
        expect(jsonDecode(req.body), {'email': 'a@b.co'});
        return jsonResponse({
          'result': true,
          'data': {'userId': 13, 'username': 'y'},
        }, 201);
      };
      await opened();
      expect((await chat.invite(chat.groupById(g1)!, '\t12\n'))!.userId, 12);
      expect((await chat.invite(chat.groupById(g1)!, '  a@b.co '))!.userId, 13);
    });

    test(
      'the backend decides the hierarchy: a refusal is surfaced as the Turkish text and nothing is cached',
      () async {
        backend.routes['/chat/tenant/t1/groups/$g1/members/99'] = (_) =>
            jsonResponse({'message': 'You can only invite users with your role level or lower'}, 403);
        await opened(level: 2);
        Object? error;
        try {
          await chat.invite(chat.groupById(g1)!, '99');
        } catch (e) {
          error = e;
        }
        expect(error, isA<ApiException>());
        expect((error! as ApiException).statusCode, 403);
      },
    );
  });
}
