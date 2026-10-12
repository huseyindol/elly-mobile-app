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

/// A file part for multipart requests.
class UploadFile {
  final String field;
  final String path;
  const UploadFile(this.field, this.path);
}

class ApiService {
  static const String baseUrl = 'https://api.huseyindol.com/api/v1';

  /// Called when the session can't be refreshed (refresh token expired/invalid).
  static void Function()? onSessionExpired;

  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  // Concurrent 401s share one refresh call.
  static Future<bool>? _refreshing;

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

  Future<dynamic> post(String endpoint, Map<String, dynamic> body, {String? tenantId}) => _send(
      () async => _client.post(_uri(endpoint),
          headers: await _getHeaders(overrideTenantId: tenantId, auth: !endpoint.startsWith('/auth/')),
          body: jsonEncode(body)),
      endpoint);

  Future<dynamic> put(String endpoint, Map<String, dynamic> body, {String? tenantId}) => _send(
      () async => _client.put(_uri(endpoint),
          headers: await _getHeaders(overrideTenantId: tenantId), body: jsonEncode(body)),
      endpoint);

  Future<dynamic> delete(String endpoint, {String? tenantId}) =>
      _send(() async => _client.delete(_uri(endpoint), headers: await _getHeaders(overrideTenantId: tenantId)), endpoint);

  /// multipart/form-data request (banners: `data` JSON part, assets: `file` + `subFolder`).
  Future<dynamic> multipart(
    String method,
    String endpoint, {
    Map<String, String> fields = const {},
    List<UploadFile> files = const [],
  }) =>
      _send(() async {
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

  Future<dynamic> _send(Future<http.Response> Function() request, String endpoint) async {
    var response = await request();
    if (response.statusCode == 401 && !endpoint.startsWith('/auth/')) {
      if (await _refreshSession()) {
        response = await request();
      } else {
        onSessionExpired?.call();
        throw ApiException('Oturum süresi doldu, lütfen tekrar giriş yapın.', statusCode: 401);
      }
    }
    return _handleResponse(response);
  }

  Future<bool> _refreshSession() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await secureStorage.read(key: 'refreshToken');
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _client.post(
        _uri('/auth/refresh'),
        headers: await _getHeaders(auth: false),
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode != 200) return false;
      final data = (jsonDecode(response.body) as Map)['data'] as Map?;
      final token = data?['token']?.toString();
      if (token == null || token.isEmpty) return false;
      await secureStorage.write(key: 'accessToken', value: token);
      final newRefresh = data?['refreshToken']?.toString();
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await secureStorage.write(key: 'refreshToken', value: newRefresh);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  dynamic _handleResponse(http.Response response) {
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
