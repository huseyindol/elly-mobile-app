import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/chat/chat_members_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

const g1 = '11111111-1111-4111-8111-111111111111';
const me = 7;
const _me = {'id': me, 'username': 'ben', 'firstName': 'Ben', 'lastName': 'Admin'};

Map<String, dynamic> member(int id, {String role = 'MEMBER', String first = 'Üye', String last = '', String? user}) => {
  'userId': id,
  'username': user ?? 'u$id',
  'firstName': first,
  'lastName': last,
  'role': role,
};

/// Members screen / invite / DM dialog rules that protect the group: no "Çıkar" on the own row, fail-closed when the
/// own identity is unknown, invite hierarchy hint per role, hostile names and ids.
void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late List<Map<String, dynamic>> members;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    members = [
      member(1, role: 'OWNER', first: 'Kurucu'),
      member(me, first: 'Ben'),
      member(5, first: 'Ayşe'),
      member(6),
    ];
    backend.ok('/chat/tenant/t1/groups', [
      {'id': g1, 'name': 'Ekip', 'type': 'GROUP', 'createdBy': 1, 'visibilityLevel': 1, 'tenantId': 't1'},
    ]);
    backend.routes['/chat/tenant/t1/groups/$g1/members'] = (_) => okData(members);
  });

  tearDown(() => live.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpMembers(
    WidgetTester tester, {
    List<String> perms = const ['chat:read', 'chat:manage'],
    List<String> roles = const ['ADMIN'],
    Map<String, dynamic>? profile = _me,
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await backend.signIn(auth, perms, roles: roles, me: profile);
      live.realtime.start();
      await live.chat.open(myUserId: auth.userId, myLevel: auth.roleLevel);
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
          home: ChatMembersScreen(group: live.chat.groupById(g1)!),
        ),
      ),
    );
    await settle(tester);
  }

  Finder remove(int id) => find.byKey(ValueKey('chat_remove_$id'));

  group('"Gruptan çıkar"', () {
    testWidgets('chat:manage + known identity: others yes; the owner row and the OWN row never', (tester) async {
      await pumpMembers(tester);
      expect(remove(5), findsOneWidget);
      expect(remove(6), findsOneWidget);
      expect(remove(1), findsNothing, reason: 'owner');
      expect(remove(me), findsNothing, reason: 'own row (would lock the user out)');
    });

    testWidgets('a SUPER_ADMIN does not get it on the own row either', (tester) async {
      await pumpMembers(tester, roles: ['SUPER_ADMIN']);
      expect(remove(me), findsNothing);
      expect(remove(5), findsOneWidget);
    });

    testWidgets('own identity unknown (no profile, no roles): nobody is removable — fail-closed', (tester) async {
      await pumpMembers(tester, roles: const [], profile: null);
      expect(auth.identityKnown, isFalse);
      for (final id in [1, me, 5, 6]) {
        expect(remove(id), findsNothing, reason: 'user $id');
      }
    });

    testWidgets('without chat:manage there is no remove button and no invite panel at all', (tester) async {
      await pumpMembers(tester, perms: ['chat:read']);
      for (final id in [1, me, 5, 6]) {
        expect(remove(id), findsNothing);
      }
      expect(find.byKey(const ValueKey('chat_invite_input')), findsNothing);
    });

    testWidgets('the confirmation shows the member name as plain text (bidi revealed, HTML literal)', (tester) async {
      members = [member(1, role: 'OWNER'), member(me), member(5, first: '<b>Ali</b>\u202E', last: '&amp;')];
      await pumpMembers(tester);
      expect(find.text('<b>Ali</b>⟨U+202E⟩ &'), findsOneWidget);
      await tester.tap(remove(5));
      await tester.pumpAndSettle();
      expect(find.textContaining('"<b>Ali</b>⟨U+202E⟩ &" gruptan çıkarılacak'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(backend.requestsTo('/members/5'), isEmpty);
    });

    testWidgets('a refused removal (403) keeps the member and shows the error', (tester) async {
      backend.routes['/chat/tenant/t1/groups/$g1/members/5'] = (_) =>
          http.Response('{"message":"You do not have access to this group"}', 403);
      await pumpMembers(tester);
      await tester.tap(remove(5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await settle(tester);
      expect(backend.requestsTo('/members/5').single.method, 'DELETE');
      expect(find.byKey(const ValueKey('chat_member_5')), findsOneWidget);
      expect(find.text('Bu gruba erişiminiz yok.'), findsOneWidget);
    });
  });

  group('invite hierarchy', () {
    for (final (roles, expectsAll) in [
      (<String>['SUPER_ADMIN'], true),
      (<String>['ADMIN'], false),
      (<String>['EDITOR'], false),
      (<String>['VIEWER'], false),
      (<String>['TENANT'], false),
      (<String>['SOMETHING_NEW'], false),
      (<String>[], false),
    ]) {
      testWidgets('roles $roles: the hint ${expectsAll ? 'says "everyone"' : 'is limited to own level and below'}', (
        tester,
      ) async {
        await pumpMembers(tester, roles: roles, profile: roles.isEmpty ? null : _me);
        expect(find.textContaining('herkesi'), expectsAll ? findsOneWidget : findsNothing);
        expect(find.textContaining('altındaki'), expectsAll ? findsNothing : findsOneWidget);
      });
    }

    Future<void> invite(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const ValueKey('chat_invite_input')), text);
      await tester.tap(find.byKey(const ValueKey('chat_invite_submit')));
      await settle(tester);
    }

    for (final bad in [
      '',
      '   ',
      '0',
      '-1',
      '+',
      '12.5',
      '1e3',
      '１２',
      'abc',
      'a@',
      '@b.co',
      'a b@c.de',
      'a@b',
      '99999999999999999999',
    ]) {
      testWidgets('invalid input ${bad.isEmpty ? '(empty)' : '"$bad"'} never reaches the network', (tester) async {
        await pumpMembers(tester);
        await invite(tester, bad);
        expect(backend.requests.where((r) => r.method == 'POST' && r.url.path.contains('/members')), isEmpty);
        expect(find.byType(ChatMembersScreen), findsOneWidget);
        expect(find.text('Üyeler (4)'), findsOneWidget);
      });
    }

    for (final (label, status, message, shown) in [
      (
        'above own level',
        403,
        'You can only invite users with your role level or lower',
        'Yalnız kendi rol seviyenizdeki ve altındaki kullanıcıları davet edebilirsiniz.',
      ),
      ('already a member', 409, 'User is already a member of this group', 'Kullanıcı zaten bu grubun üyesi.'),
      ('rate limited', 429, 'Rate limit exceeded', 'Çok hızlı mesaj gönderiyorsunuz; biraz bekleyin.'),
      ('other error', 500, 'Beklenmeyen hata', 'Beklenmeyen hata'),
    ]) {
      testWidgets('by id, backend refusal ($label): shown in Turkish, member list unchanged, input kept', (
        tester,
      ) async {
        backend.routes['/chat/tenant/t1/groups/$g1/members/42'] = (_) =>
            http.Response('{"message":"$message"}', status);
        await pumpMembers(tester);
        await invite(tester, '42');
        expect(find.text(shown), findsOneWidget);
        expect(find.text('Üyeler (4)'), findsOneWidget);
        expect(tester.widget<TextFormField>(find.byKey(const ValueKey('chat_invite_input'))).controller!.text, '42');
      });
    }

    testWidgets('by e-mail the address is trimmed; unknown user → Turkish "not found"', (tester) async {
      backend.routes['/chat/tenant/t1/groups/$g1/members/by-email'] = (_) =>
          http.Response('{"message":"User not found with email : x@y.zz"}', 404);
      await pumpMembers(tester);
      await invite(tester, '  x@y.zz  ');
      expect(find.text('Bu e-postayla kayıtlı kullanıcı bulunamadı.'), findsOneWidget);
      expect(backend.requestsTo('/members/by-email').single.body, contains('"x@y.zz"'));
    });
  });

  group('direct message dialog', () {
    Future<void> openDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await backend.signIn(auth, ['chat:read'], roles: const ['ADMIN'], me: _me);
        live.realtime.start();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ...live.providers,
          ],
          child: MaterialApp(theme: appTheme, home: const ChatScreen()),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('chat_dm_button')));
      await tester.pumpAndSettle();
    }

    for (final bad in ['0', '00', '99999999999999999999']) {
      testWidgets('user id "$bad" is refused before any request', (tester) async {
        await openDialog(tester);
        await tester.enterText(find.byKey(const ValueKey('chat_dm_user_id')), bad);
        await tester.tap(find.byKey(const ValueKey('chat_dm_submit')));
        await tester.pump();
        expect(find.text('Geçerli bir kullanıcı ID girin'), findsOneWidget);
        expect(backend.requests.where((r) => r.url.path.contains('/chat/dm')), isEmpty);
      });
    }

    testWidgets('only ASCII digits can be typed: "1a-2/३" becomes "12" and POSTs /chat/dm/12 (never a path piece)', (
      tester,
    ) async {
      backend.routes['/chat/dm/12'] = (_) => http.Response('{"message":"User not found"}', 404);
      await openDialog(tester);
      await tester.enterText(find.byKey(const ValueKey('chat_dm_user_id')), '1a-2/३');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('chat_dm_user_id'))).controller!.text, '12');
      await tester.tap(find.byKey(const ValueKey('chat_dm_submit')));
      await settle(tester);
      expect(backend.requestsTo('/chat/dm/12').single.method, 'POST');
      expect(find.text('User not found'), findsOneWidget, reason: 'dialog stays open with the backend text');
    });
  });
}
