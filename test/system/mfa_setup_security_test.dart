import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/account/mfa_setup_screen.dart';
import 'package:elly_mobile_app/services/user_admin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

const _secret = 'JBSWY3DPEHPK3PXP';
const _groups = ['JBSW', 'Y3DP', 'EHPK', '3PXP'];
const _masked = '•••• •••• •••• ••••';

String _uri({
  String label = 'Elly+CMS%3Aben',
  String? secret,
  String extra = '',
}) =>
    'otpauth://totp/$label?secret=${secret ?? _secret}&issuer=Elly+CMS&algorithm=SHA1&digits=6&period=30$extra';

void main() {
  group('isValidOtpauthUri (backend TotpService.buildQrUri biçimi)', () {
    test(
      'standart URI geçerli; şema/host büyük-küçük harf duyarsız (RFC 3986)',
      () {
        expect(isValidOtpauthUri(_uri(), _secret), isTrue);
        expect(
          isValidOtpauthUri(
            _uri().replaceFirst('otpauth://totp', 'OTPAUTH://TOTP'),
            _secret,
          ),
          isTrue,
        );
      },
    );

    test(
      'etiket/issuer kodlamaları: boşluk, +, %3A, Türkçe harf, @ ve parantez',
      () {
        for (final label in [
          'Elly+CMS%3Aben',
          'Elly%20CMS%3Aben',
          'Elly%20CMS:ben%40site.com',
          'Elly%20CMS%3A%C3%9C%C5%9Fenmez',
          'Elly(Prod)%3Aben',
          'ben',
        ]) {
          expect(
            isValidOtpauthUri(_uri(label: label), _secret),
            isTrue,
            reason: label,
          );
        }
      },
    );

    test('secret yüzde-kodlu gelse de çözülmüş değeri aynıysa geçerli; harf büyüklüğü farkı geçersiz', () {
      expect(
        isValidOtpauthUri(
          'otpauth://totp/E:a?secret=JBSWY3DP%45HPK3PXP',
          _secret,
        ),
        isTrue,
      );
      expect(
        isValidOtpauthUri(_uri(secret: _secret.toLowerCase()), _secret),
        isFalse,
      );
    });

    test('yabancı şema / host / HOTP / migration bağlantıları açılmaz', () {
      for (final bad in [
        'https://evil.example/totp/x?secret=$_secret',
        'http://totp/x?secret=$_secret',
        'javascript:alert(1)',
        'tel:+900000000000',
        'file:///etc/passwd',
        'intent://totp/x?secret=$_secret#Intent;scheme=otpauth;end',
        'otpauth://hotp/E:a?secret=$_secret&counter=1',
        'otpauth://evil.example/x?secret=$_secret',
        'otpauth://totp.evil.example/E:a?secret=$_secret',
        'otpauth-migration://offline?data=$_secret',
        'otpauth:totp/E:a?secret=$_secret',
        'otpauth:///totp/E:a?secret=$_secret',
      ]) {
        expect(isValidOtpauthUri(bad, _secret), isFalse, reason: bad);
      }
    });

    test('etiket yok, secret yok/boş/farklı/kısmi; baştaki-sondaki boşluk ya da satır sonu → açılmaz', () {
      for (final bad in [
        'otpauth://totp/?secret=$_secret',
        'otpauth://totp/E:a',
        'otpauth://totp/E:a?secret=',
        'otpauth://totp/E:a?secret=${_secret}X',
        'otpauth://totp/E:a?secret=${_secret.substring(0, 8)}',
        'otpauth://totp/E:a?secret=BASKA',
        'otpauth://totp/E:a?other=$_secret',
        ' ${_uri()}',
        '',
      ]) {
        expect(isValidOtpauthUri(bad, _secret), isFalse, reason: bad);
      }
    });

    test('secret\'ı boş olan kurulum hiçbir URI ile açılmaz', () {
      expect(isValidOtpauthUri('otpauth://totp/E:a?secret=', ''), isFalse);
      expect(isValidOtpauthUri(_uri(), ''), isFalse);
    });

    test(
      'yinelenen secret parametresinde ilk değer authenticator\'ın gördüğüdür: ikisi de eşleşmeli',
      () {
        // Dart queryParameters SON değeri alır; bazı authenticator uygulamaları İLKİNİ okur.
        expect(
          isValidOtpauthUri(_uri(extra: '&secret=$_secret'), _secret),
          isTrue,
          reason: 'ikisi de aynı → sorun yok',
        );
        expect(
          isValidOtpauthUri(
            'otpauth://totp/E:a?secret=$_secret&secret=BASKA',
            _secret,
          ),
          isFalse,
        );
        expect(
          isValidOtpauthUri(
            'otpauth://totp/E:a?secret=BASKA&secret=$_secret',
            _secret,
          ),
          isFalse,
          reason: 'yinelenen secret: URI doğrulayıcı ve authenticator farklı anahtar görebilir',
        );
      },
    );

    test(
      'beklenmeyen parametre / host bileşeni (image, port, userinfo) reddedilir',
      () {
        for (final bad in [
          _uri(extra: '&image=https://evil.example/logo.png'),
          _uri(extra: '&callback=https://evil.example'),
          _uri().replaceFirst('otpauth://totp', 'otpauth://totp:8080'),
          _uri().replaceFirst('otpauth://totp', 'otpauth://evil@totp'),
          _uri().replaceFirst('digits=6', 'digits=8'),
          _uri().replaceFirst('period=30', 'period=0'),
          _uri().replaceFirst('algorithm=SHA1', 'algorithm=MD5'),
          '${_uri()}#fragment',
        ]) {
          expect(isValidOtpauthUri(bad, _secret), isFalse, reason: bad);
        }
      },
    );

    test(
      'secret base32 alfabesinde değilse bağlantı açılmaz (elle girişe düşer)',
      () {
        for (final bad in [
          'abc!def',
          'JBSWY3DP\$HPK3PXP',
          'JBSWY3DP0189HPK3',
          'JBSW Y3DP',
        ]) {
          expect(
            isValidOtpauthUri(
              'otpauth://totp/E:a?secret=${Uri.encodeQueryComponent(bad)}',
              bad,
            ),
            isFalse,
            reason: bad,
          );
        }
      },
    );
  });

  group('formatSecret', () {
    test('boş, 4\'ün katı olmayan ve tek karakter', () {
      expect(formatSecret(''), '');
      expect(formatSecret('A'), 'A');
      expect(formatSecret('ABCDE'), 'ABCD E');
      expect(formatSecret('ABCDEFGH'), 'ABCD EFGH');
    });

    test(
      'maskeli: aynı uzunluk ve gruplama, hiçbir secret karakteri sızmaz',
      () {
        for (final s in ['', 'A', 'ABCDE', _secret, 'A' * 52]) {
          final m = formatSecret(s, masked: true);
          expect(m.replaceAll(' ', '').replaceAll('•', ''), isEmpty, reason: s);
          expect(m.replaceAll(' ', '').length, s.length, reason: s);
          expect(
            m,
            formatSecret(s).replaceAll(RegExp('[^ ]'), '•'),
            reason: 'gruplama aynı',
          );
        }
      },
    );
  });

  group('MfaSetupScreen', () {
    late FakeBackend backend;
    late AuthProvider auth;
    late List<Uri> launched;
    late bool launchResult;
    late List<String> clipboard;

    setUp(() {
      backend = FakeBackend();
      auth = backend.newAuth();
      launched = [];
      launchResult = true;
      clipboard = [];
      backend.ok('/auth/mfa/setup', {
        'secret': _secret,
        'qrUri': _uri(),
        'issuer': 'Elly CMS',
      });
      backend.routes['/auth/mfa/setup/verify'] = (req) =>
          (jsonDecode(req.body) as Map)['code'] == '123456'
          ? okData('ok')
          : jsonResponse({'message': 'Geçersiz doğrulama kodu.'}, 401);
      backend.ok('/auth/refresh', {'token': 'yeni', 'refreshToken': 'r2'});
    });

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpSetup(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            clipboard.add((call.arguments as Map)['text'] as String);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      FlutterSecureStorage.setMockInitialValues({
        'accessToken': 'a',
        'refreshToken': 'r',
        'tenantId': 't1',
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            theme: appTheme,
            home: MfaSetupScreen(
              apiService: backend.api,
              launcher: (uri) async {
                launched.add(uri);
                return launchResult;
              },
            ),
          ),
        ),
      );
      await settle(tester);
    }

    Finder key(String k) => find.byKey(ValueKey(k));

    /// Geçerli yaşam döngüsü geçişleri: resumed → inactive → hidden → paused ve dönüş.
    Future<void> background(
      WidgetTester tester,
      AppLifecycleState target,
    ) async {
      const down = [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ];
      for (final s in down) {
        tester.binding.handleAppLifecycleStateChanged(s);
        if (s == target) break;
      }
      await tester.pump();
    }

    Future<void> foreground(WidgetTester tester) async {
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pump();
    }

    String secretText(WidgetTester tester) =>
        tester.widget<Text>(key('mfa_secret_text')).data!;

    /// Ekrandaki tüm metinler (Text, TextField içeriği, SnackBar, hata).
    List<String> allTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(
        find.byType(Text, skipOffstage: false),
      ))
        if (t.data != null)
          t.data!
        else if (t.textSpan != null)
          t.textSpan!.toPlainText(),
      for (final e in tester.widgetList<EditableText>(
        find.byType(EditableText, skipOffstage: false),
      ))
        e.controller.text,
    ];

    bool leaks(Iterable<String> texts) => texts.any(
      (t) => t.contains(_secret) || _groups.any((g) => t.contains(g)),
    );

    group('maskeleme', () {
      testWidgets(
        'varsayılan maskeli: ekrandaki hiçbir metinde secret ya da 4\'lü grupları yok',
        (tester) async {
          await pumpSetup(tester);
          expect(secretText(tester), _masked);
          expect(leaks(allTexts(tester)), isFalse);
        },
      );

      testWidgets('göster → gruplu secret; gizle → yeniden maskeli', (
        tester,
      ) async {
        await pumpSetup(tester);
        await tester.tap(key('mfa_secret_toggle'));
        await tester.pump();
        expect(secretText(tester), _groups.join(' '));
        await tester.tap(key('mfa_secret_toggle'));
        await tester.pump();
        expect(secretText(tester), _masked);
      });

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        testWidgets(
          'açıkken uygulama $state olunca yeniden maskelenir; geri dönünce kendiliğinden açılmaz',
          (tester) async {
            await pumpSetup(tester);
            await tester.tap(key('mfa_secret_toggle'));
            await tester.pump();
            expect(secretText(tester), isNot(_masked));

            await background(tester, state);
            expect(secretText(tester), _masked);
            await foreground(tester);
            expect(
              secretText(tester),
              _masked,
              reason: 'resumed secret\'ı geri açmamalı',
            );

            await tester.tap(key('mfa_secret_toggle'));
            await tester.pump();
            expect(
              secretText(tester),
              _groups.join(' '),
              reason: 'kullanıcı yine açabilir',
            );
          },
        );
      }

      testWidgets(
        'maskeliyken arka plana gidip gelmek durumu değiştirmez (zaten maskeli)',
        (tester) async {
          await pumpSetup(tester);
          await background(tester, AppLifecycleState.paused);
          await foreground(tester);
          expect(secretText(tester), _masked);
        },
      );

      testWidgets(
        'erişilebilirlik ağacı: maskeliyken secret yok ("Gizli anahtar gizlendi"), açıkken okunur',
        (tester) async {
          final handle = tester.ensureSemantics();
          await pumpSetup(tester);
          var node = tester.getSemantics(key('mfa_secret_text'));
          expect(node.label, contains('Gizli anahtar gizlendi'));
          expect(
            node.label.contains('•'),
            isFalse,
            reason: 'ekran okuyucu 16 kez "madde" okumasın',
          );
          expect(node.label.contains('JBSW'), isFalse);

          await tester.tap(key('mfa_secret_toggle'));
          await tester.pump();
          node = tester.getSemantics(key('mfa_secret_text'));
          expect(node.label, _groups.join(' '));
          handle.dispose();
        },
      );

      testWidgets(
        'arka plana gidince (maskelenmiş) tüm semantik etiketlerde secret yok',
        (tester) async {
          final handle = tester.ensureSemantics();
          await pumpSetup(tester);
          await tester.tap(key('mfa_secret_toggle'));
          await tester.pump();
          await background(tester, AppLifecycleState.paused);
          expect(leaks(allTexts(tester)), isFalse);
          final semantics = tester
              .getSemantics(find.byType(Scaffold).first)
              .getSemanticsData();
          expect(semantics.label.contains(_secret), isFalse);
          await foreground(tester);
          handle.dispose();
        },
      );

      testWidgets(
        'hata sonrası yeniden deneme yeni secret\'ı da maskeli getirir',
        (tester) async {
          var calls = 0;
          backend.routes['/auth/mfa/setup'] = (_) {
            calls++;
            return calls == 1
                ? jsonResponse({'message': 'Sunucu meşgul'}, 503)
                : okData({'secret': _secret, 'qrUri': _uri()});
          };
          await pumpSetup(tester);
          expect(key('mfa_secret_text'), findsNothing);
          expect(find.textContaining('Sunucu meşgul'), findsOneWidget);
          await tester.tap(find.text('Tekrar Dene'));
          await settle(tester);
          expect(secretText(tester), _masked);
        },
      );
    });

    group('secret hiçbir mesajda görünmez', () {
      testWidgets(
        'kopyalama: pano düz secret alır, SnackBar metni secret içermez',
        (tester) async {
          await pumpSetup(tester);
          await tester.tap(key('mfa_secret_copy'));
          await tester.pump();
          expect(clipboard, [_secret]);
          final bar = find.byType(SnackBar);
          expect(bar, findsOneWidget);
          expect(
            leaks(
              tester
                  .widgetList<Text>(
                    find.descendant(of: bar, matching: find.byType(Text)),
                  )
                  .map((t) => t.data ?? ''),
            ),
            isFalse,
          );
          expect(
            leaks(allTexts(tester)),
            isFalse,
            reason: 'kopyalama ekrandaki maskeyi açmaz',
          );
        },
      );

      testWidgets(
        'Authenticator açılamadı SnackBar\'ı secret ya da URI içermez',
        (tester) async {
          launchResult = false;
          await pumpSetup(tester);
          await tester.tap(key('mfa_open_authenticator'));
          await tester.pump();
          expect(
            find.textContaining('Authenticator uygulaması açılamadı'),
            findsOneWidget,
          );
          expect(leaks(allTexts(tester)), isFalse);
          expect(allTexts(tester).any((t) => t.contains('otpauth')), isFalse);
        },
      );

      testWidgets(
        'yanlış kod (401): satır içi mesaj backend\'inki, secret içermez; doğrulama gövdesi yalnız {code}',
        (tester) async {
          await pumpSetup(tester);
          await tester.enterText(key('mfa_setup_code'), '000000');
          await tester.tap(key('mfa_verify_button'));
          await settle(tester);
          expect(find.text('Geçersiz doğrulama kodu.'), findsOneWidget);
          expect(leaks(allTexts(tester)), isFalse);
          for (final r in backend.requestsTo('/auth/mfa/setup/verify')) {
            expect(jsonDecode(r.body), {
              'code': '000000',
            }, reason: 'secret sunucuya geri gönderilmez');
            expect(r.url.toString().contains(_secret), isFalse);
          }
          expect(
            backend.requestsTo('/auth/mfa/setup'),
            hasLength(1),
            reason: 'yanlış kod yeni secret üretmez',
          );
        },
      );

      testWidgets(
        'sunucu hatası (500, gövdesiz) ve ağ hatası: genel mesaj, secret yok',
        (tester) async {
          backend.routes['/auth/mfa/setup/verify'] = (_) =>
              http.Response('', 500);
          await pumpSetup(tester);
          await tester.enterText(key('mfa_setup_code'), '123456');
          await tester.tap(key('mfa_verify_button'));
          await settle(tester);
          expect(find.textContaining('Sunucu hatası (500)'), findsOneWidget);
          expect(leaks(allTexts(tester)), isFalse);
        },
      );

      testWidgets(
        'yükleme hatası ekranı secret göstermez; boş secret "Kurulum anahtarı alınamadı" olur',
        (tester) async {
          backend.ok('/auth/mfa/setup', {'secret': '', 'qrUri': _uri()});
          await pumpSetup(tester);
          expect(
            find.textContaining('Kurulum anahtarı alınamadı'),
            findsOneWidget,
          );
          expect(key('mfa_secret_text'), findsNothing);
          expect(key('mfa_open_authenticator'), findsNothing);
          expect(leaks(allTexts(tester)), isFalse);
        },
      );

      testWidgets(
        'doğrulama kodu alanı secret taşımaz; yalnız rakam, en çok 6 hane',
        (tester) async {
          await pumpSetup(tester);
          await tester.enterText(key('mfa_setup_code'), 'ab12-34 5678');
          await tester.pump();
          expect(
            tester
                .widget<TextFormField>(key('mfa_setup_code'))
                .controller!
                .text,
            '123456',
          );
        },
      );
    });

    group('otpauth bağlantısı', () {
      Future<void> withUri(WidgetTester tester, Object? qrUri) async {
        backend.ok('/auth/mfa/setup', {
          'secret': _secret,
          'qrUri': qrUri,
          'issuer': 'Elly CMS',
        });
        await pumpSetup(tester);
      }

      for (final bad in <Object?>[
        null,
        '',
        'https://evil.example/?secret=$_secret',
        'javascript:alert(1)',
        'otpauth://hotp/E:a?secret=$_secret',
        'otpauth://evil.example/E:a?secret=$_secret',
        'otpauth://totp/E:a?secret=BASKA',
        'otpauth-migration://offline?data=x',
      ]) {
        testWidgets(
          'qrUri=${bad is String && bad.length > 40 ? '${bad.substring(0, 40)}…' : bad}: "Authenticator\'da aç" yok, '
          'elle giriş var',
          (tester) async {
            await withUri(tester, bad);
            expect(key('mfa_open_authenticator'), findsNothing);
            expect(key('mfa_secret_text'), findsOneWidget);
            expect(find.textContaining('elle girin'), findsOneWidget);
            expect(launched, isEmpty);
          },
        );
      }

      testWidgets(
        'geçerli URI: buton var, açılan Uri backend\'inkiyle birebir aynı ve yalnız kullanıcı dokununca',
        (tester) async {
          await pumpSetup(tester);
          expect(
            launched,
            isEmpty,
            reason: 'ekran açılırken otomatik başlatma yok',
          );
          await tester.tap(key('mfa_open_authenticator'));
          await tester.pump();
          expect(launched.single.toString(), _uri());
          expect(launched.single.scheme, 'otpauth');
        },
      );
    });
  });
}
