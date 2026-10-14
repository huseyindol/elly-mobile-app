import 'dart:async';

import 'package:elly_mobile_app/providers/call_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'fake_backend.dart';
import 'fake_call_media.dart';
import 'fake_realtime.dart';

const me = 7;
const c1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const c2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const c3 = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const g1 = '11111111-1111-4111-8111-111111111111';

/// Lets queued microtasks and 1 ms timers run (signal handlers, media queue, notices, mock storage).
Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 2));

/// A signed-in [CallProvider] over fake STOMP + fake media: everything in memory, nothing leaves the process.
/// [FakeCalls] holds one [FakeCallMedia] per call; [leaks] lists every resource a finished call kept.
class CallRig {
  final FakeRealtime live;
  final FakeCalls calls;
  bool providerDisposed = false;

  CallRig._(this.live, this.calls);

  factory CallRig({
    Duration ringGuard = const Duration(seconds: 35),
    Duration connectGuard = const Duration(seconds: 30),
  }) {
    final backend = FakeBackend(); // resets the mock secure storage: set the token after it
    final live = FakeRealtime(backend);
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    return CallRig._(live, FakeCalls(live, ringGuard: ringGuard, connectGuard: connectGuard)..listen());
  }

  /// Opens the (fake) socket and starts listening for [userId]'s call signals. Await [flush] (or flushMicrotasks).
  Future<void> start({int userId = me}) async {
    live.realtime.start();
    for (var i = 0; i < 100 && !live.realtime.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    calls.provider.start(userId);
  }

  /// Same, for `fakeAsync` zones: no real timers, microtasks only.
  void startSync(void Function() flushMicrotasks, {int userId = me}) {
    live.realtime.start();
    flushMicrotasks();
    calls.provider.start(userId);
  }

  CallProvider get provider => calls.provider;

  void signal(Map<String, Object?> body, {int user = me}) => calls.signal(user, body);

  void incoming({String id = c1, bool ringAll = false, int from = 5, String name = 'mehmet', int user = me}) => signal({
    'type': 'INCOMING_CALL',
    'callId': id,
    'peerUserId': from,
    'peerDisplayName': name,
    'ringAll': ringAll,
  }, user: user);

  /// Drops the socket and brings it back at once (the frames in between are lost, like a real outage).
  Future<void> dropAndReconnect() async {
    live.link.drop();
    await flush();
    live.realtime.retryNow();
    for (var i = 0; i < 100 && !live.realtime.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  List<String> get leaks => calls.leaks;

  Future<void> dispose() async {
    if (!providerDisposed) calls.dispose();
    live.dispose();
  }
}
