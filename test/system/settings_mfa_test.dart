import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/account/mfa_setup_screen.dart';
import 'package:elly_mobile_app/screens/account/settings_screen.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

const _secret = 'JBSWY3DPEHPK3PXP';
const _uri = 'otpauth://totp/Elly+CMS%3Aben?secret=$_secret&issuer=Elly+CMS&algorithm=SHA1&digits=6&period=30';

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late bool mfaEnabled;
  late List<Uri> launched;
  late bool launchResult;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    mfaEnabled = false;
    launched = [];
    launchResult = true;
    backend.routes['/auth/mfa/status'] = (_) => okData({'mfaEnabled': mfaEnabled});
    backend.ok('/auth/mfa/setup', {'secret': _secret, 'qrUri': _uri, 'issuer': 'Elly CMS'});
    backend.routes['/auth/mfa/setup/verify'] = (req) {
      if ((jsonDecode(req.body) as Map)['code'] != '123456') {
        return jsonResponse({'message': 'Geçersiz doğrulama kodu. Authenticator uygulamanızı kontrol edin.'}, 401);
      }
      mfaEnabled = true;
      return okData('2FA başarıyla etkinleştirildi.');
    };
    backend.routes['/auth/mfa/disable'] = (req) {
      if ((jsonDecode(req.body) as Map)['password'] != 'Dogru123') {
        return jsonResponse({'message': 'Şifre hatalı.'}, 401);
      }
      mfaEnabled = false;
      return okData('ok');
    };
    backend.ok('/auth/refresh', {'token': 'yeni', 'refreshToken': 'r2'});
    backend.routes['/storage/tenant/t1/quota'] = (_) =>
        okData({'tenantId': 't1', 'usedBytes': 1024, 'limitBytes': 1073741824, 'usedPercent': 0.0});
    backend.routes['/storage/tenant/t1/quota/limit'] = (req) => okData({
      'tenantId': 't1',
      'usedBytes': 1024,
      'limitBytes': (jsonDecode(req.body) as Map)['limitBytes'],
      'usedPercent': 0.0,
    });
    backend.routes['/storage/tenant/t1/quota/recompute'] = (_) =>
        okData({'tenantId': 't1', 'usedBytes': 2048, 'limitBytes': 1073741824, 'usedPercent': 0.0});
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(WidgetTester tester, {List<String> roles = const ['ADMIN']}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      backend.permissions(const ['posts:read'], roles: roles);
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'refreshToken': 'r', 'tenantId': 't1'});
      await auth.checkAuthStatus();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: appTheme,
          home: SettingsScreen(
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
  String secretText(WidgetTester tester) => tester.widget<Text>(key('mfa_secret_text')).data!;

  Future<void> openSetup(WidgetTester tester) async {
    await pumpSettings(tester);
    await tester.tap(key('mfa_enable'));
    await settle(tester);
    expect(find.byType(MfaSetupScreen), findsOneWidget);
  }

  group('2FA setup', () {
    testWidgets('status "Kapalı" → "Etkinleştir" opens setup (GET /auth/mfa/setup with the session)', (tester) async {
      await pumpSettings(tester);
      expect(find.descendant(of: key('mfa_status'), matching: find.text('Kapalı')), findsOneWidget);
      expect(key('mfa_disable'), findsNothing);
      await tester.tap(key('mfa_enable'));
      await settle(tester);
      final setup = backend.requestsTo('/auth/mfa/setup').single;
      expect(setup.headers['Authorization'], 'Bearer a');
    });

    testWidgets('secret is masked by default; "göster" reveals it grouped; app in background masks again', (
      tester,
    ) async {
      await openSetup(tester);
      expect(secretText(tester), '•••• •••• •••• ••••');
      expect(find.textContaining(_secret), findsNothing);

      await tester.tap(key('mfa_secret_toggle'));
      await tester.pump();
      expect(secretText(tester), 'JBSW Y3DP EHPK 3PXP');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(secretText(tester), '•••• •••• •••• ••••');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('copy puts the plain secret on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await openSetup(tester);
      await tester.tap(key('mfa_secret_copy'));
      await tester.pump();
      expect(copied, _secret);
    });

    testWidgets('"Authenticator\'da aç" launches the backend otpauth URI; failure tells to copy', (tester) async {
      await openSetup(tester);
      await tester.tap(key('mfa_open_authenticator'));
      await tester.pump();
      expect(launched.single.toString(), _uri);

      launchResult = false;
      await tester.tap(key('mfa_open_authenticator'));
      await tester.pump();
      expect(find.textContaining('Authenticator uygulaması açılamadı'), findsOneWidget);
    });

    testWidgets('an otpauth URI for another secret is not offered (manual entry only)', (tester) async {
      backend.ok('/auth/mfa/setup', {
        'secret': _secret,
        'qrUri': 'otpauth://totp/x?secret=BASKA',
        'issuer': 'Elly CMS',
      });
      await openSetup(tester);
      expect(key('mfa_open_authenticator'), findsNothing);
      expect(key('mfa_secret_text'), findsOneWidget);
    });

    testWidgets('code must be 6 digits before any request', (tester) async {
      await openSetup(tester);
      await tester.enterText(key('mfa_setup_code'), '12a45');
      await tester.tap(key('mfa_verify_button'));
      await settle(tester);
      expect(backend.requestsTo('/auth/mfa/setup/verify'), isEmpty);
      expect(find.text('6 haneli kodu girin'), findsOneWidget);
    });

    testWidgets('wrong code (401): inline backend message, still signed in, Bearer sent', (tester) async {
      await openSetup(tester);
      await tester.enterText(key('mfa_setup_code'), '000000');
      await tester.tap(key('mfa_verify_button'));
      await settle(tester);
      expect(find.textContaining('Geçersiz doğrulama kodu'), findsOneWidget);
      expect(auth.isAuthenticated, isTrue, reason: 'a wrong code must not end the session');
      expect(find.byType(MfaSetupScreen), findsOneWidget);
      expect(backend.requestsTo('/auth/mfa/setup/verify').first.headers['Authorization'], 'Bearer a');
    });

    testWidgets('correct code: POST {code}, back to settings with status "Aktif"', (tester) async {
      await openSetup(tester);
      await tester.enterText(key('mfa_setup_code'), '123456');
      await tester.tap(key('mfa_verify_button'));
      await settle(tester);
      await settle(tester); // status reload after the pop
      expect(jsonDecode(backend.requestsTo('/auth/mfa/setup/verify').single.body), {'code': '123456'});
      expect(find.byType(MfaSetupScreen), findsNothing);
      expect(find.descendant(of: key('mfa_status'), matching: find.text('Aktif')), findsOneWidget);
      expect(key('mfa_disable'), findsOneWidget);
    });

    testWidgets('leaving before verifying asks first', (tester) async {
      await openSetup(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2FA kurulumu tamamlanmadı'), findsOneWidget);
      await tester.tap(find.text('Kal'));
      await tester.pumpAndSettle();
      expect(find.byType(MfaSetupScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(key('confirm_leave_button'));
      await settle(tester);
      expect(find.byType(MfaSetupScreen), findsNothing);
    });
  });

  group('2FA disable', () {
    testWidgets('wrong password: error in the dialog, session kept; right password disables', (tester) async {
      mfaEnabled = true;
      await pumpSettings(tester);
      await tester.tap(key('mfa_disable'));
      await tester.pumpAndSettle();

      await tester.tap(key('mfa_disable_confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Şifrenizi girin'), findsOneWidget);
      expect(backend.requestsTo('/auth/mfa/disable'), isEmpty);

      await tester.enterText(key('mfa_disable_password'), 'yanlis');
      await tester.tap(key('mfa_disable_confirm'));
      await settle(tester);
      expect(find.text('Şifre hatalı.'), findsOneWidget);
      expect(auth.isAuthenticated, isTrue);

      await tester.enterText(key('mfa_disable_password'), 'Dogru123');
      await tester.tap(key('mfa_disable_confirm'));
      await settle(tester);
      await settle(tester); // status reload
      expect(jsonDecode(backend.requestsTo('/auth/mfa/disable').last.body), {'password': 'Dogru123'});
      expect(find.text('2FA devre dışı bırakıldı'), findsOneWidget);
      expect(find.descendant(of: key('mfa_status'), matching: find.text('Kapalı')), findsOneWidget);
    });
  });

  group('storage quota (settings)', () {
    testWidgets('non SUPER_ADMIN: read-only note, no limit controls', (tester) async {
      await pumpSettings(tester);
      expect(key('storage_readonly_note'), findsOneWidget);
      expect(key('storage_limit_field'), findsNothing);
    });

    testWidgets('SUPER_ADMIN: limit in GB → PUT …/limit {limitBytes}; recompute → POST', (tester) async {
      await pumpSettings(tester, roles: ['SUPER_ADMIN']);
      expect(tester.widget<TextField>(key('storage_limit_field')).controller!.text, '1');
      await tester.enterText(key('storage_limit_field'), '2,5');
      await tester.tap(key('storage_limit_save'));
      await settle(tester);
      await settle(tester);
      final put = backend.requestsTo('/storage/tenant/t1/quota/limit').single;
      expect(put.method, 'PUT');
      expect(jsonDecode(put.body), {'limitBytes': 2684354560});
      expect(find.text('Limit güncellendi'), findsOneWidget);

      await tester.tap(key('storage_recompute'));
      await settle(tester);
      expect(backend.requestsTo('/storage/tenant/t1/quota/recompute').single.method, 'POST');
    });

    testWidgets('invalid limit is refused locally', (tester) async {
      await pumpSettings(tester, roles: ['SUPER_ADMIN']);
      await tester.enterText(key('storage_limit_field'), '0');
      await tester.tap(key('storage_limit_save'));
      await settle(tester);
      expect(backend.requestsTo('/quota/limit'), isEmpty);
      expect(find.text('Geçerli bir limit (GB) girin'), findsOneWidget);
    });
  });

  group('ApiService /auth/* rules', () {
    test('2FA management sends the session; login / refresh / 2FA login step do not', () {
      for (final e in ['/auth/login', '/auth/refresh', '/auth/mfa/verify']) {
        expect(ApiService.isPublicAuthEndpoint(e), isTrue, reason: e);
      }
      for (final e in [
        '/auth/mfa/status',
        '/auth/mfa/setup',
        '/auth/mfa/setup/verify',
        '/auth/mfa/disable',
        '/users',
      ]) {
        expect(ApiService.isPublicAuthEndpoint(e), isFalse, reason: e);
      }
    });

    test('/auth/mfa/verify (login step) and /auth/login go without Bearer and never refresh on 401', () async {
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'refreshToken': 'r'});
      backend.routes['/auth/mfa/verify'] = (_) => jsonResponse({'message': 'Kod geçersiz'}, 401);
      await expectLater(
        backend.api.post('/auth/mfa/verify', {'mfaToken': 'm', 'code': '1'}),
        throwsA(isA<ApiException>()),
      );
      expect(backend.requestsTo('/auth/mfa/verify').single.headers.containsKey('Authorization'), isFalse);
      expect(backend.requestsTo('/auth/refresh'), isEmpty);
    });

    test('wrong 2FA code: refresh once, retry, then the backend message (no session expiry)', () async {
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'refreshToken': 'r'});
      var expired = false;
      ApiService.onSessionExpired = () => expired = true;
      addTearDown(() => ApiService.onSessionExpired = null);
      await expectLater(
        backend.api.post('/auth/mfa/setup/verify', {'code': '000000'}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Geçersiz doğrulama kodu'))),
      );
      expect(backend.requestsTo('/auth/refresh'), hasLength(1));
      expect(backend.requestsTo('/auth/mfa/setup/verify'), hasLength(2));
      expect(backend.requestsTo('/auth/mfa/setup/verify').last.headers['Authorization'], 'Bearer yeni');
      expect(expired, isFalse);
    });
  });
}
