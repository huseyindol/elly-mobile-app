import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/config/nav_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/rabbit/queue_detail_screen.dart';
import 'package:elly_mobile_app/screens/rabbit/rabbit_screen.dart';
import 'package:elly_mobile_app/screens/rabbit/republish_screen.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/rabbit_admin.dart';
import 'package:elly_mobile_app/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

/// RabbitMQ: yazarak onay (kuyruk adı birebir), republish gövde doğrulaması, mesaj gövdesinin düz metin
/// gösterimi ve `rabbit:read` / `rabbit:manage` ayrımı. Mevcut `rabbit_admin_test` / `rabbit_screen_test`
/// temel akışı kapsar; burada kenar durumlar var.
Map<String, dynamic> _queue(String name, int messages) => {
  'name': name,
  'vhost': '/',
  'messages': messages,
  'messagesReady': messages,
  'messagesUnacknowledged': 0,
  'consumers': 1,
  'state': 'running',
  'durable': true,
  'autoDelete': false,
};

Map<String, dynamic> _msg(
  String payload, {
  String enc = 'string',
  Object? props,
  String key = 'rk',
}) => {
  'payload': payload,
  'payloadEncoding': enc,
  'properties': props ?? {'content_type': 'application/json'},
  'routingKey': key,
  'redelivered': false,
};

void main() {
  group('rabbit_admin (saf)', () {
    test('queuePath: ayırıcı/özel karakterli adlar tek path parçası olarak kodlanır', () {
      expect(queuePath('a/b'), '/admin/rabbit/queues/a%2Fb');
      expect(queuePath('q?x=1#f'), '/admin/rabbit/queues/q%3Fx%3D1%23f');
      expect(queuePath('100%'), '/admin/rabbit/queues/100%25');
      expect(
        queuePath('türkçe kuyruk'),
        '/admin/rabbit/queues/t%C3%BCrk%C3%A7e%20kuyruk',
      );
      expect(queuePath('q', '/messages'), '/admin/rabbit/queues/q/messages');
      expect(
        queuePath('a%2Fb'),
        '/admin/rabbit/queues/a%252Fb',
        reason: 'önceden kodlanmış metin çift kodlanır',
      );
    });

    test(
      'queuePath: nokta parçaları ("." / "..") ham bırakılmaz (path traversal)',
      () {
        for (final dots in ['.', '..']) {
          expect(
            queuePath(dots, '/purge'),
            isNot('/admin/rabbit/queues/$dots/purge'),
            reason: dots,
          );
        }
      },
    );

    test('clampPeekCount: sınırlar ve negatif', () {
      expect(
        [
          for (final n in [-5, 0, 1, 99, 100, 101, 100000]) clampPeekCount(n),
        ],
        [1, 1, 1, 99, 100, 100, 100],
      );
    });

    test('countOf: sayı → int, diğer her şey 0', () {
      expect(countOf(7), 7);
      expect(countOf(7.9), 7);
      expect(countOf('7'), 0);
      expect(countOf(null), 0);
      expect(countOf(true), 0);
    });

    test('rabbitErrorText: bilinmeyen durum ve ApiException olmayan hata metni aynen geçer', () {
      expect(
        rabbitErrorText(ApiException('Kuyruk adı geçersiz', statusCode: 400)),
        'Kuyruk adı geçersiz',
      );
      expect(rabbitErrorText(ApiException('x', statusCode: 500)), 'x');
      expect(rabbitErrorText(ApiException('x')), 'x');
      expect(
        rabbitErrorText(ApiException('süre doldu', statusCode: 401)),
        'süre doldu',
      );
      expect(rabbitErrorText(StateError('bozuk')), contains('bozuk'));
    });

    group('republishPayloadError', () {
      test(
        'payload zorunlu: boş ya da yalnız boşluk, her content type\'ta',
        () {
          for (final ct in ['application/json', 'text/plain', '']) {
            for (final p in ['', ' ', '\n\t  ']) {
              expect(
                republishPayloadError(p, ct),
                'Payload zorunludur',
                reason: 'ct="$ct" payload="$p"',
              );
            }
          }
        },
      );

      test('"json" içeren her content type JSON doğrular (büyük/küçük harf, +json, charset)', () {
        for (final ct in [
          'application/json',
          'Application/JSON',
          'application/json; charset=utf-8',
          'application/vnd.api+json',
          'text/json',
          'JSON',
        ]) {
          expect(republishPayloadError('{bad', ct), isNotNull, reason: ct);
          expect(republishPayloadError('{"a":1}', ct), isNull, reason: ct);
        }
      });

      test(
        'JSON olmayan content type\'ta gövde serbest metin; olduğu gibi geçer',
        () {
          for (final ct in [
            'text/plain',
            'application/xml',
            'text/html',
            'application/octet-stream',
          ]) {
            expect(republishPayloadError('{bad', ct), isNull, reason: ct);
            expect(republishPayloadError('<a>x</a>', ct), isNull, reason: ct);
          }
        },
      );

      test('JSON gövdeler: nesne, dizi, skaler geçerli; kuyruk çöpü, eksik tırnak, tek tırnak, NaN geçersiz', () {
        for (final ok in [
          '{}',
          '[]',
          '[1,2]',
          '"x"',
          '123',
          'null',
          'true',
          ' {"a":{"b":[1,2,{"c":null}]}} ',
          '{"a":"ü"}',
        ]) {
          expect(
            republishPayloadError(ok, 'application/json'),
            isNull,
            reason: ok,
          );
        }
        for (final bad in [
          '{"a":1}x',
          '{"a":1}{"b":2}',
          "{'a':1}",
          '{a:1}',
          '{"a":1,}',
          '[1,2',
          'NaN',
          'undefined',
          '{"a":}',
        ]) {
          expect(
            republishPayloadError(bad, 'application/json'),
            isNotNull,
            reason: bad,
          );
        }
      });

      test(
        'content type boş/boşluksa varsayılan application/json gönderildiği için JSON doğrulanır',
        () {
          // republishPayload() boş content type'ı 'application/json' yapar; doğrulama da aynı değeri görmeli.
          for (final ct in ['', '   ']) {
            expect(
              republishPayload(
                targetQueue: 'q',
                payload: '{bad',
                contentType: ct,
              )['contentType'],
              'application/json',
            );
            expect(
              republishPayloadError('{bad', ct),
              isNotNull,
              reason: 'ct="$ct"',
            );
          }
        },
      );
    });

    test('republishPayload: tam üç anahtar, hedef/content type trim, payload bayt bayt aynı', () {
      const payload = '  {"a":1}\n\n';
      final p = republishPayload(
        targetQueue: '\t email-queue\n',
        payload: payload,
        contentType: ' text/plain ',
      );
      expect(p, {
        'targetQueue': 'email-queue',
        'payload': payload,
        'contentType': 'text/plain',
      });
    });

    group('prettyPayload / clipText', () {
      test('JSON olmayan metin (HTML, etiket, kontrol karakteri) olduğu gibi döner; JSON güzelleştirilir', () {
        for (final raw in [
          '<script>alert(1)</script>',
          '<img src=x onerror=alert(1)>',
          'düz metin',
          '',
          '   ',
          '{bozuk',
          '\u0000\u001b[31mkırmızı\u001b[0m',
          'a\u{202E}b',
        ]) {
          expect(
            prettyPayload(raw),
            raw,
            reason: raw.codeUnits.take(6).toString(),
          );
        }
        expect(
          prettyPayload('{"a":[1,2]}'),
          '{\n  "a": [\n    1,\n    2\n  ]\n}',
        );
      });

      test('JSON içindeki kontrol karakterleri kaçışlı gösterilir (ham NUL/ESC ekrana basılmaz)', () {
        final out = prettyPayload('{"a":"x\\u0000y\\u001bz"}');
        expect(out.contains('\u0000'), isFalse);
        expect(out.contains('\u001b'), isFalse);
        expect(out, contains(r'\u0000'));
      });

      test(
        'clipText: sınırda kesmez, 1 aşımda keser ve kalan sayıyı yazar',
        () {
          expect(clipText('a' * 10000), 'a' * 10000);
          final cut = clipText('a' * 10001);
          expect(cut, startsWith('a' * 10000));
          expect(cut, endsWith('… (1 karakter daha)'));
          expect(clipText(''), '');
        },
      );

      test(
        'clipText sürrogat çiftini ortadan bölmez (UTF-16 geçerli kalır)',
        () {
          final cut = clipText('${'a' * 9999}😀${'b' * 10}', max: 10000);
          final lone = cut.codeUnits
              .where((c) => c >= 0xD800 && c <= 0xDFFF)
              .length;
          expect(
            lone % 2,
            0,
            reason: 'yalnız kalan yüksek sürrogat -> geçersiz UTF-16',
          );
          expect(() => Characters(cut).length, returnsNormally);
        },
      );

      test(
        'JSON sayı sadakati: büyük tamsayı ve ondalık yazımı güzelleştirmede bozulmaz',
        () {
          // Republish formu peek gövdesini prettyPayload ile doldurur; sayı değişirse yayınlanan mesaj farklı olur.
          final out = prettyPayload(
            '{"id":12345678901234567890,"amount":1.10,"big":1e3}',
          );
          expect(out, contains('12345678901234567890'));
          expect(out, contains('1.10'));
          expect(out, contains('1e3'));
        },
      );
    });
  });

  group('RabbitMQ ekranları', () {
    late FakeBackend backend;
    late AuthProvider auth;
    var queues = <Map<String, dynamic>>[];
    var messages = <Map<String, dynamic>>[];

    setUp(() {
      backend = FakeBackend();
      auth = backend.newAuth();
      queues = [_queue('email-queue', 3), _queue('email-queue.dlq', 7)];
      messages = [_msg('{"a":1}')];
      backend
        ..ok('/admin/rabbit/overview', {
          'rabbitmqVersion': '3.13.1',
          'queueCount': 2,
        })
        ..routes['/admin/rabbit/queues'] = ((_) => okData(queues));
      for (final name in ['email-queue', 'email-queue.dlq']) {
        backend.routes['/admin/rabbit/queues/$name'] = (_) =>
            okData(queues.firstWhere((q) => q['name'] == name));
        backend.routes['/admin/rabbit/queues/$name/messages'] = (_) =>
            okData(messages);
        backend.routes['/admin/rabbit/queues/$name/purge'] = (_) =>
            jsonResponse({'result': true}, 204);
        backend.routes['/admin/rabbit/queues/$name/republish'] = (_) =>
            jsonResponse({'result': true}, 202);
      }
    });

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpHome(
      WidgetTester tester,
      List<String> permissions,
      Widget home,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => backend.signIn(auth, permissions));
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(theme: appTheme, home: home),
        ),
      );
      await settle(tester);
    }

    Finder key(String k) => find.byKey(ValueKey(k));
    Future<void> pumpList(WidgetTester tester, List<String> permissions) =>
        pumpHome(tester, permissions, RabbitScreen(apiService: backend.api));
    Future<void> pumpDetail(
      WidgetTester tester,
      List<String> permissions, {
      String name = 'email-queue.dlq',
    }) => pumpHome(
      tester,
      permissions,
      QueueDetailScreen(
        queue: queues.firstWhere((q) => q['name'] == name),
        apiService: backend.api,
      ),
    );

    Future<void> peek(WidgetTester tester) async {
      await tester.tap(key('peek_button'));
      await settle(tester);
    }

    Future<void> openMessage(WidgetTester tester, int index) async {
      await tester.tap(find.byKey(ValueKey('message_$index')));
      await tester.pumpAndSettle();
    }

    group('purge: kuyruk adı birebir yazılmalı', () {
      Future<bool> confirmEnabledAfterTyping(
        WidgetTester tester,
        String typed,
      ) async {
        await tester.enterText(key('confirm_dialog_text'), typed);
        await tester.pump();
        return tester
                .widget<ElevatedButton>(key('confirm_purge_button'))
                .onPressed !=
            null;
      }

      testWidgets(
        'benzer adlar kabul edilmez: büyük harf, eksik/fazla karakter, başka kuyruk, boş',
        (tester) async {
          await pumpList(tester, ['rabbit:read', 'rabbit:manage']);
          await tester.tap(key('purge_email-queue.dlq'));
          await tester.pumpAndSettle();
          for (final typed in [
            '',
            'EMAIL-QUEUE.DLQ',
            'Email-Queue.dlq',
            'email-queue.dl',
            'email-queue.dlq.',
            'email-queue.dlqx',
            'email-queue',
            'email queue.dlq',
            'email-queue .dlq',
            'e-mail-queue.dlq',
            'email-queue.dlq​', // sıfır genişlikli boşluk
            'еmail-queue.dlq', // Kiril "е"
          ]) {
            expect(
              await confirmEnabledAfterTyping(tester, typed),
              isFalse,
              reason: 'yazılan: "$typed"',
            );
          }
          expect(
            await confirmEnabledAfterTyping(tester, 'email-queue.dlq'),
            isTrue,
          );
          expect(
            backend.requestsTo('/purge'),
            isEmpty,
            reason: 'onaylanana kadar istek yok',
          );
        },
      );

      testWidgets(
        'doğru ad yazıldıktan sonra tekrar bozulursa buton yeniden kapanır',
        (tester) async {
          await pumpList(tester, ['rabbit:read', 'rabbit:manage']);
          await tester.tap(key('purge_email-queue'));
          await tester.pumpAndSettle();
          expect(
            await confirmEnabledAfterTyping(tester, 'email-queue'),
            isTrue,
          );
          expect(
            await confirmEnabledAfterTyping(tester, 'email-queu'),
            isFalse,
          );
        },
      );

      testWidgets(
        'dialog adı ve mesaj sayısını gösterir; yanlış kuyruğun purge yolu çağrılmaz',
        (tester) async {
          await pumpList(tester, ['rabbit:read', 'rabbit:manage']);
          await tester.tap(key('purge_email-queue.dlq'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('"email-queue.dlq" kuyruğundaki 7 mesaj'),
            findsOneWidget,
          );
          await confirmEnabledAfterTyping(tester, 'email-queue.dlq');
          await tester.tap(key('confirm_purge_button'));
          await settle(tester);
          expect(backend.requestsTo('/purge').map((r) => r.url.path), [
            endsWith('/queues/email-queue.dlq/purge'),
          ]);
        },
      );

      testWidgets(
        'özel karakterli kuyruk adı: yazılan ad gerçek ad, POST yolu kodlu',
        (tester) async {
          queues = [_queue('a/b c', 2)];
          backend.routes['/admin/rabbit/queues/a%2Fb%20c/purge'] = (_) =>
              jsonResponse({'result': true}, 204);
          await pumpList(tester, ['rabbit:read', 'rabbit:manage']);
          await tester.tap(key('purge_a/b c'));
          await tester.pumpAndSettle();
          expect(
            await confirmEnabledAfterTyping(tester, 'a%2Fb%20c'),
            isFalse,
            reason: 'kodlanmış biçim ad değil',
          );
          expect(await confirmEnabledAfterTyping(tester, 'a/b c'), isTrue);
          await tester.tap(key('confirm_purge_button'));
          await settle(tester);
          expect(
            backend.requestsTo('/purge').single.url.path,
            endsWith('/queues/a%2Fb%20c/purge'),
          );
        },
      );

      testWidgets(
        'sunucu reddederse (409) hata gösterilir, liste "temizlendi" demez',
        (tester) async {
          backend.routes['/admin/rabbit/queues/email-queue.dlq/purge'] = (_) =>
              jsonResponse({'message': 'busy'}, 409);
          await pumpList(tester, ['rabbit:read', 'rabbit:manage']);
          await tester.tap(key('purge_email-queue.dlq'));
          await tester.pumpAndSettle();
          await confirmEnabledAfterTyping(tester, 'email-queue.dlq');
          await tester.tap(key('confirm_purge_button'));
          await settle(tester);
          expect(find.text('Queue şu an kullanımda'), findsOneWidget);
          expect(find.textContaining('temizlendi'), findsNothing);
        },
      );

      testWidgets(
        'aynı onay dialogu yalnız bir kez gönderir (çift dokunuş tek istek)',
        (tester) async {
          await pumpList(tester, ['rabbit:read', 'rabbit:manage']);
          await tester.tap(key('purge_email-queue.dlq'));
          await tester.pumpAndSettle();
          await confirmEnabledAfterTyping(tester, 'email-queue.dlq');
          await tester.tap(key('confirm_purge_button'));
          await settle(tester);
          expect(backend.requestsTo('/purge'), hasLength(1));
        },
      );
    });

    group('mesaj gövdesi düz metin', () {
      Future<SelectableText> payloadOf(
        WidgetTester tester,
        String payload, {
        Object? props,
      }) async {
        messages = [_msg(payload, props: props)];
        await pumpDetail(tester, ['rabbit:read']);
        await peek(tester);
        await openMessage(tester, 0);
        expect(tester.takeException(), isNull);
        return tester.widget<SelectableText>(key('message_payload_0'));
      }

      for (final html in [
        '<script>alert(1)</script>',
        '<img src=x onerror=alert(1)>',
        '<iframe src="https://evil.example"></iframe>',
        '<a href="javascript:alert(1)">tıkla</a>',
        '<style>body{display:none}</style>x',
        '&lt;b&gt;&amp;',
      ]) {
        testWidgets('HTML metin olarak: $html', (tester) async {
          final text = await payloadOf(tester, html);
          expect(text.data, html, reason: 'ayrıştırılmadan, kaçışsız, birebir');
          expect(find.byType(Image), findsNothing);
        });
      }

      testWidgets(
        'JSON içindeki HTML değeri güzelleştirilir ama etiketler olduğu gibi kalır',
        (tester) async {
          final text = await payloadOf(tester, '{"body":"<b>x</b>"}');
          expect(text.data, '{\n  "body": "<b>x</b>"\n}');
        },
      );

      testWidgets(
        'kontrol karakterleri (NUL, ESC, CR) korunur; bidi kontrolü (RLO) görünür işarete döner',
        (tester) async {
          const raw = 'a\u0000b\u001b[31mc\r\nd\u{202E}e';
          final text = await payloadOf(tester, raw);
          expect(text.data, 'a\u0000b\u001b[31mc\r\nd⟨U+202E⟩e');
        },
      );

      testWidgets(
        '10.000 karakterden uzun gövde kesilir, kalan karakter sayısı yazar',
        (tester) async {
          final text = await payloadOf(tester, 'x' * 10050);
          expect(text.data, endsWith('… (50 karakter daha)'));
          expect(text.data!.length, lessThan(10100));
        },
      );

      testWidgets(
        'kesim noktasında emoji olan gövde ekranı çökertmez',
        (tester) async {
          final text = await payloadOf(tester, '${'a' * 9999}😀${'b' * 10}');
          expect(text.data, endsWith('karakter daha)'));
        },
      );

      testWidgets(
        'routing key ve properties de düz metin (HTML ayrıştırılmaz)',
        (tester) async {
          messages = [
            _msg(
              'x',
              key: '<b>rk</b>',
              props: {'headers': '<script>1</script>'},
            ),
          ];
          await pumpDetail(tester, ['rabbit:read']);
          await peek(tester);
          expect(find.text('#1 · <b>rk</b>'), findsOneWidget);
          await openMessage(tester, 0);
          expect(find.textContaining('<script>1</script>'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('eksik payload / properties / liste dışı veri: çökmez', (
        tester,
      ) async {
        messages = [
          {'payloadEncoding': 'string'},
          {'payload': null, 'properties': null, 'routingKey': null},
        ];
        await pumpDetail(tester, ['rabbit:read']);
        await peek(tester);
        expect(find.byKey(const ValueKey('message_0')), findsOneWidget);
        expect(find.byKey(const ValueKey('message_1')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('peek adedi: 0 → 1, boş → varsayılan 10, harf girilemez', (
        tester,
      ) async {
        await pumpDetail(tester, ['rabbit:read']);
        for (final (typed, expected) in [
          ('0', '1'),
          ('', '10'),
          ('abc', '10'),
          ('250', '100'),
        ]) {
          await tester.enterText(key('peek_count'), typed);
          await peek(tester);
          expect(
            backend.requestsTo('/messages').last.url.queryParameters['count'],
            expected,
            reason: 'girilen "$typed"',
          );
        }
      });
    });

    group('rabbit:read ve rabbit:manage ayrımı', () {
      testWidgets(
        'liste: yalnız read → hiçbir kuyrukta purge yok; manage → boş olmayan kuyruklarda var',
        (tester) async {
          await pumpList(tester, ['rabbit:read']);
          expect(find.textContaining('Purge'), findsNothing);
          expect(key('purge_email-queue'), findsNothing);
        },
      );

      testWidgets(
        'detay: yalnız read → purge, manuel republish, mesaj republish yok; yine de peek yapılabilir',
        (tester) async {
          await pumpDetail(tester, ['rabbit:read']);
          expect(key('detail_purge'), findsNothing);
          expect(key('manual_republish'), findsNothing);
          await peek(tester);
          expect(find.byKey(const ValueKey('message_0')), findsOneWidget);
          await openMessage(tester, 0);
          expect(key('republish_message_0'), findsNothing);
        },
      );

      testWidgets(
        'detay: manage → purge, manuel republish ve mesaj republish görünür',
        (tester) async {
          await pumpDetail(tester, ['rabbit:read', 'rabbit:manage']);
          expect(key('detail_purge'), findsOneWidget);
          expect(key('manual_republish'), findsOneWidget);
          await peek(tester);
          await openMessage(tester, 0);
          expect(key('republish_message_0'), findsOneWidget);
        },
      );

      testWidgets(
        'oturum sırasında manage izni kalkarsa aksiyonlar kendiliğinden kaybolur',
        (tester) async {
          await pumpList(tester, ['rabbit:read', 'rabbit:manage']);
          expect(key('purge_email-queue.dlq'), findsOneWidget);
          await tester.runAsync(() async {
            backend.permissions(const ['rabbit:read']);
            await auth.loadPermissions();
          });
          await tester.pumpAndSettle();
          expect(key('purge_email-queue.dlq'), findsNothing);
        },
      );

      testWidgets(
        'izin yükleme hatası: manage bilinmiyorsa aksiyonlar gizli kalır (fail-closed)',
        (tester) async {
          await tester.runAsync(() async {
            backend.routes['/users/me/permissions'] = (_) =>
                jsonResponse({'message': 'x'}, 500);
          });
          await pumpHome(
            tester,
            const [],
            RabbitScreen(apiService: backend.api),
          );
          expect(find.textContaining('Purge'), findsNothing);
        },
      );

      test('çekmece: RabbitMQ yalnız rabbit:read ile görünür; tek başına rabbit:manage göstermez', () async {
        final item = NavConfig.byId('rabbitmq');
        await backend.signIn(auth, const ['rabbit:read']);
        expect(isNavItemVisible(auth, item), isTrue);
        backend.permissions(const ['rabbit:manage']);
        await auth.loadPermissions();
        expect(isNavItemVisible(auth, item), isFalse);
        backend.permissions(const ['posts:read']);
        await auth.loadPermissions();
        expect(isNavItemVisible(auth, item), isFalse);
      });
    });

    group('republish formu', () {
      Future<void> openManual(
        WidgetTester tester, {
        List<String> permissions = const ['rabbit:read', 'rabbit:manage'],
      }) async {
        await pumpDetail(tester, permissions);
        await tester.tap(key('manual_republish'));
        await settle(tester);
        expect(find.byType(RepublishScreen), findsOneWidget);
      }

      Future<void> send(WidgetTester tester) async {
        await tester.tap(key('republish_send'));
        await tester.pumpAndSettle();
      }

      Future<void> confirm(WidgetTester tester) async {
        await tester.tap(key('confirm_republish_button'));
        await settle(tester);
      }

      testWidgets(
        'varsayılanlar: hedef email-queue, content type application/json, payload boş',
        (tester) async {
          await openManual(tester);
          expect(
            tester
                .widget<TextFormField>(key('republish_target'))
                .controller!
                .text,
            'email-queue',
          );
          expect(
            tester
                .widget<TextFormField>(key('republish_contentType'))
                .controller!
                .text,
            'application/json',
          );
          expect(
            tester
                .widget<TextFormField>(key('republish_payload'))
                .controller!
                .text,
            isEmpty,
          );
        },
      );

      testWidgets(
        'boş/boşluk payload ve boş hedef yerelde reddedilir; onay dialogu açılmaz, istek yok',
        (tester) async {
          await openManual(tester);
          await tester.enterText(key('republish_payload'), '   ');
          await tester.enterText(key('republish_target'), '  ');
          await send(tester);
          expect(find.text('Payload zorunludur'), findsOneWidget);
          expect(find.text('Hedef queue zorunludur'), findsOneWidget);
          expect(find.text('Mesajı Publish Et'), findsNothing);
          expect(backend.requestsTo('/republish'), isEmpty);
        },
      );

      testWidgets(
        'JSON content type + JSON olmayan gövde reddedilir; düzeltince gider (hata hemen güncellenir)',
        (tester) async {
          await openManual(tester);
          await tester.enterText(key('republish_payload'), 'merhaba');
          await send(tester);
          expect(
            find.text('Content type JSON ama payload geçerli JSON değil'),
            findsOneWidget,
          );
          await tester.enterText(key('republish_contentType'), 'text/plain');
          await send(tester);
          expect(
            find.text('Mesajı Publish Et'),
            findsOneWidget,
            reason: 'artık onay dialogu',
          );
          await confirm(tester);
          final body = jsonDecode(
            backend.requestsTo('/email-queue.dlq/republish').single.body,
          ) as Map;
          expect(body, {
            'targetQueue': 'email-queue',
            'payload': 'merhaba',
            'contentType': 'text/plain',
          });
        },
      );

      testWidgets(
        'gövde bayt bayt korunur (baş/son boşluk, satır sonu, HTML) ve hedef trim edilir',
        (tester) async {
          await openManual(tester);
          await tester.enterText(key('republish_contentType'), 'text/html');
          const payload = '  <b>merhaba</b>\n\n';
          await tester.enterText(key('republish_payload'), payload);
          await tester.enterText(key('republish_target'), ' email-queue ');
          await send(tester);
          expect(
            find.textContaining('"email-queue" kuyruğuna publish edilecek'),
            findsOneWidget,
          );
          await confirm(tester);
          final body =
              jsonDecode(backend.requestsTo('/republish').single.body) as Map;
          expect(body['payload'], payload);
          expect(body['targetQueue'], 'email-queue');
          expect(body['contentType'], 'text/html');
        },
      );

      testWidgets('kaynak kuyruk adı yolda kodlanır, hedef gövdede ham gider', (
        tester,
      ) async {
        queues = [_queue('a/b c', 1)];
        backend.routes['/admin/rabbit/queues/a%2Fb%20c'] = (_) =>
            okData(queues.single);
        backend.routes['/admin/rabbit/queues/a%2Fb%20c/republish'] = (_) =>
            jsonResponse({'result': true}, 202);
        await pumpDetail(tester, [
          'rabbit:read',
          'rabbit:manage',
        ], name: 'a/b c');
        await tester.tap(key('manual_republish'));
        await settle(tester);
        await tester.enterText(key('republish_payload'), '{"a":1}');
        await tester.enterText(key('republish_target'), 'hedef/kuyruk');
        await send(tester);
        await confirm(tester);
        final req = backend.requestsTo('/republish').single;
        expect(req.url.path, endsWith('/queues/a%2Fb%20c/republish'));
        expect((jsonDecode(req.body) as Map)['targetQueue'], 'hedef/kuyruk');
      });

      testWidgets(
        'sunucu reddederse (403) hata SnackBar\'da, form açık kalır, gönderim tekrar edilebilir',
        (tester) async {
          backend.routes['/admin/rabbit/queues/email-queue.dlq/republish'] = (
            _,
          ) => jsonResponse({'message': 'no'}, 403);
          await openManual(tester);
          await tester.enterText(key('republish_payload'), '{"a":1}');
          await send(tester);
          await confirm(tester);
          expect(find.text('Bu işlem için yetkin yok'), findsOneWidget);
          expect(find.byType(RepublishScreen), findsOneWidget);
          expect(
            tester.widget<ElevatedButton>(key('republish_send')).onPressed,
            isNotNull,
            reason: 'kilit açıldı',
          );
        },
      );

      testWidgets(
        'peek\'ten gelen text/plain mesaj: content type ve ham gövde forma taşınır',
        (tester) async {
          messages = [
            _msg('merhaba <b>dünya</b>', props: {'content_type': 'text/plain'}),
          ];
          await pumpDetail(tester, ['rabbit:read', 'rabbit:manage']);
          await peek(tester);
          await openMessage(tester, 0);
          await tester.tap(key('republish_message_0'));
          await settle(tester);
          expect(
            tester
                .widget<TextFormField>(key('republish_contentType'))
                .controller!
                .text,
            'text/plain',
          );
          expect(
            tester
                .widget<TextFormField>(key('republish_payload'))
                .controller!
                .text,
            'merhaba <b>dünya</b>',
          );
        },
      );

      for (final (name, props) in <(String, Object?)>[
        ('özellik yok', <String, dynamic>{}),
        ('boş metin', {'content_type': ''}),
        ('metin değil', {'content_type': 5}),
      ]) {
        testWidgets('content_type $name → varsayılan application/json', (
          tester,
        ) async {
          messages = [_msg('{"a":1}', props: props)];
          await pumpDetail(tester, ['rabbit:read', 'rabbit:manage']);
          await peek(tester);
          await openMessage(tester, 0);
          await tester.tap(key('republish_message_0'));
          await settle(tester);
          expect(
            tester
                .widget<TextFormField>(key('republish_contentType'))
                .controller!
                .text,
            'application/json',
          );
        });
      }

      testWidgets(
        'base64 mesaj: Republish kapalı ve etiket sebebi söyler; manage yoksa hiç görünmez',
        (tester) async {
          messages = [_msg('AAEC', enc: 'base64')];
          await pumpDetail(tester, ['rabbit:read', 'rabbit:manage']);
          await peek(tester);
          await openMessage(tester, 0);
          expect(
            tester.widget<TextButton>(key('republish_message_0')).onPressed,
            isNull,
          );
          expect(find.textContaining('base64 desteklenmiyor'), findsOneWidget);
          expect(find.text('base64'), findsOneWidget, reason: 'rozet');
          expect(backend.requestsTo('/republish'), isEmpty);
        },
      );

      testWidgets(
        'payloadEncoding "base64" dışındaki değerler (büyük harf / boş) metin sayılır',
        (tester) async {
          messages = [_msg('x', enc: 'string')];
          await pumpDetail(tester, ['rabbit:read', 'rabbit:manage']);
          await peek(tester);
          await openMessage(tester, 0);
          expect(
            tester.widget<TextButton>(key('republish_message_0')).onPressed,
            isNotNull,
          );
        },
      );
    });
  });
}
