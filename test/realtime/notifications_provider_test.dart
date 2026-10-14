import 'package:elly_mobile_app/models/chat_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

Map<String, dynamic> n(int id, {bool read = false, String? link, Map<String, dynamic>? metadata}) => {
  'id': id,
  'userId': 1,
  'type': 'FORM_SUBMISSION',
  'title': 'Bildirim $id',
  'message': 'mesaj $id',
  'link': link,
  'read': read,
  'tenantId': 't1',
  'metadata': metadata,
  'createdAt': '2026-10-14T09:00:00Z',
};

Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 5));

/// Admin `useNotifications` parity: unread count, list, read / read-all / delete, live pushes, re-sync on reconnect.
void main() {
  late FakeBackend backend;
  late FakeRealtime live;
  late int countCalls;
  late int unread;

  setUp(() {
    backend = FakeBackend();
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    live = FakeRealtime(backend);
    countCalls = 0;
    unread = 3;
    backend.routes['/notifications/unread-count'] = (_) {
      countCalls++;
      return okData({'count': unread});
    };
    backend.routes['/notifications'] = (req) => okData({
      'content': req.url.queryParameters['page'] == '0'
          ? [n(3), n(2, read: true)]
          : [n(1, read: true), n(2, read: true)],
      'last': req.url.queryParameters['page'] != '0',
    });
  });

  tearDown(() => live.dispose());

  Future<void> started() async {
    live.realtime.start();
    live.notifications.start();
    await pumpEvents();
  }

  test('start: subscribes the user queues and loads the unread count', () async {
    await started();
    expect(live.link.destinations, {'/user/queue/notifications', '/user/queue/notifications/unread-count'});
    expect(live.notifications.unreadCount, 3);
  });

  test('list: first page newest first, next page appended without duplicates', () async {
    await started();
    await live.notifications.load();
    expect(live.notifications.items.map((x) => x.id), [3, 2]);
    expect(live.notifications.hasMore, isTrue);
    expect(backend.requests.last.url.query, contains('page=0&size=20'));
    await live.notifications.loadMore();
    expect(live.notifications.items.map((x) => x.id), [3, 2, 1]);
    expect(live.notifications.hasMore, isFalse);
  });

  test('live push: count +1, prepended, emitted for the in-app banner; duplicates and garbage ignored', () async {
    await started();
    await live.notifications.load();
    await pumpEvents(); // the count refresh that follows a list load
    final banner = <AppNotification>[];
    final sub = live.notifications.incoming.listen(banner.add);

    live.push('/user/queue/notifications', n(9, metadata: {'groupId': 'g'}));
    await pumpEvents();
    expect(live.notifications.unreadCount, 4);
    expect(live.notifications.items.first.id, 9);
    expect(banner.single.metadata['groupId'], 'g');

    live.push('/user/queue/notifications', n(9));
    live.push('/user/queue/notifications', 'not json');
    live.push('/user/queue/notifications', {'title': 'no id'});
    await pumpEvents();
    expect(live.notifications.unreadCount, 4);
    expect(banner, hasLength(1));
    await sub.cancel();
  });

  test('server unread-count push is the source of truth', () async {
    await started();
    live.push('/user/queue/notifications/unread-count', {'count': 42});
    expect(live.notifications.unreadCount, 42);
    live.push('/user/queue/notifications/unread-count', {'count': 'x'});
    expect(live.notifications.unreadCount, 42);
  });

  test('mark read / all read / delete', () async {
    backend.routes['/notifications/3/read'] = (_) => okData(n(3, read: true));
    backend.routes['/notifications/read-all'] = (_) => okData({'updated': 1});
    backend.routes['/notifications/2'] = (_) => jsonResponse({'result': true, 'data': null}, 200);
    await started();
    await live.notifications.load();

    await live.notifications.markRead(live.notifications.items.first);
    expect(backend.requestsTo('/notifications/3/read').single.method, 'POST');
    expect(live.notifications.items.first.read, isTrue);
    expect(live.notifications.unreadCount, 2);

    await live.notifications.markRead(live.notifications.items.first); // already read → no request
    expect(backend.requestsTo('/notifications/3/read'), hasLength(1));

    await live.notifications.remove(live.notifications.items[1]);
    expect(backend.requestsTo('/notifications/2').single.method, 'DELETE');
    expect(live.notifications.items.map((x) => x.id), [3]);
    expect(live.notifications.unreadCount, 2, reason: 'a read one does not change the count');

    await live.notifications.markAllRead();
    expect(live.notifications.unreadCount, 0);
    expect(live.notifications.items.every((x) => x.read), isTrue);
  });

  test('a failing action throws (the screen shows it) and changes nothing', () async {
    backend.routes['/notifications/3/read'] = (_) => http.Response('{"message":"Bulunamadı"}', 404);
    await started();
    await live.notifications.load();
    await expectLater(live.notifications.markRead(live.notifications.items.first), throwsA(anything));
    expect(live.notifications.items.first.read, isFalse);
    expect(live.notifications.unreadCount, 3);
  });

  test('every reconnect re-fetches the count, and the list once it was opened', () async {
    await started();
    await live.notifications.load();
    await pumpEvents();
    final listCalls = backend.requestsTo('/notifications').length;
    final counts = countCalls;

    unread = 7;
    live.link.drop();
    await Future<void>.delayed(const Duration(milliseconds: 1400)); // backoff ≈ 1 s
    await pumpEvents();
    expect(live.links, hasLength(2));
    expect(live.notifications.unreadCount, 7);
    expect(countCalls, greaterThan(counts));
    expect(backend.requestsTo('/notifications').length, listCalls + 1);
  });

  test('reset (sign-out): state cleared, queues unsubscribed, late responses dropped', () async {
    await started();
    await live.notifications.load();
    unread = 99;
    final late = live.notifications.refreshCount();
    live.notifications.reset();
    await late;
    expect(live.notifications.unreadCount, 0);
    expect(live.notifications.items, isEmpty);
    expect(live.notifications.loaded, isFalse);
    expect(live.link.destinations, isEmpty);
  });
}
