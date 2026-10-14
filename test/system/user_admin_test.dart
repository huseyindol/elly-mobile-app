import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/user_admin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const panelRoles = ['SUPER_ADMIN', 'ADMIN', 'EDITOR', 'VIEWER'];

  group('role hierarchy (backend roleLevel)', () {
    test('levels: SUPER_ADMIN 4, ADMIN 3, EDITOR 2, VIEWER/TENANT/custom/none 1', () {
      expect([for (final r in panelRoles) roleLevel(r)], [4, 3, 2, 1]);
      expect(roleLevel('TENANT'), 1);
      expect(roleLevel('MARKETING'), 1);
      expect(maxRoleLevel(const []), 1);
      expect(maxRoleLevel(const ['VIEWER', 'ADMIN', 'EDITOR']), 3);
      expect(maxRoleLevel(const ['TENANT']), 1);
    });

    // Every caller level × every role: assignable iff not TENANT and not above the caller.
    for (final me in panelRoles) {
      final myLevel = roleLevel(me);
      for (final target in [...panelRoles, 'TENANT']) {
        final assignable = target != 'TENANT' && roleLevel(target) <= myLevel;
        test('$me ${assignable ? 'may' : 'may not'} assign $target', () {
          expect(canAssignRole(myLevel, target), assignable);
        });
        final manageable = roleLevel(target) <= myLevel;
        test('$me ${manageable ? 'may' : 'may not'} manage a $target user', () {
          expect(canManageUser(myLevel, [target]), manageable);
        });
      }
    }

    test('a user with several roles counts with the highest one', () {
      expect(canManageUser(3, const ['VIEWER', 'SUPER_ADMIN']), isFalse);
      expect(canManageUser(3, const ['VIEWER', 'EDITOR']), isTrue);
      expect(canManageUser(1, const []), isTrue, reason: 'no role = level 1');
    });

    test('ADMIN default on an empty role list only for callers that could assign ADMIN', () {
      expect(canUseDefaultAdminRole(4), isTrue);
      expect(canUseDefaultAdminRole(3), isTrue);
      expect(canUseDefaultAdminRole(2), isFalse);
      expect(canUseDefaultAdminRole(1), isFalse);
    });
  });

  group('payloads', () {
    test('panel create: trimmed fields, roleIds, audience; empty roles → key omitted (backend ADMIN default)', () {
      expect(
        createUserPayload(
          audience: 'panel',
          username: ' ali ',
          email: ' a@b.com ',
          password: ' Pass1234',
          firstName: ' Ali ',
          lastName: 'Veli',
          roleIds: [2, 3],
        ),
        {
          'username': 'ali',
          'email': 'a@b.com',
          'password': ' Pass1234',
          'firstName': 'Ali',
          'lastName': 'Veli',
          'roleIds': [2, 3],
          'audience': 'panel',
        },
      );
      final noRoles = createUserPayload(
        audience: 'panel',
        username: 'a',
        email: 'e',
        password: 'p',
        firstName: '',
        lastName: '',
      );
      expect(noRoles.containsKey('roleIds'), isFalse);
    });

    test('tenant create never sends roleIds (backend rejects them)', () {
      final p = createUserPayload(
        audience: 'tenant',
        username: 'a',
        email: 'e',
        password: 'p',
        firstName: '',
        lastName: '',
        roleIds: [1],
      );
      expect(p.containsKey('roleIds'), isFalse);
      expect(p['audience'], 'tenant');
    });

    test('update: blank username/email/password left out, names sent (empty clears)', () {
      expect(updateUserPayload(username: ' ', email: '', firstName: '', lastName: ' Dol '), {
        'firstName': '',
        'lastName': 'Dol',
      });
      expect(
        updateUserPayload(username: 'ali', email: 'a@b.com', firstName: 'A', lastName: 'B', newPassword: 'Yeni1234'),
        {'username': 'ali', 'email': 'a@b.com', 'firstName': 'A', 'lastName': 'B', 'newPassword': 'Yeni1234'},
      );
    });
  });

  group('validation (backend Dto annotations)', () {
    test('password rule: ≥8, lower + upper + digit; edge whitespace rejected', () {
      expect(passwordError('Abcdefg1'), isNull);
      expect(passwordError('Abc def1'), isNull, reason: 'inner space is fine');
      for (final bad in ['', 'abcdefg1', 'ABCDEFG1', 'Abcdefgh', 'Abc1', ' Abcdefg1', 'Abcdefg1 ']) {
        expect(passwordError(bad), isNotNull, reason: '"$bad"');
      }
    });

    test('username 3–50, e-mail format, optional when not required', () {
      expect(usernameError('ab'), isNotNull);
      expect(usernameError('abc'), isNull);
      expect(usernameError('a' * 51), isNotNull);
      expect(usernameError(''), isNotNull);
      expect(usernameError('', required: false), isNull);
      expect(emailError('a@b.co'), isNull);
      expect(emailError('a@b'), isNotNull);
      expect(emailError(''), isNotNull);
      expect(emailError('', required: false), isNull);
    });
  });

  group('userErrorText', () {
    test('known backend messages in Turkish', () {
      expect(userErrorText(ApiException('Current password is incorrect', statusCode: 400)), 'Mevcut şifre hatalı.');
      expect(
        userErrorText(ApiException('New password must be different from current password', statusCode: 400)),
        'Yeni şifre mevcut şifreden farklı olmalı.',
      );
      expect(
        userErrorText(ApiException('Username already exists: ali', statusCode: 409)),
        'Bu kullanıcı adı zaten kullanılıyor.',
      );
      expect(
        userErrorText(ApiException('Email already exists: a@b.com', statusCode: 409)),
        'Bu e-posta adresi zaten kullanılıyor.',
      );
    });

    test('hierarchy 403 names the role; other 403s explain the rule', () {
      expect(
        userErrorText(
          ApiException("Cannot assign role 'SUPER_ADMIN': exceeds your own permission level", statusCode: 403),
        ),
        contains('"SUPER_ADMIN" rolünü atayamazsınız'),
      );
      expect(userErrorText(ApiException('Access Denied', statusCode: 403)), contains('yetkiniz yok'));
    });

    test('Turkish backend messages pass through', () {
      expect(
        userErrorText(ApiException('Kendi hesabınızı silemezsiniz', statusCode: 400)),
        'Kendi hesabınızı silemezsiniz',
      );
    });
  });

  group('2FA setup', () {
    const secret = 'JBSWY3DPEHPK3PXP';
    const uri = 'otpauth://totp/Elly+CMS%3Aali?secret=$secret&issuer=Elly+CMS&algorithm=SHA1&digits=6&period=30';

    test('backend TotpService URI for the same secret is valid', () {
      expect(isValidOtpauthUri(uri, secret), isTrue);
    });

    test('other schemes, HOTP, missing label or a different secret are rejected', () {
      for (final bad in [
        'https://evil.example/?secret=$secret',
        'otpauth://hotp/Elly:ali?secret=$secret',
        'otpauth://totp/?secret=$secret',
        'otpauth://totp/Elly:ali?secret=OTHERSECRET',
        'otpauth://totp/Elly:ali',
        'javascript:alert(1)',
        '',
      ]) {
        expect(isValidOtpauthUri(bad, secret), isFalse, reason: bad);
      }
      expect(isValidOtpauthUri(uri, ''), isFalse);
    });

    test('secret grouped by four; masked keeps the length, shows no character', () {
      expect(formatSecret(secret), 'JBSW Y3DP EHPK 3PXP');
      expect(formatSecret('ABCDEF'), 'ABCD EF');
      final masked = formatSecret(secret, masked: true);
      expect(masked, '•••• •••• •••• ••••');
      expect(RegExp('[A-Z0-9]').hasMatch(masked), isFalse);
    });
  });

  test('displayNameOf: full name, else username', () {
    expect(displayNameOf({'firstName': 'Hüseyin', 'lastName': 'Dol', 'username': 'h'}), 'Hüseyin Dol');
    expect(displayNameOf({'firstName': '', 'lastName': null, 'username': 'h'}), 'h');
    expect(displayNameOf(null), '');
  });

  test('groupPermissions: by module, both sorted; malformed keys skipped', () {
    expect(groupPermissions(['posts:update', 'pages:read', 'posts:read', 'bad', ':x']), {
      'pages': ['read'],
      'posts': ['read', 'update'],
    });
  });

  test('formatSecret groups by code point (no split surrogate)', () {
    expect(formatSecret('ABC😀DEF'), 'ABC😀 DEF');
    expect(formatSecret('ABC😀DEF', masked: true), '•••• •••');
  });
}
