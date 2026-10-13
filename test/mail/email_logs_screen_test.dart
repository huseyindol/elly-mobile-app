import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/mail/email_logs_screen.dart';
import 'package:elly_mobile_app/services/text_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _log(int id, String status, {int retry = 0, String? sentAt}) => {
  'id': id,
  'recipient': 'alici$id@ornek.com',
  'subject': 'Konu $id',
  'templateName': 'form-notification',
  'status': status,
  'retryCount': retry,
  'createdAt': '2026-04-0${id}T08:00:00',
  'sentAt': sentAt,
};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.routes['/emails'] = (req) {
      final status = req.url.queryParameters['status'];
      final all = [_log(3, 'FAILED', retry: 3), _log(2, 'SENT', sentAt: '2026-04-02T08:01:00'), _log(1, 'PENDING')];
      final items = status == null ? all : all.where((l) => l['status'] == status).toList();
      return okData({'content': items, 'last': true, 'totalElements': items.length});
    };
    backend.ok('/emails/3/retry', _log(3, 'PENDING'));
    backend.ok('/emails/1/retry', _log(1, 'PENDING'));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, List<String> perms) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, perms));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: EmailLogsScreen(apiService: backend.api)),
      ),
    );
    await settle(tester);
  }

  Iterable<http.Request> gets() => backend.requestsTo('/emails').where((r) => r.method == 'GET');
  Iterable<http.Request> retries(int id) => backend.requestsTo('/emails/$id/retry');
  Finder inRow(int id, Finder f) => find.descendant(of: find.byKey(ValueKey('email_log_$id')), matching: f);

  testWidgets('newest first, paged; rows with status badge, template, retry count; total', (tester) async {
    await pump(tester, ['emails:read']);

    final url = gets().single.url;
    expect(url.queryParametersAll['sort'], ['id,desc']);
    expect(url.queryParameters['page'], '0');
    expect(url.queryParameters.containsKey('status'), isFalse);
    expect(find.text('Toplam 3 kayıt'), findsOneWidget);
    expect(inRow(3, find.text('alici3@ornek.com')), findsOneWidget);
    expect(inRow(3, find.text('Başarısız')), findsOneWidget);
    expect(inRow(2, find.text('Gönderildi')), findsOneWidget);
    expect(inRow(1, find.text('Beklemede')), findsOneWidget);
    expect(inRow(3, find.text('#3 · form-notification')), findsOneWidget);
    expect(inRow(3, find.textContaining('Deneme: 3')), findsOneWidget);
  });

  testWidgets('status chip → server-side ?status= filter, list replaced', (tester) async {
    await pump(tester, ['emails:read']);
    await tester.tap(find.byKey(const ValueKey('status_FAILED')));
    await settle(tester);

    expect(gets().last.url.queryParameters['status'], 'FAILED');
    expect(find.byKey(const ValueKey('email_log_3')), findsOneWidget);
    expect(find.byKey(const ValueKey('email_log_2')), findsNothing);
    expect(find.text('Toplam 1 kayıt'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('status_all')));
    await settle(tester);
    expect(gets().last.url.queryParameters.containsKey('status'), isFalse);
    expect(find.byKey(const ValueKey('email_log_2')), findsOneWidget);
  });

  testWidgets('empty status shows its own message', (tester) async {
    backend.routes['/emails'] = (_) => okData({'content': <Object>[], 'last': true, 'totalElements': 0});
    await pump(tester, ['emails:read']);
    await tester.tap(find.byKey(const ValueKey('status_PENDING')));
    await settle(tester);
    expect(find.text('"Beklemede" durumunda kayıt yok.'), findsOneWidget);
  });

  testWidgets('retry: needs emails:retry; never offered for SENT', (tester) async {
    await pump(tester, ['emails:read']);
    expect(find.byKey(const ValueKey('retry_3')), findsNothing);

    await pump(tester, ['emails:read', 'emails:retry']);
    expect(find.byKey(const ValueKey('retry_3')), findsOneWidget);
    expect(find.byKey(const ValueKey('retry_1')), findsOneWidget, reason: 'stuck PENDING');
    expect(find.byKey(const ValueKey('retry_2')), findsNothing, reason: 'SENT');
  });

  testWidgets('retry: POST → message → list reloads', (tester) async {
    await pump(tester, ['emails:read', 'emails:retry']);
    await tester.tap(find.byKey(const ValueKey('retry_3')));
    await settle(tester);

    expect(retries(3).single.method, 'POST');
    expect(find.text('Mail yeniden kuyruğa alındı'), findsOneWidget);
    expect(gets(), hasLength(2));
  });

  testWidgets('retry error shows the backend message, no reload', (tester) async {
    backend.routes['/emails/3/retry'] = (_) =>
        jsonResponse({'message': 'MailAccount pasif, retry imkansiz (accountId=2)'}, 400);
    await pump(tester, ['emails:read', 'emails:retry']);
    await tester.tap(find.byKey(const ValueKey('retry_3')));
    await settle(tester);

    expect(find.text('MailAccount pasif, retry imkansiz (accountId=2)'), findsOneWidget);
    expect(gets(), hasLength(1));
  });

  testWidgets('detail: every field; retry pops back and reloads', (tester) async {
    await pump(tester, ['emails:read', 'emails:retry']);
    await tester.tap(find.byKey(const ValueKey('email_log_3')));
    await tester.pumpAndSettle();

    expect(find.text('Mail #3'), findsOneWidget);
    for (final text in [
      'alici3@ornek.com',
      'Konu 3',
      'form-notification',
      '3',
      formatDateTimeTr('2026-04-03T08:00:00'),
      'Henüz gönderilmedi',
      'Başarısız',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }

    await tester.tap(find.byKey(const ValueKey('email_log_retry_button')));
    await settle(tester);
    expect(retries(3), hasLength(1));
    expect(find.text('Mail #3'), findsNothing);
    expect(gets(), hasLength(2));
  });

  testWidgets('detail of a SENT mail: sent time, retry disabled with the reason', (tester) async {
    await pump(tester, ['emails:read', 'emails:retry']);
    await tester.tap(find.byKey(const ValueKey('email_log_2')));
    await tester.pumpAndSettle();

    expect(find.text(formatDateTimeTr('2026-04-02T08:01:00')), findsOneWidget);
    expect(find.text('Gönderilmiş mail yeniden kuyruğa alınamaz.'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('email_log_retry_button'))).onPressed, isNull);
  });

  testWidgets('detail without emails:retry has no retry button', (tester) async {
    await pump(tester, ['emails:read']);
    await tester.tap(find.byKey(const ValueKey('email_log_3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('email_log_retry_button')), findsNothing);
  });
}
