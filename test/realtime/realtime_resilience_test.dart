import 'dart:async';
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

/// `--dart-define=VERIFY_FINDINGS=true` runs the skipped BULGU tests (they fail today, proving the finding).
const _verify = bool.fromEnvironment('VERIFY_FINDINGS');

/// Deterministic [Random]: only `nextDouble` (the jitter) is used by RealtimeService.
class _Rand implements Random {
  final double Function() draw;
  _Rand(this.draw);

  @override
  double nextDouble() => draw();

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

/// RealtimeService resilience beyond the happy path (fake_async, no network): exact backoff / jitter bounds, rapid
/// start / stop / foreground races, stale callbacks of dead links, the ERROR → session-check → reconnect flow.
void main() {
  late List<FakeStompLink> links;
  late List<Completer<String?>> tokenReads;
  late int sessionChecks;
  String? token;

  /// [pendingToken]: every token read stays open until the test completes it ([tokenReads]).
  RealtimeService service({
    Random? random,
    bool pendingToken = false,
    Future<void> Function()? checkSession,
    bool autoConnect = false,
  }) => RealtimeService(
    connector: ({required url, required headers, required onConnected, required onError, required onClosed}) {
      final link = FakeStompLink(url, headers, onConnected, onError, onClosed);
      links.add(link);
      if (autoConnect) Future.microtask(link.connected);
      return link;
    },
    readToken: () {
      if (!pendingToken) return Future.value(token);
      final c = Completer<String?>();
      tokenReads.add(c);
      return c.future;
    },
    checkSession: checkSession ?? () async => sessionChecks++,
    random: random ?? Random(1),
  );

  Iterable<FakeStompLink> open() => links.where((l) => !l.closed);

  setUp(() {
    links = [];
    tokenReads = [];
    sessionChecks = 0;
    token = 'tok-1';
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('backoff: exact bounds and jitter', () {
    // base 1,2,4,8,16 then capped at 30 s — attempt n waits base * (0.8 + r * 0.4)
    const bases = [1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000];

    /// Connection never succeeds (socket closes at once): the n-th retry fires after exactly [expected] ms.
    void expectDelays(FakeAsync async, RealtimeService rt, List<int> expected) {
      rt.start();
      async.flushMicrotasks();
      for (var i = 0; i < expected.length; i++) {
        links.last.drop();
        final before = links.length;
        async.elapse(Duration(milliseconds: expected[i] - 1));
        expect(links, hasLength(before), reason: 'attempt $i fired early (expected ${expected[i]} ms)');
        async.elapse(const Duration(milliseconds: 1));
        expect(links, hasLength(before + 1), reason: 'attempt $i did not fire at ${expected[i]} ms');
      }
      rt.stop();
    }

    test('lowest jitter draw (0.0) = -20 %: 0.8 s … 24 s', () {
      fakeAsync((async) {
        final rt = service(random: _Rand(() => 0.0));
        expectDelays(async, rt, [for (final b in bases) (b * 0.8).round()]);
      });
    });

    test('highest jitter draw (→1.0) = +20 %: 1.2 s … 36 s, never above', () {
      fakeAsync((async) {
        final rt = service(random: _Rand(() => 0.9999999999));
        expectDelays(async, rt, [for (final b in bases) (b * 1.2).round()]);
        expect((30000 * 1.2).round(), 36000);
      });
    });

    test('40 failures in a row with random jitter: every wait = base * jitter, always inside ±20 %, cap 30 s', () {
      fakeAsync((async) {
        final seeded = Random(42);
        final draws = <double>[];
        final rt = service(
          random: _Rand(() {
            final v = seeded.nextDouble();
            draws.add(v);
            return v;
          }),
        );
        rt.start();
        async.flushMicrotasks();
        for (var i = 0; i < 40; i++) {
          links.last.drop();
          final base = bases[min(i, bases.length - 1)];
          final wait = (base * (0.8 + draws.last * 0.4)).round();
          expect(wait, inInclusiveRange(base * 0.8 - 1, base * 1.2 + 1));
          expect(wait, lessThanOrEqualTo(36000));
          final before = links.length;
          async.elapse(Duration(milliseconds: wait - 1));
          expect(links, hasLength(before), reason: 'attempt $i early');
          async.elapse(const Duration(milliseconds: 1));
          expect(links, hasLength(before + 1), reason: 'attempt $i late');
        }
        rt.stop();
      });
    });

    test('a failed attempt never overlaps another: only one retry timer, never two connections in flight', () {
      fakeAsync((async) {
        final rt = service()..start();
        async.flushMicrotasks();
        links.last.drop();
        links.first.drop(); // a second close callback of the same dead link
        links.first.stompError();
        async.elapse(const Duration(minutes: 2));
        expect(links, hasLength(2), reason: 'one retry only; the 2nd link is alive and never dropped');
        expect(open(), hasLength(1));
        rt.stop();
      });
    });

    test('stop → start resets the backoff (first retry ≈ 1 s, not the 30 s cap)', () {
      fakeAsync((async) {
        final rt = service(random: _Rand(() => 0.5))..start();
        async.flushMicrotasks();
        for (var i = 0; i < 8; i++) {
          links.last.drop();
          async.elapse(const Duration(seconds: 40));
        }
        rt.stop();
        rt.start();
        async.flushMicrotasks();
        final before = links.length;
        links.last.drop();
        async.elapse(const Duration(milliseconds: 1000));
        expect(links, hasLength(before + 1));
        rt.stop();
      });
    });

    test('coming back to the foreground resets the backoff and connects at once (no wait)', () {
      fakeAsync((async) {
        final rt = service(random: _Rand(() => 0.5))..start();
        async.flushMicrotasks();
        for (var i = 0; i < 7; i++) {
          links.last.drop();
          async.elapse(const Duration(seconds: 40));
        }
        links.last.drop(); // 30 s retry pending
        rt.setForeground(false);
        rt.setForeground(true);
        async.flushMicrotasks();
        final resumed = links.length;
        links.last.drop();
        async.elapse(const Duration(milliseconds: 1000));
        expect(links, hasLength(resumed + 1), reason: 'attempt counter restarted at 1 s');
        rt.stop();
      });
    });

    test('connectionSeq increments once per CONNECTED; a repeated CONNECTED on the same link does not', () {
      fakeAsync((async) {
        final rt = service()..start();
        final got = <String>[];
        rt.subscribe('/topic/a', got.add);
        async.flushMicrotasks();
        links.last.connected();
        links.last.connected();
        links.last.connected();
        expect(rt.connectionSeq, 1);
        expect(links.last.subscriptions['/topic/a'], hasLength(1), reason: 'subscribed once');
        links.last.deliver('/topic/a', 'x');
        expect(got, ['x'], reason: 'delivered once');
        rt.stop();
      });
    });
  });

  group('races: rapid start / stop / foreground', () {
    for (final oldFirst in [true, false]) {
      test('start → stop → start while the token read is pending (${oldFirst ? 'old' : 'new'} read completes first): '
          'one link, the new token', () {
        fakeAsync((async) {
          final rt = service(pendingToken: true);
          rt.start(); // read #0 (previous user)
          rt.stop();
          rt.start(); // read #1 (next user)
          expect(tokenReads, hasLength(2));
          if (oldFirst) {
            tokenReads[0].complete('old-user');
            async.flushMicrotasks();
            expect(links, isEmpty, reason: 'stale read must not connect');
            tokenReads[1].complete('new-user');
          } else {
            tokenReads[1].complete('new-user');
            async.flushMicrotasks();
            tokenReads[0].complete('old-user');
          }
          async.flushMicrotasks();
          expect(links, hasLength(1));
          expect(links.single.headers, {'Authorization': 'Bearer new-user'});
          rt.stop();
        });
      });
    }

    test('stop while the token read is pending: no connection ever (signed out meanwhile)', () {
      fakeAsync((async) {
        final rt = service(pendingToken: true)..start();
        rt.stop();
        tokenReads.single.complete('tok');
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        expect(links, isEmpty);
      });
    });

    test('start() twice = one connection; 10 quick start/stop cycles then a final start = one open link', () {
      fakeAsync((async) {
        final rt = service()..start();
        rt.start();
        async.flushMicrotasks();
        expect(links, hasLength(1));
        for (var i = 0; i < 10; i++) {
          rt.stop();
          rt.start();
          if (i.isEven) async.flushMicrotasks();
        }
        async.flushMicrotasks();
        expect(open(), hasLength(1));
        rt.stop();
        expect(open(), isEmpty);
      });
    });

    test('late callbacks of a stopped link are ignored: CONNECTED, ERROR, close — no state, no retry, no check', () {
      fakeAsync((async) {
        final rt = service()..start();
        async.flushMicrotasks();
        final old = links.single;
        rt.stop();
        old.connected();
        old.stompError();
        old.drop();
        async.elapse(const Duration(minutes: 5));
        expect(rt.connected, isFalse);
        expect(rt.connectionSeq, 0);
        expect(sessionChecks, 0);
        expect(links, hasLength(1));
      });
    });

    test('stop → start: late CONNECTED / close of the old link do not touch the new connection', () {
      fakeAsync((async) {
        final rt = service()..start();
        async.flushMicrotasks();
        final old = links.single;
        rt.stop();
        token = 'tok-2';
        rt.start();
        async.flushMicrotasks();
        final fresh = links.last;
        expect(fresh, isNot(same(old)));

        old.connected(); // must not mark the NEW link connected
        expect(rt.connected, isFalse);
        expect(rt.connectionSeq, 0);
        fresh.connected();
        expect(rt.connectionSeq, 1);
        old.connected();
        old.drop();
        old.stompError();
        expect(rt.connected, isTrue, reason: 'new connection survives the old one dying');
        expect(rt.connectionSeq, 1);
        expect(fresh.closed, isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(links, hasLength(2));
        rt.stop();
      });
    });

    test('drop → reconnect: a late CONNECTED / close of the dead link changes nothing (no duplicate attach)', () {
      fakeAsync((async) {
        final rt = service()..start();
        final got = <String>[];
        rt.subscribe('/topic/a', got.add);
        async.flushMicrotasks();
        final dead = links.last..connected();
        dead.drop();
        async.elapse(const Duration(milliseconds: 1300));
        final fresh = links.last..connected();
        expect(rt.connectionSeq, 2);

        dead.connected();
        dead.drop();
        expect(rt.connectionSeq, 2);
        expect(rt.connected, isTrue);
        expect(fresh.subscriptions['/topic/a'], hasLength(1));
        fresh.deliver('/topic/a', 'once');
        expect(got, ['once']);
        async.elapse(const Duration(minutes: 1));
        expect(links, hasLength(2));
        rt.stop();
      });
    });

    test('foreground flapping (false, true, false, true before any token read finishes) = one open link', () {
      fakeAsync((async) {
        final rt = service(autoConnect: true)..start();
        async.flushMicrotasks();
        expect(links, hasLength(1));
        rt.setForeground(false);
        rt.setForeground(true);
        rt.setForeground(false);
        rt.setForeground(true);
        async.flushMicrotasks();
        expect(open(), hasLength(1));
        expect(links, hasLength(2), reason: 'the flapping created at most one extra connection');
        expect(rt.connected, isTrue);
        rt.stop();
      });
    });

    test('foreground → foreground (resumed twice) and background → background do not open or close twice', () {
      fakeAsync((async) {
        final rt = service(autoConnect: true)..start();
        async.flushMicrotasks();
        rt.setForeground(true);
        rt.setForeground(true);
        async.flushMicrotasks();
        expect(links, hasLength(1));
        rt.setForeground(false);
        rt.setForeground(false);
        async.elapse(const Duration(minutes: 3));
        expect(links, hasLength(1));
        expect(open(), isEmpty);
        rt.setForeground(true);
        rt.setForeground(true);
        async.flushMicrotasks();
        expect(links, hasLength(2));
        expect(open(), hasLength(1));
        rt.stop();
      });
    });

    test('backgrounded while the token read is pending: no link; resume connects exactly once', () {
      fakeAsync((async) {
        final rt = service(pendingToken: true)..start();
        rt.setForeground(false);
        tokenReads.single.complete('tok');
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(links, isEmpty);
        rt.setForeground(true);
        tokenReads.last.complete('tok');
        async.flushMicrotasks();
        expect(links, hasLength(1));
        rt.stop();
      });
    });

    test('background during a pending retry cancels it; resume opens one link; the old timer never fires a 2nd', () {
      fakeAsync((async) {
        final rt = service()..start();
        async.flushMicrotasks();
        links.last.drop(); // retry in ~1 s
        rt.setForeground(false);
        async.elapse(const Duration(minutes: 1));
        expect(links, hasLength(1));
        rt.setForeground(true);
        async.flushMicrotasks();
        expect(links, hasLength(2));
        async.elapse(const Duration(minutes: 2));
        expect(links, hasLength(2));
        expect(open(), hasLength(1));
        rt.stop();
      });
    });

    test('resume while a retry is pending (still foreground): the pending timer is replaced, not doubled', () {
      fakeAsync((async) {
        final rt = service()..start();
        async.flushMicrotasks();
        links.last.drop();
        rt.setForeground(false);
        rt.setForeground(true);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(links, hasLength(2));
        expect(open(), hasLength(1));
        rt.stop();
      });
    });
  });

  group('subscriptions do not leak between connections or users', () {
    test('subscribe on link 1, cancel while offline, subscribe a new one: link 2 has exactly the live ones', () {
      fakeAsync((async) {
        final rt = service()..start();
        final a = <String>[];
        final b = <String>[];
        final c = <String>[];
        rt.subscribe('/topic/a', a.add);
        final subB = rt.subscribe('/topic/b', b.add);
        async.flushMicrotasks();
        links.last.connected();
        final first = links.last;
        first.drop();
        subB.cancel(); // while offline
        rt.subscribe('/topic/c', c.add);
        async.elapse(const Duration(milliseconds: 1300));
        links.last.connected();
        expect(links.last.destinations, {'/topic/a', '/topic/c'});
        links.last
          ..deliver('/topic/a', '1')
          ..deliver('/topic/b', '2')
          ..deliver('/topic/c', '3');
        expect(a, ['1']);
        expect(b, isEmpty, reason: 'cancelled while offline');
        expect(c, ['3']);
        rt.stop();
      });
    });

    test('a handle created before a reconnect cancels the subscription on the NEW link', () {
      fakeAsync((async) {
        final rt = service()..start();
        final got = <String>[];
        async.flushMicrotasks();
        links.last.connected();
        final handle = rt.subscribe('/topic/a', got.add);
        links.last.drop();
        async.elapse(const Duration(milliseconds: 1300));
        links.last.connected();
        expect(links.last.destinations, {'/topic/a'});
        handle.cancel();
        handle.cancel(); // idempotent
        expect(links.last.destinations, isEmpty);
        links.last.deliver('/topic/a', 'x');
        expect(got, isEmpty);
        rt.stop();
      });
    });

    test('sign-out → another user signs in: nothing of the first user is subscribed on the new connection', () {
      fakeAsync((async) {
        final rt = service(autoConnect: true)..start();
        final seenByA = <String>[];
        rt.subscribe('/topic/user/7/membership', seenByA.add);
        rt.subscribe('/topic/tenant/t1/group/g', seenByA.add);
        rt.subscribe('/user/queue/notifications', seenByA.add);
        async.flushMicrotasks();
        expect(links.single.destinations, hasLength(3));

        rt.stop(); // logout
        token = 'tok-user-b';
        rt.start(); // login
        async.flushMicrotasks();
        expect(links, hasLength(2));
        expect(links.last.headers['Authorization'], 'Bearer tok-user-b');
        expect(links.last.destinations, isEmpty);
        expect(rt.connectionSeq, 2, reason: 'monotonic across sessions: providers compare it with the value they saw');

        // B subscribes its own; A's are not coming back after yet another reconnect.
        rt.subscribe('/topic/user/9/membership', (_) {});
        links.last.drop();
        async.elapse(const Duration(milliseconds: 1300));
        async.flushMicrotasks();
        expect(links.last.destinations, {'/topic/user/9/membership'});
        expect(links.last.destinations.any((d) => d.contains('/7/') || d.contains('/t1/')), isFalse);
        expect(seenByA, isEmpty);
        rt.stop();
      });
    });

    test(
      'stop → a frame of the old link still in flight must not reach the old subscribers (SECURITY, defense)',
      () {
        fakeAsync((async) {
          final rt = service(autoConnect: true)..start();
          final got = <String>[];
          rt.subscribe('/topic/user/7/membership', got.add);
          async.flushMicrotasks();
          final old = links.single;
          rt.stop();
          old.deliver('/topic/user/7/membership', {'groupId': 'x'});
          expect(got, isEmpty);
        });
      },
      skip: _verify
          ? null
          : 'BULGU (düşük): stop() `_subs`i temizliyor ama eski bağlantıdaki işleyici sarmalayıcısı pasifleştirilmiyor '
                '(_attach içinde `_link != link` / abonelik hâlâ kayıtlı mı kontrolü yok) — kuyrukta kalan MESSAGE çıkış sonrası '
                'eski abonelere ulaşır. stomp_dart_client deactivate sonrası çerçeve vermez; derinlemesine savunma boşluğu.',
    );

    test(
      'reconnect → a frame of the dead link still in flight must not be handled a 2nd time',
      () {
        fakeAsync((async) {
          final rt = service()..start();
          final got = <String>[];
          rt.subscribe('/topic/a', got.add);
          async.flushMicrotasks();
          final dead = links.last..connected();
          dead.drop();
          async.elapse(const Duration(milliseconds: 1300));
          links.last.connected();
          dead.deliver('/topic/a', 'late');
          expect(got, isEmpty);
          rt.stop();
        });
      },
      skip: _verify ? null : 'BULGU (düşük): ölü bağlantının sarmalayıcısı sub.onMessage\'ı hâlâ çağırır (yukarıdaki ile aynı kök neden).',
    );
  });

  group('ERROR before CONNECTED → session check → reconnect', () {
    test('ERROR and the close that follows it on the same link = ONE check and ONE reconnect', () {
      fakeAsync((async) {
        final rt = service()..start();
        async.flushMicrotasks();
        links.last.stompError();
        links.first.drop(); // the server closes the socket after ERROR
        async.flushMicrotasks();
        expect(sessionChecks, 1);
        expect(links, hasLength(2));
        async.elapse(const Duration(minutes: 3));
        expect(links, hasLength(2), reason: 'no stray backoff retry');
        expect(open(), hasLength(1));
        rt.stop();
      });
    });

    test('pending check + background → foreground: the resume connects once; the late check does not add a 2nd', () {
      fakeAsync((async) {
        final check = Completer<void>();
        final rt = service(
          checkSession: () {
            sessionChecks++;
            return check.future;
          },
        )..start();
        async.flushMicrotasks();
        links.last.stompError();
        async.flushMicrotasks();
        expect(sessionChecks, 1);
        expect(links, hasLength(1), reason: 'waiting for the refresh result');

        rt.setForeground(false);
        rt.setForeground(true);
        async.flushMicrotasks();
        expect(links, hasLength(2));
        check.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(links, hasLength(2));
        expect(open(), hasLength(1));
        rt.stop();
      });
    });

    test('pending check + sign-out: the late result never reconnects a signed-out user', () {
      fakeAsync((async) {
        final check = Completer<void>();
        final rt = service(
          checkSession: () {
            sessionChecks++;
            return check.future;
          },
        )..start();
        async.flushMicrotasks();
        links.last.stompError();
        async.flushMicrotasks();
        rt.stop();
        check.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        expect(links, hasLength(1));
        expect(rt.started, isFalse);
      });
    });

    test('pending check + sign-out + another sign-in: the late result of the first session adds no 2nd link', () {
      fakeAsync((async) {
        final check = Completer<void>();
        final rt = service(
          checkSession: () {
            sessionChecks++;
            return check.future;
          },
        )..start();
        async.flushMicrotasks();
        links.last.stompError();
        async.flushMicrotasks();
        rt.stop();
        rt.start(); // user B
        async.flushMicrotasks();
        expect(links, hasLength(2));
        check.complete();
        async.flushMicrotasks();
        expect(links, hasLength(2));
        expect(open(), hasLength(1));
        rt.stop();
      });
    });

    test('a failing session check (offline) still reconnects once; the next rejection backs off — no check storm', () {
      fakeAsync((async) {
        final rt = service(
          checkSession: () async {
            sessionChecks++;
            throw ApiException('offline');
          },
        )..start();
        async.flushMicrotasks();
        links.last.stompError();
        async.flushMicrotasks();
        expect(links, hasLength(2));
        links.last.stompError();
        async.flushMicrotasks();
        expect(links, hasLength(2), reason: 'backoff now, not an immediate retry');
        async.elapse(const Duration(milliseconds: 1300));
        expect(links, hasLength(3));
        links.last.stompError();
        async.elapse(const Duration(minutes: 1));
        expect(sessionChecks, 1, reason: 'one check per failure streak');
        rt.stop();
      });
    });

    test('rejected again after a successful connect + drop: a new streak = a new check', () {
      fakeAsync((async) {
        final rt = service()..start();
        async.flushMicrotasks();
        links.last.stompError();
        async.flushMicrotasks();
        expect(sessionChecks, 1);
        links.last.connected();
        links.last.drop();
        async.elapse(const Duration(milliseconds: 1300));
        links.last.stompError();
        async.flushMicrotasks();
        expect(sessionChecks, 2);
        rt.stop();
      });
    });

    test(
      'a new session (stop → start) starts with a clean streak: its first rejection is checked',
      () {
        fakeAsync((async) {
          final rt = service()..start();
          async.flushMicrotasks();
          links.last.stompError(); // check #1
          async.flushMicrotasks();
          links.last.stompError(); // same streak → backoff, no check
          async.flushMicrotasks();
          expect(sessionChecks, 1);

          rt.stop();
          rt.start(); // another user
          async.flushMicrotasks();
          links.last.stompError();
          async.flushMicrotasks();
          expect(sessionChecks, 2);
          rt.stop();
        });
      },
      skip: _verify
          ? null
          : 'BULGU (düşük): `_sessionChecked` stop()/start() ile sıfırlanmıyor — bir önceki oturumun ret serisi '
                'bittiyse yeni kullanıcının ilk CONNECT reddi oturum kontrolü yapmadan yalnız backoff\'a düşer.',
    );
  });

  group('with ApiService (default session check)', () {
    late FakeBackend backend;
    late int expired;
    late int refreshCalls;
    late int countCalls;

    setUp(() {
      backend = FakeBackend();
      expired = 0;
      refreshCalls = 0;
      countCalls = 0;
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

    Future<void> until(bool Function() condition) async {
      for (var i = 0; i < 40 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test(
      'refresh succeeds: exactly ONE refresh, ONE reconnect (with the new token), no logout, no stray retry',
      () async {
        backend.routes['/notifications/unread-count'] = (req) {
          countCalls++;
          return req.headers['Authorization'] == 'Bearer new' ? okData({'count': 0}) : http.Response('', 401);
        };
        backend.routes['/auth/refresh'] = (_) {
          refreshCalls++;
          return okData({'token': 'new', 'refreshToken': 'r2'});
        };
        final rt = real()..start();
        await Future<void>.delayed(Duration.zero);
        links.single.stompError();
        links.single.drop();
        await until(() => links.length >= 2);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(links, hasLength(2));
        expect(links.last.headers['Authorization'], 'Bearer new');
        expect(refreshCalls, 1);
        expect(countCalls, 2, reason: '401, then the retry with the refreshed token');
        expect(expired, 0);
        rt.stop();
      },
    );

    test(
      'refresh fails: logout flow once; if nothing stops the service the 2nd rejection backs off (no refresh storm)',
      () async {
        backend.routes['/notifications/unread-count'] = (_) => http.Response('', 401);
        backend.routes['/auth/refresh'] = (_) {
          refreshCalls++;
          return http.Response(jsonEncode({'message': 'expired'}), 401);
        };
        final rt = real()..start();
        await Future<void>.delayed(Duration.zero);
        links.single.stompError();
        await until(() => links.length >= 2);
        expect(expired, 1);
        expect(refreshCalls, 1);

        links.last.stompError(); // still rejected, same streak
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(refreshCalls, 1, reason: 'no refresh per retry');
        expect(expired, 1);
        expect(links, hasLength(2), reason: 'waiting for the backoff');
        rt.stop();
      },
    );

    test('refresh fails and logout stops the service: no link is ever opened again', () async {
      backend.routes['/notifications/unread-count'] = (_) => http.Response('', 401);
      backend.routes['/auth/refresh'] = (_) => http.Response(jsonEncode({'message': 'expired'}), 401);
      final rt = real();
      ApiService.onSessionExpired = () {
        expired++;
        rt.stop();
      };
      rt.start();
      await Future<void>.delayed(Duration.zero);
      links.single.stompError();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(expired, 1);
      expect(links, hasLength(1));
      expect(rt.started, isFalse);
      expect(rt.connected, isFalse);
    });
  });
}
