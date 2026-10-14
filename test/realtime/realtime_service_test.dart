import 'dart:convert';
import 'dart:math';

import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/realtime_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

/// RealtimeService over fake STOMP links: CONNECT header, resubscribe, backoff, lifecycle, sign-out, token refresh.
void main() {
  late List<FakeStompLink> links;
  late int sessionChecks;
  String? token;

  RealtimeService service({bool autoConnect = false, Future<void> Function()? checkSession}) => RealtimeService(
    connector: ({required url, required headers, required onConnected, required onError, required onClosed}) {
      final link = FakeStompLink(url, headers, onConnected, onError, onClosed);
      links.add(link);
      if (autoConnect) Future.microtask(link.connected);
      return link;
    },
    readToken: () async => token,
    checkSession: checkSession ?? () async => sessionChecks++,
    random: Random(1),
  );

  setUp(() {
    links = [];
    sessionChecks = 0;
    token = 'tok-1';
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('connects to <API origin>/ws with "Authorization: Bearer <stored token>"', () {
    fakeAsync((async) {
      final rt = service()..start();
      async.flushMicrotasks();
      expect(links, hasLength(1));
      expect(links.single.url, '${Uri.parse(ApiService.baseUrl).origin}/ws');
      expect(links.single.headers, {'Authorization': 'Bearer tok-1'});
      expect(rt.connected, isFalse);
      links.single.connected();
      expect(rt.connected, isTrue);
      expect(rt.connectionSeq, 1);
      rt.stop();
    });
  });

  test('no token (signed out meanwhile) → no connection attempt', () {
    fakeAsync((async) {
      token = null;
      final rt = service()..start();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(links, isEmpty);
      rt.stop();
    });
  });

  test('subscriptions made before CONNECTED are attached on connect; send only while connected', () {
    fakeAsync((async) {
      final rt = service()..start();
      final got = <String>[];
      rt.subscribe('/topic/presence', got.add);
      expect(rt.send('/app/x'), isFalse);
      async.flushMicrotasks();
      links.last.connected();
      expect(links.last.destinations, {'/topic/presence'});
      links.last.deliver('/topic/presence', {'userId': 1});
      expect(got, ['{"userId":1}']);
      expect(rt.send('/app/tenant-chat/t1/g/typing'), isTrue);
      expect(links.last.sent, [('/app/tenant-chat/t1/g/typing', '')]);
      rt.stop();
    });
  });

  test('a throwing handler does not break other subscribers', () {
    fakeAsync((async) {
      final rt = service(autoConnect: true)..start();
      final got = <String>[];
      rt.subscribe('/topic/a', (_) => throw const FormatException('bad'));
      rt.subscribe('/topic/a', got.add);
      async.flushMicrotasks();
      links.last.deliver('/topic/a', 'x');
      expect(got, ['x']);
      rt.stop();
    });
  });

  test('dropped connection: exponential backoff (1 s, 2 s, 4 s … 30 s, ±20 %) and every subscription again', () {
    fakeAsync((async) {
      final rt = service()..start();
      rt.subscribe('/topic/presence', (_) {});
      final cancelled = rt.subscribe('/topic/groups/new', (_) {});
      async.flushMicrotasks();
      links.last.connected();
      cancelled.cancel();
      var seq = rt.connectionSeq;

      final delays = <int>[];
      for (var i = 0; i < 7; i++) {
        links.last.drop();
        expect(rt.connected, isFalse);
        final before = links.length;
        var waited = 0;
        while (links.length == before) {
          async.elapse(const Duration(milliseconds: 100));
          waited += 100;
          expect(waited, lessThan(40000));
        }
        delays.add(waited);
        expect(links[before - 1].closed, isTrue);
      }
      // base 1,2,4,8,16,30,30 s with ±20 % jitter
      const bases = [1000, 2000, 4000, 8000, 16000, 30000, 30000];
      for (var i = 0; i < bases.length; i++) {
        expect(delays[i], inInclusiveRange(bases[i] * 0.8 - 100, bases[i] * 1.2 + 100), reason: 'attempt $i');
      }

      links.last.connected();
      expect(rt.connectionSeq, seq + 1);
      expect(links.last.destinations, {'/topic/presence'}, reason: 'cancelled subscription is not restored');
      seq = rt.connectionSeq;

      // A successful connect resets the backoff.
      links.last.drop();
      final before = links.length;
      async.elapse(const Duration(milliseconds: 1300));
      expect(links.length, before + 1);
      rt.stop();
    });
  });

  test('stop (sign-out): closes, forgets subscriptions, never reconnects; next start uses the new token', () {
    fakeAsync((async) {
      final rt = service(autoConnect: true)..start();
      rt.subscribe('/topic/presence', (_) {});
      async.flushMicrotasks();
      final first = links.last;
      rt.stop();
      expect(first.closed, isTrue);
      expect(rt.connected, isFalse);
      first.drop(); // late close callback of the old link
      async.elapse(const Duration(minutes: 2));
      expect(links, hasLength(1));

      token = 'tok-2';
      rt.start();
      async.flushMicrotasks();
      expect(links, hasLength(2));
      expect(links.last.headers['Authorization'], 'Bearer tok-2');
      expect(links.last.destinations, isEmpty, reason: 'previous user subscriptions are gone');
      rt.stop();
    });
  });

  test('background closes the socket (no retries); foreground reconnects at once and re-subscribes', () {
    fakeAsync((async) {
      final rt = service(autoConnect: true)..start();
      rt.subscribe('/user/queue/notifications', (_) {});
      async.flushMicrotasks();
      expect(rt.connectionSeq, 1);

      rt.setForeground(false);
      expect(links.last.closed, isTrue);
      expect(rt.connected, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(links, hasLength(1));

      rt.setForeground(true);
      async.flushMicrotasks();
      expect(links, hasLength(2));
      expect(rt.connected, isTrue);
      expect(rt.connectionSeq, 2, reason: 'listeners re-sync after resume');
      expect(links.last.destinations, {'/user/queue/notifications'});
      rt.stop();
    });
  });

  test('not started (signed out): foreground changes do nothing', () {
    fakeAsync((async) {
      final rt = service();
      rt.setForeground(false);
      rt.setForeground(true);
      async.flushMicrotasks();
      expect(links, isEmpty);
    });
  });

  test('CONNECT rejected (ERROR before CONNECTED): session check once, then reconnect at once with the new token', () {
    fakeAsync((async) {
      final rt = service(
        checkSession: () async {
          sessionChecks++;
          token = 'tok-refreshed'; // ApiService refreshed it on 401
        },
      )..start();
      async.flushMicrotasks();
      links.last.stompError();
      async.flushMicrotasks();
      expect(sessionChecks, 1);
      expect(links, hasLength(2));
      expect(links.last.headers['Authorization'], 'Bearer tok-refreshed');

      // Rejected again in the same streak → no second check, normal backoff.
      links.last.stompError();
      async.flushMicrotasks();
      expect(sessionChecks, 1);
      expect(links, hasLength(2));
      async.elapse(const Duration(milliseconds: 1300));
      expect(links, hasLength(3));

      // After a successful connect the next rejection checks the session again.
      links.last.connected();
      links.last.drop();
      async.elapse(const Duration(milliseconds: 1300));
      links.last.stompError();
      async.flushMicrotasks();
      expect(sessionChecks, 2);
      rt.stop();
    });
  });

  test('ERROR after CONNECTED is a normal drop (backoff, no session check)', () {
    fakeAsync((async) {
      final rt = service(autoConnect: true)..start();
      async.flushMicrotasks();
      links.last.stompError('broker error');
      async.flushMicrotasks();
      expect(sessionChecks, 0);
      expect(links, hasLength(1));
      async.elapse(const Duration(milliseconds: 1300));
      expect(links, hasLength(2));
      rt.stop();
    });
  });

  group('with ApiService (default session check = GET /notifications/unread-count)', () {
    late FakeBackend backend;
    late int expired;

    setUp(() {
      backend = FakeBackend();
      expired = 0;
      ApiService.onSessionExpired = () => expired++;
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'old', 'refreshToken': 'r1', 'tenantId': 't1'});
    });

    tearDown(() => ApiService.onSessionExpired = null);

    RealtimeService real() => RealtimeService(
      api: backend.api,
      connector: ({required url, required headers, required onConnected, required onError, required onClosed}) {
        final link = FakeStompLink(url, headers, onConnected, onError, onClosed);
        links.add(link);
        return link;
      },
      random: Random(1),
    );

    test('expired token: 401 → refresh → reconnect with the refreshed token', () async {
      backend.routes['/notifications/unread-count'] = (req) =>
          req.headers['Authorization'] == 'Bearer new' ? okData({'count': 0}) : http.Response('', 401);
      backend.routes['/auth/refresh'] = (_) => okData({'token': 'new', 'refreshToken': 'r2'});
      final rt = real()..start();
      await Future<void>.delayed(Duration.zero);
      expect(links.single.headers['Authorization'], 'Bearer old');

      links.single.stompError();
      for (var i = 0; i < 20 && links.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(links, hasLength(2));
      expect(links.last.headers['Authorization'], 'Bearer new');
      expect(expired, 0);
      rt.stop();
    });

    test('refresh fails → the regular session-expired (logout) flow runs; after stop nothing reconnects', () async {
      backend.routes['/notifications/unread-count'] = (_) => http.Response('', 401);
      backend.routes['/auth/refresh'] = (_) => http.Response(jsonEncode({'message': 'expired'}), 401);
      final rt = real();
      ApiService.onSessionExpired = () {
        expired++;
        rt.stop(); // what AuthWrapper does on logout
      };
      rt.start();
      await Future<void>.delayed(Duration.zero);
      links.single.stompError();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(expired, 1);
      expect(links, hasLength(1));
      expect(rt.started, isFalse);
    });
  });
}
