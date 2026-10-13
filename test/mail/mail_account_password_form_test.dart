import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/mail/mail_account_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

/// The write-only SMTP password on the real form: create requires it, edit omits the key when blank,
/// a typed password goes out untrimmed, and the field never shows server data.
Map<String, dynamic> _account({Map<String, dynamic> extra = const {}}) => {
  'id': 1,
  'name': 'Hesap 1',
  'fromAddress': 'h1@firma.com',
  'smtpHost': 'smtp.firma.com',
  'smtpPort': 587,
  'smtpUsername': 'user1',
  'active': true,
  'tenantId': 'tenant1',
  'isPrimary': false,
  ...extra,
};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.ok('/mail-accounts', _account());
    backend.ok('/mail-accounts/1', _account());
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, {Map<String, dynamic>? account}) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, ['mail:read', 'mail:create', 'mail:update']));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          home: MailAccountFormScreen(account: account, apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
  }

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

  Iterable<http.Request> writes(String method) => backend.requests.where((r) => r.method == method);
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  const create = {
    'name': 'Satış',
    'fromAddress': 'sales@firma.com',
    'smtpHost': 'smtp.firma.com',
    'smtpUsername': 'sales',
  };

  group('create', () {
    testWidgets('a whitespace-only password counts as empty: required error, nothing sent', (tester) async {
      await pump(tester);
      await fill(tester, {...create, 'smtpPassword': '    '});
      await save(tester);
      expect(find.text('Şifre zorunludur'), findsOneWidget);
      expect(writes('POST'), isEmpty);
    });

    testWidgets('the typed password goes out exactly as typed (surrounding spaces kept)', (tester) async {
      await pump(tester);
      await fill(tester, {...create, 'smtpPassword': '  s3cr3t pass  '});
      await save(tester);
      expect(body(writes('POST').single)['smtpPassword'], '  s3cr3t pass  ');
    });

    testWidgets('the field is marked required; helper "mevcut şifre korunur" is edit-only', (tester) async {
      await pump(tester);
      final decoration = tester
          .widget<InputDecorator>(
            find.descendant(
              of: find.byKey(const ValueKey('mail_field_smtpPassword')),
              matching: find.byType(InputDecorator),
            ),
          )
          .decoration;
      expect(decoration.label, isNotNull, reason: 'required style (rich label with the "zorunlu" semantics)');
      expect(decoration.labelText, isNull);
      expect(find.byTooltip('Şifreyi göster'), findsOneWidget);
      expect(find.text('Boş bırakırsanız mevcut şifre korunur'), findsNothing);
    });
  });

  group('edit', () {
    testWidgets('a whitespace-only password is not an error and the key is omitted (stored one is kept)', (
      tester,
    ) async {
      await pump(tester, account: _account());
      expect(find.text('SMTP Şifre'), findsOneWidget, reason: 'no required marker when editing');
      await fill(tester, {'smtpPassword': '   '});
      await save(tester);
      expect(find.text('Şifre zorunludur'), findsNothing);
      expect(body(writes('PUT').single).containsKey('smtpPassword'), isFalse);
    });

    testWidgets('typing a password and clearing it again sends no password key', (tester) async {
      await pump(tester, account: _account());
      await fill(tester, {'smtpPassword': 'gecici'});
      await fill(tester, {'smtpPassword': ''});
      await save(tester);
      expect(body(writes('PUT').single).containsKey('smtpPassword'), isFalse);
    });

    testWidgets('a password leaked in the server detail is neither shown nor sent back', (tester) async {
      backend.ok('/mail-accounts/1', _account(extra: {'smtpPassword': 'SIZINTI', 'password': 'SIZINTI2'}));
      await pump(tester, account: _account());
      final field = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('mail_field_smtpPassword')), matching: find.byType(EditableText)),
      );
      expect(field.controller.text, isEmpty);
      expect(find.textContaining('SIZINTI'), findsNothing);

      await fill(tester, {'name': 'Yeni'});
      await save(tester);
      final sent = writes('PUT').single.body;
      expect(sent, isNot(contains('SIZINTI')));
      expect(body(writes('PUT').single).containsKey('smtpPassword'), isFalse);
    });

    testWidgets('the password never appears in a URL / query string', (tester) async {
      await pump(tester, account: _account());
      await fill(tester, {'smtpPassword': 'cok-gizli-123'});
      await save(tester);
      expect(backend.requests.where((r) => r.url.toString().contains('cok-gizli-123')), isEmpty);
    });

    testWidgets('a failed save keeps what was typed (retry does not lose the password) and shows the backend error', (
      tester,
    ) async {
      backend.routes['/mail-accounts/1'] = (req) =>
          req.method == 'PUT' ? jsonResponse({'message': 'SMTP host erisilemiyor'}, 400) : okData(_account());
      await pump(tester, account: _account());
      await fill(tester, {'smtpPassword': 'tekrar-dene'});
      await save(tester);
      expect(find.text('SMTP host erisilemiyor'), findsOneWidget);

      await save(tester);
      expect(writes('PUT'), hasLength(2));
      expect(body(writes('PUT').last)['smtpPassword'], 'tekrar-dene');
    });
  });
}
