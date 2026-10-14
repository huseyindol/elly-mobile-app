import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/users/users_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _user(int id, String username, List<String> roles, {bool active = true}) => {
  'id': id,
  'username': username,
  'email': '$username@x.com',
  'firstName': 'Ad$id',
  'lastName': 'Soyad',
  'provider': 'local',
  'isActive': active,
  'roles': roles,
  'createdAt': '2026-01-02T10:00:00Z',
};

const _roles = [
  {'id': 1, 'name': 'SUPER_ADMIN', 'description': 'Tam yetki'},
  {'id': 2, 'name': 'ADMIN', 'description': 'Yönetici'},
  {'id': 3, 'name': 'EDITOR', 'description': 'Editör'},
  {'id': 4, 'name': 'VIEWER', 'description': 'Görüntüleyici'},
  {'id': 5, 'name': 'TENANT', 'description': 'Site kullanıcısı'},
];

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.routes['/users'] = (req) {
      if (req.method == 'POST') return okData({'id': 99, ...jsonDecode(req.body) as Map});
      return okData(
        req.url.queryParameters['audience'] == 'tenant'
            ? [
                _user(10, 'musteri', ['TENANT']),
              ]
            : [
                _user(1, 'ben', ['ADMIN']),
                _user(2, 'patron', ['SUPER_ADMIN']),
                _user(3, 'editor', ['EDITOR']),
                _user(4, 'pasif', ['VIEWER'], active: false),
              ],
      );
    };
    backend.ok('/roles', _roles);
    for (final id in [1, 2, 3, 4, 10]) {
      backend.routes['/users/$id'] = (req) => okData(
        req.method == 'PUT'
            ? {
                ..._user(id, 'u$id', const ['EDITOR']),
                ...jsonDecode(req.body) as Map,
              }
            : (id == 1 ? _user(1, 'ben', ['ADMIN']) : _user(id, 'editor', ['EDITOR'])),
      );
      backend.routes['/users/$id/status'] = (_) => okData(_user(id, 'u', const []));
      backend.routes['/roles/users/$id/roles'] = (_) => jsonResponse({'result': true, 'data': null}, 200);
    }
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpUsers(WidgetTester tester, {List<String> roles = const ['ADMIN']}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, ['users:manage'], roles: roles, me: _user(1, 'ben', roles)));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: appTheme,
          home: UsersScreen(apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));
  Iterable<http.Request> sent(String method, String path) =>
      backend.requests.where((r) => r.method == method && r.url.path.endsWith(path));

  group('list (panel tab)', () {
    testWidgets('own row: "Siz", edit only — no delete, no deactivate', (tester) async {
      await pumpUsers(tester);
      expect(find.descendant(of: key('user_1'), matching: find.text('Siz')), findsOneWidget);
      expect(key('edit_1'), findsOneWidget);
      expect(key('delete_1'), findsNothing);
      expect(key('status_1'), findsNothing);
    });

    testWidgets('ADMIN: a SUPER_ADMIN row is locked (no edit/status/delete), lower rows are manageable', (
      tester,
    ) async {
      await pumpUsers(tester);
      expect(key('user_locked_2'), findsOneWidget);
      for (final action in ['edit_2', 'status_2', 'delete_2']) {
        expect(key(action), findsNothing, reason: action);
      }
      for (final action in ['edit_3', 'status_3', 'delete_3']) {
        expect(key(action), findsOneWidget, reason: action);
      }
      expect(find.descendant(of: key('status_4'), matching: find.text('Aktifleştir')), findsOneWidget);
    });

    testWidgets('SUPER_ADMIN may manage another SUPER_ADMIN', (tester) async {
      await pumpUsers(tester, roles: ['SUPER_ADMIN']);
      expect(key('user_locked_2'), findsNothing);
      expect(key('delete_2'), findsOneWidget);
    });

    testWidgets('search filters by name / username / e-mail (Turkish fold)', (tester) async {
      await pumpUsers(tester);
      await tester.enterText(key('list_search_field'), 'EDİTOR');
      await tester.pumpAndSettle();
      expect(key('user_3'), findsOneWidget);
      expect(key('user_2'), findsNothing);
    });

    testWidgets('tenant tab: audience=tenant, no role badges', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('audience_tenant'));
      await settle(tester);
      expect(backend.requests.last.url.queryParameters['audience'], 'tenant');
      expect(key('user_10'), findsOneWidget);
      expect(find.descendant(of: key('user_10'), matching: find.text('TENANT')), findsNothing);
    });
  });

  group('destructive actions', () {
    testWidgets('delete needs the username typed, then DELETE /users/{id}', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('delete_3'));
      await tester.pumpAndSettle();
      final confirm = key('confirm_delete_button');
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
      await tester.enterText(key('confirm_dialog_text'), 'edito');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
      await tester.enterText(key('confirm_dialog_text'), 'editor');
      await tester.pump();
      await tester.tap(confirm);
      await settle(tester);
      expect(sent('DELETE', '/users/3'), hasLength(1));
      expect(find.text('Kullanıcı silindi'), findsOneWidget);
    });

    testWidgets('deactivate asks first; "Vazgeç" sends nothing, confirm → PATCH ?isActive=false', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('status_3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(sent('PATCH', '/users/3/status'), isEmpty);

      await tester.tap(key('status_3'));
      await tester.pumpAndSettle();
      await tester.tap(key('confirm_dialog_button'));
      await settle(tester);
      final req = sent('PATCH', '/users/3/status').single;
      expect(req.url.queryParameters['isActive'], 'false');
    });

    testWidgets('activate needs no confirmation', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('status_4'));
      await settle(tester);
      expect(sent('PATCH', '/users/4/status').single.url.queryParameters['isActive'], 'true');
    });

    testWidgets('backend refusal is shown in Turkish', (tester) async {
      backend.routes['/users/3'] = (_) => jsonResponse({'message': 'Access Denied'}, 403);
      await pumpUsers(tester);
      await tester.tap(key('delete_3'));
      await tester.pumpAndSettle();
      await tester.enterText(key('confirm_dialog_text'), 'editor');
      await tester.pump();
      await tester.tap(key('confirm_delete_button'));
      await settle(tester);
      expect(find.textContaining('yetkiniz yok'), findsOneWidget);
    });
  });

  group('form', () {
    Future<void> fill(WidgetTester tester, Map<String, String> values) async {
      for (final e in values.entries) {
        await tester.enterText(key('user_field_${e.key}'), e.value);
      }
      await tester.pump();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(key('crud_save_button'));
      await settle(tester);
    }

    testWidgets('ADMIN creates a panel user: roles up to ADMIN (no SUPER_ADMIN/TENANT), POST body', (tester) async {
      await pumpUsers(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);

      for (final r in ['ADMIN', 'EDITOR', 'VIEWER']) {
        expect(key('role_$r'), findsOneWidget, reason: r);
      }
      expect(key('role_SUPER_ADMIN'), findsNothing);
      expect(key('role_TENANT'), findsNothing);
      expect(find.textContaining('Rol seçilmezse ADMIN'), findsOneWidget);

      await fill(tester, {'username': 'yeni', 'email': 'yeni@x.com', 'password': 'Gizli123', 'firstName': 'Yeni'});
      await tester.ensureVisible(key('role_EDITOR'));
      await tester.tap(key('role_EDITOR'));
      await tester.pump();
      await save(tester);

      final body = jsonDecode(sent('POST', '/users').single.body) as Map;
      expect(body, {
        'username': 'yeni',
        'email': 'yeni@x.com',
        'password': 'Gizli123',
        'firstName': 'Yeni',
        'lastName': '',
        'roleIds': [3],
        'audience': 'panel',
      });
      expect(find.byType(UsersScreen), findsOneWidget);
    });

    testWidgets('weak password and short username block the save (no request)', (tester) async {
      await pumpUsers(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await fill(tester, {'username': 'ab', 'email': 'yeni@x.com', 'password': 'gizli123'});
      await save(tester);
      expect(sent('POST', '/users'), isEmpty);
      expect(find.text('Kullanıcı adı 3-50 karakter olmalıdır'), findsOneWidget);
      expect(find.textContaining('büyük/küçük harf + rakam olmalıdır'), findsOneWidget);
    });

    testWidgets('EDITOR with users:manage must pick a role (cannot fall back to ADMIN); sees EDITOR/VIEWER only', (
      tester,
    ) async {
      await pumpUsers(tester, roles: ['EDITOR']);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(key('role_ADMIN'), findsNothing);
      expect(key('role_EDITOR'), findsOneWidget);
      expect(key('role_VIEWER'), findsOneWidget);

      await fill(tester, {'username': 'yeni', 'email': 'yeni@x.com', 'password': 'Gizli123'});
      await save(tester);
      expect(sent('POST', '/users'), isEmpty);
      expect(find.textContaining('En az bir rol seçin'), findsWidgets);
    });

    testWidgets('tenant create: no role section, audience=tenant, no roleIds', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('audience_tenant'));
      await settle(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(key('user_field_roles'), findsNothing);
      expect(sent('GET', '/roles'), isEmpty);
      await fill(tester, {'username': 'musteri2', 'email': 'm@x.com', 'password': 'Gizli123'});
      await save(tester);
      final body = jsonDecode(sent('POST', '/users').single.body) as Map;
      expect(body['audience'], 'tenant');
      expect(body.containsKey('roleIds'), isFalse);
    });

    testWidgets('edit: only changed parts are sent (fields → PUT /users/{id}; roles → PUT /roles/users/{id}/roles)', (
      tester,
    ) async {
      await pumpUsers(tester);
      await tester.tap(key('edit_3'));
      await settle(tester);
      expect(sent('GET', '/users/3'), hasLength(1), reason: 'edits from the detail record');
      expect(tester.widget<CheckboxListTile>(key('role_EDITOR')).value, isTrue);

      await fill(tester, {'firstName': 'Yeni Ad'});
      await save(tester);
      final put = jsonDecode(sent('PUT', '/users/3').single.body) as Map;
      expect(put['firstName'], 'Yeni Ad');
      expect(put.containsKey('newPassword'), isFalse);
      expect(sent('PUT', '/roles/users/3/roles'), isEmpty, reason: 'roles untouched');

      await tester.tap(key('edit_3'));
      await settle(tester);
      await tester.ensureVisible(key('role_VIEWER'));
      await tester.tap(key('role_VIEWER'));
      await tester.pump();
      await save(tester);
      expect(sent('PUT', '/users/3'), hasLength(1), reason: 'fields unchanged → no second PUT');
      expect(jsonDecode(sent('PUT', '/roles/users/3/roles').single.body), {
        'roleIds': [3, 4],
      });
    });

    testWidgets('edit: removing every role is rejected (backend @NotEmpty)', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('edit_3'));
      await settle(tester);
      await tester.ensureVisible(key('role_EDITOR'));
      await tester.tap(key('role_EDITOR'));
      await tester.pump();
      await save(tester);
      expect(sent('PUT', '/roles/users/3/roles'), isEmpty);
      expect(find.text('En az bir rol seçin'), findsOneWidget);
    });

    testWidgets('edit: a filled new password is sent as an admin reset', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('edit_3'));
      await settle(tester);
      await fill(tester, {'password': 'Sifirla99'});
      await save(tester);
      expect((jsonDecode(sent('PUT', '/users/3').single.body) as Map)['newPassword'], 'Sifirla99');
    });

    testWidgets('own account: no password reset, roles read-only (cannot demote yourself)', (tester) async {
      await pumpUsers(tester);
      await tester.tap(key('edit_1'));
      await settle(tester);
      expect(key('user_field_password'), findsNothing);
      expect(key('user_field_roles'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.textContaining('Kendi rollerinizi değiştiremezsiniz'), findsOneWidget);

      await fill(tester, {'lastName': 'Yeni'});
      await save(tester);
      expect(sent('PUT', '/users/1'), hasLength(1));
      expect(sent('PUT', '/roles/users/1/roles'), isEmpty);
    });

    testWidgets('hierarchy 403 on role assignment is explained; the form stays open', (tester) async {
      backend.routes['/roles/users/3/roles'] = (_) =>
          jsonResponse({'message': "Cannot assign role 'ADMIN': exceeds your own permission level"}, 403);
      await pumpUsers(tester);
      await tester.tap(key('edit_3'));
      await settle(tester);
      await tester.ensureVisible(key('role_ADMIN'));
      await tester.tap(key('role_ADMIN'));
      await tester.pump();
      await save(tester);
      expect(find.textContaining('"ADMIN" rolünü atayamazsınız'), findsOneWidget);
      expect(key('crud_save_button'), findsOneWidget, reason: 'form stays open');
    });
  });
}
