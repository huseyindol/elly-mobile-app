import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/rabbit_admin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queuePath encodes the name as one segment', () {
    expect(queuePath('email-queue'), '/admin/rabbit/queues/email-queue');
    expect(queuePath('a/b c', '/purge'), '/admin/rabbit/queues/a%2Fb%20c/purge');
  });

  test('peek count clamped to the backend range 1–100, default 10', () {
    expect(clampPeekCount(null), 10);
    expect(clampPeekCount(0), 1);
    expect(clampPeekCount(500), 100);
    expect(clampPeekCount(25), 25);
  });

  test('payloads are text: JSON pretty-printed, anything else (HTML too) untouched', () {
    expect(prettyPayload('{"a":1}'), '{\n  "a": 1\n}');
    const html = '<img src=x onerror=alert(1)>';
    expect(prettyPayload(html), html);
  });

  test('clipText keeps short text, cuts long text with the remaining count', () {
    expect(clipText('abc', max: 5), 'abc');
    expect(clipText('abcdefgh', max: 5), 'abcde\n… (3 karakter daha)');
  });

  test('republish payload: trimmed target, payload as typed, default content type', () {
    expect(republishPayload(targetQueue: ' email-queue ', payload: ' {"a":1} ', contentType: ' '), {
      'targetQueue': 'email-queue',
      'payload': ' {"a":1} ',
      'contentType': 'application/json',
    });
  });

  test('republish validation: required payload; JSON content type needs valid JSON', () {
    expect(republishPayloadError('', 'text/plain'), isNotNull);
    expect(republishPayloadError('{bad', 'application/json'), isNotNull);
    expect(republishPayloadError('{"a":1}', 'application/json'), isNull);
    expect(republishPayloadError('{bad', 'text/plain'), isNull);
  });

  test('rabbitErrorText maps statuses like the admin', () {
    expect(rabbitErrorText(ApiException('x', statusCode: 503)), 'RabbitMQ şu an erişilemez');
    expect(rabbitErrorText(ApiException('x', statusCode: 403)), 'Bu işlem için yetkin yok');
    expect(rabbitErrorText(ApiException('x', statusCode: 404)), 'Queue bulunamadı');
    expect(rabbitErrorText(ApiException('x', statusCode: 409)), 'Queue şu an kullanımda');
    expect(rabbitErrorText(ApiException('başka', statusCode: 400)), 'başka');
  });
}
