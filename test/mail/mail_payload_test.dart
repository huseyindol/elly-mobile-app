import 'package:elly_mobile_app/services/mail_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const values = {
    'name': ' Satış ',
    'fromAddress': 'sales@example.invalid ',
    'smtpHost': 'mail.example.invalid',
    'smtpPort': '587',
    'smtpUsername': 'sales@example.invalid',
    'tenantId': ' ',
    'isPrimary': true,
    'active': false,
  };

  group('mailAccountPayload (SMTP password is write-only)', () {
    test('blank password is omitted, so an update keeps the stored one', () {
      for (final blank in ['', '   ']) {
        final payload = mailAccountPayload(values, password: blank);
        expect(payload.containsKey('smtpPassword'), isFalse, reason: '"$blank"');
      }
    });

    test('a typed password is sent exactly as typed (spaces are part of it)', () {
      expect(mailAccountPayload(values, password: ' <app-password> ')['smtpPassword'], ' <app-password> '); // ggignore
    });

    test('DTO fields: trimmed text, int port, flags, empty tenant → null', () {
      expect(mailAccountPayload(values, password: 'x'), {
        'name': 'Satış',
        'fromAddress': 'sales@example.invalid',
        'smtpHost': 'mail.example.invalid',
        'smtpPort': 587,
        'smtpUsername': 'sales@example.invalid',
        'smtpPassword': 'x', // ggignore
        'isPrimary': true,
        'active': false,
        'tenantId': null,
        'dailyLimit': 500,
      });
      expect(mailAccountPayload({...values, 'tenantId': 'tenant1'}, password: '')['tenantId'], 'tenant1');
    });

    test('active defaults to true, isPrimary to false', () {
      final payload = mailAccountPayload({'name': 'a'}, password: '');
      expect(payload['active'], isTrue);
      expect(payload['isPrimary'], isFalse);
    });
  });

  group('emailTemplatePayload', () {
    test('update sends the key back (PUT validates it) and the lock version', () {
      expect(
        emailTemplatePayload(
          templateKey: 'welcome-mail',
          subject: ' Merhaba [[\${userName}]] ',
          htmlBody: '  <p th:text="\${userName}"></p>\n',
          description: '  ',
          active: false,
          optimisticLockVersion: 3,
        ),
        {
          'templateKey': 'welcome-mail',
          'subject': 'Merhaba [[\${userName}]]',
          'htmlBody': '  <p th:text="\${userName}"></p>\n',
          'description': null,
          'active': false,
          'optimisticLockVersion': 3,
        },
      );
    });

    test('create has no lock version', () {
      final payload = emailTemplatePayload(
        templateKey: 'a-b',
        subject: 's',
        htmlBody: 'h',
        description: ' Hoş geldin ',
        active: true,
      );
      expect(payload.containsKey('optimisticLockVersion'), isFalse);
      expect(payload['description'], 'Hoş geldin');
    });

    test('templateKeyPattern = backend regex', () {
      for (final ok in ['welcome', 'form-submit-2']) {
        expect(templateKeyPattern.hasMatch(ok), isTrue, reason: ok);
      }
      for (final bad in ['Welcome', 'a_b', 'a b', 'çay', '']) {
        expect(templateKeyPattern.hasMatch(bad), isFalse, reason: bad);
      }
    });
  });

  group('e-mail logs', () {
    test('endpoint: newest first, optional status', () {
      expect(emailLogsEndpoint(null), '/emails?sort=id,desc');
      expect(emailLogsEndpoint('FAILED'), '/emails?status=FAILED&sort=id,desc');
    });

    test('SENT cannot be retried; FAILED and PENDING can', () {
      expect(canRetryEmail({'status': 'SENT'}), isFalse);
      expect(canRetryEmail({'status': 'FAILED'}), isTrue);
      expect(canRetryEmail({'status': 'PENDING'}), isTrue);
    });

    test('labels for every backend EmailStatus', () {
      expect(emailStatusLabels.keys, ['PENDING', 'SENT', 'FAILED', 'QUOTA_EXCEEDED']);
    });
  });

  test('emailPattern', () {
    expect(emailPattern.hasMatch('a@b.co'), isTrue);
    for (final bad in ['a@b', 'a b@c.de', '@b.co', 'a@.']) {
      expect(emailPattern.hasMatch(bad), isFalse, reason: bad);
    }
  });
}
