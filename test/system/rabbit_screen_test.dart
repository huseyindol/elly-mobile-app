import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/rabbit/queue_detail_screen.dart';
import 'package:elly_mobile_app/screens/rabbit/rabbit_screen.dart';
import 'package:elly_mobile_app/screens/rabbit/republish_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _queue(String name, int messages, {String state = 'running'}) => {
  'name': name,
  'vhost': '/',
  'messages': messages,
  'messagesReady': messages,
  'messagesUnacknowledged': 0,
  'consumers': 1,
  'state': state,
  'arguments': {'x-dead-letter-exchange': 'dlx'},
  'policy': null,
  'durable': true,
  'autoDelete': false,
};

const _html = '<script>alert(1)</script><b>kalın</b>';

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend
      ..ok('/admin/rabbit/overview', {
        'rabbitmqVersion': '3.13.1',
        'erlangVersion': '26.2',
        'clusterName': 'rabbit@elly',
        'totalMessages': 7,
        'totalConsumers': 2,
        'queueCount': 2,
        'exchangeCount': 9,
      })
      ..ok('/admin/rabbit/queues', [_queue('email-queue', 0), _queue('email-queue.dlq', 7, state: 'idle')])
      ..ok('/admin/rabbit/queues/email-queue.dlq', _queue('email-queue.dlq', 7, state: 'idle'))
      ..ok('/admin/rabbit/queues/email-queue.dlq/messages', [
        {
          'payload': '{"to":"a@b.com","html":"$_html"}',
          'payloadEncoding': 'string',
          'properties': {'content_type': 'application/json'},
          'routingKey': 'email-queue',
          'redelivered': true,
        },
        {'payload': 'AAEC', 'payloadEncoding': 'base64', 'properties': {}, 'routingKey': '', 'redelivered': false},
      ]);
    backend.routes['/admin/rabbit/queues/email-queue.dlq/purge'] = (_) => jsonResponse({'result': true}, 204);
    backend.routes['/admin/rabbit/queues/email-queue.dlq/republish'] = (_) =>
        jsonResponse({'result': true, 'message': 'ok'}, 202);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpRabbit(WidgetTester tester, List<String> permissions) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, permissions));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          theme: appTheme,
          home: RabbitScreen(apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> openDetail(WidgetTester tester, List<String> permissions) async {
    await pumpRabbit(tester, permissions);
    await tester.tap(find.text('email-queue.dlq'));
    await settle(tester);
    expect(find.byType(QueueDetailScreen), findsOneWidget);
  }

  testWidgets('overview and queue counts; read-only user gets no purge', (tester) async {
    await pumpRabbit(tester, ['rabbit:read']);
    expect(find.text('RabbitMQ 3.13.1'), findsOneWidget);
    expect(find.text('9'), findsOneWidget); // exchanges
    expect(find.descendant(of: key('queue_email-queue.dlq'), matching: find.text('Toplam: 7')), findsOneWidget);
    expect(find.textContaining('Purge'), findsNothing);
  });

  testWidgets('rabbit:manage: purge disabled on an empty queue; typed name required, then POST …/purge', (
    tester,
  ) async {
    await pumpRabbit(tester, ['rabbit:read', 'rabbit:manage']);
    expect(tester.widget<TextButton>(key('purge_email-queue')).onPressed, isNull);

    await tester.tap(key('purge_email-queue.dlq'));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(key('confirm_purge_button')).onPressed, isNull);
    await tester.enterText(key('confirm_dialog_text'), 'email-queue');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(key('confirm_purge_button')).onPressed, isNull, reason: 'other queue name');
    await tester.enterText(key('confirm_dialog_text'), 'email-queue.dlq');
    await tester.pump();
    await tester.tap(key('confirm_purge_button'));
    await settle(tester);

    expect(backend.requestsTo('/email-queue.dlq/purge').single.method, 'POST');
    expect(find.text('Queue "email-queue.dlq" temizlendi'), findsOneWidget);
    expect(backend.requestsTo('/admin/rabbit/queues').length, greaterThan(1), reason: 'list reloaded');
  });

  testWidgets('purge cancelled → nothing sent', (tester) async {
    await pumpRabbit(tester, ['rabbit:read', 'rabbit:manage']);
    await tester.tap(key('purge_email-queue.dlq'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(backend.requestsTo('/purge'), isEmpty);
  });

  testWidgets('broker unavailable (503) → admin wording', (tester) async {
    backend.routes['/admin/rabbit/overview'] = (_) => jsonResponse({'message': 'x'}, 503);
    await pumpRabbit(tester, ['rabbit:read']);
    expect(find.textContaining('RabbitMQ şu an erişilemez'), findsOneWidget);
  });

  group('detail', () {
    testWidgets('fresh detail; messages only on request; payload is plain text (HTML not rendered)', (tester) async {
      await openDetail(tester, ['rabbit:read']);
      expect(backend.requestsTo('/queues/email-queue.dlq'), hasLength(1));
      expect(backend.requestsTo('/messages'), isEmpty, reason: 'peek is not automatic');
      expect(find.textContaining('x-dead-letter-exchange'), findsOneWidget);

      await tester.enterText(key('peek_count'), '500');
      await tester.tap(key('peek_button'));
      await settle(tester);
      expect(backend.requestsTo('/messages').single.url.queryParameters['count'], '100');
      expect(find.text('redelivered'), findsOneWidget);

      await tester.tap(find.text('#1 · email-queue'));
      await tester.pumpAndSettle();
      final payload = tester.widget<SelectableText>(key('message_payload_0'));
      expect(payload.data, contains(_html), reason: 'markup shown verbatim');
      expect(find.byKey(const ValueKey('republish_message_0')), findsNothing, reason: 'no rabbit:manage');
      expect(key('detail_purge'), findsNothing);
      expect(key('manual_republish'), findsNothing);
    });

    testWidgets('republish a peeked message: prefilled, confirmed, POST body', (tester) async {
      await openDetail(tester, ['rabbit:read', 'rabbit:manage']);
      await tester.tap(key('peek_button'));
      await settle(tester);
      await tester.tap(find.text('#1 · email-queue'));
      await tester.pumpAndSettle();
      await tester.tap(key('republish_message_0'));
      await settle(tester);
      expect(find.byType(RepublishScreen), findsOneWidget);

      await tester.tap(key('republish_send'));
      await tester.pumpAndSettle();
      expect(find.text('Mesajı Publish Et'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(backend.requestsTo('/republish'), isEmpty);

      await tester.tap(key('republish_send'));
      await tester.pumpAndSettle();
      await tester.tap(key('confirm_republish_button'));
      await settle(tester);
      final body = jsonDecode(backend.requestsTo('/email-queue.dlq/republish').single.body) as Map;
      expect(body['targetQueue'], 'email-queue');
      expect(body['contentType'], 'application/json');
      expect(jsonDecode(body['payload'] as String), {'to': 'a@b.com', 'html': _html});
      expect(find.byType(RepublishScreen), findsNothing);
    });

    testWidgets('base64 message cannot be republished as text', (tester) async {
      await openDetail(tester, ['rabbit:read', 'rabbit:manage']);
      await tester.tap(key('peek_button'));
      await settle(tester);
      await tester.tap(find.text('#2 · —'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(key('republish_message_1')).onPressed, isNull);
    });

    testWidgets('manual republish: invalid JSON with a JSON content type is refused locally', (tester) async {
      await openDetail(tester, ['rabbit:read', 'rabbit:manage']);
      await tester.tap(key('manual_republish'));
      await settle(tester);
      await tester.enterText(key('republish_payload'), '{bozuk');
      await tester.tap(key('republish_send'));
      await tester.pumpAndSettle();
      expect(find.text('Content type JSON ama payload geçerli JSON değil'), findsOneWidget);
      expect(find.text('Mesajı Publish Et'), findsNothing);
    });

    testWidgets('detail purge uses the same typed confirmation', (tester) async {
      await openDetail(tester, ['rabbit:read', 'rabbit:manage']);
      await tester.tap(key('detail_purge'));
      await tester.pumpAndSettle();
      await tester.enterText(key('confirm_dialog_text'), 'email-queue.dlq');
      await tester.pump();
      await tester.tap(key('confirm_purge_button'));
      await settle(tester);
      expect(backend.requestsTo('/email-queue.dlq/purge'), hasLength(1));
    });
  });

  group('fix round', () {
    testWidgets('republish from a peeked message: raw body (numbers intact), copy note, peek list cleared', (
      tester,
    ) async {
      backend.ok('/admin/rabbit/queues/email-queue.dlq/messages', [
        {
          'payload': '{"id":12345678901234567890,"amount":1.10}',
          'payloadEncoding': 'string',
          'properties': {'message_id': 'm-1'},
          'routingKey': 'email-queue',
        },
      ]);
      await openDetail(tester, ['rabbit:read', 'rabbit:manage']);
      await tester.tap(key('peek_button'));
      await settle(tester);
      await tester.tap(find.text('#1 · email-queue'));
      await tester.pumpAndSettle();
      await tester.tap(key('republish_message_0'));
      await settle(tester);
      expect(
        tester.widget<TextFormField>(key('republish_payload')).controller!.text,
        '{"id":12345678901234567890,"amount":1.10}',
      );
      await tester.tap(key('republish_send'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kaynak kuyruktaki mesaj silinmez (kopyalanır)'), findsOneWidget);
      await tester.tap(key('confirm_republish_button'));
      await settle(tester);
      expect(
        (jsonDecode(backend.requestsTo('/republish').single.body) as Map)['payload'],
        '{"id":12345678901234567890,"amount":1.10}',
      );
      expect(key('message_0'), findsNothing, reason: 'stale peek list cleared');
      expect(find.text('Mesajları Göster'), findsOneWidget);
    });

    testWidgets('manual republish from a non-DLQ queue has no default target', (tester) async {
      backend.ok('/admin/rabbit/queues/email-queue', _queue('email-queue', 0));
      await pumpRabbit(tester, ['rabbit:read', 'rabbit:manage']);
      await tester.tap(find.text('email-queue'));
      await settle(tester);
      await tester.tap(key('manual_republish'));
      await settle(tester);
      expect(tester.widget<TextFormField>(key('republish_target')).controller!.text, isEmpty);
      expect(find.textContaining('Kaynak bir DLQ değil'), findsOneWidget);
    });

    testWidgets('long payload: "Tümünü göster" (background isolate) and "Kopyala" (raw)', (tester) async {
      final raw = '{"a":"${'x' * 10010}"}';
      backend.ok('/admin/rabbit/queues/email-queue.dlq/messages', [
        {'payload': raw, 'payloadEncoding': 'string', 'properties': {}, 'routingKey': 'rk'},
      ]);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await openDetail(tester, ['rabbit:read']);
      await tester.tap(key('peek_button'));
      await settle(tester);
      await tester.tap(find.text('#1 · rk'));
      await tester.pumpAndSettle();
      expect(tester.widget<SelectableText>(key('message_payload_0')).data, endsWith('karakter daha)'));

      await tester.tap(key('message_payload_0_copy'));
      await tester.pump();
      expect(copied, raw);

      await tester.tap(key('message_payload_0_all'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
      expect(tester.widget<SelectableText>(key('message_payload_0')).data, startsWith('{\n  "a": "xxx'));
      expect(key('message_payload_0_all'), findsNothing);
    });

    testWidgets('purge dialog says the count is approximate', (tester) async {
      await pumpRabbit(tester, ['rabbit:read', 'rabbit:manage']);
      await tester.tap(key('purge_email-queue.dlq'));
      await tester.pumpAndSettle();
      expect(find.textContaining('7 mesaj (yaklaşık'), findsOneWidget);
    });
  });
}
