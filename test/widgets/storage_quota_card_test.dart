import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/account/settings_screen.dart';
import 'package:elly_mobile_app/widgets/storage_quota_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

/// StorageQuotaCard: eşik renkleri/uyarı metinleri, SUPER_ADMIN (rol bazlı) limit + yeniden hesapla kapısı,
/// limit girdisi dönüşümü. `quotaColor` eşikleri dashboard_screen_test'te; burada kartın kendisi.
const _gib = 1024 * 1024 * 1024;

Map<String, dynamic> _quota({
  num percent = 10,
  num used = 100,
  num limit = _gib,
}) => {
  'tenantId': 't1',
  'usedBytes': used,
  'limitBytes': limit,
  'usedPercent': percent,
};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late Map<String, dynamic> quota;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    quota = _quota();
    backend.routes['/storage/tenant/t1/quota'] = (_) => okData(quota);
    backend.routes['/storage/tenant/t1/quota/limit'] = (req) {
      quota = {
        ...quota,
        'limitBytes': (jsonDecode(req.body) as Map)['limitBytes'],
      };
      return okData(quota);
    };
    backend.routes['/storage/tenant/t1/quota/recompute'] = (_) {
      quota = {...quota, 'usedBytes': 555};
      return okData(quota);
    };
    backend.ok('/storage/quota', _quota(percent: 5));
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    bool settings = false,
    bool canEditLimit = false,
    String? tenantId = 't1',
    VoidCallback? onManage,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({
      'accessToken': 'a',
      'tenantId': ?tenantId,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StorageQuotaCard(
              api: backend.api,
              settings: settings,
              canEditLimit: canEditLimit,
              onManage: onManage,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));
  Color percentColor(WidgetTester tester) =>
      tester.widget<Text>(key('storage_percent')).style!.color!;
  ColorScheme scheme() => appTheme.colorScheme;

  group('eşikler: yüzde metni, renk, uyarı', () {
    final cases = <(num, String, Color Function(), String?)>[
      (0, '%0,0', () => AppColors.success, null),
      (69.9, '%69,9', () => AppColors.success, null),
      (70, '%70,0', () => AppColors.warning, 'Kota dolmak üzere.'),
      (89.9, '%89,9', () => AppColors.warning, 'Kota dolmak üzere.'),
      (
        90,
        '%90,0',
        () => scheme().onErrorContainer,
        'Kota neredeyse dolu — yeni yüklemeler reddedilebilir.',
      ),
      (
        100,
        '%100,0',
        () => scheme().onErrorContainer,
        'Kota neredeyse dolu — yeni yüklemeler reddedilebilir.',
      ),
      (
        140,
        '%100,0',
        () => scheme().onErrorContainer,
        'Kota neredeyse dolu — yeni yüklemeler reddedilebilir.',
      ),
      (-5, '%0,0', () => AppColors.success, null),
    ];
    for (final (percent, text, color, warning) in cases) {
      testWidgets('usedPercent=$percent → $text', (tester) async {
        quota = _quota(percent: percent);
        await pumpCard(tester);
        expect(find.text(text), findsOneWidget);
        expect(percentColor(tester), color());
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .color,
          color(),
        );
        for (final w in [
          'Kota dolmak üzere.',
          'Kota neredeyse dolu — yeni yüklemeler reddedilebilir.',
        ]) {
          expect(
            find.text(w),
            w == warning ? findsOneWidget : findsNothing,
            reason: w,
          );
        }
      });
    }

    testWidgets('usedPercent yoksa/geçersizse 0 sayılır, kart çökmez', (
      tester,
    ) async {
      quota = {'tenantId': 't1', 'usedBytes': 1, 'limitBytes': 10};
      await pumpCard(tester);
      expect(find.text('%0,0'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
    });

    testWidgets(
      'kalan = limit - kullanılan; kullanım limiti aşarsa kalan 0 (negatif yazılmaz)',
      (tester) async {
        quota = _quota(percent: 120, used: 2 * _gib, limit: _gib);
        await pumpCard(tester);
        expect(find.text('0 B'), findsWidgets);
      },
    );
  });

  group('dashboard kartı (settings:false)', () {
    testWidgets(
      'canEditLimit true olsa da limit alanı ve salt-okunur not yok; Yönet butonu çalışır',
      (tester) async {
        var managed = 0;
        await pumpCard(tester, canEditLimit: true, onManage: () => managed++);
        expect(key('storage_limit_field'), findsNothing);
        expect(key('storage_recompute'), findsNothing);
        expect(key('storage_readonly_note'), findsNothing);
        await tester.tap(find.text('Yönet'));
        expect(managed, 1);
      },
    );

    testWidgets('onManage yoksa "Yönet" yok', (tester) async {
      await pumpCard(tester);
      expect(find.text('Yönet'), findsNothing);
    });
  });

  group('ayarlar kartı (settings:true)', () {
    testWidgets('canEditLimit=false: salt-okunur not, hiçbir yazma kontrolü', (
      tester,
    ) async {
      await pumpCard(tester, settings: true);
      expect(key('storage_readonly_note'), findsOneWidget);
      expect(key('storage_limit_field'), findsNothing);
      expect(key('storage_limit_save'), findsNothing);
      expect(key('storage_recompute'), findsNothing);
    });

    testWidgets(
      'canEditLimit=true: alan GB olarak dolu, kaydet + yeniden hesapla var, not yok',
      (tester) async {
        await pumpCard(tester, settings: true, canEditLimit: true);
        expect(
          tester.widget<TextField>(key('storage_limit_field')).controller!.text,
          '1',
        );
        expect(key('storage_limit_save'), findsOneWidget);
        expect(key('storage_recompute'), findsOneWidget);
        expect(key('storage_readonly_note'), findsNothing);
      },
    );

    testWidgets('oturum tenant\'ı yoksa /storage/quota kullanılır', (
      tester,
    ) async {
      await pumpCard(tester, tenantId: null);
      expect(backend.requestsTo('/storage/quota'), hasLength(1));
      expect(backend.requestsTo('/storage/tenant/'), isEmpty);
    });

    for (final (input, bytes) in [
      ('2', 2 * _gib),
      ('1,5', 1610612736),
      ('1.5', 1610612736),
      (' 3 ', 3 * _gib),
      ('.5', 536870912),
    ]) {
      testWidgets('limit "$input" GB → PUT limitBytes=$bytes', (tester) async {
        await pumpCard(tester, settings: true, canEditLimit: true);
        await tester.enterText(key('storage_limit_field'), input);
        await tester.tap(key('storage_limit_save'));
        await settle(tester);
        expect(jsonDecode(backend.requestsTo('/quota/limit').single.body), {
          'limitBytes': bytes,
        });
        expect(find.text('Limit güncellendi'), findsOneWidget);
      });
    }

    for (final input in ['', '0', '0,0', '.', ',', '1.2.3', '1,2,3']) {
      testWidgets('geçersiz limit "$input" yerelde reddedilir, istek yok', (
        tester,
      ) async {
        await pumpCard(tester, settings: true, canEditLimit: true);
        await tester.enterText(key('storage_limit_field'), input);
        await tester.tap(key('storage_limit_save'));
        await settle(tester);
        expect(backend.requestsTo('/quota/limit'), isEmpty);
        expect(find.text('Geçerli bir limit (GB) girin'), findsOneWidget);
      });
    }

    testWidgets(
      'yeniden hesapla: POST boş gövde, kullanılan değer güncellenir',
      (tester) async {
        await pumpCard(tester, settings: true, canEditLimit: true);
        await tester.tap(key('storage_recompute'));
        await settle(tester);
        final req = backend.requestsTo('/quota/recompute').single;
        expect(req.method, 'POST');
        expect(jsonDecode(req.body), isEmpty);
        expect(find.text('555 B'), findsOneWidget);
        expect(find.text('Kullanım yeniden hesaplandı'), findsOneWidget);
      },
    );

    testWidgets(
      'sunucu limit değişikliğini reddederse (403) hata gösterilir, değerler değişmez, kontroller açılır',
      (tester) async {
        backend.routes['/storage/tenant/t1/quota/limit'] = (_) =>
            jsonResponse({'message': 'Yetkisiz'}, 403);
        await pumpCard(tester, settings: true, canEditLimit: true);
        await tester.enterText(key('storage_limit_field'), '5');
        await tester.tap(key('storage_limit_save'));
        await settle(tester);
        expect(find.text('Yetkisiz'), findsOneWidget);
        expect(find.text('Limit güncellendi'), findsNothing);
        expect(
          tester.widget<ElevatedButton>(key('storage_limit_save')).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'yükleme hatası → "Tekrar Dene" ile yeniden istenir; hatada yazma kontrolü yok',
      (tester) async {
        var fail = true;
        backend.routes['/storage/tenant/t1/quota'] = (_) =>
            fail ? jsonResponse({'message': 'x'}, 500) : okData(quota);
        await pumpCard(tester, settings: true, canEditLimit: true);
        expect(find.text('Depolama bilgisi yüklenemedi.'), findsOneWidget);
        expect(key('storage_limit_field'), findsNothing);
        fail = false;
        await tester.tap(find.text('Tekrar Dene'));
        await settle(tester);
        expect(key('storage_limit_field'), findsOneWidget);
      },
    );
  });

  group('gbToBytes', () {
    test('ondalık virgül/nokta, boşluk; 1024³ çarpanı', () {
      expect(gbToBytes('1'), _gib);
      expect(gbToBytes('1,5'), 3 * _gib ~/ 2);
      expect(gbToBytes(' 2 '), 2 * _gib);
      expect(gbToBytes(',5'), _gib ~/ 2);
    });

    test('0, negatif, NaN, Infinity, boş, çoklu ayraç → null', () {
      for (final t in [
        '0',
        '-1',
        'NaN',
        'Infinity',
        '-Infinity',
        '',
        ' ',
        '1.2.3',
        'abc',
      ]) {
        expect(gbToBytes(t), isNull, reason: '"$t"');
      }
    });

    test(
      'bayta yuvarlanınca 0 olan çok küçük değer limit olarak gönderilmez',
      () {
        expect(gbToBytes('0.0000000001'), isNull);
      },
      skip:
          'BULGU (düşük, lib/widgets/storage_quota_card.dart gbToBytes): "0.0000000001" GB > 0 geçiyor ama '
          'yuvarlanınca 0 bayt oluyor -> PUT limitBytes=0 (tüm yüklemeler reddedilir). Öneri: sonucu `bytes > 0` ile '
          'doğrula (null döndür).',
    );

    test(
      'aşırı büyük sayı istisna fırlatmaz (null ya da sınırlanmış)',
      () {
        expect(() => gbToBytes('9' * 300), returnsNormally);
      },
      skip:
          'BULGU (düşük, lib/widgets/storage_quota_card.dart gbToBytes): 300 haneli giriş gb sonlu ama gb*1024³ '
          'Infinity -> round() "Unsupported operation: Infinity or NaN toInt" fırlatır; _setLimit yakalamaz '
          '(işlenmeyen istisna). Öneri: çarpım sonucunun isFinite kontrolü.',
    );
  });

  group('SettingsScreen: limit/yeniden hesapla yalnız SUPER_ADMIN rolünde (permission değil rol)', () {
    Future<void> pumpSettings(
      WidgetTester tester,
      List<String> roles, {
      List<String> permissions = const ['posts:read'],
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      backend.ok('/auth/mfa/status', {'mfaEnabled': false});
      await tester.runAsync(() async {
        backend.permissions(permissions, roles: roles);
        FlutterSecureStorage.setMockInitialValues({
          'accessToken': 'a',
          'tenantId': 't1',
        });
        await auth.checkAuthStatus();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            theme: appTheme,
            home: SettingsScreen(apiService: backend.api),
          ),
        ),
      );
      await settle(tester);
    }

    for (final (roles, editable) in <(List<String>, bool)>[
      (['SUPER_ADMIN'], true),
      (['ADMIN', 'SUPER_ADMIN'], true),
      (['EDITOR', 'VIEWER', 'SUPER_ADMIN'], true),
      (['ADMIN'], false),
      (['EDITOR'], false),
      (['VIEWER'], false),
      (['TENANT'], false),
      (<String>[], false),
      (['super_admin'], false),
      (['ROLE_SUPER_ADMIN'], false),
      (['SUPER_ADMIN_X'], false),
    ]) {
      testWidgets(
        'roller $roles → ${editable ? 'limit kontrolleri var' : 'salt-okunur not'}',
        (tester) async {
          await pumpSettings(tester, roles);
          expect(
            key('storage_limit_field'),
            editable ? findsOneWidget : findsNothing,
          );
          expect(
            key('storage_recompute'),
            editable ? findsOneWidget : findsNothing,
          );
          expect(
            key('storage_readonly_note'),
            editable ? findsNothing : findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'tüm permission\'lar olsa bile SUPER_ADMIN rolü yoksa kontrol yok (izin değil rol)',
      (tester) async {
        await pumpSettings(
          tester,
          ['ADMIN'],
          permissions: [
            'storage:update',
            'storage:manage',
            'users:manage',
            'rabbit:manage',
          ],
        );
        expect(key('storage_limit_field'), findsNothing);
        expect(key('storage_readonly_note'), findsOneWidget);
      },
    );

    testWidgets(
      'oturum sırasında SUPER_ADMIN rolü kalkarsa kontroller kendiliğinden kapanır',
      (tester) async {
        await pumpSettings(tester, ['SUPER_ADMIN']);
        expect(key('storage_limit_field'), findsOneWidget);
        await tester.runAsync(() async {
          backend.permissions(const ['posts:read'], roles: const ['ADMIN']);
          await auth.loadPermissions();
        });
        await tester.pumpAndSettle();
        expect(key('storage_limit_field'), findsNothing);
        expect(key('storage_readonly_note'), findsOneWidget);
      },
    );

    testWidgets(
      'izinler yüklenemediyse (roller bilinmiyor) kontroller açılmaz (fail-closed)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        backend.ok('/auth/mfa/status', {'mfaEnabled': false});
        backend.routes['/users/me/permissions'] = (_) =>
            jsonResponse({'message': 'x'}, 500);
        await tester.runAsync(() async {
          FlutterSecureStorage.setMockInitialValues({
            'accessToken': 'a',
            'tenantId': 't1',
          });
          await auth.checkAuthStatus();
        });
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: MaterialApp(
              theme: appTheme,
              home: SettingsScreen(apiService: backend.api),
            ),
          ),
        );
        await settle(tester);
        expect(key('storage_limit_field'), findsNothing);
        expect(key('storage_recompute'), findsNothing);
      },
    );
  });
}
