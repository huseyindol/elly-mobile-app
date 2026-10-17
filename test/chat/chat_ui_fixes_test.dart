import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/chat/chat_conversation_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_members_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_screen.dart';
import 'package:elly_mobile_app/widgets/connection_banner.dart';
import 'package:elly_mobile_app/widgets/info_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_realtime.dart';
import '../helpers/gated_backend.dart';
import '../helpers/fake_backend.dart';

const g1 = '11111111-1111-4111-8111-111111111111';
const me = 7;

Map<String, dynamic> msg(String id, {int sender = 5, String content = 'merhaba', int minute = 0}) => {
  'id': id,
  'groupId': g1,
  'senderType': 'ADMIN',
  'senderId': sender,
  'senderUsername': 'user$sender',
  'content': content,
  'contentType': 'TEXT',
  'deleted': false,
  'createdAt': DateTime.utc(2026, 10, 14, 9, minute).toIso8601String(),
};

/// Phase 5 review fixes: no jump while reading older messages (+ "N yeni mesaj" chip, read receipts only at the
/// bottom), one semantics node per message, composer/SnackBar layout, banner source, send keeps new typing, file
/// confirmation, connection strip timing, members panel with the keyboard, list row time.
void main() {
  late GatedBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late List<Map<String, dynamic>> history;
  late bool canWrite;

  setUp(() {
    backend = GatedBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    history = [for (var i = 0; i < 40; i++) msg('h$i', content: 'mesaj $i', minute: i)];
    canWrite = true;
    backend.ok('/chat/tenant/t1/groups', [
      {'id': g1, 'name': 'Ekip', 'type': 'GROUP', 'createdBy': 1, 'visibilityLevel': 1, 'tenantId': 't1'},
    ]);
    backend.routes['/chat/tenant/t1/groups/$g1/access'] = (_) => okData({
      'canRead': true,
      'canWrite': canWrite,
      'denialMessage': canWrite ? null : 'Bu gruba yazmak için üye olmalısınız.',
    });
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (req) {
      if (req.method == 'POST') {
        final body = jsonDecode(req.body) as Map;
        return jsonResponse({
          'result': true,
          'data': msg('sent', sender: me, content: body['content'], minute: 59),
        }, 201);
      }
      return okData(req.url.queryParameters.containsKey('before') ? <Object>[] : history);
    };
    backend.ok('/chat/tenant/t1/groups/$g1/bans', []);
    backend.ok('/chat/tenant/t1/groups/$g1/members', [
      {'userId': 5, 'username': 'ayse', 'firstName': 'Ayşe', 'lastName': '', 'role': 'MEMBER'},
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
    bool startRealtime = true,
    Size size = const Size(800, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await backend.signIn(auth, perms, roles: const ['ADMIN'], me: const {'id': me, 'username': 'ben'});
      if (startRealtime) live.realtime.start();
      await live.chat.open(myUserId: auth.userId, myLevel: auth.roleLevel);
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

  Widget conversation({Future<PickedChatFile?> Function()? pick}) =>
      ChatConversationScreen(groupId: g1, launcher: (_) async => true, pickFile: pick ?? () async => null);

  int reads() => live.link.sent.where((s) => s.$1 == '/app/tenant-chat/t1/$g1/read').length;
  final list = find.byKey(const ValueKey('chat_messages'));

  group('reading older messages', () {
    testWidgets('a new message does not move the view: chip "N yeni mesaj", no read receipt until back down', (
      tester,
    ) async {
      await pump(tester, conversation());
      expect(reads(), 1, reason: 'opening at the newest message');
      await tester.drag(list, const Offset(0, 600));
      await tester.pumpAndSettle();
      final shown = find
          .byWidgetPredicate((w) => w is Text && (w.textSpan?.toPlainText() ?? '').startsWith('mesaj '))
          .hitTestable();
      final anchorText = tester.widget<Text>(shown.first).textSpan!.toPlainText();
      final anchor = tester.getTopLeft(find.text(anchorText));

      live.push('/topic/tenant/t1/group/$g1', msg('n1', content: 'yeni 1', minute: 50));
      live.push('/topic/tenant/t1/group/$g1', msg('n2', content: 'yeni 2', minute: 51));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text(anchorText)), anchor, reason: 'content did not shift');
      expect(find.text('2 yeni mesaj'), findsOneWidget);
      expect(reads(), 1, reason: 'not read while the user is up in the history');

      await tester.tap(find.byKey(const ValueKey('chat_new_messages')));
      await tester.pumpAndSettle();
      expect(find.text('yeni 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_new_messages')), findsNothing);
      expect(reads(), 2, reason: 'back at the newest message → one read receipt');
    });

    testWidgets('at the bottom new messages appear at once and are read', (tester) async {
      await pump(tester, conversation());
      live.push('/topic/tenant/t1/group/$g1', msg('n1', content: 'yeni 1', minute: 50));
      await tester.pumpAndSettle();
      expect(find.text('yeni 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_new_messages')), findsNothing);
    });

    testWidgets('own message while scrolled up jumps to the newest', (tester) async {
      await pump(tester, conversation());
      await tester.drag(list, const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('chat_composer')), 'benim');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_send')));
      await settle(tester);
      expect(find.text('benim'), findsWidgets);
      expect(tester.widget<ListView>(list).controller!.offset, 0);
    });
  });

  testWidgets('"Tümünü göster" uses the bubble text color (own bubble: white)', (tester) async {
    history = [msg('m1', sender: me, content: 'x' * 1500)];
    await pump(tester, conversation());
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Tümünü göster'));
    expect(button.style!.foregroundColor!.resolve({}), Colors.white);
  });

  testWidgets('each message is one semantics node with sender, time, role and text + custom actions', (tester) async {
    final handle = tester.ensureSemantics();
    history = [msg('m1', content: 'selam https://elly.dev'), msg('m2', sender: me, content: 'benimki', minute: 1)];
    await pump(tester, conversation());
    final other = tester.getSemantics(find.byKey(const ValueKey('chat_msg_m1')));
    expect(other.label, matches(RegExp(r'^user5, (?:\d\d\.\d\d )?\d\d:\d\d, Admin: selam https://elly\.dev$')));
    final actions = other
        .getSemanticsData()
        .customSemanticsActionIds!
        .map(CustomSemanticsAction.getAction)
        .map((a) => a!.label);
    expect(actions, containsAll(['Metni kopyala', 'Bağlantıyı aç: https://elly.dev']));
    expect(actions, isNot(contains('Mesajı sil')));

    final own = tester.getSemantics(find.byKey(const ValueKey('chat_msg_m2')));
    expect(own.label, matches(RegExp(r'^Siz, (?:\d\d\.\d\d )?\d\d:\d\d: benimki$')));
    final ownActions = own
        .getSemanticsData()
        .customSemanticsActionIds!
        .map(CustomSemanticsAction.getAction)
        .map((a) => a!.label);
    expect(ownActions, contains('Mesajı sil'));
    handle.dispose();
  });

  testWidgets('SnackBars sit above the composer', (tester) async {
    backend.routes['/chat/tenant/t1/groups/$g1/messages'] = (req) =>
        req.method == 'POST' ? jsonResponse({'message': 'Sunucu hatası'}, 500) : okData(history);
    await pump(tester, conversation());
    await tester.enterText(find.byKey(const ValueKey('chat_composer')), 'deneme');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await settle(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(SnackBar)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(const ValueKey('chat_composer'))).dy),
    );
  });

  testWidgets('composer banner comes only from access: shown when writing is denied, gone when access returns', (
    tester,
  ) async {
    canWrite = false;
    await pump(tester, conversation());
    expect(find.text('Bu gruba yazmak için üye olmalısınız.'), findsOneWidget);
    canWrite = true;
    live.push('/topic/user/$me/membership', {
      'action': 'JOINED',
      'groupId': g1,
      'userId': me,
      'group': {'id': g1, 'name': 'Ekip', 'type': 'GROUP', 'visibilityLevel': 1, 'tenantId': 't1'},
      'message': 'Gruba dahil edildiniz.',
    });
    await settle(tester);
    expect(find.text('Bu gruba yazmak için üye olmalısınız.'), findsNothing);
    expect(find.byType(InfoNote), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('chat_composer'))).enabled, isTrue);
  });

  testWidgets('send keeps what was typed while the request was in flight', (tester) async {
    await pump(tester, conversation());
    await tester.enterText(find.byKey(const ValueKey('chat_composer')), 'ilk');
    await tester.pump();
    final gate = backend.hold('/chat/tenant/t1/groups/$g1/messages');
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('chat_composer')), 'ilk ikinci');
    gate.complete();
    await settle(tester);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('chat_composer'))).controller!.text, ' ikinci');
  });

  testWidgets('typing row only while someone types and outside any live region; 4000-character limit warned', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, conversation());
    expect(find.byKey(const ValueKey('chat_typing')), findsNothing);
    live.push('/topic/tenant/t1/group/$g1/typing', {'groupId': g1, 'userId': 5, 'username': 'Ayşe', 'typing': true});
    await tester.pump();
    expect(find.text('Ayşe yazıyor…'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('chat_typing'))).getSemanticsData().flagsCollection.isLiveRegion,
      isFalse,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('chat_typing')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('chat_composer')), 'a' * 4000);
    await tester.pump();
    expect(find.byKey(const ValueKey('chat_length_limit')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('file: confirmation with name and size, "Yükleniyor: ad" while uploading', (tester) async {
    backend.ok('/chat/tenant/t1/files', 'assets/chat/rapor.pdf');
    await pump(tester, conversation(pick: () async => (path: 'pubspec.yaml', name: 'rapor.pdf', size: 2048)));
    await tester.tap(find.byKey(const ValueKey('chat_attach')));
    await tester.pumpAndSettle();
    expect(find.textContaining('rapor.pdf (2 KB)'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(backend.requestsTo('/files'), isEmpty);

    final gate = backend.hold('/chat/tenant/t1/files');
    await tester.tap(find.byKey(const ValueKey('chat_attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // dialog closed
    expect(find.text('Yükleniyor: rapor.pdf'), findsOneWidget);
    gate.complete();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('chat_uploading')), findsNothing);
    expect(backend.requestsTo('/files'), hasLength(1));
  });

  testWidgets('file over 10 MB is refused before any confirmation', (tester) async {
    await pump(tester, conversation(pick: () async => (path: 'x', name: 'buyuk.zip', size: chatMaxFileBytes + 1)));
    await tester.tap(find.byKey(const ValueKey('chat_attach')));
    await tester.pumpAndSettle();
    expect(find.text('Dosya 10 MB\'tan büyük olamaz.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('connection strip', () {
    testWidgets('short drops show nothing; after 2 s neutral text; after 10 s error color; "Şimdi dene" reconnects', (
      tester,
    ) async {
      await pump(tester, conversation());
      final banner = find.byKey(const ValueKey('chat_connection_banner'));
      live.link.drop();
      await tester.pump(const Duration(milliseconds: 1500));
      expect(banner, findsNothing);
      await tester.pump(const Duration(seconds: 1)); // backoff reconnect already happened (≈1 s)
      expect(live.realtime.connected, isTrue);
      expect(banner, findsNothing, reason: 'a ~1 s drop never shows the strip');

      live.autoConnect = false;
      live.link.drop();
      await tester.pump(const Duration(milliseconds: 2100));
      expect(banner, findsOneWidget);
      expect(find.text(ConnectionBanner.message), findsOneWidget);
      final scheme = appTheme.colorScheme;
      expect(tester.widget<Container>(banner).color, scheme.surface);
      await tester.pump(const Duration(seconds: 9));
      expect(tester.widget<Container>(banner).color, scheme.errorContainer);

      // The pending link fails; "Şimdi dene" opens the next one at once instead of waiting for the backoff.
      live.link.drop();
      await tester.pump();
      final before = live.links.length;
      await tester.tap(find.byKey(const ValueKey('chat_connection_retry')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(live.links.length, before + 1);
      live.link.connected();
      await tester.pump();
      expect(banner, findsNothing);
    });
  });

  testWidgets('members: invite note collapses to one line while the keyboard is open', (tester) async {
    await pump(tester, const SizedBox(), perms: ['chat:read', 'chat:manage']);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
          child: ChatMembersScreen(group: live.chat.groupById(g1)!),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(InfoNote), findsNothing);
    expect(find.textContaining('altındaki'), findsOneWidget);
  });

  testWidgets('chat list row shows the last message time', (tester) async {
    await pump(tester, const ChatScreen());
    live.push('/topic/tenant/t1/group/$g1', msg('n1', content: 'son', minute: 33));
    await tester.pump();
    final local = DateTime.utc(2026, 10, 14, 9, 33).toLocal();
    final hhmm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    expect(find.textContaining(hhmm), findsOneWidget);
  });
}
