import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/chat/chat_conversation_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_group_form_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_members_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

const g1 = '11111111-1111-4111-8111-111111111111';
const g2 = '22222222-2222-4222-8222-222222222222';
const me = 7;
const _me = {'id': me, 'username': 'ben', 'firstName': 'Ben', 'lastName': 'Admin'};

Map<String, dynamic> chatGroup(String id, {String name = 'Ekip', int createdBy = 1, int level = 1}) => {
  'id': id,
  'name': name,
  'type': 'GROUP',
  'createdBy': createdBy,
  'visibilityLevel': level,
  'tenantId': 't1',
  'visitorAccess': false,
  'updatedAt': '2026-10-01T09:00:00Z',
};

Map<String, dynamic> msg(
  String id, {
  int? sender = 5,
  String content = 'merhaba',
  String type = 'ADMIN',
  String? sessionId,
  int minute = 0,
  String contentType = 'TEXT',
}) => {
  'id': id,
  'groupId': g1,
  'senderType': type,
  'senderId': type == 'ADMIN' ? sender : null,
  'sessionId': sessionId,
  'senderUsername': type == 'GUEST' ? 'Misafir Ali' : 'user$sender',
  'content': content,
  'contentType': contentType,
  'deleted': false,
  'createdAt': DateTime.utc(2026, 10, 14, 9, minute).toIso8601String(),
};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late List<Map<String, dynamic>> history;
  late bool canWrite;
  late List<Uri> launched;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    history = [msg('m1', content: 'ilk mesaj', minute: 1)];
    canWrite = true;
    launched = [];
    backend.ok('/chat/tenant/t1/groups', [chatGroup(g1), chatGroup(g2, name: 'Destek')]);
    backend.routes['/chat/tenant/t1/groups/$g1/access'] = (_) => okData({
      'groupId': g1,
      'member': canWrite,
      'canRead': true,
      'canWrite': canWrite,
      'denialMessage': canWrite ? null : 'Bu gruba yazmak için üye olmalısınız.',
    });
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (req) {
      if (req.method == 'POST') {
        final body = jsonDecode(req.body) as Map;
        return jsonResponse({
          'result': true,
          'data': msg('new', sender: me, content: body['content'], minute: 30),
        }, 201);
      }
      return okData(req.url.queryParameters.containsKey('before') ? <Object>[] : history);
    };
    backend.ok('/chat/tenant/t1/groups/$g1/bans', []);
    backend.ok('/chat/tenant/t1/groups/$g1/members', [
      {'userId': 1, 'username': 'kurucu', 'firstName': 'Kurucu', 'lastName': '', 'role': 'OWNER'},
      {'userId': me, 'username': 'ben', 'firstName': 'Ben', 'lastName': 'Admin', 'role': 'MEMBER'},
      {'userId': 5, 'username': 'ayse', 'firstName': 'Ayşe', 'lastName': 'Y', 'role': 'MEMBER'},
    ]);
  });

  tearDown(() => live.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    List<String> perms = const ['chat:read'],
    List<String> roles = const ['ADMIN'],
    Map<String, dynamic>? profile = _me,
    bool open = true,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await backend.signIn(auth, perms, roles: roles, me: profile);
      live.realtime.start();
      if (open) await live.chat.open(myUserId: auth.userId, myLevel: auth.roleLevel);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ...live.providers,
        ],
        child: MaterialApp(theme: appTheme, home: home),
      ),
    );
    await settle(tester);
  }

  Widget conversation() => ChatConversationScreen(
    groupId: g1,
    launcher: (uri) async {
      launched.add(uri);
      return true;
    },
  );

  group('chat list', () {
    testWidgets('groups with badges; a live message shows the unread count and preview; tap opens it', (tester) async {
      await pump(tester, const ChatScreen(), open: false);
      expect(find.text('Ekip'), findsOneWidget);
      expect(find.text('Destek'), findsOneWidget);
      expect(find.text('Herkese açık'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('chat_new_group')), findsOneWidget);

      live.push('/topic/tenant/t1/group/$g2', {...msg('x', content: 'selam\u202E'), 'groupId': g2});
      await tester.pump();
      expect(find.byKey(const ValueKey('chat_unread_$g2')), findsOneWidget);
      expect(find.text('user5: selam⟨U+202E⟩'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('1 okunmamış mesaj')), findsOneWidget);
      semantics.dispose();

      await tester.tap(find.text('Ekip'));
      await settle(tester);
      expect(find.byType(ChatConversationScreen), findsOneWidget);
      expect(find.text('ilk mesaj'), findsOneWidget);
    });

    testWidgets('load failure: error with retry', (tester) async {
      backend.routes['/chat/tenant/t1/groups'] = (_) => jsonResponse({'message': 'Sunucu hatası'}, 500);
      await pump(tester, const ChatScreen(), open: false);
      expect(find.text('Sunucu hatası'), findsOneWidget);
      backend.ok('/chat/tenant/t1/groups', [chatGroup(g1)]);
      await tester.tap(find.text('Tekrar Dene'));
      await settle(tester);
      expect(find.text('Ekip'), findsOneWidget);
    });

    testWidgets('DM: user id validated, POST /chat/dm/{id}, conversation opened', (tester) async {
      backend.ok('/chat/dm/12', {...chatGroup(g1, name: ''), 'type': 'DM'});
      await pump(tester, const ChatScreen(), open: false);
      await tester.tap(find.byKey(const ValueKey('chat_dm_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat_dm_submit')));
      await tester.pump();
      expect(find.text('Geçerli bir kullanıcı ID girin'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('chat_dm_user_id')), '12');
      await tester.tap(find.byKey(const ValueKey('chat_dm_submit')));
      await settle(tester);
      expect(backend.requestsTo('/chat/dm/12').single.method, 'POST');
      expect(find.byType(ChatConversationScreen), findsOneWidget);
      expect(find.text('Direkt mesaj'), findsWidgets);
    });
  });

  group('conversation', () {
    testWidgets('untrusted content is plain text: entities decoded, tags literal, bidi visible', (tester) async {
      history = [msg('m1', content: '&lt;b&gt;kalın&lt;/b&gt; &amp; \u202Etxt.exe <img src=x onerror=alert(1)>')];
      await pump(tester, conversation());
      expect(find.text('<b>kalın</b> & ⟨U+202E⟩txt.exe <img src=x onerror=alert(1)>'), findsOneWidget);
    });

    testWidgets('long message: preview + "Tümünü göster" / "Daha az göster"', (tester) async {
      history = [msg('m1', content: 'x' * 1500)];
      await pump(tester, conversation());
      expect(find.text('${'x' * 1000}…'), findsOneWidget);
      await tester.tap(find.text('Tümünü göster'));
      await tester.pump();
      expect(find.text('x' * 1500), findsOneWidget);
      expect(find.text('Daha az göster'), findsOneWidget);
    });

    testWidgets('http(s) link opens only after confirmation; other schemes are plain text', (tester) async {
      history = [msg('m1', content: 'bak https://elly.dev/x ve javascript:alert(1)')];
      await pump(tester, conversation());
      await tester.tapOnText(find.textRange.ofSubstring('https://elly.dev/x'));
      await tester.pumpAndSettle();
      expect(find.textContaining('https://elly.dev/x', findRichText: true), findsWidgets);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(launched, isEmpty);

      await tester.tapOnText(find.textRange.ofSubstring('https://elly.dev/x'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await tester.pumpAndSettle();
      expect(launched, [Uri.parse('https://elly.dev/x')]);

      await tester.tapOnText(find.textRange.ofSubstring('javascript:alert(1)'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('send: typing signal, POST, own message shown, composer cleared', (tester) async {
      await pump(tester, conversation());
      expect(live.link.sent, contains(('/app/tenant-chat/t1/$g1/read', '')));
      await tester.enterText(find.byKey(const ValueKey('chat_composer')), 'Yeni mesaj');
      await tester.pump();
      expect(live.link.sent, contains(('/app/tenant-chat/t1/$g1/typing', '')));
      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await settle(tester);
      expect(jsonDecode(backend.requestsTo('/messages').lastWhere((r) => r.method == 'POST').body), {
        'content': 'Yeni mesaj',
        'contentType': 'TEXT',
      });
      expect(find.text('Yeni mesaj'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('chat_composer'))).controller!.text, isEmpty);
    });

    testWidgets('live: messages, typing indicator, "Görüldü" under the own last message', (tester) async {
      history = [msg('m1', sender: me, content: 'benim')];
      await pump(tester, conversation());
      live.push('/topic/tenant/t1/group/$g1/read', {'groupId': g1, 'userId': 5, 'username': 'ayse'});
      await tester.pump();
      expect(find.textContaining('Görüldü: ayse'), findsOneWidget);

      live.push('/topic/tenant/t1/group/$g1/typing', {'groupId': g1, 'userId': 5, 'username': 'Ayşe', 'typing': true});
      await tester.pump();
      expect(find.text('Ayşe yazıyor…'), findsOneWidget);
      live.push('/topic/tenant/t1/group/$g1', msg('m2', content: 'canlı', minute: 5));
      await tester.pump();
      expect(find.text('canlı'), findsOneWidget);
      expect(find.text('Ayşe yazıyor…'), findsNothing);
    });

    testWidgets('no write access: composer disabled, backend reason shown', (tester) async {
      canWrite = false;
      await pump(tester, conversation());
      expect(tester.widget<TextField>(find.byKey(const ValueKey('chat_composer'))).enabled, isFalse);
      expect(find.text('Bu gruba yazmak için üye olmalısınız.'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('chat_send'))).onPressed, isNull);
    });

    testWidgets('send refused (403): banner + access re-checked', (tester) async {
      await pump(tester, conversation());
      backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (req) => req.method == 'POST'
          ? jsonResponse({'message': 'Bu sohbette yazma yetkiniz kaldırıldı'}, 403)
          : okData(history);
      final accessCalls = backend.requestsTo('/access').length;
      await tester.enterText(find.byKey(const ValueKey('chat_composer')), 'deneme');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await settle(tester);
      expect(find.text('Bu sohbette yazma yetkiniz kaldırıldı'), findsWidgets);
      expect(backend.requestsTo('/access').length, accessCalls + 1);
    });

    testWidgets('own message: long press → delete (confirmed) → "Bu mesaj silindi"', (tester) async {
      history = [msg('m1', sender: me, content: 'silinecek')];
      backend.routes['/chat/tenant/t1/messages/m1'] = (_) => http.Response('', 204);
      await pump(tester, conversation());
      await tester.longPress(find.text('silinecek'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat_action_ban')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat_action_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await settle(tester);
      expect(backend.requestsTo('/messages/m1').single.method, 'DELETE');
      expect(find.text('Bu mesaj silindi'), findsOneWidget);
    });

    testWidgets("someone else's message: no delete; guest ban only with chat:manage", (tester) async {
      history = [msg('m1', type: 'GUEST', sessionId: 's-1', content: 'misafir yazdı')];
      await pump(tester, conversation());
      expect(find.text('Misafir'), findsOneWidget, reason: 'sender badge');
      await tester.longPress(find.text('misafir yazdı'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat_action_delete')), findsNothing);
      expect(find.byKey(const ValueKey('chat_action_ban')), findsNothing);
      expect(find.text('Metni kopyala'), findsOneWidget);
    });

    testWidgets('chat:manage: ban a guest (confirmed) → POST /bans, "Yasaklı" badge', (tester) async {
      history = [msg('m1', type: 'GUEST', sessionId: 's-1', content: 'misafir yazdı')];
      backend.routes['/chat/tenant/t1/groups/$g1/bans'] = (req) => req.method == 'POST'
          ? jsonResponse({
              'result': true,
              'data': {'id': 'b'},
            }, 201)
          : okData([]);
      await pump(tester, conversation(), perms: ['chat:read', 'chat:manage']);
      await tester.longPress(find.text('misafir yazdı'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat_action_ban')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await settle(tester);
      expect(jsonDecode(backend.requestsTo('/bans').lastWhere((r) => r.method == 'POST').body), {'sessionId': 's-1'});
      expect(find.text('Yasaklı'), findsOneWidget);
    });

    testWidgets('scrolling up loads the older page (?before=<oldest id>) until the start', (tester) async {
      history = [for (var i = 0; i < 50; i++) msg('h$i', minute: i)];
      await pump(tester, conversation());
      for (
        var i = 0;
        i < 6 && !backend.requestsTo('/messages').any((r) => r.url.queryParameters['before'] != null);
        i++
      ) {
        await tester.drag(find.byKey(const ValueKey('chat_messages')), const Offset(0, 1500));
        await settle(tester);
      }
      expect(backend.requestsTo('/messages').where((r) => r.url.queryParameters['before'] == 'h0'), hasLength(1));
      await tester.drag(find.byKey(const ValueKey('chat_messages')), const Offset(0, 3000));
      await settle(tester);
      expect(find.text('Sohbetin başı'), findsOneWidget);
    });

    testWidgets('file message: only our upload path is a file button (opens after confirmation)', (tester) async {
      history = [
        msg('f1', content: 'assets/chat/rapor.pdf', contentType: 'FILE'),
        msg('f2', content: 'https://evil.com/x.exe', contentType: 'FILE', minute: 1),
      ];
      await pump(tester, conversation());
      expect(find.text('rapor.pdf'), findsOneWidget);
      expect(find.text('https://evil.com/x.exe'), findsOneWidget, reason: 'not a stored path → plain text');
      await tester.tap(find.text('rapor.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await tester.pumpAndSettle();
      expect(launched.single.path, '/assets/chat/rapor.pdf');
    });

    testWidgets('deleted group (live): the conversation closes', (tester) async {
      await pump(tester, const ChatScreen());
      await tester.tap(find.text('Ekip'));
      await settle(tester);
      live.push('/topic/groups/deleted', g1);
      await tester.pumpAndSettle();
      expect(find.byType(ChatConversationScreen), findsNothing);
      expect(find.text('Bu grup silindi.'), findsOneWidget);
    });

    for (final (label, perms, roles, createdBy, profile, visible) in [
      ('owner with chat:manage', ['chat:read', 'chat:manage'], ['EDITOR'], me, _me, true),
      ('SUPER_ADMIN (not owner)', ['chat:read', 'chat:manage'], ['SUPER_ADMIN'], 1, _me, true),
      ('ADMIN, not owner', ['chat:read', 'chat:manage'], ['ADMIN'], 1, _me, false),
      ('owner without chat:manage', ['chat:read'], ['VIEWER'], me, _me, false),
      ('own id unknown (fail closed)', ['chat:read', 'chat:manage'], <String>[], me, null, false),
    ]) {
      testWidgets('"Grubu sil" gating: $label → ${visible ? 'shown' : 'hidden'}', (tester) async {
        backend.ok('/chat/tenant/t1/groups', [chatGroup(g1, createdBy: createdBy)]);
        await pump(tester, conversation(), perms: perms, roles: roles, profile: profile);
        expect(find.byKey(const ValueKey('chat_delete_group')), visible ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('delete group: confirmed DELETE, screen closes', (tester) async {
      backend.ok('/chat/tenant/t1/groups', [chatGroup(g1, createdBy: me)]);
      backend.routes['/chat/tenant/t1/groups/$g1'] = (_) => http.Response('', 204);
      await pump(tester, const ChatScreen(), perms: ['chat:read', 'chat:manage']);
      await tester.tap(find.text('Ekip'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat_delete_group')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await settle(tester);
      expect(backend.requestsTo('/groups/$g1').last.method, 'DELETE');
      expect(find.byType(ChatConversationScreen), findsNothing);
      expect(find.text('Ekip'), findsNothing);
    });
  });

  group('members', () {
    Future<void> pumpMembers(
      WidgetTester tester, {
      List<String> perms = const ['chat:read'],
      List<String> roles = const ['ADMIN'],
    }) async {
      await pump(tester, const SizedBox(), perms: perms, roles: roles);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute(builder: (_) => ChatMembersScreen(group: live.chat.groupById(g1)!)));
      await settle(tester);
    }

    testWidgets('list: owner badge, online after a presence event; no invite / remove without chat:manage', (
      tester,
    ) async {
      await pumpMembers(tester);
      expect(find.text('Üyeler (3)'), findsOneWidget);
      expect(find.text('Sahip'), findsOneWidget);
      expect(find.text('Çevrimiçi'), findsNothing);
      live.push('/topic/presence', {'userId': 5, 'username': 'ayse', 'status': 'ONLINE'});
      await tester.pump();
      expect(find.text('Çevrimiçi'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_invite_input')), findsNothing);
      expect(find.byKey(const ValueKey('chat_remove_5')), findsNothing);
    });

    testWidgets('chat:manage: remove only for others that are not the owner (confirmed DELETE)', (tester) async {
      backend.routes['/chat/tenant/t1/groups/$g1/members/5'] = (_) => http.Response('', 204);
      await pumpMembers(tester, perms: ['chat:read', 'chat:manage']);
      expect(find.byKey(const ValueKey('chat_remove_1')), findsNothing, reason: 'owner');
      expect(find.byKey(const ValueKey('chat_remove_$me')), findsNothing, reason: 'self');
      await tester.tap(find.byKey(const ValueKey('chat_remove_5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await settle(tester);
      expect(backend.requestsTo('/members/5').single.method, 'DELETE');
      expect(find.text('Üyeler (2)'), findsOneWidget);
    });

    for (final (role, hint) in [('ADMIN', 'altındaki'), ('EDITOR', 'altındaki'), ('SUPER_ADMIN', 'herkesi')]) {
      testWidgets('invite hint by role level: $role', (tester) async {
        await pumpMembers(tester, perms: ['chat:read', 'chat:manage'], roles: [role]);
        expect(find.textContaining(hint), findsOneWidget);
      });
    }

    testWidgets('invite: input validated; hierarchy refusal (403) shown in Turkish; success adds the member', (
      tester,
    ) async {
      backend.routes['/chat/tenant/t1/groups/$g1/members/by-email'] = (req) =>
          jsonResponse({'message': 'You can only invite users with your role level or lower'}, 403);
      backend.routes['/chat/tenant/t1/groups/$g1/members/12'] = (_) => jsonResponse({
        'result': true,
        'data': {'userId': 12, 'username': 'yeni', 'firstName': 'Yeni', 'lastName': 'Üye', 'role': 'MEMBER'},
      }, 201);
      await pumpMembers(tester, perms: ['chat:read', 'chat:manage']);
      final input = find.byKey(const ValueKey('chat_invite_input'));

      await tester.enterText(input, 'abc');
      await tester.tap(find.byKey(const ValueKey('chat_invite_submit')));
      await tester.pump();
      expect(find.text('Geçerli bir kullanıcı ID girin'), findsOneWidget);
      expect(backend.requestsTo('/members/'), isEmpty);

      await tester.enterText(input, 'super@elly.dev');
      await tester.tap(find.byKey(const ValueKey('chat_invite_submit')));
      await settle(tester);
      expect(
        find.text('Yalnız kendi rol seviyenizdeki ve altındaki kullanıcıları davet edebilirsiniz.'),
        findsOneWidget,
      );

      await tester.enterText(input, '12');
      await tester.tap(find.byKey(const ValueKey('chat_invite_submit')));
      await settle(tester);
      expect(find.text('Yeni Üye'), findsOneWidget);
      expect(find.text('Üyeler (4)'), findsOneWidget);
    });
  });

  group('new group form', () {
    for (final (role, tenantOption) in [('ADMIN', true), ('SUPER_ADMIN', true), ('EDITOR', false), ('VIEWER', false)]) {
      testWidgets('Tenant Chat option only for ADMIN+: $role → $tenantOption', (tester) async {
        await pump(tester, const ChatGroupFormScreen(), roles: [role]);
        expect(find.byKey(const ValueKey('chat_scope_tenant')), tenantOption ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('name required; tenant chat with visitor access posts tenantId + visitorAccess', (tester) async {
      backend.routes['/chat/tenant/t1/groups'] = (req) => req.method == 'POST'
          ? jsonResponse({'result': true, 'data': chatGroup(g2, name: 'Site')}, 201)
          : okData([chatGroup(g1)]);
      await pump(tester, const ChatScreen(), perms: ['chat:read']);
      await tester.tap(find.byKey(const ValueKey('chat_new_group')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat_group_save')));
      await tester.pumpAndSettle();
      expect(find.text('Grup adı zorunlu'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('chat_group_name')), 'Site');
      await tester.tap(find.byKey(const ValueKey('chat_scope_tenant')));
      await tester.pumpAndSettle();
      expect(find.textContaining('t1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat_visitor_access')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat_group_save')));
      await settle(tester);
      expect(jsonDecode(backend.requestsTo('/chat/tenant/t1/groups').lastWhere((r) => r.method == 'POST').body), {
        'name': 'Site',
        'tenantId': 't1',
        'visitorAccess': true,
      });
      expect(find.byType(ChatConversationScreen), findsOneWidget, reason: 'the new group opens');
    });
  });
}
