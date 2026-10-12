import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);
http.Response okData(Object data) => jsonResponse({'result': true, 'data': data}, 200);

/// In-memory backend for widget tests: path (relative to /api/v1) → handler. No network.
class FakeBackend {
  final Map<String, http.Response Function(http.Request)> routes = {};
  final List<http.Request> requests = [];

  FakeBackend() {
    FlutterSecureStorage.setMockInitialValues({});
  }

  late final ApiService api = ApiService(
    client: MockClient((req) async {
      requests.add(req);
      final handler = routes[req.url.path.replaceFirst(RegExp(r'^.*/api/v1'), '')];
      return handler == null ? http.Response('', 404) : handler(req);
    }),
  );

  AuthProvider newAuth() => AuthProvider(apiService: api);

  /// Serves GET /users/me/permissions with the given `<module>:<action>` keys.
  void permissions(List<String> keys) {
    routes['/users/me/permissions'] = (_) => okData({'permissions': keys});
  }

  /// Serves `{result: true, data}` for [path] (query string ignored).
  void ok(String path, Object data) => routes[path] = (_) => okData(data);

  /// App start with a stored token: [auth] loads [keys] through this backend.
  /// Call inside `tester.runAsync` in widget tests.
  Future<void> signIn(AuthProvider auth, List<String> keys) {
    permissions(keys);
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    return auth.checkAuthStatus();
  }

  Iterable<http.Request> requestsTo(String suffix) => requests.where((r) => r.url.path.endsWith(suffix));
}
