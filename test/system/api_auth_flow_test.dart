import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `ApiService.isPublicAuthEndpoint` ve 401 akışı: oturumsuz `/auth/*` uçları Authorization almaz ve 401'de
/// refresh denemez; oturum isteyen 2FA/şifre uçları Bearer alır, 401'de TEK refresh + TEK tekrar yapılır, hâlâ
/// 401 ise backend mesajı gösterilir ve oturum DÜŞMEZ; refresh gerçekten başarısızsa oturum biter.
void main() {
  late List<http.Request> sent;
  late http.Response Function(http.Request req) respond;
  late ApiService api;
  late int expired;

  http.Response json(Object body, int status) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status);
  Iterable<http.Request> to(String suffix) =>
      sent.where((r) => r.url.path.endsWith(suffix));
  String? auth(http.Request r) => r.headers['Authorization'];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'accessToken': 'a1',
      'refreshToken': 'r1',
      'tenantId': 't1',
    });
    sent = [];
    expired = 0;
    ApiService.onSessionExpired = () => expired++;
    respond = (_) => http.Response('', 404);
    api = ApiService(
      client: MockClient((req) async {
        sent.add(req);
        return respond(req);
      }),
    );
  });
  tearDown(() => ApiService.onSessionExpired = null);

  group('isPublicAuthEndpoint', () {
    test('oturumsuz uçlar: login, refresh, 2FA giriş adımı', () {
      for (final e in ['/auth/login', '/auth/refresh', '/auth/mfa/verify']) {
        expect(ApiService.isPublicAuthEndpoint(e), isTrue, reason: e);
      }
    });

    test('JWT isteyen 2FA yönetimi ve /auth dışı her uç oturumludur', () {
      for (final e in [
        '/auth/mfa/status',
        '/auth/mfa/setup',
        '/auth/mfa/setup/verify',
        '/auth/mfa/disable',
        '/auth/mfa/',
        '/users/me',
        '/users/me/password',
        '/users/auth/login',
        '/authors',
        '/auth',
        'auth/login',
        '',
      ]) {
        expect(ApiService.isPublicAuthEndpoint(e), isFalse, reason: '"$e"');
      }
    });

    test('kenar: yalnız TAM "/auth/mfa/verify" oturumsuz; eğik çizgi, büyük harf, ek parça ya da başka kök oturumlu', () {
      for (final e in [
        '/auth/mfa/verify/',
        '/auth/mfa/Verify',
        '/auth/mfa/verify/extra',
        '/auth/mfa/setup/verify',
        '/auth/mfa/disable/verify',
        '/AUTH/login',
      ]) {
        expect(ApiService.isPublicAuthEndpoint(e), isFalse, reason: e);
      }
    });
  });

  group('Authorization başlığı', () {
    test(
      '/auth/mfa/setup (GET) ve setup/verify, disable (POST) Bearer alır',
      () async {
        respond = (_) => json({'result': true, 'data': {}}, 200);
        await api.get('/auth/mfa/setup');
        await api.get('/auth/mfa/status');
        await api.post('/auth/mfa/setup/verify', {'code': '123456'});
        await api.post('/auth/mfa/disable', {'password': 'x'});
        expect(sent, hasLength(4));
        for (final r in sent) {
          expect(auth(r), 'Bearer a1', reason: r.url.path);
          expect(r.headers['X-Tenant-Id'], 't1');
        }
      },
    );

    test('/auth/login, /auth/refresh, /auth/mfa/verify Bearer almaz (bayat token backend\'i 401\'letmesin)', () async {
      respond = (_) => json({'result': true, 'data': {}}, 200);
      await api.post('/auth/login', {'usernameOrEmail': 'u'}, tenantId: 'tx');
      await api.post('/auth/refresh', {'refreshToken': 'r1'});
      await api.post('/auth/mfa/verify', {
        'mfaToken': 'm',
        'code': '1',
      }, tenantId: 'tx');
      expect(sent, hasLength(3));
      for (final r in sent) {
        expect(
          r.headers.containsKey('Authorization'),
          isFalse,
          reason: r.url.path,
        );
      }
      expect(
        sent.first.headers['X-Tenant-Id'],
        'tx',
        reason: 'tenant başlığı yine gider',
      );
    });

    test(
      'depoda token yoksa oturumlu uçta da Authorization başlığı eklenmez',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        respond = (_) => json({'result': true, 'data': {}}, 200);
        await api.post('/auth/login', {});
        await api.get('/auth/mfa/status');
        expect(sent.map((r) => r.headers.containsKey('Authorization')), [
          false,
          false,
        ]);
      },
    );

    test('boş token Bearer olarak gönderilmez', () async {
      FlutterSecureStorage.setMockInitialValues({'accessToken': ''});
      respond = (_) => json({'result': true, 'data': {}}, 200);
      await api.get('/auth/mfa/setup');
      expect(sent.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'PUT / DELETE / PATCH / multipart oturumlu uçlarda her zaman Bearer alır',
      () async {
        respond = (_) => json({'result': true, 'data': {}}, 200);
        await api.put('/users/me/password', {
          'currentPassword': 'a',
          'newPassword': 'b',
        });
        await api.delete('/users/5');
        await api.patch('/users/5/status?isActive=false');
        await api.multipart('POST', '/assets', fields: {'k': 'v'});
        expect(sent.map(auth), everyElement('Bearer a1'));
      },
    );
  });

  group('yanlış kod / şifre (401): oturum düşmez', () {
    http.Response refreshOk(http.Request req) => json({
      'result': true,
      'data': {'token': 'a2', 'refreshToken': 'r2'},
    }, 200);

    for (final (name, method, path, message)
        in <(String, String, String, String)>[
          (
            'yanlış 2FA kurulum kodu',
            'POST',
            '/auth/mfa/setup/verify',
            'Geçersiz doğrulama kodu.',
          ),
          (
            'yanlış 2FA kapatma şifresi',
            'POST',
            '/auth/mfa/disable',
            'Şifre hatalı.',
          ),
          (
            'yanlış mevcut şifre (PUT)',
            'PUT',
            '/users/me/password',
            'Mevcut şifre hatalı.',
          ),
        ]) {
      test(
        '$name: 1 refresh + 1 tekrar → backend mesajı, onSessionExpired çağrılmaz, depo korunur',
        () async {
          respond = (req) {
            if (req.url.path.endsWith('/auth/refresh')) return refreshOk(req);
            return json({'message': message}, 401);
          };
          final call = method == 'PUT'
              ? api.put(path, {'x': 1})
              : api.post(path, {'x': 1});
          await expectLater(
            call,
            throwsA(
              isA<ApiException>()
                  .having((e) => e.message, 'message', message)
                  .having((e) => e.statusCode, 'status', 401),
            ),
          );
          expect(to(path), hasLength(2), reason: 'tek tekrar, döngü yok');
          expect(to('/auth/refresh'), hasLength(1));
          expect(expired, 0, reason: 'oturum düşmemeli');
          expect(
            auth(to(path).last),
            'Bearer a2',
            reason: 'tekrar yenilenmiş token ile',
          );
          final storage = const FlutterSecureStorage();
          expect(await storage.read(key: 'accessToken'), 'a2');
          expect(
            await storage.read(key: 'refreshToken'),
            'r2',
            reason: 'refresh token döner',
          );
          expect(await storage.read(key: 'tenantId'), 't1');
        },
      );
    }

    test('ardışık yanlış denemeler: her refresh bir önceki turun yeni refresh token\'ını kullanır', () async {
      var n = 1;
      respond = (req) {
        if (req.url.path.endsWith('/auth/refresh')) {
          n++;
          return json({
            'result': true,
            'data': {'token': 'a$n', 'refreshToken': 'r$n'},
          }, 200);
        }
        return json({'message': 'Geçersiz doğrulama kodu.'}, 401);
      };
      for (var i = 0; i < 3; i++) {
        await expectLater(
          api.post('/auth/mfa/setup/verify', {'code': '000000'}),
          throwsA(isA<ApiException>()),
        );
      }
      final refreshBodies = [
        for (final r in to('/auth/refresh'))
          (jsonDecode(r.body) as Map)['refreshToken'],
      ];
      expect(refreshBodies, ['r1', 'r2', 'r3']);
      expect(expired, 0);
    });

    test(
      'refresh isteği: Bearer yok, gövdede refreshToken, tenant başlığı var',
      () async {
        respond = (req) => req.url.path.endsWith('/auth/refresh')
            ? refreshOk(req)
            : json({'message': 'x'}, 401);
        await expectLater(
          api.post('/auth/mfa/disable', {'password': 'p'}),
          throwsA(isA<ApiException>()),
        );
        final refresh = to('/auth/refresh').single;
        expect(refresh.headers.containsKey('Authorization'), isFalse);
        expect(jsonDecode(refresh.body), {'refreshToken': 'r1'});
        expect(refresh.headers['X-Tenant-Id'], 't1');
      },
    );

    test('refresh yeni refreshToken dönmezse eskisi saklı kalır', () async {
      respond = (req) => req.url.path.endsWith('/auth/refresh')
          ? json({
              'result': true,
              'data': {'token': 'a2'},
            }, 200)
          : (auth(req) == 'Bearer a2'
                ? json({'result': true, 'data': 'ok'}, 200)
                : json({'message': 'süre'}, 401));
      expect(await api.get('/users/me'), 'ok');
      expect(
        await const FlutterSecureStorage().read(key: 'refreshToken'),
        'r1',
      );
    });

    test('eşzamanlı iki 401 TEK refresh paylaşır; ikisi de yenilenmiş token ile tekrarlanır', () async {
      respond = (req) {
        if (req.url.path.endsWith('/auth/refresh')) return refreshOk(req);
        return auth(req) == 'Bearer a2'
            ? json({'result': true, 'data': req.url.path}, 200)
            : http.Response('', 401);
      };
      final results = await Future.wait([
        api.get('/x'),
        api.get('/y'),
        api.get('/auth/mfa/status'),
      ]);
      expect(
        [for (final r in results) '$r'.split('/').last],
        ['x', 'y', 'status'],
      );
      expect(to('/auth/refresh'), hasLength(1));
      expect(expired, 0);
    });
  });

  group('gerçek oturum bitişi: refresh başarısız → onSessionExpired', () {
    Matcher sessionEnded() => throwsA(
      isA<ApiException>()
          .having((e) => e.statusCode, 'status', 401)
          .having((e) => e.message, 'message', contains('Oturum süresi doldu')),
    );

    final failures = <String, http.Response Function()>{
      'refresh 401': () => json({'message': 'Invalid refresh token'}, 401),
      'refresh 403': () => json({'message': 'x'}, 403),
      'refresh 500': () => http.Response('', 500),
      'refresh 200 ama result:false (token yok)': () =>
          json({'result': false}, 200),
      'refresh 200 token boş': () => json({
        'result': true,
        'data': {'token': ''},
      }, 200),
      'refresh 200 data null': () => json({'result': true, 'data': null}, 200),
      'refresh 200 JSON değil': () => http.Response('<html>', 200),
    };
    for (final e in failures.entries) {
      test(
        'oturumlu uç (/auth/mfa/disable) 401 + ${e.key} → oturum biter, tekrar yok',
        () async {
          respond = (req) => req.url.path.endsWith('/auth/refresh')
              ? e.value()
              : json({'message': 'x'}, 401);
          await expectLater(
            api.post('/auth/mfa/disable', {'password': 'p'}),
            sessionEnded(),
          );
          expect(expired, 1);
          expect(
            to('/auth/mfa/disable'),
            hasLength(1),
            reason: 'refresh yokken tekrar denenmez',
          );
          expect(to('/auth/refresh'), hasLength(1));
        },
      );
    }

    test(
      'depoda refreshToken yok → refresh çağrısı bile yapılmadan oturum biter',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'accessToken': 'a1',
          'tenantId': 't1',
        });
        respond = (_) => http.Response('', 401);
        await expectLater(api.get('/users/me'), sessionEnded());
        expect(expired, 1);
        expect(to('/auth/refresh'), isEmpty);
      },
    );

    test(
      'refresh ağ hatası (istisna) da oturumu bitirir; istisna dışarı sızmaz',
      () async {
        final failing = ApiService(
          client: MockClient((req) async {
            sent.add(req);
            if (req.url.path.endsWith('/auth/refresh'))
              throw http.ClientException('bağlantı koptu');
            return http.Response('', 401);
          }),
        );
        await expectLater(failing.get('/users/me'), sessionEnded());
        expect(expired, 1);
      },
    );

    test('yenilenen token ile tekrar da 401 olursa: tek tekrar, döngü yok, oturum düşmez, backend mesajı', () async {
      respond = (req) => req.url.path.endsWith('/auth/refresh')
          ? json({
              'result': true,
              'data': {'token': 'a2', 'refreshToken': 'r2'},
            }, 200)
          : json({'message': 'Bu kaynak için yetkisiz'}, 401);
      await expectLater(
        api.get('/users/me'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Bu kaynak için yetkisiz',
          ),
        ),
      );
      expect(to('/users/me'), hasLength(2));
      expect(expired, 0);
    });

    test('oturumsuz uçlarda 401 asla refresh/oturum sonu tetiklemez (yanlış şifre / yanlış 2FA girişi)', () async {
      respond = (_) =>
          json({'message': 'Kullanıcı adı veya şifre hatalı'}, 401);
      for (final path in ['/auth/login', '/auth/mfa/verify', '/auth/refresh']) {
        await expectLater(
          api.post(path, {}),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Kullanıcı adı veya şifre hatalı',
            ),
          ),
          reason: path,
        );
      }
      expect(
        to('/auth/refresh'),
        hasLength(1),
        reason: 'yalnız /auth/refresh\'e yapılan doğrudan çağrının kendisi',
      );
      expect(expired, 0);
    });
  });

  group('AuthProvider ile uçtan uca (onSessionExpired = logout)', () {
    late AuthProvider provider;
    setUp(() {
      provider = AuthProvider(apiService: api);
    });

    test('yanlış 2FA kodu / şifre sonrası kullanıcı giriş yapmış kalır, depo silinmez', () async {
      respond = (req) {
        if (req.url.path.endsWith('/auth/refresh')) {
          return json({
            'result': true,
            'data': {'token': 'a2', 'refreshToken': 'r2'},
          }, 200);
        }
        if (req.url.path.endsWith('/users/me/permissions')) {
          return json({
            'result': true,
            'data': {
              'permissions': ['users:manage'],
              'roles': ['ADMIN'],
            },
          }, 200);
        }
        if (req.url.path.endsWith('/users/me'))
          return json({
            'result': true,
            'data': {'id': 1, 'username': 'u'},
          }, 200);
        return json({'message': 'Geçersiz doğrulama kodu.'}, 401);
      };
      await provider.checkAuthStatus();
      expect(provider.isAuthenticated, isTrue);
      await expectLater(
        api.post('/auth/mfa/setup/verify', {'code': '1'}),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.post('/auth/mfa/disable', {'password': 'x'}),
        throwsA(isA<ApiException>()),
      );
      expect(provider.isAuthenticated, isTrue);
      expect(provider.profile, isNotNull);
      expect(await const FlutterSecureStorage().read(key: 'accessToken'), 'a2');
    });

    test('refresh başarısızsa oturum gerçekten kapanır: depo temiz, profil/izin/rol sıfır', () async {
      respond = (req) {
        if (req.url.path.endsWith('/users/me/permissions')) {
          return json({
            'result': true,
            'data': {
              'permissions': ['users:manage'],
              'roles': ['ADMIN'],
            },
          }, 200);
        }
        if (req.url.path.endsWith('/users/me'))
          return json({
            'result': true,
            'data': {'id': 1, 'username': 'u'},
          }, 200);
        return http.Response('', 401); // refresh dahil her şey 401
      };
      await provider.checkAuthStatus();
      expect(provider.isAuthenticated, isTrue);
      await expectLater(
        api.post('/auth/mfa/disable', {'password': 'x'}),
        throwsA(isA<ApiException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.profile, isNull);
      expect(provider.roles, isEmpty);
      expect(provider.permissions, isEmpty);
      expect(
        await const FlutterSecureStorage().read(key: 'accessToken'),
        isNull,
      );
      expect(
        await const FlutterSecureStorage().read(key: 'refreshToken'),
        isNull,
      );
    });
  });
}
