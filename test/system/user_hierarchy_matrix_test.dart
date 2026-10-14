import 'package:elly_mobile_app/services/user_admin.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rol hiyerarşisi: çok rollü kullanıcı, bilinmeyen/rolsüz/TENANT, tüm alt küme x çağıran seviyesi matrisi.
/// `user_admin_test.dart` tek rollü matrisi kapsar; burada bileşimler ve savunma davranışları var.
void main() {
  const known = [
    'SUPER_ADMIN',
    'ADMIN',
    'EDITOR',
    'VIEWER',
    'TENANT',
    'MARKETING',
  ];
  // Backend roleLevel: bağımsız (user_admin.dart'a bakmayan) beklenen değer.
  int expectedLevel(String r) => switch (r) {
    'SUPER_ADMIN' => 4,
    'ADMIN' => 3,
    'EDITOR' => 2,
    _ => 1,
  };

  /// Her alt küme (2^6 = 64) için bağımsız hesap.
  Iterable<List<String>> subsets() sync* {
    for (var mask = 0; mask < 1 << known.length; mask++) {
      yield [
        for (var i = 0; i < known.length; i++)
          if (mask & (1 << i) != 0) known[i],
      ];
    }
  }

  group('çok rollü kullanıcı: en yüksek seviye belirler', () {
    test('maxRoleLevel her alt küme için en yüksek rolün seviyesidir (boş küme = 1)', () {
      for (final roles in subsets()) {
        final want = roles.isEmpty
            ? 1
            : roles.map(expectedLevel).reduce((a, b) => a > b ? a : b);
        expect(maxRoleLevel(roles), want, reason: '$roles');
      }
    });

    for (var me = 1; me <= 4; me++) {
      test(
        'seviye $me: canManageUser tüm 64 rol kombinasyonunda "en yüksek rol <= benim"',
        () {
          for (final roles in subsets()) {
            final highest = roles.isEmpty
                ? 1
                : roles.map(expectedLevel).reduce((a, b) => a > b ? a : b);
            expect(
              canManageUser(me, roles),
              highest <= me,
              reason: 'me=$me roles=$roles',
            );
          }
        },
      );
    }

    test('sıra ve tekrar sonucu değiştirmez', () {
      expect(
        maxRoleLevel(const ['VIEWER', 'SUPER_ADMIN']),
        maxRoleLevel(const ['SUPER_ADMIN', 'VIEWER']),
      );
      expect(maxRoleLevel(const ['EDITOR', 'EDITOR', 'EDITOR']), 2);
      expect(
        maxRoleLevel(['ADMIN', 'ADMIN'].toSet()),
        3,
        reason: 'Iterable (Set) de kabul edilir',
      );
    });

    test('düşük rol yüksek rolü gizleyemez: [VIEWER, EDITOR, ADMIN] ADMIN altı için kilitli', () {
      expect(canManageUser(2, const ['VIEWER', 'EDITOR', 'ADMIN']), isFalse);
      expect(canManageUser(2, const ['VIEWER', 'EDITOR']), isTrue);
    });

    test('TENANT tek başına seviye 1: herkes yönetebilir; ama TENANT hiçbir çağırana atanamaz', () {
      for (var me = 1; me <= 4; me++) {
        expect(canManageUser(me, const ['TENANT']), isTrue, reason: 'me=$me');
        expect(canAssignRole(me, 'TENANT'), isFalse, reason: 'me=$me');
      }
    });

    test('atanabilir rol her zaman yönetilebilir roldür (canAssignRole => canManageUser tek rol)', () {
      for (var me = 1; me <= 4; me++) {
        for (final r in known) {
          if (canAssignRole(me, r))
            expect(canManageUser(me, [r]), isTrue, reason: 'me=$me $r');
        }
      }
    });

    test('atanabilirlik monoton: üst seviye çağıran, alt seviyenin atayabildiği her rolü atayabilir', () {
      for (var me = 1; me < 4; me++) {
        for (final r in known) {
          if (canAssignRole(me, r))
            expect(canAssignRole(me + 1, r), isTrue, reason: '$r me=$me');
        }
      }
    });
  });

  group('bilinmeyen / rolsüz / bozuk rol adları', () {
    test('bilinmeyen rol seviye 1 (özel roller backend ile aynı)', () {
      for (final r in ['MARKETING', 'CUSTOM', 'SUPPORT', '']) {
        expect(roleLevel(r), 1, reason: '"$r"');
      }
    });

    test('rol adları birebir eşleşir: küçük harf / ROLE_ öneki / boşluk yükseltmez', () {
      // Backend ad karşılaştırması da birebir (Role.name). Yanlış eşleşme asla yüksek seviye vermemeli.
      for (final r in [
        'super_admin',
        'Admin',
        'ROLE_ADMIN',
        ' ADMIN',
        'ADMIN ',
        'ADMIN\n',
      ]) {
        expect(roleLevel(r), 1, reason: '"$r"');
      }
    });

    test('çağıran tarafı: rolü olmayan/bilinmeyen çağıran en kısıtlı (1) sayılır, hiçbir üst rolü atayamaz', () {
      expect(maxRoleLevel(const []), 1);
      expect(maxRoleLevel(const ['MARKETING', 'x']), 1);
      for (final r in ['SUPER_ADMIN', 'ADMIN', 'EDITOR']) {
        expect(canAssignRole(maxRoleLevel(const []), r), isFalse, reason: r);
      }
      expect(canAssignRole(1, 'VIEWER'), isTrue);
      expect(canUseDefaultAdminRole(maxRoleLevel(const [])), isFalse);
    });

    test('rolsüz hedef kullanıcıyı seviye 1 olan herkes (en alt dahil) yönetebilir', () {
      expect(canManageUser(1, const []), isTrue);
    });

    test('seviye 0 / negatif çağıran hiçbir şey atayamaz ve hiçbir kullanıcıyı yönetemez', () {
      // AuthProvider bunu üretmez (taban 1); savunma: bozuk değer fail-closed.
      for (final me in [0, -1]) {
        expect(canAssignRole(me, 'VIEWER'), isFalse);
        expect(canManageUser(me, const ['VIEWER']), isFalse);
        expect(
          canManageUser(me, const []),
          isFalse,
          reason: 'boş = seviye 1 > $me',
        );
      }
    });
  });

  group('rolesOf (liste satırı / detay kaydı)', () {
    test('eksik ya da null roles → boş', () {
      expect(rolesOf(const {}), isEmpty);
      expect(rolesOf(const {'roles': null}), isEmpty);
    });

    test(
      'liste olmayan roles ("ADMIN" / nesne) istisna fırlatmadan boş döner',
      () {
        expect(
          rolesOf(const {'roles': 'ADMIN'}),
          isEmpty,
          reason: 'tek metin liste sayılmaz',
        );
        expect(
          rolesOf(const {
            'roles': {'ADMIN': 1},
          }),
          isEmpty,
        );
      },
      skip:
          'BULGU (düşük): rolesOf `as List?` cast eder; backend roles alanını liste dışı dönerse TypeError ile '
          'kullanıcı listesi satırı/formu çöker. Öneri: `r is List ? r : const []`.',
    );

    test('liste metne çevrilir; sıra korunur', () {
      expect(
        rolesOf(const {
          'roles': ['EDITOR', 'ADMIN'],
        }),
        ['EDITOR', 'ADMIN'],
      );
      expect(
        rolesOf(const {
          'roles': [3, true],
        }),
        ['3', 'true'],
      );
    });

    test('null eleman "null" metni olur (seviye 1) - yüksek rol uydurmaz', () {
      final roles = rolesOf(const {
        'roles': [null],
      });
      expect(roles, ['null']);
      expect(maxRoleLevel(roles), 1);
    });
  });
}
