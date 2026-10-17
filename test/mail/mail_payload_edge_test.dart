import 'package:elly_mobile_app/services/mail_payload.dart';
import 'package:flutter_test/flutter_test.dart';

/// Edge cases of [mailAccountPayload] on top of `mail_payload_test.dart`: the write-only SMTP password and the
/// tenant null semantics. ("create requires the password" is enforced by the form validator, see
/// `mail_account_password_form_test.dart`; the function itself only decides whether the key is sent.)
void main() {
  const base = <String, Object?>{
    'name': 'Satış',
    'fromAddress': 'sales@example.invalid',
    'smtpHost': 'mail.example.invalid',
    'smtpPort': '587',
    'smtpUsername': 'sales',
  };

  group('smtpPassword key', () {
    test('absent (not null, not "") for every blank spelling, so an edit cannot wipe the stored one', () {
      for (final blank in ['', ' ', '   ', '\t', '\n', ' \t\r\n ', ' ', ' ', '　']) {
        final payload = mailAccountPayload(base, password: blank);
        expect(
          payload.containsKey('smtpPassword'),
          isFalse,
          reason: 'U+${blank.runes.map((r) => r.toRadixString(16)).join(',')}',
        );
        expect(payload.values.contains(''), isFalse, reason: 'no empty-string field smuggled in');
      }
    });

    test('blank password: exactly the DTO fields, nothing else', () {
      expect(mailAccountPayload(base, password: '').keys.toSet(), {
        'name', 'fromAddress', 'smtpHost', 'smtpPort', 'smtpUsername', 'isPrimary', 'active', 'tenantId', //
      });
    });

    test('typed password is sent byte for byte: no trim, no case change, no escaping', () {
      for (final password in [
        ' basinda',
        'sonunda ',
        '  ikisi de  ',
        'tab\there',
        '<placeholder> "q" \'s\' \\ / <b>&amp;',
        'ÜĞİŞÇÖ ığüşçö',
        '🔑 emoji',
        'a' * 500,
        '0',
        'false',
        'null',
      ]) {
        expect(mailAccountPayload(base, password: password)['smtpPassword'], password); // ggignore
      }
    });

    test('the value is always a String (never null), the key present only when something non-blank was typed', () {
      final withPassword = mailAccountPayload(base, password: 'x'); // ggignore
      expect(withPassword['smtpPassword'], isA<String>());
      expect(mailAccountPayload(base, password: ' x ').containsKey('smtpPassword'), isTrue); // ggignore
    });

    test('only the `password` argument decides: a smtpPassword inside the form values is ignored', () {
      expect(
        mailAccountPayload({...base, 'smtpPassword': 'x'}, password: '').containsKey('smtpPassword'), // ggignore
        isFalse,
      );
      expect(mailAccountPayload({...base, 'smtpPassword': 'x'}, password: 'y')['smtpPassword'], 'y'); // ggignore
    });

    test('the input map is not modified', () {
      final values = {...base, 'tenantId': ' t1 '};
      final copy = Map<String, Object?>.from(values);
      mailAccountPayload(values, password: ' p ');
      expect(values, copy);
    });
  });

  group('tenantId null semantics (admin create sends "" - mobile sends null)', () {
    Object? tenant(Object? raw) => mailAccountPayload({...base, 'tenantId': raw}, password: '')['tenantId'];

    test('empty / blank / null / missing → null, always with the key present', () {
      expect(tenant(''), isNull);
      expect(tenant('   '), isNull);
      expect(tenant('\n\t'), isNull);
      expect(tenant(null), isNull);
      final payload = mailAccountPayload(base, password: '');
      expect(payload.containsKey('tenantId'), isTrue, reason: 'null must be sent explicitly ("atanmamış")');
      expect(payload['tenantId'], isNull);
    });

    test('a value is trimmed and otherwise kept as is', () {
      expect(tenant('tenant1'), 'tenant1');
      expect(tenant(' tenant1 '), 'tenant1');
      expect(tenant('Tenant-2'), 'Tenant-2', reason: 'no case folding');
      expect(tenant('null'), 'null', reason: 'the text "null" is a tenant id, not a null');
      expect(tenant(7), '7');
    });
  });

  group('other fields', () {
    Map<String, dynamic> pay(Map<String, Object?> v) => mailAccountPayload({...base, ...v}, password: '');

    test('port: digits → int; blank / junk → null (the form rejects those before saving)', () {
      expect(pay({'smtpPort': '587'})['smtpPort'], 587);
      expect(pay({'smtpPort': ' 465 '})['smtpPort'], 465);
      expect(pay({'smtpPort': 25})['smtpPort'], 25);
      expect(pay({'smtpPort': ''})['smtpPort'], isNull);
      expect(pay({'smtpPort': 'abc'})['smtpPort'], isNull);
      expect(pay({'smtpPort': '58.7'})['smtpPort'], isNull);
      expect(pay({'smtpPort': null})['smtpPort'], isNull);
    });

    test('text fields are trimmed; null / missing become empty strings, not "null"', () {
      final p = mailAccountPayload({'name': null, 'fromAddress': '  a@b.co  '}, password: '');
      expect(p['name'], '');
      expect(p['fromAddress'], 'a@b.co');
      expect(p['smtpHost'], '');
      expect(p['smtpUsername'], '');
    });

    test('flags: isPrimary only for true; active false only for false', () {
      expect(pay({'isPrimary': true})['isPrimary'], isTrue);
      expect(pay({'isPrimary': false})['isPrimary'], isFalse);
      expect(pay({'isPrimary': null})['isPrimary'], isFalse);
      expect(pay({'active': false})['active'], isFalse);
      expect(pay({'active': true})['active'], isTrue);
      expect(pay({'active': null})['active'], isTrue);
    });
  });

  group('canRetryEmail / status helpers on odd logs', () {
    test('only SENT is excluded; a missing / unknown / lower-case status is not blocked client-side', () {
      expect(canRetryEmail({'status': 'SENT'}), isFalse);
      expect(canRetryEmail({}), isTrue);
      expect(canRetryEmail({'status': null}), isTrue);
      expect(canRetryEmail({'status': 'FAILED'}), isTrue);
      expect(canRetryEmail({'status': 'PENDING'}), isTrue);
      expect(
        canRetryEmail({'status': 'sent'}),
        isTrue,
        reason: 'backend enum is upper-case; unknown spellings are left to the server',
      );
    });

    test('email logs endpoint encodes the status', () {
      expect(emailLogsEndpoint('A&B'), '/emails?status=A%26B&sort=id,desc');
    });
  });
}
