import 'dart:async';
import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/mail/email_logs_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_template_form_screen.dart';
import 'package:elly_mobile_app/screens/mail/email_templates_screen.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

/// Permission gating of the communication screens (edge cases on top of the per-screen tests):
/// e-mail log "retry" (`emails:retry`, never for SENT) and the e-mail template read-only mode (no
/// `email_templates:manage`).
Map<String, dynamic> _log(int id, Object? status) => {
  'id': id,
  'recipient': 'alici$id@ornek.com',
  'subject': 'Konu $id',
  'templateName': 'welcome',
  'status': status,
  'retryCount': 0,
  'createdAt': '2026-04-0${id}T08:00:00',
  'sentAt': null,
};

Map<String, dynamic> _template(String key, {int lock = 4}) => {
  'id': 1,
  'tenantId': 'tenant1',
  'templateKey': key,
  'subject': 'Merhaba',
  'htmlBody': '<p>x</p>',
  'description': 'Açıklama',
  'active': true,
  'version': 1,
  'optimisticLockVersion': lock,
  'createdAt': '2026-03-01T10:00:00',
  'updatedAt': '2026-03-02T11:30:00',
};

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

  /// Permissions change while the screen is open (token refresh / role change on the server).
  Future<void> changePermissions(WidgetTester tester, List<String> perms) async {
    backend.permissions(perms);
    await tester.runAsync(auth.loadPermissions);
    await settle(tester);
  }

  group('e-mail logs: retry', () {
    void serveLogs(List<Map<String, dynamic>> logs) {
      backend.routes['/emails'] = (_) => okData({'content': logs, 'last': true, 'totalElements': logs.length});
      for (final l in logs) {
        backend.ok('/emails/${l['id']}/retry', {...l, 'status': 'PENDING'});
      }
    }

    Finder retryButton(int id) => find.byKey(ValueKey('retry_$id'));

    testWidgets('look-alike permissions do not enable it (exact emails:retry only)', (tester) async {
      serveLogs([_log(1, 'FAILED')]);
      await pump(tester, [
        'emails:read',
        'emails:retries',
        'email:retry',
        'emails:Retry',
        'emails:update',
        'emails:manage',
        'emails:*',
        'email_templates:manage',
        'mail:update',
        'retry',
      ], EmailLogsScreen(apiService: backend.api));

      expect(find.byKey(const ValueKey('email_log_1')), findsOneWidget);
      expect(retryButton(1), findsNothing);
    });

    testWidgets('status matrix with emails:retry: only SENT has no button (unknown / missing status can be retried)', (
      tester,
    ) async {
      serveLogs([_log(1, 'FAILED'), _log(2, 'SENT'), _log(3, 'PENDING'), _log(4, 'PROCESSING'), _log(5, null)]);
      await pump(tester, ['emails:read', 'emails:retry'], EmailLogsScreen(apiService: backend.api));

      expect(retryButton(1), findsOneWidget);
      expect(retryButton(2), findsNothing, reason: 'SENT');
      expect(retryButton(3), findsOneWidget);
      expect(retryButton(4), findsOneWidget);
      expect(retryButton(5), findsOneWidget);
    });

    testWidgets('SENT: no retry anywhere - not in the list, detail button is disabled with the reason, no POST ever', (
      tester,
    ) async {
      serveLogs([_log(2, 'SENT')]);
      await pump(tester, ['emails:read', 'emails:retry'], EmailLogsScreen(apiService: backend.api));
      expect(retryButton(2), findsNothing);

      await tester.tap(find.byKey(const ValueKey('email_log_2')));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('email_log_retry_button'));
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Gönderilmiş mail yeniden kuyruğa alınamaz.'), findsOneWidget);
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets(
      'the retry rights are re-read live: revoked while the list is open → buttons vanish; granted → appear',
      (tester) async {
        serveLogs([_log(1, 'FAILED')]);
        await pump(tester, ['emails:read', 'emails:retry'], EmailLogsScreen(apiService: backend.api));
        expect(retryButton(1), findsOneWidget);

        await changePermissions(tester, ['emails:read']);
        expect(retryButton(1), findsNothing);

        await changePermissions(tester, ['emails:read', 'emails:retry']);
        expect(retryButton(1), findsOneWidget);
      },
    );

    testWidgets('detail: no button without emails:retry, enabled for PENDING and unknown statuses', (tester) async {
      serveLogs([_log(1, 'PENDING'), _log(3, 'PROCESSING')]);
      await pump(tester, ['emails:read'], EmailLogsScreen(apiService: backend.api));
      await tester.tap(find.byKey(const ValueKey('email_log_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('email_log_retry_button')), findsNothing);
      expect(
        find.text('Gönderilmiş mail yeniden kuyruğa alınamaz.'),
        findsNothing,
        reason: 'the SENT reason is only for SENT',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await changePermissions(tester, ['emails:read', 'emails:retry']);
      for (final id in [1, 3]) {
        await tester.tap(find.byKey(ValueKey('email_log_$id')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('email_log_retry_button'))).onPressed,
          isNotNull,
          reason: '#$id',
        );
        expect(find.text('Gönderilmiş mail yeniden kuyruğa alınamaz.'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a retry in flight locks its button: a second tap does not send a second POST', (tester) async {
      final release = Completer<http.Response>();
      var posts = 0;
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
      final api = ApiService(
        client: MockClient((req) async {
          final path = req.url.path.replaceFirst(RegExp(r'^.*/api/v1'), '');
          if (path == '/users/me/permissions') {
            return okData({
              'permissions': ['emails:read', 'emails:retry'],
            });
          }
          if (path == '/emails/1/retry') {
            posts++;
            return release.future;
          }
          return okData({
            'content': [_log(1, 'FAILED')],
            'last': true,
            'totalElements': 1,
          });
        }),
      );
      final localAuth = AuthProvider(apiService: api);
      await tester.runAsync(localAuth.checkAuthStatus);
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: localAuth,
          child: MaterialApp(home: EmailLogsScreen(apiService: api)),
        ),
      );
      await settle(tester);

      await tester.tap(retryButton(1));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(tester.widget<IconButton>(retryButton(1)).onPressed, isNull, reason: 'locked while in flight');
      await tester.tap(retryButton(1), warnIfMissed: false);
      await tester.pump();
      expect(posts, 1);

      release.complete(okData(_log(1, 'PENDING')));
      await settle(tester);
      expect(posts, 1);
    });
  });

  group('e-mail templates: read-only without email_templates:manage', () {
    setUp(() {
      backend.routes['/email-templates'] = (_) => okData({
        'content': [_template('welcome')],
        'last': true,
        'totalElements': 1,
      });
      backend.ok('/email-templates/welcome', _template('welcome'));
    });

    Iterable<http.Request> writes() =>
        backend.requests.where((r) => r.method != 'GET' && !r.url.path.endsWith('/preview'));

    EditableText editable(WidgetTester tester, String field) => tester.widget<EditableText>(
      find.descendant(of: find.byKey(ValueKey('template_field_$field')), matching: find.byType(EditableText)),
    );

    testWidgets('look-alike permissions do not unlock editing (exact email_templates:manage only)', (tester) async {
      await pump(tester, [
        'email_templates:read',
        'email_templates:update',
        'email_templates:write',
        'email_templates:create',
        'email_templates:delete',
        'email_template:manage',
        'email_templates:Manage',
        'email_templates:*',
        'emails:manage',
        'mail:update',
      ], EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));

      expect(find.byKey(const ValueKey('crud_save_button')), findsNothing);
      expect(editable(tester, 'subject').readOnly, isTrue);
    });

    testWidgets('every field is read-only, the Aktif switch is disabled, there is no save bar or delete', (
      tester,
    ) async {
      await pump(tester, [
        'email_templates:read',
      ], EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));

      for (final field in ['subject', 'description', 'htmlBody']) {
        expect(editable(tester, field).readOnly, isTrue, reason: field);
      }
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('template_field_active'))).onChanged, isNull);
      expect(find.byKey(const ValueKey('crud_save_button')), findsNothing);
      expect(find.byKey(const ValueKey('template_delete_button')), findsNothing);
      expect(find.textContaining('Düzenleme yetkiniz yok'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('template_preview_button')),
        findsOneWidget,
        reason: 'viewing / previewing stays',
      );
      expect(find.text('Aktif'), findsOneWidget);
    });

    testWidgets('the stored values are shown unchanged; tapping the switch changes nothing; no write request happens', (
      tester,
    ) async {
      await pump(tester, [
        'email_templates:read',
      ], EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));
      expect(editable(tester, 'subject').controller.text, 'Merhaba');
      expect(editable(tester, 'htmlBody').controller.text, '<p>x</p>');

      await tester.tap(find.byKey(const ValueKey('template_field_active')), warnIfMissed: false);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('template_field_active'))).value, isTrue);

      expect(writes(), isEmpty);
    });

    testWidgets('list: no FAB and no delete icon on any row; rows still open the (read-only) template', (tester) async {
      await pump(tester, ['email_templates:read'], EmailTemplatesScreen(apiService: backend.api));
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byKey(const ValueKey('delete_welcome')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('template_welcome')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('template_field_subject')), findsOneWidget);
      expect(editable(tester, 'subject').readOnly, isTrue);
      expect(writes(), isEmpty);
    });

    testWidgets(
      'manage revoked while the edit screen is open → it turns read-only, the save bar and delete disappear',
      (tester) async {
        await pump(tester, [
          'email_templates:read',
          'email_templates:manage',
        ], EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));
        expect(find.byKey(const ValueKey('crud_save_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('template_delete_button')), findsOneWidget);
        expect(editable(tester, 'subject').readOnly, isFalse);

        await changePermissions(tester, ['email_templates:read']);
        expect(find.byKey(const ValueKey('crud_save_button')), findsNothing);
        expect(find.byKey(const ValueKey('template_delete_button')), findsNothing);
        expect(editable(tester, 'subject').readOnly, isTrue);
        expect(find.textContaining('Düzenleme yetkiniz yok'), findsOneWidget);
      },
    );

    testWidgets('with manage the same screen is editable and PUT carries the key + lock version (control)', (
      tester,
    ) async {
      backend.ok('/email-templates/welcome', _template('welcome', lock: 6));
      await pump(tester, [
        'email_templates:read',
        'email_templates:manage',
      ], EmailTemplateFormScreen(templateKey: 'welcome', apiService: backend.api));
      await tester.enterText(find.byKey(const ValueKey('template_field_subject')), 'Yeni konu');
      await tester.ensureVisible(find.byKey(const ValueKey('crud_save_button')));
      await tester.tap(find.byKey(const ValueKey('crud_save_button')));
      await settle(tester);

      final put = backend.requests.singleWhere((r) => r.method == 'PUT');
      final body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['templateKey'], 'welcome');
      expect(body['subject'], 'Yeni konu');
      expect(body['optimisticLockVersion'], 6);
    });
  });
}
