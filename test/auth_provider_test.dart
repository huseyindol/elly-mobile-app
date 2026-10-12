import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, int status) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);
http.Response _ok(Object data) => _json({'result': true, 'data': data}, 200);

const _perms = {
  'roles': ['EDITOR'],
  'permissions': ['posts:read', 'posts:update'],
  'permissionsByModule': {
    'posts': ['read', 'update']
  },
};

void main() {
  late List<http.Request> requests;
  late Map<String, http.Response Function(http.Request)> routes;

  AuthProvider build() => AuthProvider(
        apiService: ApiService(
          client: MockClient((req) async {
            requests.add(req);
            final handler = routes[req.url.path.replaceFirst(RegExp(r'^.*/api/v1'), '')];
            return handler == null ? http.Response('', 404) : handler(req);
          }),
        ),
      );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    requests = [];
    routes = {'/users/me/permissions': (_) => _ok(_perms)};
  });

  test('login without 2FA authenticates and loads permissions', () async {
    routes['/auth/login'] = (_) => _ok({'token': 'a', 'refreshToken': 'r', 'username': 'u'});
    final auth = build();

    expect(await auth.login(usernameOrEmail: 'u', password: 'p', tenantId: 't1'), isTrue);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.mfaPending, isFalse);
    expect(auth.can('posts', 'read'), isTrue);
    expect(auth.can('posts', 'update'), isTrue);
    expect(auth.can('posts', 'delete'), isFalse);
    expect(auth.can('pages', 'read'), isFalse);
    expect(requests.last.headers['Authorization'], 'Bearer a');
  });

  test('2FA: login → code step → verify success', () async {
    routes['/auth/login'] = (_) => _ok({'mfaRequired': true, 'mfaToken': 'm1', 'token': null});
    routes['/auth/mfa/verify'] = (_) => _ok({'token': 'a', 'refreshToken': 'r'});
    final auth = build();

    expect(await auth.login(usernameOrEmail: 'u', password: 'p', tenantId: 't1'), isFalse);
    expect(auth.mfaPending, isTrue);
    expect(auth.errorMessage, isNull);
    expect(auth.isAuthenticated, isFalse);

    expect(await auth.verifyMfa('123456'), isTrue);
    final verify = requests.firstWhere((r) => r.url.path.endsWith('/auth/mfa/verify'));
    expect(jsonDecode(verify.body), {'mfaToken': 'm1', 'code': '123456'});
    expect(verify.headers['X-Tenant-Id'], 't1');
    expect(verify.headers.containsKey('Authorization'), isFalse);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.mfaPending, isFalse);
    expect(auth.can('posts', 'read'), isTrue);
  });

  test('2FA: invalid code shows the API error and keeps the code step; cancel goes back', () async {
    routes['/auth/login'] = (_) => _ok({'mfaRequired': true, 'mfaToken': 'm1'});
    routes['/auth/mfa/verify'] = (_) => _json({'message': 'Geçersiz kod'}, 401);
    final auth = build();

    await auth.login(usernameOrEmail: 'u', password: 'p', tenantId: 't1');
    expect(await auth.verifyMfa('000000'), isFalse);
    expect(auth.errorMessage, 'Geçersiz kod');
    expect(auth.mfaPending, isTrue);
    expect(auth.isAuthenticated, isFalse);

    auth.cancelMfa();
    expect(auth.mfaPending, isFalse);
    expect(auth.errorMessage, isNull);
  });

  test('permissions: failed load keeps auth-response permissions and reports error', () async {
    routes['/auth/login'] = (_) => _ok({'token': 'a', 'refreshToken': 'r', 'permissions': ['pages:read']});
    routes['/users/me/permissions'] = (_) => http.Response('', 500);
    final auth = build();

    await auth.login(usernameOrEmail: 'u', password: 'p', tenantId: 't1');
    expect(auth.isAuthenticated, isTrue);
    expect(auth.permissionsLoaded, isTrue);
    expect(auth.permissionsError, isNotNull);
    expect(auth.can('pages', 'read'), isTrue);
  });

  test('permissions: app start with token loads them; failure leaves nothing granted; logout clears', () async {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    routes['/users/me/permissions'] = (_) => http.Response('', 500);
    final auth = build();

    await auth.checkAuthStatus();
    expect(auth.isAuthenticated, isTrue);
    expect(auth.permissionsLoaded, isFalse);
    expect(auth.permissionsError, isNotNull);
    expect(auth.can('posts', 'read'), isFalse);

    routes['/users/me/permissions'] = (_) => _ok(_perms);
    await auth.loadPermissions();
    expect(auth.permissionsError, isNull);
    expect(auth.can('posts', 'read'), isTrue);

    await auth.logout();
    expect(auth.isAuthenticated, isFalse);
    expect(auth.can('posts', 'read'), isFalse);
  });
}
