import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/mail/email_template_form_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_template_preview_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_templates_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _template(String key, {bool active = true, String? tenant = 'tenant1', int lock = 4}) => {
  'id': key.length,
  'tenantId': tenant,
  'templateKey': key,
  'subject': 'Merhaba [[\${userName}]]',
  'htmlBody': '<p th:text="\${userName}">x</p>',
  'description': 'Hoş geldin maili',
  'active': active,
  'version': 1,
  'optimisticLockVersion': lock,
  'createdAt': '2026-03-01T10:00:00',
  'updatedAt': '2026-03-02T11:30:00',
};

const _manage = ['email_templates:read', 'email_templates:manage'];

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late List<String> rendered;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    rendered = [];
    backend.routes['/email-templates'] = (req) => req.method == 'GET'
        ? okData({
            'content': [_template('welcome'), _template('global-reset', active: false, tenant: null)],
            'last': true,
            'totalElements': 2,
          })
        : okData(_template('yeni-sablon'));
    backend.ok('/email-templates/welcome', _template('welcome'));
    backend.ok('/email-templates/yeni-sablon', _template('yeni-sablon', lock: 0));
    backend.ok('/emails/templates', ['form-notification', 'welcome-static']);
    backend.ok('/email-templates/welcome/preview', {
      'html': '<html><body><p>Merhaba Ahmet</p><script>x()</script></body></html>',
      'subject': 'Merhaba Ahmet',
    });
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Widget fakeView(String html) {
    rendered.add(html);
    return Text('RENDERED', key: ValueKey(html));
  }

  Future<void> pump(WidgetTester tester, List<String> perms, Widget home) async {
    tester.view.physicalSize = const Size(1000, 2600);
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

  Iterable<http.Request> sent(String method, String suffix) =>
      backend.requestsTo(suffix).where((r) => r.method == method);
  Map<String, dynamic> lastBody(String method, String suffix) =>
      jsonDecode(sent(method, suffix).last.body) as Map<String, dynamic>;

  group('list', () {
    testWidgets('paged GET, key/subject/status/updated, "Genel şablon" for global ones', (tester) async {
      await pump(tester, _manage, EmailTemplatesScreen(apiService: backend.api));

      final url = sent('GET', '/email-templates').single.url;
      expect(url.queryParameters['page'], '0');
      expect(url.queryParameters['size'], '20');
      expect(find.text('welcome'), findsOneWidget);
      expect(find.text('Merhaba [[\${userName}]]'), findsNWidgets(2));
      expect(find.text('Aktif'), findsOneWidget);
      expect(find.text('Pasif'), findsOneWidget);
      expect(find.text('Genel şablon'), findsOneWidget);
      expect(find.textContaining('Güncelleme: '), findsNWidgets(2));
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('read only: no FAB, no delete; classpath only with emails:read', (tester) async {
      await pump(tester, ['email_templates:read'], EmailTemplatesScreen(apiService: backend.api));
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('delete_welcome')), findsNothing);
      expect(find.byKey(const ValueKey('classpath_templates_button')), findsNothing);
      expect(backend.requestsTo('/emails/templates'), isEmpty);
    });

    testWidgets('classpath templates sheet lists the JAR names', (tester) async {
      await pump(tester, ['email_templates:read', 'emails:read'], EmailTemplatesScreen(apiService: backend.api));
      await tester.tap(find.byKey(const ValueKey('classpath_templates_button')));
      await settle(tester);
      expect(find.text("Classpath Template'leri (2)"), findsOneWidget);
      expect(find.text('form-notification'), findsOneWidget);
      expect(find.text('welcome-static'), findsOneWidget);
    });

    testWidgets('delete needs the key typed (admin DestructiveConfirmDialog), then DELETE (204)', (tester) async {
      backend.routes['/email-templates/welcome'] = (req) =>
          req.method == 'DELETE' ? http.Response('', 204) : okData(_template('welcome'));
      await pump(tester, _manage, EmailTemplatesScreen(apiService: backend.api));

      await tester.tap(find.byKey(const ValueKey('delete_welcome')));
      await tester.pumpAndSettle();
      ElevatedButton confirm() => tester.widget<ElevatedButton>(find.byKey(const ValueKey('confirm_delete_button')));
      expect(confirm().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('confirm_dialog_text')), 'welcom');
      await tester.pump();
      expect(confirm().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('confirm_dialog_text')), 'welcome');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);

      expect(sent('DELETE', '/email-templates/welcome'), hasLength(1));
      expect(find.text('Template silindi'), findsOneWidget, reason: '204 without body is a success');
      expect(sent('GET', '/email-templates'), hasLength(2));
    });
  });

  group('form', () {
    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('crud_save_button')));
      await settle(tester);
    }

    testWidgets('create: key pattern validated; POST DTO; then the edit screen of the new key', (tester) async {
      await pump(tester, _manage, EmailTemplateFormScreen(apiService: backend.api, previewViewBuilder: fakeView));

      await tester.enterText(find.byKey(const ValueKey('template_field_templateKey')), 'Yeni Şablon');
      await tester.enterText(find.byKey(const ValueKey('template_field_subject')), 'Konu');
      await tester.enterText(find.byKey(const ValueKey('template_field_htmlBody')), '<p>x</p>');
      await save(tester);
      expect(find.text('Sadece küçük harf, rakam ve tire (-) kullanılabilir'), findsOneWidget);
      expect(sent('POST', '/email-templates'), isEmpty);

      await tester.enterText(find.byKey(const ValueKey('template_field_templateKey')), 'yeni-sablon');
      await save(tester);
      expect(lastBody('POST', '/email-templates'), {
        'templateKey': 'yeni-sablon',
        'subject': 'Konu',
        'htmlBody': '<p>x</p>',
        'description': null,
        'active': true,
      });
      expect(find.text('Template Düzenle'), findsOneWidget);
      expect(sent('GET', '/email-templates/yeni-sablon'), hasLength(1));
      expect(find.byKey(const ValueKey('template_preview_button')), findsOneWidget);
    });

    testWidgets('required fields', (tester) async {
      await pump(tester, _manage, EmailTemplateFormScreen(apiService: backend.api));
      await save(tester);
      expect(find.text('Template Key zorunlu'), findsOneWidget);
      expect(find.text('Konu zorunlu'), findsOneWidget);
      expect(find.text('HTML Body zorunlu'), findsOneWidget);
      expect(find.textContaining('3 alan hatalı'), findsOneWidget);
    });

    testWidgets('HTML body is a code field: monospace, no autocorrect / smart quotes', (tester) async {
      await pump(tester, _manage, EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));
      final body = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('template_field_htmlBody')), matching: find.byType(EditableText)),
      );
      expect(body.controller.text, '<p th:text="\${userName}">x</p>');
      expect(body.style.fontFamily, 'monospace');
      expect(body.autocorrect, isFalse);
      expect(body.smartQuotesType, SmartQuotesType.disabled);
      expect(body.smartDashesType, SmartDashesType.disabled);
    });

    testWidgets('edit: key fixed; PUT sends key + lock version back; stays on the screen', (tester) async {
      backend.routes['/email-templates/welcome'] = (req) =>
          okData(req.method == 'PUT' ? _template('welcome', lock: 5) : _template('welcome'));
      await pump(tester, _manage, EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));

      expect(find.byKey(const ValueKey('template_field_templateKey')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('template_field_subject')), 'Yeni konu');
      await tester.tap(find.byKey(const ValueKey('template_field_active')));
      await tester.pump();
      await save(tester);

      expect(lastBody('PUT', '/email-templates/welcome'), {
        'templateKey': 'welcome',
        'subject': 'Yeni konu',
        'htmlBody': '<p th:text="\${userName}">x</p>',
        'description': 'Hoş geldin maili',
        'active': false,
        'optimisticLockVersion': 4,
      });
      expect(find.text('Template güncellendi'), findsOneWidget);
      expect(find.text('Template Düzenle'), findsOneWidget);

      await save(tester);
      expect(lastBody('PUT', '/email-templates/welcome')['optimisticLockVersion'], 5, reason: 'from the response');
    });

    testWidgets('409 → "someone else updated it" message', (tester) async {
      backend.routes['/email-templates/welcome'] = (req) =>
          req.method == 'PUT' ? jsonResponse({'message': 'conflict'}, 409) : okData(_template('welcome'));
      await pump(tester, _manage, EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));
      await save(tester);
      expect(find.textContaining('Başka biri bu template'), findsOneWidget);
    });

    testWidgets('without manage: read only, no save / delete, preview still available', (tester) async {
      await pump(tester, [
        'email_templates:read',
      ], EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));
      expect(find.byKey(const ValueKey('crud_save_button')), findsNothing);
      expect(find.byKey(const ValueKey('template_delete_button')), findsNothing);
      expect(find.byKey(const ValueKey('template_preview_button')), findsOneWidget);
      final subject = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('template_field_subject')), matching: find.byType(EditableText)),
      );
      expect(subject.readOnly, isTrue);
      expect(find.textContaining('Düzenleme yetkiniz yok'), findsOneWidget);
    });

    testWidgets('delete from the edit screen asks for the key too', (tester) async {
      backend.routes['/email-templates/welcome'] = (req) =>
          req.method == 'DELETE' ? http.Response('', 204) : okData(_template('welcome'));
      await pump(tester, _manage, EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));
      await tester.tap(find.byKey(const ValueKey('template_delete_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('confirm_dialog_text')), 'welcome');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);
      expect(sent('DELETE', '/email-templates/welcome'), hasLength(1));
    });
  });

  group('preview', () {
    testWidgets('renders the saved template with the admin default data; HTML goes to the safe view', (tester) async {
      await pump(tester, [
        'email_templates:read',
      ], EmailTemplatePreviewScreen(templateKey: 'welcome', apiService: backend.api, htmlViewBuilder: fakeView));

      expect(lastBody('POST', '/email-templates/welcome/preview'), {
        'data': {'userName': 'Ahmet', 'link': 'https://example.com'},
      });
      expect(find.text('Konu: Merhaba Ahmet'), findsOneWidget);
      expect(find.text('RENDERED'), findsOneWidget);
      expect(rendered.last, contains('<script>'), reason: 'raw response; SafeHtmlView sanitizes it');
      expect(find.byKey(const ValueKey('preview_unsaved_note')), findsNothing);
    });

    testWidgets('test data: invalid JSON / non-object rejected; valid object re-renders', (tester) async {
      await pump(tester, [
        'email_templates:read',
      ], EmailTemplatePreviewScreen(templateKey: 'welcome', apiService: backend.api, htmlViewBuilder: fakeView));
      await tester.tap(find.byKey(const ValueKey('preview_data_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('preview_data_field')), '{bozuk');
      await tester.tap(find.byKey(const ValueKey('preview_data_apply')));
      await tester.pump();
      expect(find.text('Geçersiz JSON formatı'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('preview_data_field')), '[1, 2]');
      await tester.tap(find.byKey(const ValueKey('preview_data_apply')));
      await tester.pump();
      expect(find.textContaining('JSON nesnesi olmalı'), findsOneWidget);
      expect(sent('POST', '/email-templates/welcome/preview'), hasLength(1));

      await tester.enterText(find.byKey(const ValueKey('preview_data_field')), '{"userName": "Zeynep", "n": 3}');
      await tester.tap(find.byKey(const ValueKey('preview_data_apply')));
      await settle(tester);
      expect(lastBody('POST', '/email-templates/welcome/preview'), {
        'data': {'userName': 'Zeynep', 'n': 3},
      });
    });

    testWidgets('render error → ErrorView with retry', (tester) async {
      backend.routes['/email-templates/welcome/preview'] = (_) => jsonResponse({'message': 'Thymeleaf hatası'}, 400);
      await pump(tester, [
        'email_templates:read',
      ], EmailTemplatePreviewScreen(templateKey: 'welcome', apiService: backend.api, htmlViewBuilder: fakeView));
      expect(find.text('Thymeleaf hatası'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(rendered, isEmpty);
    });

    testWidgets('opened from a dirty form: says unsaved changes are not shown', (tester) async {
      await pump(
        tester,
        _manage,
        EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api, previewViewBuilder: fakeView),
      );
      await tester.enterText(find.byKey(const ValueKey('template_field_subject')), 'Değişti');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('template_preview_button')));
      await settle(tester);

      expect(find.byKey(const ValueKey('preview_unsaved_note')), findsOneWidget);
      expect(find.text('RENDERED'), findsOneWidget);
    });
  });
}
