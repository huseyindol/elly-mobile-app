import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Token yenileme sonucu: yalnız sunucu geçersiz/iptal derse ([sessionInvalid]) oturum kapatılır;
/// ağ veya 5xx hatalarında ([transientError]) kayıtlı token'lar korunur.
enum RefreshResult { refreshed, sessionInvalid, transientError }

/// A file part for multipart requests.
class UploadFile {
  final String field;
  final String path;
  const UploadFile(this.field, this.path);
}

class ApiService {
  // Override per build: --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.huseyindol.com/api/v1',
  );

  /// Called when the session can't be refreshed (refresh token expired/invalid).
  static void Function()? onSessionExpired;

  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  // Concurrent 401s share one refresh call.
  static Future<RefreshResult>? _refreshing;

  Future<Map<String, String>> _getHeaders({String? overrideTenantId, bool json = true, bool auth = true}) async {
    // An expired bearer makes the backend JWT filter reject even /auth/refresh with 401.
    final token = auth ? await secureStorage.read(key: 'accessToken') : null;
    final activeTenantId = overrideTenantId ?? await secureStorage.read(key: 'tenantId');
    return {
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (activeTenantId != null) 'X-Tenant-Id': activeTenantId,
    };
  }

  Future<dynamic> get(String endpoint, {String? tenantId}) =>
      _send(() async => _client.get(_uri(endpoint), headers: await _getHeaders(overrideTenantId: tenantId)), endpoint);

  /// `/auth/*` calls made without a session (login, refresh, 2FA login step): no Bearer, and a 401 is a wrong
  /// credential, not an expired session. The 2FA management endpoints (`/auth/mfa/status|setup|setup/verify|
  /// disable`) need the session: Bearer + refresh on 401 — a wrong code/password (also 401) then fails again after
  /// the refresh and its backend message is shown, the session stays.
  static bool isPublicAuthEndpoint(String endpoint) =>
      endpoint.startsWith('/auth/') && (!endpoint.startsWith('/auth/mfa/') || endpoint == '/auth/mfa/verify');

  Future<dynamic> post(String endpoint, Map<String, dynamic> body, {String? tenantId}) => _send(
    () async => _client.post(
      _uri(endpoint),
      headers: await _getHeaders(overrideTenantId: tenantId, auth: !isPublicAuthEndpoint(endpoint)),
      body: jsonEncode(body),
    ),
    endpoint,
  );

  Future<dynamic> put(String endpoint, Map<String, dynamic> body, {String? tenantId}) => _send(
    () async => _client.put(
      _uri(endpoint),
      headers: await _getHeaders(overrideTenantId: tenantId),
      body: jsonEncode(body),
    ),
    endpoint,
  );

  /// Body-less PATCH (`/users/{id}/status?isActive=…`).
  Future<dynamic> patch(String endpoint) =>
      _send(() async => _client.patch(_uri(endpoint), headers: await _getHeaders()), endpoint);

  Future<dynamic> delete(String endpoint, {String? tenantId}) => _send(
    () async => _client.delete(_uri(endpoint), headers: await _getHeaders(overrideTenantId: tenantId)),
    endpoint,
  );

  /// multipart/form-data request (banners: `data` JSON part, assets: `file` + `subFolder`).
  Future<dynamic> multipart(
    String method,
    String endpoint, {
    Map<String, String> fields = const {},
    List<UploadFile> files = const [],
  }) => _send(() async {
    final request = http.MultipartRequest(method, _uri(endpoint))
      ..headers.addAll(await _getHeaders(json: false))
      ..fields.addAll(fields);
    for (final f in files) {
      // Without an explicit type the part is application/octet-stream and the
      // backend's image check fails ("File is not an image").
      final mime = lookupMimeType(f.path) ?? 'application/octet-stream';
      request.files.add(await http.MultipartFile.fromPath(f.field, f.path, contentType: MediaType.parse(mime)));
    }
    return http.Response.fromStream(await _client.send(request));
  }, endpoint);

  Uri _uri(String endpoint) => Uri.parse('$baseUrl$endpoint');

  /// Absolute URL of a stored file path (`assets/t/…` → `https://api…/assets/t/…`; served without auth),
  /// same rule as the admin/tenant `getImageUrl`. Full and data URLs are returned as they are.
  static String fileUrl(String path) {
    if (RegExp(r'^(https?:|data:)').hasMatch(path)) return path;
    return '${Uri.parse(baseUrl).origin}/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Future<dynamic> _send(Future<http.Response> Function() request, String endpoint) async {
    var response = await request();
    if (response.statusCode == 401 && !isPublicAuthEndpoint(endpoint)) {
      switch (await _refreshSession()) {
        case RefreshResult.refreshed:
          response = await request();
        case RefreshResult.sessionInvalid:
          onSessionExpired?.call();
          throw ApiException('Oturum süresi doldu, lütfen tekrar giriş yapın.', statusCode: 401);
        case RefreshResult.transientError:
          throw ApiException('Bağlantı sorunu nedeniyle oturum doğrulanamadı. Lütfen tekrar deneyin.', statusCode: 503);
      }
    }
    return _handleResponse(response);
  }

  /// Access token süresi dolmuş veya [leeway] içinde dolacaksa tek bir refresh çağrısıyla tazeler.
  /// `tokenExpiresAt` kayıtlı değilse (eski kurulum/testler) dokunmaz; ilk 401 normal yoldan yeniler.
  Future<void> ensureFreshToken({Duration leeway = const Duration(minutes: 2)}) async {
    final rawExp = await secureStorage.read(key: 'tokenExpiresAt');
    if (rawExp == null) return;
    final expMs = int.tryParse(rawExp);
    if (expMs == null) return;
    if (DateTime.now().millisecondsSinceEpoch + leeway.inMilliseconds < expMs) return;
    final res = await _refreshSession();
    if (res == RefreshResult.sessionInvalid) {
      onSessionExpired?.call();
    }
  }

  /// Best-effort tekil cihaz çıkışı: yerel depo silinmiş olsa bile eldeki [accessToken] ile
  /// backend'den yalnız [refreshToken]'ı iptal eder; 401/ağ hatalarını yoksayar.
  Future<void> revokeSession({
    required String accessToken,
    String? refreshToken,
    String? tenantId,
  }) async {
    try {
      await _client.post(
        _uri('/auth/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
          if (tenantId != null) 'X-Tenant-Id': tenantId,
        },
        body: jsonEncode({
          if (refreshToken != null && refreshToken.isNotEmpty) 'refreshToken': refreshToken,
        }),
      );
    } catch (_) {}
  }

  Future<RefreshResult> _refreshSession() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<RefreshResult> _doRefresh() async {
    final refreshToken = await secureStorage.read(key: 'refreshToken');
    if (refreshToken == null || refreshToken.isEmpty) return RefreshResult.sessionInvalid;
    late final http.Response response;
    try {
      response = await _client.post(
        _uri('/auth/refresh'),
        headers: await _getHeaders(auth: false),
        body: jsonEncode({'refreshToken': refreshToken}),
      );
    } catch (_) {
      // Ağ / zaman aşımı hatası: sunucu oturumu reddetmedi, token'ları koru.
      return RefreshResult.transientError;
    }

    if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403) {
      return RefreshResult.sessionInvalid;
    }
    if (response.statusCode != 200) {
      return RefreshResult.transientError;
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['result'] != true) return RefreshResult.sessionInvalid;
      final data = decoded['data'];
      if (data is! Map) return RefreshResult.sessionInvalid;
      final token = data['token']?.toString();
      if (token == null || token.isEmpty) return RefreshResult.sessionInvalid;
      await secureStorage.write(key: 'accessToken', value: token);
      final newRefresh = data['refreshToken']?.toString();
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await secureStorage.write(key: 'refreshToken', value: newRefresh);
      }
      final exp = data['expiredDate'];
      if (exp is num) {
        await secureStorage.write(key: 'tokenExpiresAt', value: '${exp.toInt()}');
      }
      return RefreshResult.refreshed;
    } catch (_) {
      return RefreshResult.sessionInvalid;
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode == 204) return null; // e.g. DELETE /email-templates/{key}: no body
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (ok && decoded is Map && decoded['result'] == true) return decoded['data'];
    throw ApiException(_errorMessage(decoded, response.statusCode), statusCode: response.statusCode);
  }

  /// Backend ErrorResponse: { message, validationErrors: {field: msg}, details: [...] }
  static String _errorMessage(dynamic decoded, int status) {
    if (decoded is! Map) return 'Sunucu hatası ($status)';
    final parts = <String>[];
    final message = decoded['message'] ?? decoded['error'];
    if (message != null) parts.add(message.toString());
    final validation = decoded['validationErrors'];
    if (validation is Map && validation.isNotEmpty) {
      parts.add(validation.entries.map((e) => '${e.key}: ${e.value}').join('\n'));
    }
    final details = decoded['details'];
    if (details is List && details.isNotEmpty) parts.add(details.join('\n'));
    return parts.isEmpty ? 'Sunucu hatası ($status)' : parts.join('\n');
  }
}
