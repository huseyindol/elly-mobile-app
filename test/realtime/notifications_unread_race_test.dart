import 'package:elly_mobile_app/models/chat_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';
import '../helpers/gated_backend.dart';

/// `--dart-define=VERIFY_FINDINGS=true` runs the skipped BULGU tests (they fail today, proving the finding).
const _verify = bool.fromEnvironment('VERIFY_FINDINGS');

Map<String, dynamic> n(int id, {bool read = false}) => {
  'id': id,
  'userId': 1,
  'type': 'SYSTEM',
  'title': 'Bildirim $id',
  'message': 'mesaj $id',
  'link': null,
  'read': read,
  'metadata': null,
  'createdAt': '2026-10-14T09:00:00Z',
};

Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 10));

/// Unread badge consistency when REST responses and WebSocket pushes cross each other: never negative, no
/// double-counting, the server's number wins.
void main() {
  late GatedBackend backend;
  late FakeRealtime live;
  late int serverUnread;
  late List<Map<String, dynamic>> list;

  setUp(() {
    backend = GatedBackend();
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    live = FakeRealtime(backend);
    serverUnread = 3;
    list = [n(3), n(2), n(1)];
    backend.routes['/notifications/unread-count'] = (_) => okData({'count': serverUnread});
    backend.routes['/notifications'] = (_) => okData({'content': list, 'last': true});
    for (final id in [1, 2, 3, 9]) {
      backend.routes['/notifications/$id/read'] = (_) => okData(n(id, read: true));
      backend.routes['/notifications/$id'] = (_) => okData(<String, dynamic>{});
    }
    backend.routes['/notifications/read-all'] = (_) => okData({'updated': 3});
  });

  tearDown(() => live.dispose());

  Future<void> started({bool load = true}) async {
    live.realtime.start();
    live.notifications.start();
    await pumpEvents();
    if (load) await live.notifications.load();
    await pumpEvents();
  }

  AppNotification item(int id) => live.notifications.items.firstWhere((x) => x.id == id);

  group('never negative, never below what the list can justify', () {
    test(
      'the count says 0 (stale) but the list shows unread items: marking / deleting / mark-all keep it at 0',
      () async {
        serverUnread = 0;
        await started();
        expect(live.notifications.unreadCount, 0);
        await live.notifications.markRead(item(3));
        expect(live.notifications.unreadCount, 0);
        await live.notifications.remove(item(2));
        expect(live.notifications.unreadCount, 0);
        await live.notifications.markAllRead();
        expect(live.notifications.unreadCount, 0);
      },
    );

    test('count 1, three consecutive reads of different items: floor at 0', () async {
      serverUnread = 1;
      await started();
      for (final id in [3, 2, 1]) {
        await live.notifications.markRead(item(id));
        expect(live.notifications.unreadCount, greaterThanOrEqualTo(0));
      }
      expect(live.notifications.unreadCount, 0);
    });

    test('count not yet known (null → 0): actions do not go below zero', () async {
      live.realtime.start();
      live.notifications.start();
      backend.routes['/notifications/unread-count'] = (_) => throw Exception('offline');
      await pumpEvents();
      await live.notifications.load();
      expect(live.notifications.unreadCount, 0);
      await live.notifications.markRead(item(3));
      await live.notifications.remove(item(2));
      expect(live.notifications.unreadCount, 0);
    });

    test('deleting a READ notification never changes the count; deleting an unread one lowers it once', () async {
      list = [n(3), n(2, read: true), n(1)];
      serverUnread = 2;
      await started();
      await live.notifications.remove(item(2));
      expect(live.notifications.unreadCount, 2);
      await live.notifications.remove(item(1));
      expect(live.notifications.unreadCount, 1);
    });

    test('server push after a local change wins (no extra decrement afterwards)', () async {
      await started();
      await live.notifications.markRead(item(3));
      expect(live.notifications.unreadCount, 2);
      live.push('/user/queue/notifications/unread-count', {'count': 5});
      expect(live.notifications.unreadCount, 5);
      await live.notifications.markRead(item(3)); // already read → no request, no change
      expect(live.notifications.unreadCount, 5);
    });

    test(
      'a negative or fractional server count',
      () async {
        await started();
        live.push('/user/queue/notifications/unread-count', {'count': 2.7});
        expect(live.notifications.unreadCount, 2);
        live.push('/user/queue/notifications/unread-count', {'count': -5});
        expect(live.notifications.unreadCount, greaterThanOrEqualTo(0));
      },
      skip: _verify
          ? null
          : 'BULGU (düşük): _onCount negatif sayıyı olduğu gibi saklıyor (unreadCount → -5). '
                'Rozet ≤0 iken gizli ama tooltip/semantik ve sonraki "-1" hesapları bozulur; max(0, …) ile kıskaçlanmalı.',
    );

    test('count garbage is ignored: null, string, bool, list, missing key', () async {
      await started();
      for (final body in [
        '{"count":null}',
        '{"count":"7"}',
        '{"count":true}',
        '{"count":[1]}',
        '{}',
        '[]',
        '7',
        'x',
        '',
      ]) {
        live.link.deliver('/user/queue/notifications/unread-count', body);
      }
      expect(live.notifications.unreadCount, 3);
    });
  });

  group('WebSocket and REST crossing each other', () {
    test('the server\'s new count arrives AFTER the read response: no double effect', () async {
      await started();
      await live.notifications.markRead(item(3));
      live.push('/user/queue/notifications/unread-count', {'count': 2});
      expect(live.notifications.unreadCount, 2);
    });

    test(
      'the server\'s new count arrives BEFORE the read response (backend pushes inside markRead): stays 2',
      () async {
        await started();
        final gate = backend.hold('/notifications/3/read');
        final read = live.notifications.markRead(item(3));
        await pumpEvents();
        live.push('/user/queue/notifications/unread-count', {'count': 2}); // server already counted this read
        gate.complete();
        await read;
        expect(live.notifications.unreadCount, 2);
        expect(item(3).read, isTrue);
      },
      skip: _verify
          ? null
          : 'BULGU (orta): markRead yanıtı gelince sayaç yerelde bir daha azaltılıyor; backend '
                'markRead içinde unread-count push\'u yolladığı için push önce gelirse (2) yerel düşüş 1 yapar ve bir sonraki '
                'senkrona kadar rozet yanlış (gerçekte 2 okunmamış). Düzeltme: düşüşü yalnız push gelmediyse uygula ya da '
                'markRead sonrası refreshCount() çağır.',
    );

    test(
      'two quick taps on the same unread notification (second one before the first answer) count once',
      () async {
        await started();
        final gate = backend.hold('/notifications/3/read');
        final stale = item(3);
        final first = live.notifications.markRead(stale);
        final second = live.notifications.markRead(stale);
        await pumpEvents();
        gate.complete();
        await Future.wait([first, second]);
        expect(live.notifications.unreadCount, 2);
        expect(backend.requestsTo('/notifications/3/read'), hasLength(1));
      },
      skip: _verify
          ? null
          : 'BULGU (orta): markRead aynı bildirim için uçuştaki isteği izlemiyor — art arda iki dokunuş '
                '(ya da banner "Aç" + liste dokunuşu) iki POST + iki yerel düşüş yapar (3 → 1). Açılamayan '
                'bildirimde ekran kapanmadığı için çift dokunuş gerçekçi.',
    );

    test(
      'a stale (still "unread") object marked read twice one after the other counts once',
      () async {
        await started();
        final stale = item(3);
        await live.notifications.markRead(stale);
        await live.notifications.markRead(stale); // e.g. the banner\'s captured object
        expect(live.notifications.unreadCount, 2);
        expect(backend.requestsTo('/notifications/3/read'), hasLength(1));
      },
      skip: _verify
          ? null
          : 'BULGU (düşük): markRead `n.read` bayrağına yakalanan nesneden bakıyor, güncel listedeki '
                'durumdan değil — bayat nesneyle ikinci çağrı yeniden POST eder ve sayacı bir daha düşürür.',
    );

    test(
      'a new notification pushed while the count request is in flight: the older answer must not erase it',
      () async {
        await started();
        serverUnread = 3;
        final gate = backend.hold('/notifications/unread-count');
        final refresh = live.notifications.refreshCount();
        await pumpEvents();
        serverUnread = 4; // the new one is created on the server...
        live.push('/user/queue/notifications', n(9)); // ...and pushed (+1 locally → 4)
        expect(live.notifications.unreadCount, 4);
        gate.complete(); // the answer computed BEFORE the new notification
        await refresh;
        expect(live.notifications.unreadCount, 4);
      },
      skip: _verify
          ? null
          : 'BULGU (düşük): refreshCount yanıtı, daha yeni bir WS push\'unu (yeni bildirim / count) eziyor; '
                'istek sıra numarası ya da "push geldiyse yanıtı yok say" kontrolü yok. Bir sonraki push / yeniden bağlanmaya '
                'kadar rozet 1 eksik.',
    );

    test('a stale refresh answer must not overwrite a server count push that arrived meanwhile', () async {
      await started();
      final gate = backend.hold('/notifications/unread-count');
      serverUnread = 3;
      final refresh = live.notifications.refreshCount();
      await pumpEvents();
      live.push('/user/queue/notifications/unread-count', {'count': 0}); // read-all in the web panel
      gate.complete();
      await refresh;
      expect(live.notifications.unreadCount, 0);
    }, skip: _verify ? null : 'BULGU (düşük): aynı kök neden — refreshCount sonucu daha yeni push\'u eziyor.');

    test(
      'the same notification pushed twice while the list is NOT loaded counts once (and banners once)',
      () async {
        await started(load: false);
        final banner = <AppNotification>[];
        final sub = live.notifications.incoming.listen(banner.add);
        live.push('/user/queue/notifications', n(9));
        live.push('/user/queue/notifications', n(9));
        await pumpEvents();
        expect(live.notifications.unreadCount, 4);
        expect(banner, hasLength(1));
        await sub.cancel();
      },
      skip: _verify
          ? null
          : 'BULGU (düşük): _onPush tekilleştirmeyi yalnız yüklü listeye göre yapıyor (`_items.any`); '
                'liste hiç açılmadıysa aynı id\'li tekrar push sayacı iki kez artırır ve ikinci banner gösterir.',
    );

    test('a push for an already-read notification does not raise the count; a loaded duplicate is ignored', () async {
      await started();
      live.push('/user/queue/notifications', n(8, read: true));
      expect(live.notifications.unreadCount, 3);
      live.push('/user/queue/notifications', n(9));
      live.push('/user/queue/notifications', n(9));
      expect(live.notifications.unreadCount, 4);
      expect(live.notifications.items.where((x) => x.id == 9), hasLength(1));
    });

    test('reconnect re-reads the truth: a drifted local count is replaced by the server\'s', () async {
      await started();
      live.push('/user/queue/notifications', n(9));
      live.push('/user/queue/notifications', n(9));
      serverUnread = 1;
      live.link.drop();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await pumpEvents();
      expect(live.notifications.unreadCount, 1);
    });
  });

  group('a failed action leaves the numbers alone', () {
    test('mark-all-read / delete that the server refuses do not touch count or list', () async {
      backend.routes['/notifications/read-all'] = (_) => jsonResponse({'message': 'hata'}, 500);
      backend.routes['/notifications/2'] = (_) => jsonResponse({'message': 'yok'}, 404);
      await started();
      await expectLater(live.notifications.markAllRead(), throwsA(anything));
      await expectLater(live.notifications.remove(item(2)), throwsA(anything));
      expect(live.notifications.unreadCount, 3);
      expect(live.notifications.items.map((x) => x.id), [3, 2, 1]);
      expect(live.notifications.items.every((x) => !x.read), isTrue);
    });

    test('paging: a duplicate row on page 2 is dropped; load() resets paging', () async {
      backend.routes['/notifications'] = (req) => okData({
        'content': req.url.queryParameters['page'] == '0' ? [n(3), n(2)] : [n(2), n(1)],
        'last': req.url.queryParameters['page'] != '0',
      });
      await started();
      await live.notifications.loadMore();
      expect(live.notifications.items.map((x) => x.id), [3, 2, 1]);
      await live.notifications.load();
      expect(live.notifications.items.map((x) => x.id), [3, 2]);
      expect(live.notifications.hasMore, isTrue);
    });
  });
}
