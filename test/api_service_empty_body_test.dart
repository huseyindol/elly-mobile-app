import 'dart:convert';

import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `ApiService._handleResponse`: 204 No Content is a body-less success (`DELETE /email-templates/{key}`) and the
/// rest of the response contract (`{result, data}` wrapper, ErrorResponse → message, 401 refresh) is unchanged.
void main() {
  late List<http.BaseRequest> sent;
  late http.Response Function(http.BaseRequest request) respond;
  late ApiService api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'tok', 'tenantId': 't1'});
    sent = [];
    respond = (_) => http.Response('', 204);
    api = ApiService(
      client: MockClient((req) async {
        sent.add(req);
        return respond(req);
      }),
    );
  });
  tearDown(() => ApiService.onSessionExpired = null);

  http.Response json(Object body, int status) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  group('204 No Content', () {
    test('is a success with null for every verb', () async {
      expect(await api.get('/a'), isNull);
      expect(await api.post('/a', {'x': 1}), isNull);
      expect(await api.put('/a', {'x': 1}), isNull);
      expect(await api.delete('/a'), isNull);
      expect(await api.multipart('POST', '/a', fields: {'k': 'v'}), isNull);
      expect(sent.map((r) => r.method), ['GET', 'POST', 'PUT', 'DELETE', 'POST']);
    });

    test('whatever the body says: it is still a body-less success (null, no exception)', () async {
      for (final body in ['', '{"result":true,"data":{"id":1}}', 'not json', '{"result":false,"message":"x"}', '   ']) {
        respond = (_) => http.Response(body, 204);
        expect(await api.delete('/a'), isNull, reason: 'body "$body"');
      }
    });

    test('keeps the headers of the request (token, tenant) - the empty body changes nothing about the call', () async {
      await api.delete('/email-templates/welcome-mail');
      final headers = sent.single.headers;
      expect(sent.single.url.path, endsWith('/email-templates/welcome-mail'));
      expect(headers['Authorization'], 'Bearer tok');
      expect(headers['X-Tenant-Id'], 't1');
      expect(headers['Accept'], 'application/json');
    });

    test('after a 401 + successful refresh the retried call may be a 204', () async {
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'old', 'refreshToken': 'r1', 'tenantId': 't1'});
      var expired = false;
      ApiService.onSessionExpired = () => expired = true;
      respond = (req) {
        if (req.url.path.endsWith('/auth/refresh')) {
          return json({
            'result': true,
            'data': {'token': 'new', 'refreshToken': 'r2'},
          }, 200);
        }
        return req.headers['Authorization'] == 'Bearer new'
            ? http.Response('', 204)
            : json({'message': 'expired'}, 401);
      };

      expect(await api.delete('/email-templates/a'), isNull);
      expect(expired, isFalse);
      expect(sent.where((r) => r.url.path.endsWith('/email-templates/a')), hasLength(2), reason: 'one retry');
      expect(sent.where((r) => r.url.path.endsWith('/auth/refresh')), hasLength(1));
    });
  });

  group('other empty / odd bodies are NOT success', () {
    test('200 with an empty body → ApiException "Sunucu hatası (200)"', () async {
      respond = (_) => http.Response('', 200);
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 200)
              .having((e) => e.message, 'message', 'Sunucu hatası (200)'),
        ),
      );
    });

    test('200 / 201 / 202 / 205 with no body are errors (only 204 is special)', () async {
      for (final status in [200, 201, 202, 205, 206]) {
        respond = (_) => http.Response('', status);
        await expectLater(
          api.post('/x', {}),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status)),
          reason: '$status',
        );
      }
    });

    test('200 with non-JSON, null, a bare list, or result != true → error', () async {
      for (final body in [
        '<html>gateway</html>',
        'null',
        '[]',
        '{}',
        '{"data":{"id":1}}',
        '{"result":false,"data":{"id":1}}',
        '{"result":"true"}',
      ]) {
        respond = (_) => http.Response(body, 200);
        await expectLater(api.get('/x'), throwsA(isA<ApiException>()), reason: body);
      }
    });

    test('200 {result:false,message} → the backend message', () async {
      respond = (_) => json({'result': false, 'message': 'Mail hesabı bulunamadı'}, 200);
      await expectLater(
        api.get('/x'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Mail hesabı bulunamadı')),
      );
    });

    test('4xx / 5xx with an empty body → "Sunucu hatası (<status>)" carrying the status', () async {
      for (final status in [400, 403, 404, 409, 500, 502, 503]) {
        respond = (_) => http.Response('', status);
        await expectLater(
          api.delete('/x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.message, 'message', 'Sunucu hatası ($status)'),
          ),
          reason: '$status',
        );
      }
    });

    test('3xx without a body is an error, not a silent success', () async {
      respond = (_) => http.Response('', 304);
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 304)));
    });
  });

  group('the success / error contract is unchanged', () {
    test('200 {result:true,data} → data (map, list, scalar, paged); missing data → null', () async {
      for (final data in <Object?>[
        {'id': 1, 'ad': 'Çağrı'},
        [1, 2],
        'SMTP bağlantısı başarılı',
        42,
        {'content': [], 'last': true},
      ]) {
        respond = (_) => json({'result': true, 'data': data}, 200);
        expect(await api.get('/x'), data);
      }
      respond = (_) => json({'result': true}, 200);
      expect(await api.get('/x'), isNull);
      respond = (_) => json({'result': true, 'data': null}, 201);
      expect(await api.post('/x', {}), isNull);
    });

    test('UTF-8 body is decoded from bytes (Turkish characters)', () async {
      respond = (_) => http.Response.bytes(utf8.encode('{"result":true,"data":"İğdır şehri"}'), 200);
      expect(await api.get('/x'), 'İğdır şehri');
    });

    test('ErrorResponse: message + validationErrors + details, joined', () async {
      respond = (_) => json({
        'message': 'Doğrulama hatası',
        'validationErrors': {'smtpPort': 'geçersiz', 'name': 'zorunlu'},
        'details': ['a', 'b'],
      }, 400);
      await expectLater(
        api.post('/x', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Doğrulama hatası\nsmtpPort: geçersiz\nname: zorunlu\na\nb')
              .having((e) => e.statusCode, 'status', 400),
        ),
      );
    });

    test('401 with no refresh token → onSessionExpired, one call, session message', () async {
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'old', 'tenantId': 't1'});
      var expired = 0;
      ApiService.onSessionExpired = () => expired++;
      respond = (_) => http.Response('', 401);
      await expectLater(
        api.delete('/email-templates/a'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.message, 'message', contains('Oturum süresi doldu')),
        ),
      );
      expect(expired, 1);
      expect(sent, hasLength(1), reason: 'no retry without a refreshed session');
    });

    test('401 on /auth/* is a plain error (no refresh loop, no session-expired)', () async {
      var expired = false;
      ApiService.onSessionExpired = () => expired = true;
      respond = (_) => json({'message': 'Kullanıcı adı veya şifre hatalı'}, 401);
      await expectLater(
        api.post('/auth/login', {}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Kullanıcı adı veya şifre hatalı')),
      );
      expect(expired, isFalse);
      expect(sent, hasLength(1));
    });

    test('a 204 from /auth/* is also just a success', () async {
      expect(await api.post('/auth/logout', {}), isNull);
    });
  });
}
