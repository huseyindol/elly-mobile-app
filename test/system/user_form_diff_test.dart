import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/users/user_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

/// Kullanıcı formu: yalnız değişen parçaların gönderilmesi ve atanamayan rolün KORUNMASI.
/// `PUT /roles/users/{id}/roles` kullanıcının TÜM rollerini değiştirir; istemci, çağıranın atayamadığı bir rolü
/// (SUPER_ADMIN, TENANT, ...) payload'dan düşürürse sessiz yetki kaybı olur. Bu dosya o payload'u doğrular.
const _allRoles = [
  {'id': 1, 'name': 'SUPER_ADMIN', 'description': ''},
  {'id': 2, 'name': 'ADMIN', 'description': ''},
  {'id': 3, 'name': 'EDITOR', 'description': ''},
  {'id': 4, 'name': 'VIEWER', 'description': ''},
  {'id': 5, 'name': 'TENANT', 'description': ''},
];

Map<String, dynamic> _user(
  int id,
  List<String> roles, {
  String username = 'hedef',
}) => {
  'id': id,
  'username': username,
  'email': '$username@x.com',
  'firstName': 'Ad',
  'lastName': 'Soyad',
  'provider': 'local',
  'isActive': true,
  'roles': roles,
};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late Map<String, dynamic> stored; // sunucudaki kayıt
  var userPutStatus = 200;
  var rolesPutStatus = 200;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    userPutStatus = 200;
    rolesPutStatus = 200;
    stored = _user(20, const ['EDITOR']);
    backend.ok('/roles', _allRoles);
    backend.routes['/users/20'] = (req) {
      if (req.method == 'PUT') {
        if (userPutStatus != 200)
          return jsonResponse({'message': 'Access Denied'}, userPutStatus);
        final body = jsonDecode(req.body) as Map;
        stored = {...stored, ...body}..remove('newPassword');
        return okData(stored);
      }
      return okData(stored);
    };
    backend.routes['/roles/users/20/roles'] = (_) => rolesPutStatus == 200
        ? jsonResponse({'result': true, 'data': null}, 200)
        : jsonResponse({
            'message': "Cannot assign role 'SUPER_ADMIN': exceeds your own permission level",
          }, 403);
    backend.routes['/users'] = (req) => okData({'id': 99});
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  /// [caller]: çağıranın rolleri; [target]: düzenlenen kullanıcının rolleri. `Form` bir launcher'dan push edilir.
  Future<void> openForm(
    WidgetTester tester, {
    required List<String> caller,
    List<String>? target,
    String audience = 'panel',
    int meId = 1,
    int targetId = 20,
    String targetUsername = 'hedef',
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (target != null)
      stored = _user(targetId, target, username: targetUsername);
    await tester.runAsync(
      () => backend.signIn(
        auth,
        const ['users:manage'],
        roles: caller,
        me: _user(meId, caller, username: 'ben'),
      ),
    );
    final row = target == null
        ? null
        : _user(targetId, target, username: targetUsername);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: appTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('open_form'),
                  onPressed: () => Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => UserFormScreen(
                        audience: audience,
                        user: row,
                        apiService: backend.api,
                      ),
                    ),
                  ),
                  child: const Text('aç'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open_form')));
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));
  Iterable<http.Request> sent(String method, String path) => backend.requests
      .where((r) => r.method == method && r.url.path.endsWith(path));
  List<int> rolePutIds() => [
    for (final id in (jsonDecode(
      sent('PUT', '/roles/users/20/roles').single.body,
    ) as Map)['roleIds'])
      id as int,
  ];
  bool checked(WidgetTester tester, String role) =>
      tester.widget<CheckboxListTile>(key('role_$role')).value == true;

  Future<void> toggle(WidgetTester tester, String role) async {
    await tester.ensureVisible(key('role_$role'));
    await tester.tap(key('role_$role'));
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(key('crud_save_button'));
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String field, String value) async {
    await tester.enterText(key('user_field_$field'), value);
    await tester.pump();
  }

  group('atanamayan rol payload\'dan düşmez (PUT /roles/users/{id}/roles)', () {
    testWidgets('ADMIN, SUPER_ADMIN kullanıcının formunu doğrudan açsa bile: SUPER_ADMIN kutusu yok, '
        'rol payload\'ı onu içerir', (tester) async {
      // Liste bu satırı kilitler; yine de form açılırsa (derin bağlantı, eski satır) istemci rolü düşürmemeli.
      await openForm(
        tester,
        caller: const ['ADMIN'],
        target: const ['SUPER_ADMIN'],
      );
      expect(
        key('role_SUPER_ADMIN'),
        findsNothing,
        reason: 'ADMIN SUPER_ADMIN atayamaz',
      );
      expect(key('role_ADMIN'), findsOneWidget);
      expect(
        [
          for (final r in ['ADMIN', 'EDITOR', 'VIEWER']) checked(tester, r),
        ],
        [false, false, false],
      );

      await toggle(tester, 'VIEWER');
      await save(tester);

      final ids = rolePutIds();
      expect(
        ids,
        contains(1),
        reason: 'SUPER_ADMIN (id 1) asla düşürücü payload ile gönderilmemeli',
      );
      expect(ids, [1, 4]);
    });

    testWidgets(
      'ADMIN o kullanıcıda hiçbir rolü değiştirmezse roller hiç gönderilmez',
      (tester) async {
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['SUPER_ADMIN'],
        );
        await type(tester, 'firstName', 'Yeni');
        await save(tester);
        expect(sent('PUT', '/users/20'), hasLength(1));
        expect(sent('PUT', '/roles/users/20/roles'), isEmpty);
      },
    );

    testWidgets(
      'SUPER_ADMIN\'i olan ADMIN kullanıcıda yalnız ADMIN\'i kaldırmak SUPER_ADMIN\'i korur',
      (tester) async {
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['SUPER_ADMIN', 'ADMIN'],
        );
        expect(checked(tester, 'ADMIN'), isTrue);
        await toggle(tester, 'ADMIN');
        await toggle(tester, 'EDITOR');
        await save(tester);
        expect(rolePutIds(), [1, 3]);
      },
    );

    // Çağıran x hedef: hedefin çağıranın atayamadığı her rolü payload'da kalmalı (rol değişikliği tetiklenirken).
    final cases = <(List<String>, List<String>, String, Set<int>)>[
      // (çağıran, hedef roller, değiştirilecek rol, atanamayan ve korunması gereken id'ler)
      (['ADMIN'], ['EDITOR', 'TENANT'], 'VIEWER', {5}),
      (['EDITOR'], ['VIEWER', 'TENANT'], 'EDITOR', {5}),
      (['SUPER_ADMIN'], ['ADMIN', 'TENANT'], 'VIEWER', {5}),
      (['ADMIN'], ['SUPER_ADMIN', 'TENANT', 'VIEWER'], 'EDITOR', {1, 5}),
      (['EDITOR', 'VIEWER'], ['ADMIN', 'VIEWER'], 'EDITOR', {2}),
    ];
    for (final (caller, target, change, keep) in cases) {
      testWidgets(
        'çağıran $caller, hedef $target, "$change" değişir → atanamayanlar $keep korunur',
        (tester) async {
          await openForm(tester, caller: caller, target: target);
          await toggle(tester, change);
          await save(tester);
          final ids = rolePutIds();
          expect(
            ids.toSet().containsAll(keep),
            isTrue,
            reason: 'gönderilen $ids, korunmalı $keep',
          );
          expect(ids, [...ids]..sort(), reason: 'sıralı gider');
        },
      );
    }

    testWidgets(
      'görünür rolü kaldırmak yalnız o rolü düşürür, diğerlerini korur',
      (tester) async {
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['ADMIN', 'VIEWER', 'TENANT'],
        );
        await toggle(tester, 'ADMIN');
        await save(tester);
        expect(rolePutIds(), [4, 5]);
      },
    );

    testWidgets(
      'görünür rollerin hepsi kalkınca, atanamayan tek rol kalsa bile liste boş sayılmaz',
      (tester) async {
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['EDITOR', 'TENANT'],
        );
        await toggle(tester, 'EDITOR');
        await save(tester);
        expect(rolePutIds(), [5]);
      },
    );
  });

  group('değişmeyen parça gönderilmez', () {
    testWidgets(
      'hiçbir şey değişmeden Kaydet: PUT yok, rol PUT yok, form kapanır',
      (tester) async {
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['EDITOR'],
        );
        await save(tester);
        expect(sent('PUT', '/users/20'), isEmpty);
        expect(sent('PUT', '/roles/users/20/roles'), isEmpty);
        expect(sent('POST', '/users'), isEmpty);
        expect(key('crud_save_button'), findsNothing, reason: 'form kapandı');
      },
    );

    testWidgets(
      'yalnızca boşluk farkı (kenar boşluğu) alan değişikliği sayılmaz',
      (tester) async {
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['EDITOR'],
        );
        await type(tester, 'firstName', '  Ad  ');
        await type(tester, 'email', ' hedef@x.com ');
        await save(tester);
        expect(sent('PUT', '/users/20'), isEmpty);
      },
    );

    testWidgets('yalnız roller değişti: kullanıcı PUT\'u yok, sadece rol PUT', (
      tester,
    ) async {
      await openForm(tester, caller: const ['ADMIN'], target: const ['EDITOR']);
      await toggle(tester, 'VIEWER');
      await save(tester);
      expect(sent('PUT', '/users/20'), isEmpty);
      expect(rolePutIds(), [3, 4]);
    });

    testWidgets(
      'yalnız alan değişti: rol PUT yok; değişmeyen username/e-posta kayıttaki değerle gider',
      (tester) async {
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['EDITOR'],
        );
        await type(tester, 'lastName', 'Yeni');
        await save(tester);
        final put = jsonDecode(sent('PUT', '/users/20').single.body) as Map;
        expect(put, {
          'username': 'hedef',
          'email': 'hedef@x.com',
          'firstName': 'Ad',
          'lastName': 'Yeni',
        });
        expect(sent('PUT', '/roles/users/20/roles'), isEmpty);
      },
    );

    testWidgets('rol işaretleyip geri alma değişiklik sayılmaz', (
      tester,
    ) async {
      await openForm(tester, caller: const ['ADMIN'], target: const ['EDITOR']);
      await toggle(tester, 'VIEWER');
      await toggle(tester, 'VIEWER');
      await save(tester);
      expect(sent('PUT', '/roles/users/20/roles'), isEmpty);
    });

    testWidgets(
      'alan PUT\'u başarılı, rol PUT\'u 403: tekrar denemede alanlar/şifre yeniden gönderilmez',
      (tester) async {
        rolesPutStatus = 403;
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['EDITOR'],
        );
        await type(tester, 'firstName', 'Yeni');
        await type(tester, 'password', 'Sifirla99');
        await toggle(tester, 'VIEWER');
        await save(tester);
        expect(sent('PUT', '/users/20'), hasLength(1));
        expect(
          (jsonDecode(sent('PUT', '/users/20').single.body)
              as Map)['newPassword'],
          'Sifirla99',
        );
        expect(sent('PUT', '/roles/users/20/roles'), hasLength(1));
        expect(
          key('crud_save_button'),
          findsOneWidget,
          reason: 'form açık kalır',
        );

        rolesPutStatus = 200;
        await save(tester);
        expect(
          sent('PUT', '/users/20'),
          hasLength(1),
          reason: 'şifre sıfırlaması ikinci kez gitmemeli',
        );
        expect(sent('PUT', '/roles/users/20/roles'), hasLength(2));
      },
    );

    testWidgets(
      'rol PUT\'u 403 sonrası aynı seçimle tekrar: aynı payload (atanamayan rol yine korunur)',
      (tester) async {
        rolesPutStatus = 403;
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['SUPER_ADMIN'],
        );
        await toggle(tester, 'VIEWER');
        await save(tester);
        await save(tester);
        final bodies = [
          for (final r in sent('PUT', '/roles/users/20/roles'))
            jsonDecode(r.body),
        ];
        expect(bodies, hasLength(2));
        expect(bodies.every((b) => (b['roleIds'] as List).contains(1)), isTrue);
      },
    );
  });

  group('kendi hesabı', () {
    testWidgets(
      'kendi formu: rol/şifre alanı yok; kaydetmek yalnız alanları gönderir (newPassword ve rol yok)',
      (tester) async {
        backend.routes['/users/1'] = (req) {
          final me = _user(1, const ['ADMIN'], username: 'ben');
          return okData(
            req.method == 'PUT' ? {...me, ...jsonDecode(req.body) as Map} : me,
          );
        };
        await openForm(
          tester,
          caller: const ['ADMIN'],
          target: const ['ADMIN'],
          targetId: 1,
          targetUsername: 'ben',
        );
        expect(key('user_field_password'), findsNothing);
        expect(
          find.byType(CheckboxListTile),
          findsNothing,
          reason: 'kendi rolleri salt okunur',
        );
        await type(tester, 'firstName', 'Yeni');
        await save(tester);
        final put = jsonDecode(sent('PUT', '/users/1').single.body) as Map;
        expect(put.containsKey('newPassword'), isFalse);
        expect(sent('PUT', '/roles/users/1/roles'), isEmpty);
      },
    );

    testWidgets(
      'kendi hesabı: rol listesinde olmayan (atanamayan) rolleri de olsa rol PUT\'u hiç gitmez',
      (tester) async {
        // Süper admin kendi formunu açar: rol alanı salt okunur, hiçbir koşulda roller değiştirilmez.
        backend.routes['/users/1'] = (req) {
          final me = _user(1, const ['SUPER_ADMIN', 'ADMIN'], username: 'ben');
          return okData(
            req.method == 'PUT' ? {...me, ...jsonDecode(req.body) as Map} : me,
          );
        };
        await openForm(
          tester,
          caller: const ['SUPER_ADMIN', 'ADMIN'],
          target: const ['SUPER_ADMIN', 'ADMIN'],
          targetId: 1,
          targetUsername: 'ben',
        );
        await type(tester, 'lastName', 'X');
        await save(tester);
        expect(sent('PUT', '/roles/users/1/roles'), isEmpty);
      },
    );
  });

  group('oluşturma', () {
    testWidgets(
      'SUPER_ADMIN panel kullanıcısı: seçilen roller sıralı roleIds; TENANT kutusu yok',
      (tester) async {
        await openForm(tester, caller: const ['SUPER_ADMIN']);
        for (final r in ['SUPER_ADMIN', 'ADMIN', 'EDITOR', 'VIEWER']) {
          expect(key('role_$r'), findsOneWidget, reason: r);
        }
        expect(key('role_TENANT'), findsNothing);
        await type(tester, 'username', 'yeni');
        await type(tester, 'email', 'yeni@x.com');
        await type(tester, 'password', 'Gizli123');
        await toggle(tester, 'VIEWER');
        await toggle(tester, 'ADMIN');
        await save(tester);
        expect(
          (jsonDecode(sent('POST', '/users').single.body) as Map)['roleIds'],
          [2, 4],
        );
      },
    );

    testWidgets(
      // Karar (faz 4 düzeltme): boş rol listesi backend'de sessizce ADMIN atar → mobil en az bir rol ister.
      'rol seçmeyen ADMIN de kaydedemez: örtük ADMIN ataması yok (en az bir rol zorunlu)',
      (tester) async {
        await openForm(tester, caller: const ['ADMIN']);
        await type(tester, 'username', 'yeni');
        await type(tester, 'email', 'yeni@x.com');
        await type(tester, 'password', 'Gizli123');
        await save(tester);
        expect(sent('POST', '/users'), isEmpty);
        expect(find.textContaining('En az bir rol seçin'), findsWidgets);
      },
    );

    testWidgets(
      'rolü olmayan/bilinmeyen çağıran (seviye 1): ADMIN varsayılanı yok, rol seçmeden kaydedemez',
      (tester) async {
        await openForm(tester, caller: const ['MARKETING']);
        expect(key('role_VIEWER'), findsOneWidget);
        expect(key('role_EDITOR'), findsNothing);
        await type(tester, 'username', 'yeni');
        await type(tester, 'email', 'yeni@x.com');
        await type(tester, 'password', 'Gizli123');
        await save(tester);
        expect(sent('POST', '/users'), isEmpty);
        expect(find.textContaining('En az bir rol seçin'), findsWidgets);
      },
    );
  });
}
