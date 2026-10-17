import 'dart:async';
import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/mail/email_logs_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_template_form_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_template_preview_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_templates_screen.dart';
import 'package:elly_mobile_app/screens/mail/mail_accounts_screen.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/safe_html.dart';
import 'package:elly_mobile_app/widgets/app_scaffold.dart';
import 'package:elly_mobile_app/widgets/save_bar.dart';
import 'package:elly_mobile_app/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _template(String key, {int lock = 1}) => {
  'id': 1,
  'tenantId': 't1',
  'templateKey': key,
  'subject': 'Konu',
  'htmlBody': '<p>x</p>',
  'description': null,
  'active': true,
  'optimisticLockVersion': lock,
};

Map<String, dynamic> _account(int id, {String? tenant}) => {
  'id': id,
  'name': 'Hesap $id',
  'fromAddress': 'h$id@example.invalid',
  'smtpHost': 'mail.example.invalid',
  'smtpPort': 587,
  'smtpUsername': 'u$id',
  'active': true,
  'tenantId': tenant,
  'isPrimary': false,
};

/// Phase 3 review fixes (UI): keyboard save, SMTP dialog lock/timeout, template create → list reload, editor
/// height, 409 refresh, PENDING retry confirmation, preview limits, labels and contrast.
void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, List<String> perms, Widget home, {Size size = const Size(1000, 2400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, perms));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  group('AppScaffold + SaveBar', () {
    Widget scaffold({required double keyboard, VoidCallback? onSave, bool loading = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 400),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: AppScaffold(
          title: 'Form',
          body: const SizedBox(),
          bottomNavigationBar: SaveBar(onPressed: onSave, loading: loading),
        ),
      ),
    );

    testWidgets('keyboard closed: bottom bar', (tester) async {
      await tester.pumpWidget(scaffold(keyboard: 0, onSave: () {}));
      expect(find.byType(SaveBar), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.save_rounded)), findsNothing);
    });

    testWidgets('keyboard open (also landscape): save moves into the app bar with the same key', (tester) async {
      var saved = 0;
      await tester.pumpWidget(scaffold(keyboard: 250, onSave: () => saved++));
      expect(find.byType(SaveBar), findsNothing);
      final action = find.descendant(of: find.byType(AppBar), matching: find.byKey(const ValueKey('crud_save_button')));
      expect(action, findsOneWidget);
      expect(find.byTooltip('Kaydet'), findsOneWidget);
      await tester.tap(action);
      expect(saved, 1);
    });

    testWidgets('keyboard open while saving: spinner, no tappable action', (tester) async {
      await tester.pumpWidget(scaffold(keyboard: 250, onSave: () {}, loading: true));
      expect(find.byKey(const ValueKey('crud_save_button')), findsNothing);
      expect(find.bySemanticsLabel('Kaydediliyor'), findsOneWidget);
    });
  });

  group('SMTP test dialog', () {
    late Completer<http.Response> pending;
    late ApiService slowApi;

    setUp(() {
      pending = Completer<http.Response>();
      slowApi = ApiService(
        client: MockClient((req) {
          if (req.url.path.endsWith('/test')) return pending.future;
          if (req.url.path.endsWith('/users/me/permissions')) {
            return Future.value(
              okData({
                'permissions': ['mail:read', 'mail:create'],
              }),
            );
          }
          return Future.value(okData([_account(1)]));
        }),
      );
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final slowAuth = AuthProvider(apiService: slowApi);
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
      await tester.runAsync(slowAuth.checkAuthStatus);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: slowAuth,
          child: MaterialApp(home: MailAccountsScreen(apiService: slowApi)),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('test_1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('smtp_test_to')), 'a@b.co');
      await tester.tap(find.byKey(const ValueKey('smtp_test_send')));
      await tester.pump();
    }

    testWidgets('while sending: "Kapat" locked, back and barrier do not close it', (tester) async {
      await open(tester);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('smtp_test_close'))).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.text('SMTP Bağlantı Testi'), findsOneWidget);

      pending.complete(okData('Test maili basariyla gonderildi -> a@b.co'));
      await settle(tester);
      expect(find.text('Başarılı: Test maili basariyla gonderildi -> a@b.co'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('smtp_test_close')));
      await tester.pumpAndSettle();
      expect(find.text('SMTP Bağlantı Testi'), findsNothing);
    });

    testWidgets('no answer in 30 s → readable timeout error, dialog unlocked', (tester) async {
      await open(tester);
      await tester.pump(smtpTimeout + const Duration(seconds: 1));
      await tester.pump();
      expect(find.textContaining('Hata: SMTP sunucusu 30 sn içinde yanıt vermedi'), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('smtp_test_close'))).onPressed, isNotNull);
    });
  });

  test('smtpErrorText', () {
    expect(smtpErrorText(TimeoutException('x')), contains('30 sn'));
    expect(smtpErrorText(ApiException('Auth failed')), 'Auth failed');
  });

  group('mail account cards', () {
    testWidgets('action labels name the account for screen readers; tenant badge in an AA color', (tester) async {
      backend.ok('/mail-accounts', [_account(1, tenant: 'tenant1')]);
      await pump(tester, [
        'mail:read',
        'mail:update',
        'mail:create',
        'mail:delete',
      ], MailAccountsScreen(apiService: backend.api));
      for (final action in ['Düzenle', 'Test Et', 'Doğrula', 'Sil']) {
        expect(find.bySemanticsLabel('$action: Hesap 1'), findsOneWidget, reason: action);
      }
      final badge = tester.widget<StatusBadge>(find.widgetWithText(StatusBadge, 'tenant1'));
      expect(badge.color, AppColors.primaryLight);
    });
  });

  group('templates', () {
    testWidgets('create stays on the screen as its edit screen; the list reloads when leaving it', (tester) async {
      backend.routes['/email-templates'] = (req) =>
          req.method == 'GET' ? okData({'content': <Object>[], 'last': true}) : okData(_template('yeni'));
      backend.ok('/email-templates/yeni', _template('yeni'));
      await pump(tester, [
        'email_templates:read',
        'email_templates:manage',
      ], EmailTemplatesScreen(apiService: backend.api));
      int listLoads() => backend.requestsTo('/email-templates').where((r) => r.method == 'GET').length;
      expect(listLoads(), 1);

      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('template_field_templateKey')), 'yeni');
      await tester.enterText(find.byKey(const ValueKey('template_field_subject')), 'Konu');
      await tester.enterText(find.byKey(const ValueKey('template_field_htmlBody')), '<p>x</p>');
      await tester.tap(find.byKey(const ValueKey('crud_save_button')));
      await settle(tester);

      expect(find.text('Template Düzenle'), findsOneWidget);
      expect(find.byKey(const ValueKey('template_preview_button')), findsOneWidget);
      expect(listLoads(), 1, reason: 'still on the template');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(EmailTemplatesScreen), findsOneWidget);
      expect(listLoads(), 2);
    });

    testWidgets('HTML editor: fixed ~60% height, scrolls inside; subject keeps typed text exactly', (tester) async {
      backend.ok('/email-templates/a', _template('a'));
      await pump(
        tester,
        ['email_templates:read', 'email_templates:manage'],
        EmailTemplateFormScreen(templateKey: 'a', apiService: backend.api),
        size: const Size(800, 1000),
      );
      final box = tester.getSize(find.byKey(const ValueKey('template_field_htmlBody')));
      expect(box.height, 600);
      final body = tester.widget<TextField>(
        find.descendant(of: find.byKey(const ValueKey('template_field_htmlBody')), matching: find.byType(TextField)),
      );
      expect(body.expands, isTrue);
      final subject = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('template_field_subject')), matching: find.byType(EditableText)),
      );
      expect(subject.autocorrect, isFalse);
      expect(subject.enableSuggestions, isFalse);
      expect(subject.smartQuotesType, SmartQuotesType.disabled);
      expect(subject.smartDashesType, SmartDashesType.disabled);
    });

    testWidgets('409: "Yenile" action reloads the record (and says edits are lost)', (tester) async {
      backend.routes['/email-templates/a'] = (req) =>
          req.method == 'PUT' ? jsonResponse({'message': 'conflict'}, 409) : okData(_template('a', lock: 7));
      await pump(tester, [
        'email_templates:read',
        'email_templates:manage',
      ], EmailTemplateFormScreen(templateKey: 'a', apiService: backend.api));
      await tester.enterText(find.byKey(const ValueKey('template_field_subject')), 'Benim değişikliğim');
      await tester.tap(find.byKey(const ValueKey('crud_save_button')));
      await settle(tester);
      expect(find.textContaining('düzenlemeleriniz kaybolur'), findsOneWidget);

      await tester.tap(find.text('Yenile'));
      await settle(tester);
      expect(backend.requestsTo('/email-templates/a').where((r) => r.method == 'GET'), hasLength(2));
      expect(find.text('Benim değişikliğim'), findsNothing);
      expect(find.text('Konu'), findsWidgets);
    });

    testWidgets('preview over the limits: message instead of the view', (tester) async {
      backend.ok('/email-templates/a/preview', {'html': '<div>' * (maxPreviewDepth + 5), 'subject': 's'});
      final shown = <String>[];
      await pump(
        tester,
        ['email_templates:read'],
        EmailTemplatePreviewScreen(
          templateKey: 'a',
          apiService: backend.api,
          htmlViewBuilder: (h) {
            shown.add(h);
            return const Text('RENDERED');
          },
        ),
      );
      expect(find.byKey(const ValueKey('preview_too_complex')), findsOneWidget);
      expect(find.textContaining('Önizleme için çok karmaşık'), findsOneWidget);
      expect(shown, isEmpty);
    });

    testWidgets('preview: security note collapsible, mentions a possibly broken layout; JSON field labelled', (
      tester,
    ) async {
      backend.ok('/email-templates/a/preview', {'html': '<p>x</p>', 'subject': 's'});
      await pump(
        tester,
        ['email_templates:read'],
        EmailTemplatePreviewScreen(templateKey: 'a', apiService: backend.api, htmlViewBuilder: (_) => const Text('R')),
      );
      expect(find.textContaining('bozuk'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('preview_security_note')));
      await tester.pumpAndSettle();
      expect(find.textContaining('bozuk'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.byKey(const ValueKey('preview_data_button')));
      await tester.pumpAndSettle();
      expect(find.text('Değişkenler (JSON nesnesi)'), findsOneWidget);
    });
  });

  group('e-mail logs', () {
    setUp(() {
      backend.routes['/emails'] = (_) => okData({
        'content': [
          {'id': 1, 'recipient': 'a@b.co', 'subject': 's', 'templateName': 't', 'status': 'PENDING', 'retryCount': 0},
        ],
        'last': true,
        'totalElements': 1,
      });
      backend.ok('/emails/1/retry', {'id': 1, 'status': 'PENDING'});
    });

    testWidgets('PENDING retry asks first: "Vazgeç" sends nothing, confirm re-queues', (tester) async {
      await pump(tester, ['emails:read', 'emails:retry'], EmailLogsScreen(apiService: backend.api));
      expect(find.byTooltip('Yeniden kuyruğa al: #1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('retry_1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('iki kez gönderilmesine'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await settle(tester);
      expect(backend.requestsTo('/emails/1/retry'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('retry_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_retry_button')));
      await settle(tester);
      expect(backend.requestsTo('/emails/1/retry'), hasLength(1));
      expect(jsonDecode(backend.requestsTo('/emails/1/retry').single.body), isEmpty);
    });
  });
}
