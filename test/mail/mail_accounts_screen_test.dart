import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/mail/mail_account_form_screen.dart';
import 'package:elly_mobile_app/screens/mail/mail_accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _account(int id, {String? tenant, bool primary = false, bool active = true}) => {
  'id': id,
  'name': 'Hesap $id',
  'fromAddress': 'h$id@firma.com',
  'smtpHost': 'mail.example.invalid',
  'smtpPort': 587,
  'smtpUsername': 'user$id',
  'active': active,
  'tenantId': tenant,
  'isPrimary': primary,
  'createdAt': '2026-01-01T10:00:00',
  'updatedAt': '2026-01-02T10:00:00',
};

const _all = ['mail:read', 'mail:create', 'mail:update', 'mail:delete'];

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.ok('/mail-accounts', [
      _account(1, tenant: 'tenant1', primary: true),
      _account(2, tenant: 'tenant2', active: false),
      _account(3),
    ]);
    backend.ok('/mail-accounts/1', _account(1, tenant: 'tenant1', primary: true));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, List<String> perms, {Widget? home}) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, perms));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: home ?? MailAccountsScreen(apiService: backend.api)),
      ),
    );
    await settle(tester);
  }

  Finder inCard(int id, Finder f) => find.descendant(of: find.byKey(ValueKey('mail_account_$id')), matching: f);
  Iterable<http.Request> bodyRequests(String method, String suffix) =>
      backend.requestsTo(suffix).where((r) => r.method == method);
  Map<String, dynamic> lastBody(String method, String suffix) =>
      jsonDecode(bodyRequests(method, suffix).last.body) as Map<String, dynamic>;

  group('list', () {
    testWidgets('cards: host:port, user, Ana Hesap / tenant / Atanmamış / Aktif-Pasif badges', (tester) async {
      await pump(tester, _all);

      expect(inCard(1, find.text('Hesap 1')), findsOneWidget);
      expect(inCard(1, find.text('h1@firma.com')), findsOneWidget);
      expect(inCard(1, find.text('mail.example.invalid:587')), findsOneWidget);
      expect(inCard(1, find.text('user1')), findsOneWidget);
      expect(inCard(1, find.text('Ana Hesap')), findsOneWidget);
      expect(inCard(1, find.text('tenant1')), findsOneWidget);
      expect(inCard(1, find.text('Aktif')), findsOneWidget);
      expect(inCard(2, find.text('Pasif')), findsOneWidget);
      expect(inCard(2, find.text('Ana Hesap')), findsNothing);
      expect(inCard(3, find.text('Atanmamış')), findsOneWidget);
      expect(find.textContaining('smtpPassword'), findsNothing);
    });

    testWidgets('tenant chips come from the data and filter on the client', (tester) async {
      await pump(tester, _all);
      expect(find.byKey(const ValueKey('tenant_all')), findsOneWidget);
      expect(find.byKey(const ValueKey('tenant_tenant1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tenant_tenant2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tenant_tenant2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mail_account_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('mail_account_1')), findsNothing);
      expect(find.byKey(const ValueKey('mail_account_3')), findsNothing);
      expect(backend.requestsTo('/mail-accounts'), hasLength(1), reason: 'client-side like the admin');
    });

    testWidgets('read only: verify only — no edit, test mail, delete or FAB', (tester) async {
      await pump(tester, ['mail:read']);
      expect(find.byKey(const ValueKey('verify_1')), findsOneWidget);
      for (final key in ['edit_1', 'test_1', 'delete_1']) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('each action follows its backend permission (test mail = mail:create)', (tester) async {
      await pump(tester, ['mail:read', 'mail:create']);
      expect(find.byKey(const ValueKey('test_1')), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byKey(const ValueKey('edit_1')), findsNothing);
      expect(find.byKey(const ValueKey('delete_1')), findsNothing);
    });

    testWidgets('verify success → result dialog, no e-mail body sent', (tester) async {
      backend.ok('/mail-accounts/1/verify', 'SMTP baglantisi basarili');
      await pump(tester, ['mail:read']);

      await tester.tap(find.byKey(const ValueKey('verify_1')));
      await settle(tester);

      expect(bodyRequests('POST', '/mail-accounts/1/verify'), hasLength(1));
      expect(find.byKey(const ValueKey('verify_success')), findsOneWidget);
      expect(find.text('SMTP bağlantısı başarılı'), findsOneWidget);
    });

    testWidgets('verify failure → dialog with the backend SMTP error', (tester) async {
      backend.routes['/mail-accounts/2/verify'] = (_) =>
          jsonResponse({'result': false, 'message': 'Pasif mail hesabi uzerinde SMTP testi yapilamaz'}, 400);
      await pump(tester, ['mail:read']);

      await tester.tap(find.byKey(const ValueKey('verify_2')));
      await settle(tester);

      expect(find.byKey(const ValueKey('verify_failure')), findsOneWidget);
      expect(find.text('SMTP doğrulama başarısız'), findsOneWidget);
      expect(find.text('Pasif mail hesabi uzerinde SMTP testi yapilamaz'), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('verify_failure')), findsNothing);
    });

    testWidgets('test mail: e-mail validated, POST {testTo}, result stays in the dialog', (tester) async {
      backend.ok('/mail-accounts/1/test', 'Test maili basariyla gonderildi -> a@b.co');
      await pump(tester, _all);

      await tester.tap(find.byKey(const ValueKey('test_1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('smtp_test_to')), 'gecersiz');
      await tester.tap(find.byKey(const ValueKey('smtp_test_send')));
      await tester.pumpAndSettle();
      expect(find.text('Geçerli bir e-posta adresi giriniz'), findsOneWidget);
      expect(bodyRequests('POST', '/mail-accounts/1/test'), isEmpty);

      await tester.enterText(find.byKey(const ValueKey('smtp_test_to')), ' a@b.co ');
      await tester.tap(find.byKey(const ValueKey('smtp_test_send')));
      await settle(tester);
      expect(lastBody('POST', '/mail-accounts/1/test'), {'testTo': 'a@b.co'});
      expect(find.text('Başarılı: Test maili basariyla gonderildi -> a@b.co'), findsOneWidget);
      expect(find.text('SMTP Bağlantı Testi'), findsOneWidget, reason: 'dialog stays open');
    });

    testWidgets('test mail failure is shown in the dialog', (tester) async {
      backend.routes['/mail-accounts/1/test'] = (_) => jsonResponse({'message': 'Authentication failed'}, 400);
      await pump(tester, _all);
      await tester.tap(find.byKey(const ValueKey('test_1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('smtp_test_to')), 'a@b.co');
      await tester.tap(find.byKey(const ValueKey('smtp_test_send')));
      await settle(tester);
      expect(find.text('Hata: Authentication failed'), findsOneWidget);
    });

    testWidgets('delete: confirm → DELETE → list reloads', (tester) async {
      backend.ok('/mail-accounts/3', true);
      await pump(tester, _all);

      await tester.tap(find.byKey(const ValueKey('delete_3')));
      await tester.pumpAndSettle();
      expect(find.textContaining('varsayılan hesaba geçecektir'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);

      expect(bodyRequests('DELETE', '/mail-accounts/3'), hasLength(1));
      expect(backend.requestsTo('/mail-accounts').where((r) => r.method == 'GET'), hasLength(2));
      expect(find.text('Mail hesabı silindi'), findsOneWidget);
    });
  });

  group('form', () {
    Future<void> fill(WidgetTester tester, Map<String, String> values) async {
      for (final e in values.entries) {
        await tester.enterText(find.byKey(ValueKey('mail_field_${e.key}')), e.value);
      }
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('crud_save_button')));
      await tester.tap(find.byKey(const ValueKey('crud_save_button')));
      await settle(tester);
    }

    testWidgets('create: password required; payload = admin MailAccountRequest; tenant empty → null', (tester) async {
      backend.ok('/mail-accounts', _account(9));
      await pump(tester, _all, home: MailAccountFormScreen(apiService: backend.api));
      expect(
        tester.widget<TextFormField>(find.byKey(const ValueKey('mail_field_smtpPort'))).controller!.text,
        '587',
        reason: 'admin default port',
      );

      await fill(tester, {
        'name': 'Satış',
        'fromAddress': 'sales@example.invalid',
        'smtpHost': 'mail.example.invalid',
        'smtpUsername': 'sales@example.invalid',
      });
      await save(tester);
      expect(bodyRequests('POST', '/mail-accounts'), isEmpty);
      expect(find.text('Şifre zorunludur'), findsOneWidget);
      expect(find.textContaining('1 alan hatalı'), findsOneWidget);

      await fill(tester, {'smtpPassword': '<app-password>'}); // ggignore
      await save(tester);
      expect(lastBody('POST', '/mail-accounts'), {
        'name': 'Satış',
        'fromAddress': 'sales@example.invalid',
        'smtpHost': 'mail.example.invalid',
        'smtpPort': 587,
        'smtpUsername': 'sales@example.invalid',
        'smtpPassword': '<app-password>', // ggignore
        'isPrimary': false,
        'active': true,
        'tenantId': null,
      });
    });

    testWidgets('validation: e-mail, port range, max length', (tester) async {
      await pump(tester, _all, home: MailAccountFormScreen(apiService: backend.api));
      await fill(tester, {
        'name': 'x' * 256,
        'fromAddress': 'gecersiz',
        'smtpHost': 'h',
        'smtpPort': '70000',
        'smtpUsername': 'u',
        'smtpPassword': 'p', // ggignore
      });
      await save(tester);
      expect(find.text('En fazla 255 karakter'), findsOneWidget);
      expect(find.text('Geçerli bir e-posta adresi giriniz'), findsOneWidget);
      expect(find.text('Port 1-65535 aralığında olmalıdır'), findsOneWidget);
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('edit: loaded from detail; password never prefilled; blank keeps it (key omitted)', (tester) async {
      await pump(
        tester,
        _all,
        home: MailAccountFormScreen(account: _account(1), apiService: backend.api),
      );

      expect(backend.requestsTo('/mail-accounts/1').where((r) => r.method == 'GET'), hasLength(1));
      final password = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('mail_field_smtpPassword')), matching: find.byType(EditableText)),
      );
      expect(password.controller.text, isEmpty);
      expect(password.obscureText, isTrue);
      expect(find.text('Boş bırakırsanız mevcut şifre korunur'), findsOneWidget);
      expect(find.text('tenant1'), findsOneWidget);

      await fill(tester, {'name': 'Yeni Ad'});
      await save(tester);

      final body = lastBody('PUT', '/mail-accounts/1');
      expect(body.containsKey('smtpPassword'), isFalse, reason: 'never send a blank password');
      expect(body['name'], 'Yeni Ad');
      expect(body['isPrimary'], isTrue);
      expect(body['tenantId'], 'tenant1');
    });

    testWidgets('edit: a typed password is sent; show/hide toggles obscuring', (tester) async {
      await pump(
        tester,
        _all,
        home: MailAccountFormScreen(account: _account(1), apiService: backend.api),
      );
      EditableText password() => tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('mail_field_smtpPassword')), matching: find.byType(EditableText)),
      );

      await fill(tester, {'smtpPassword': '<new-password>'}); // ggignore
      await tester.tap(find.byKey(const ValueKey('mail_password_toggle')));
      await tester.pump();
      expect(password().obscureText, isFalse);
      expect(find.byTooltip('Şifreyi gizle'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mail_password_toggle')));
      await tester.pump();
      expect(password().obscureText, isTrue);

      await save(tester);
      expect(lastBody('PUT', '/mail-accounts/1')['smtpPassword'], '<new-password>'); // ggignore
    });

    testWidgets('primary switch shows the demotion note; verify uses the saved account', (tester) async {
      backend.ok('/mail-accounts/1/verify', 'SMTP baglantisi basarili');
      backend.ok('/mail-accounts/3', _account(3));
      await pump(
        tester,
        _all,
        home: MailAccountFormScreen(account: _account(3), apiService: backend.api),
      );
      expect(find.textContaining('mevcut ana hesabı'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail_field_isPrimary')));
      await tester.pump();
      expect(find.textContaining('mevcut ana hesabı'), findsOneWidget);
      expect(find.textContaining('kaydedilmemiş değişiklikler teste dahil değil'), findsOneWidget);

      backend.ok('/mail-accounts/3/verify', 'ok');
      await tester.ensureVisible(find.byKey(const ValueKey('mail_verify_button')));
      await tester.tap(find.byKey(const ValueKey('mail_verify_button')));
      await settle(tester);
      expect(bodyRequests('POST', '/mail-accounts/3/verify'), hasLength(1));
      expect(find.byKey(const ValueKey('verify_success')), findsOneWidget);
    });

    testWidgets('new form has no verify section', (tester) async {
      await pump(tester, _all, home: MailAccountFormScreen(apiService: backend.api));
      expect(find.byKey(const ValueKey('mail_verify_button')), findsNothing);
    });

    testWidgets('unsaved changes: back asks before leaving', (tester) async {
      await pump(
        tester,
        _all,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MailAccountFormScreen(account: _account(1), apiService: backend.api),
              ),
            ),
            child: const Text('aç'),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await settle(tester);
      await fill(tester, {'smtpHost': 'mail2.example.invalid'});
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_leave_button')));
      await tester.pumpAndSettle();
      expect(find.text('aç'), findsOneWidget);
    });

    testWidgets('detail load error → ErrorView, never a form from list data', (tester) async {
      backend.routes['/mail-accounts/1'] = (_) => jsonResponse({'message': 'Bulunamadı'}, 404);
      await pump(
        tester,
        _all,
        home: MailAccountFormScreen(account: _account(1), apiService: backend.api),
      );
      expect(find.text('Bulunamadı'), findsOneWidget);
      expect(find.byKey(const ValueKey('crud_save_button')), findsNothing);
    });
  });
}
