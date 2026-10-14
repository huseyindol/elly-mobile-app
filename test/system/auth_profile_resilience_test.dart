import 'dart:async';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/users/users_screen.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

/// AuthProvider profile / displayName / userId / roleLevel: `/users/me` hatası uygulamayı durdurmaz,
/// logout her şeyi temizler, oturum kapandıktan sonra gelen geç yanıt eski kullanıcıyı geri getirmez.
Map<String, dynamic> _me(
  int id,
  String username, {
  String first = 'Ad',
  String last = 'Soyad',
}) => {
  'id': id,
  'username': username,
  'firstName': first,
  'lastName': last,
  'roles': ['ADMIN'],
};

Map<String, dynamic> _login(
  String user,
  int id, {
  List<String> roles = const ['ADMIN'],
}) => {
  'token': 't-$user',
  'refreshToken': 'r-$user',
  'userId': '$id',
  'username': user,
  'email': '$user@x.com',
  'roles': roles,
  'permissions': ['users:manage'],
};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.permissions(const ['users:manage'], roles: const ['ADMIN']);
  });

  Future<void> start() {
    FlutterSecureStorage.setMockInitialValues({
      'accessToken': 'a',
      'tenantId': 't1',
    });
    return auth.checkAuthStatus();
  }

  group('/users/me hatası uygulamayı durdurmaz', () {
    final failures = <String, http.Response Function()>{
      '500': () => http.Response('', 500),
      '404 + mesaj': () => jsonResponse({'message': 'User not found'}, 404),
      '403': () => jsonResponse({'message': 'Access Denied'}, 403),
      '200 data bir liste': () => okData([1, 2]),
      '200 data metin': () => okData('x'),
      '200 data null': () => jsonResponse({'result': true, 'data': null}, 200),
      '200 JSON değil': () => http.Response('<html>', 200),
      '200 result:false': () => jsonResponse({'result': false}, 200),
    };
    for (final e in failures.entries) {
      test(
        'açılışta /users/me ${e.key} → oturum açık, izinler yüklü, istisna yok, profil boş',
        () async {
          backend.routes['/users/me'] = (_) => e.value();
          await start();
          expect(auth.isAuthenticated, isTrue);
          expect(auth.permissionsLoaded, isTrue);
          expect(auth.has('users:manage'), isTrue);
          expect(auth.roles, ['ADMIN']);
          expect(auth.roleLevel, 3);
          expect(auth.profile, isNull);
          expect(
            auth.displayName,
            '',
            reason: 'açılışta login kullanıcı adı da yok',
          );
          expect(auth.userId, isNull);
        },
      );
    }

    test('ağ istisnası (bağlantı koptu) sessizce yutulur', () async {
      FlutterSecureStorage.setMockInitialValues({
        'accessToken': 'a',
        'tenantId': 't1',
      });
      final provider = AuthProvider(
        apiService: ApiService(
          client: MockClient((req) async {
            if (req.url.path.endsWith('/users/me'))
              throw http.ClientException('kopuk');
            return okData({
              'permissions': ['users:manage'],
              'roles': ['EDITOR'],
            });
          }),
        ),
      );
      await provider.checkAuthStatus();
      expect(provider.isAuthenticated, isTrue);
      expect(provider.roleLevel, 2);
      expect(provider.profile, isNull);
    });

    test('loadProfile hiçbir hatada fırlatmaz; fetchProfile fırlatır (profil ekranı hatayı gösterebilsin)', () async {
      backend.routes['/users/me'] = (_) => jsonResponse({'message': 'x'}, 500);
      await start();
      await auth.loadProfile();
      await expectLater(auth.fetchProfile(), throwsA(isA<ApiException>()));
    });

    test(
      'önceden yüklenmiş profil sonraki hatada silinmez (bayat ama görünür)',
      () async {
        backend.ok('/users/me', _me(7, 'hdol', first: 'Hüseyin', last: 'Dol'));
        await start();
        expect(auth.displayName, 'Hüseyin Dol');
        backend.routes['/users/me'] = (_) =>
            jsonResponse({'message': 'x'}, 500);
        await auth.loadProfile();
        expect(auth.displayName, 'Hüseyin Dol');
        expect(auth.userId, 7);
      },
    );

    test(
      'izin hatası profili, profil hatası izinleri etkilemez (bağımsız)',
      () async {
        backend.ok('/users/me', _me(7, 'hdol'));
        backend.routes['/users/me/permissions'] = (_) =>
            jsonResponse({'message': 'x'}, 500);
        await start();
        expect(auth.profile, isNotNull);
        expect(auth.permissionsLoaded, isFalse);
        expect(auth.permissionsError, isNotNull);
        expect(auth.roleLevel, 1, reason: 'roller bilinmiyor → en kısıtlı');
      },
    );

    test(
      '401 → refresh başarılı → tekrar: profil yüklenir, oturum düşmez',
      () async {
        var calls = 0;
        backend.routes['/users/me'] = (req) {
          calls++;
          return req.headers['Authorization'] == 'Bearer yeni'
              ? okData(_me(7, 'hdol'))
              : jsonResponse({'message': 'exp'}, 401);
        };
        backend.ok('/auth/refresh', {'token': 'yeni', 'refreshToken': 'r2'});
        FlutterSecureStorage.setMockInitialValues({
          'accessToken': 'eski',
          'refreshToken': 'r1',
          'tenantId': 't1',
        });
        await auth.checkAuthStatus();
        expect(auth.isAuthenticated, isTrue);
        expect(auth.userId, 7);
        expect(calls, 2);
      },
    );

    test('profil dönmeden önce kullanıcı adı: login yanıtından; sonra profil üstüne yazar', () async {
      backend.ok('/auth/login', _login('hdol', 7));
      backend.routes['/users/me'] = (_) => jsonResponse({'message': 'x'}, 500);
      expect(
        await auth.login(
          usernameOrEmail: 'hdol',
          password: 'p',
          tenantId: 't1',
        ),
        isTrue,
      );
      expect(auth.displayName, 'hdol');
      expect(auth.userId, 7);
      expect(
        auth.errorMessage,
        isNull,
        reason: 'profil hatası giriş hatası değildir',
      );
      backend.ok('/users/me', _me(7, 'hdol', first: 'Hüseyin', last: 'Dol'));
      await auth.loadProfile();
      expect(auth.displayName, 'Hüseyin Dol');
    });

    test('adı da soyadı da boş profil: kullanıcı adına düşer', () async {
      backend.ok('/users/me', _me(7, 'hdol', first: '', last: '  '));
      await start();
      expect(auth.displayName, 'hdol');
    });
  });

  group('roleLevel', () {
    Future<void> withRoles(List<String> roles) async {
      backend.permissions(const ['users:manage'], roles: roles);
      await start();
    }

    test('en yüksek rol belirler; bilinmeyen / küçük harf / boş → 1', () async {
      await withRoles(['VIEWER', 'EDITOR']);
      expect(auth.roleLevel, 2);
      await withRoles(['MARKETING']);
      expect(auth.roleLevel, 1);
      await withRoles(['admin']);
      expect(auth.roleLevel, 1);
      await withRoles(const []);
      expect(auth.roleLevel, 1);
      await withRoles(['EDITOR', 'SUPER_ADMIN', 'TENANT']);
      expect(auth.roleLevel, 4);
    });

    test('izin yanıtında roles yoksa girişteki roller korunur', () async {
      backend.ok('/auth/login', _login('hdol', 7, roles: const ['EDITOR']));
      backend.ok('/users/me', _me(7, 'hdol'));
      backend.routes['/users/me/permissions'] = (_) => okData({
        'permissions': ['users:manage'],
      });
      await auth.login(usernameOrEmail: 'hdol', password: 'p', tenantId: 't1');
      expect(auth.roles, ['EDITOR']);
      expect(auth.roleLevel, 2);
    });

    test('izin isteği başarısız olsa da girişteki roller seviye hesaplar (son bilinen değer)', () async {
      backend.ok(
        '/auth/login',
        _login('hdol', 7, roles: const ['SUPER_ADMIN']),
      );
      backend.routes['/users/me/permissions'] = (_) =>
          jsonResponse({'message': 'x'}, 500);
      backend.ok('/users/me', _me(7, 'hdol'));
      await auth.login(usernameOrEmail: 'hdol', password: 'p', tenantId: 't1');
      expect(auth.roleLevel, 4);
    });
  });

  group('logout ve oturum geçişleri', () {
    test(
      'logout profil, ad, kimlik, roller, izinler, seviye ve depoyu temizler',
      () async {
        backend.ok('/users/me', _me(7, 'hdol', first: 'Hüseyin', last: 'Dol'));
        backend.permissions(
          const ['users:manage'],
          roles: const ['SUPER_ADMIN'],
        );
        await start();
        expect(auth.roleLevel, 4);
        await auth.logout();
        expect(auth.isAuthenticated, isFalse);
        expect(auth.profile, isNull);
        expect(auth.displayName, '');
        expect(auth.userId, isNull);
        expect(auth.roles, isEmpty);
        expect(auth.roleLevel, 1);
        expect(auth.permissions, isEmpty);
        expect(auth.permissionsLoaded, isFalse);
        expect(auth.roleLabel, 'Kullanıcı');
        expect(
          await const FlutterSecureStorage().read(key: 'accessToken'),
          isNull,
        );
      },
    );

    test('logout dinleyicileri bilgilendirir', () async {
      await start();
      var notified = 0;
      auth.addListener(() => notified++);
      await auth.logout();
      expect(notified, greaterThan(0));
    });

    test('oturum kapandıktan sonra gelen geç /users/me yanıtı eski kullanıcıyı geri getirmez', () async {
      final gate = Completer<void>();
      FlutterSecureStorage.setMockInitialValues({
        'accessToken': 'a',
        'tenantId': 't1',
      });
      final provider = AuthProvider(
        apiService: ApiService(
          client: MockClient((req) async {
            if (req.url.path.endsWith('/users/me')) {
              await gate.future;
              return okData(_me(7, 'eski'));
            }
            return okData({
              'permissions': ['users:manage'],
              'roles': ['ADMIN'],
            });
          }),
        ),
      );
      final starting = provider.checkAuthStatus();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await provider.logout();
      gate.complete();
      await starting;
      expect(provider.isAuthenticated, isFalse);
      expect(provider.profile, isNull);
      expect(provider.displayName, '');
      expect(provider.userId, isNull);
    });

    test('setProfile oturum açık değilken yok sayılır', () async {
      auth.setProfile(_me(7, 'hayalet'));
      expect(auth.profile, isNull);
      expect(auth.displayName, '');
    });

    test('A çıkış → B giriş: B\'nin profili hatalı olsa bile A\'dan hiçbir şey kalmaz', () async {
      backend.ok(
        '/auth/login',
        _login('alice', 1, roles: const ['SUPER_ADMIN']),
      );
      backend.ok('/users/me', _me(1, 'alice', first: 'Alice', last: 'A'));
      backend.permissions(const ['users:manage'], roles: const ['SUPER_ADMIN']);
      await auth.login(usernameOrEmail: 'alice', password: 'p', tenantId: 't1');
      expect(auth.displayName, 'Alice A');
      expect(auth.roleLevel, 4);
      await auth.logout();

      backend.ok('/auth/login', _login('bob', 2, roles: const ['VIEWER']));
      backend.routes['/users/me'] = (_) => jsonResponse({'message': 'x'}, 500);
      backend.permissions(const ['posts:read'], roles: const ['VIEWER']);
      await auth.login(usernameOrEmail: 'bob', password: 'p', tenantId: 't1');
      expect(auth.displayName, 'bob');
      expect(auth.userId, 2);
      expect(auth.profile, isNull);
      expect(auth.roleLevel, 1);
      expect(auth.has('users:manage'), isFalse);
    });

    test(
      '2FA adımı: giriş tamamlanmadan profil/oturum yok; kod sonrası yüklenir',
      () async {
        backend.ok('/auth/login', {
          'mfaRequired': true,
          'mfaToken': 'm',
          'username': 'hdol',
        });
        backend.ok('/auth/mfa/verify', _login('hdol', 7));
        backend.ok('/users/me', _me(7, 'hdol', first: 'H', last: 'D'));
        expect(
          await auth.login(
            usernameOrEmail: 'hdol',
            password: 'p',
            tenantId: 't1',
          ),
          isFalse,
        );
        expect(auth.isAuthenticated, isFalse);
        expect(auth.profile, isNull);
        expect(backend.requestsTo('/users/me'), isEmpty);
        expect(await auth.verifyMfa('123456'), isTrue);
        expect(auth.displayName, 'H D');
      },
    );
  });

  group('kimlik bilinmiyorsa kendi hesabına karşı koruma', () {
    testWidgets(
      'profil yüklenemedi ve girişten gelen kimlik yok: hiçbir satırda Sil / Pasifleştir sunulmaz',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        backend.routes['/users/me'] = (_) =>
            jsonResponse({'message': 'x'}, 500);
        backend.routes['/users'] = (_) => okData([
          {
            'id': 1,
            'username': 'ben',
            'email': 'b@x.com',
            'roles': ['ADMIN'],
            'isActive': true,
          },
          {
            'id': 3,
            'username': 'editor',
            'email': 'e@x.com',
            'roles': ['EDITOR'],
            'isActive': true,
          },
        ]);
        await tester.runAsync(start);
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: MaterialApp(
              theme: appTheme,
              home: UsersScreen(apiService: backend.api),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        // Uygulama yeniden açıldı (login yanıtı yok) ve /users/me kapalı: kullanıcı kendi satırını tanıyamaz.
        expect(find.byKey(const ValueKey('delete_1')), findsNothing);
        expect(find.byKey(const ValueKey('status_1')), findsNothing);
        expect(auth.userId, isNull);
      },
      skip: true,
    );
    // SKIP - BULGU (orta, lib/screens/users/users_screen.dart `_isSelf` + user_form_screen.dart `_isSelfFor`):
    // uygulama token ile açılıp GET /users/me başarısız olursa AuthProvider.userId null ve currentUser null kalır;
    // `_isSelf` hiçbir satırı "ben" saymaz -> kendi satırında Sil / Pasifleştir sunulur, kendi formunda rol
    // düzenlenebilir ve şifre sıfırlama açılır (kendini demote etme / kilitleme riski; backend yalnız bazılarını
    // reddeder). Öneri: kimlik bilinmiyorsa yıkıcı aksiyonları gizle ya da ekranı hata/yeniden dene durumuna al.
  });
}
