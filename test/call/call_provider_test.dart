import 'dart:async';

import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_call_media.dart';
import '../helpers/fake_realtime.dart';

const me = 7;
const c1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const c2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const g1 = '11111111-1111-4111-8111-111111111111';

Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FakeRealtime live;
  late FakeCalls calls;

  Future<void> started({Duration? ringGuard, Duration? connectGuard}) async {
    calls = FakeCalls(
      live,
      ringGuard: ringGuard ?? const Duration(seconds: 35),
      connectGuard: connectGuard ?? const Duration(seconds: 30),
    )..listen();
    live.realtime.start();
    await pumpEvents();
    calls.provider.start(me);
  }

  setUp(() {
    final backend = FakeBackend();
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    live = FakeRealtime(backend);
  });

  tearDown(() {
    calls.dispose();
    live.dispose();
  });

  void signal(Map<String, Object?> body) => calls.signal(me, body);
  void incoming({String id = c1, bool ringAll = false}) =>
      signal({'type': 'INCOMING_CALL', 'callId': id, 'peerUserId': 5, 'peerDisplayName': 'mehmet', 'ringAll': ringAll});

  /// Own call c1 to 9, answered.
  Future<void> outgoingAnswered({bool video = true}) async {
    await calls.provider.call(9, 'Ayşe', groupId: g1, video: video);
    signal({'type': 'RINGING', 'callId': c1, 'peerUserId': 9, 'peerDisplayName': 'ayse'});
    signal({'type': 'ANSWERED', 'callId': c1, 'peerUserId': 9, 'peerDisplayName': 'ayse'});
    await pumpEvents();
  }

  /// Incoming c1 answered (voice).
  Future<void> incomingAnswered({bool video = false}) async {
    incoming();
    await calls.provider.answer(video: video);
    signal({'type': 'ANSWERED', 'callId': c1, 'peerUserId': 5, 'peerDisplayName': 'mehmet'});
    await pumpEvents();
  }

  group('subscription', () {
    test(
      'only /topic/user/{me}/rtc (the user-queue copy would deliver every signal twice); idempotent start',
      () async {
        await started();
        expect(live.link.destinations, {'/topic/user/7/rtc'});
        calls.provider.start(me);
        expect(live.link.subscriptions['/topic/user/7/rtc'], hasLength(1));
      },
    );

    test('reset unsubscribes; another user id re-subscribes', () async {
      await started();
      calls.provider.reset();
      expect(live.link.destinations, isEmpty);
      calls.provider.start(8);
      expect(live.link.destinations, {'/topic/user/8/rtc'});
    });

    test('malformed frames are ignored', () async {
      await started();
      for (final body in ['', 'x', '[]', '{"type":"INCOMING_CALL","callId":"nope"}']) {
        live.push('/topic/user/7/rtc', body);
      }
      expect(calls.provider.phase, CallPhase.idle);
      expect(calls.sent, isEmpty);
    });
  });

  group('outgoing', () {
    test('media opens first, then the dial frame; offer after ANSWERED; answer SDP applied', () async {
      await started();
      await calls.provider.call(9, 'Ayşe', groupId: g1, video: true);
      expect(calls.media.ops, ['open:true', 'connect']);
      expect(calls.media.iceServers, [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]);
      expect(calls.sent, [
        [
          '/app/rtc/call',
          {'calleeUserId': 9, 'groupId': g1},
        ],
      ]);
      expect(calls.provider.phase, CallPhase.outgoing);
      expect(calls.provider.hasLocalVideo, isTrue);
      expect(calls.media.speaker, isTrue, reason: 'video call → loudspeaker');

      signal({'type': 'RINGING', 'callId': c1, 'peerUserId': 9, 'peerDisplayName': 'ayse'});
      expect(calls.provider.ringing, isTrue);
      signal({'type': 'ANSWERED', 'callId': c1, 'peerUserId': 9, 'peerDisplayName': 'ayse'});
      await pumpEvents();
      expect(calls.provider.phase, CallPhase.connecting);
      expect(calls.media.ops.last, 'offer');
      expect(calls.sent.last, [
        '/app/rtc/$c1/sdp',
        {'sdpType': 'offer', 'sdp': 'v=0 offer'},
      ]);

      signal({'type': 'SDP', 'callId': c1, 'sdpType': 'answer', 'sdp': 'v=0 their answer'});
      await pumpEvents();
      expect(calls.media.ops.last, 'remote:answer');
      expect(calls.sentTo.where((d) => d.endsWith('/sdp')), hasLength(1), reason: 'an answer needs no reply');

      calls.media.onState!(PeerState.connected);
      expect(calls.provider.phase, CallPhase.active);
      expect(calls.provider.connectedAt, isNotNull);
    });

    test('not connected: nothing opens, nothing is sent, the user is told', () async {
      await started();
      live.link.drop();
      await calls.provider.call(9, 'Ayşe', video: true);
      expect(calls.medias, isEmpty);
      expect(calls.provider.phase, CallPhase.idle);
      expect(calls.notices.single.message, contains('Canlı bağlantı yok'));
    });

    test('never calls yourself; a second call while busy is refused', () async {
      await started();
      await calls.provider.call(me, 'Ben', video: false);
      expect(calls.medias, isEmpty);
      await calls.provider.call(9, 'Ayşe', video: false);
      await calls.provider.call(10, 'Ali', video: false);
      expect(calls.medias, hasLength(1));
      expect(calls.notices.last.message, 'Zaten bir görüşmedesiniz.');
    });

    test('permission refused: no dial frame (the callee never rings), media released, settings offered', () async {
      await started();
      calls.setup = (m) => m.openError = (_) => const CallMediaException(CallMediaError.denied);
      await calls.provider.call(9, 'Ayşe', video: true);
      await pumpEvents(); // notices are delivered asynchronously
      expect(calls.sent, isEmpty);
      expect(calls.provider.phase, CallPhase.idle);
      expect(calls.media.closed, isTrue);
      expect(calls.notices.single.openSettings, isTrue);
      expect(calls.notices.single.error, isTrue);
      expect(calls.media.ops, ['open:true', 'open:false', 'close'], reason: 'audio-only retry first (admin)');
    });

    test('camera refused, microphone allowed: audio-only call with a notice', () async {
      await started();
      calls.setup = (m) => m.openError = (video) => video ? const CallMediaException(CallMediaError.denied) : null;
      await calls.provider.call(9, 'Ayşe', video: true);
      await pumpEvents();
      expect(calls.sentTo, ['/app/rtc/call']);
      expect(calls.provider.hasLocalVideo, isFalse);
      expect(calls.media.speaker, isFalse, reason: 'voice → earpiece');
      expect(calls.notices.single.message, 'Kamera açılamadı — sesli devam ediliyor.');
    });

    test('cancelled while the permission prompt is open: nothing dialed, the late stream is stopped', () async {
      await started();
      final gate = Completer<void>();
      calls.setup = (m) => m.openGate = gate;
      final calling = calls.provider.call(9, 'Ayşe', video: true);
      await pumpEvents();
      calls.provider.end();
      gate.complete();
      await calling;
      await pumpEvents();
      expect(calls.sent, isEmpty);
      expect(calls.media.closed, isTrue);
      expect(calls.media.tracksStopped, isTrue);
      expect(calls.notices, isEmpty);
    });

    test('ring guard: no reply at all → ends locally (cancel once the id is known)', () async {
      await started(ringGuard: const Duration(milliseconds: 40));
      await calls.provider.call(9, 'Ayşe', video: false);
      signal({'type': 'RINGING', 'callId': c1});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls.sentTo.last, '/app/rtc/$c1/cancel');
      expect(calls.provider.phase, CallPhase.idle);
      expect(calls.notices.last.message, 'Cevap yok.');
      expect(calls.media.tracksStopped, isTrue);
    });
  });

  group('incoming', () {
    test('ringing opens no media (privacy); answer: media first, then the answer frame', () async {
      await started();
      incoming(ringAll: true);
      expect(calls.provider.phase, CallPhase.incoming);
      expect(calls.provider.ringAll, isTrue);
      expect(calls.medias, isEmpty);
      await calls.provider.answer(video: false);
      expect(calls.media.ops, ['open:false', 'connect']);
      expect(calls.sentTo, ['/app/rtc/$c1/answer']);
      expect(calls.provider.answering, isTrue);
    });

    test('offer → our answer SDP; ICE that arrives before the offer is applied after it; own ICE is relayed', () async {
      await started();
      await incomingAnswered();
      expect(calls.provider.phase, CallPhase.connecting);
      expect(calls.media.ops, isNot(contains('offer')), reason: 'the caller makes the offer');

      signal({'type': 'ICE', 'callId': c1, 'candidate': 'candidate:early', 'sdpMid': '0', 'sdpMLineIndex': 0});
      await pumpEvents();
      expect(calls.media.ops, isNot(contains('ice:candidate:early')), reason: 'buffered until the remote description');

      signal({'type': 'SDP', 'callId': c1, 'sdpType': 'offer', 'sdp': 'v=0 their offer'});
      await pumpEvents();
      expect(calls.media.ops.sublist(calls.media.ops.indexOf('remote:offer')), ['remote:offer', 'ice:candidate:early']);
      expect(calls.sent.last, [
        '/app/rtc/$c1/sdp',
        {'sdpType': 'answer', 'sdp': 'v=0 answer'},
      ]);

      signal({'type': 'ICE', 'callId': c1, 'candidate': 'candidate:late', 'sdpMid': '0', 'sdpMLineIndex': 0});
      await pumpEvents();
      expect(calls.media.ops.last, 'ice:candidate:late');

      calls.media.onIce!('candidate:mine', '0', 0);
      expect(calls.sent.last, [
        '/app/rtc/$c1/ice',
        {'candidate': 'candidate:mine', 'sdpMid': '0', 'sdpMLineIndex': 0},
      ]);
    });

    test('permission refused on answer: the call is rejected (ring-all keeps ringing for the others)', () async {
      await started();
      calls.setup = (m) => m.openError = (_) => const CallMediaException(CallMediaError.denied);
      incoming(ringAll: true);
      await calls.provider.answer(video: false);
      await pumpEvents();
      expect(calls.sentTo, ['/app/rtc/$c1/reject'], reason: 'never /answer');
      expect(calls.provider.phase, CallPhase.idle);
      expect(calls.notices.single.openSettings, isTrue);
    });

    test('caller cancels while we are still in the permission prompt: no answer, stream stopped', () async {
      await started();
      final gate = Completer<void>();
      calls.setup = (m) => m.openGate = gate;
      incoming();
      final answering = calls.provider.answer(video: true);
      await pumpEvents();
      signal({'type': 'CANCELLED', 'callId': c1});
      gate.complete();
      await answering;
      expect(calls.sent, isEmpty);
      expect(calls.media.tracksStopped, isTrue);
      expect(calls.notices.single.message, 'Cevapsız çağrı: mehmet');
    });

    test('CALL_TAKEN (another panel user answered the support call) releases our media', () async {
      await started();
      incoming(ringAll: true);
      await calls.provider.answer(video: false);
      signal({'type': 'CALL_TAKEN', 'callId': c1});
      await pumpEvents();
      expect(calls.provider.phase, CallPhase.idle);
      expect(calls.media.tracksStopped, isTrue);
      expect(calls.notices.single.message, contains('başka bir panel kullanıcısı'));
    });

    test('second call while in a call → busy reject, ours continues', () async {
      await started();
      await incomingAnswered();
      incoming(id: c2);
      expect(calls.sentTo.last, '/app/rtc/$c2/reject');
      expect(calls.provider.phase, CallPhase.connecting);
      expect(calls.medias, hasLength(1));
    });

    test('ring guard on a silent incoming call: rejected locally, "Cevapsız çağrı"', () async {
      await started(ringGuard: const Duration(milliseconds: 40));
      incoming();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls.sentTo, ['/app/rtc/$c1/reject']);
      expect(calls.notices.single.message, 'Cevapsız çağrı: mehmet');
    });
  });

  group('signals of a foreign call id are never applied', () {
    test('SDP / ICE / HANGUP of another call during ours: peer connection untouched', () async {
      await started();
      await incomingAnswered();
      final before = List.of(calls.media.ops);
      signal({'type': 'SDP', 'callId': c2, 'sdpType': 'offer', 'sdp': 'v=0 injected'});
      signal({'type': 'ICE', 'callId': c2, 'candidate': 'candidate:injected', 'sdpMid': '0', 'sdpMLineIndex': 0});
      signal({'type': 'HANGUP', 'callId': c2});
      signal({'type': 'SDP', 'sdpType': 'offer', 'sdp': 'v=0 no id'});
      await pumpEvents();
      expect(calls.media.ops, before);
      expect(calls.provider.phase, CallPhase.connecting);
      expect(calls.sentTo.where((d) => d.endsWith('/sdp')), isEmpty);
    });

    test('a late SDP of an ended call does not reach the next call\'s media', () async {
      await started();
      await incomingAnswered();
      calls.provider.end();
      incoming(id: c2);
      await calls.provider.answer(video: false);
      signal({'type': 'ANSWERED', 'callId': c2});
      signal({'type': 'SDP', 'callId': c1, 'sdpType': 'offer', 'sdp': 'v=0 old'});
      await pumpEvents();
      expect(calls.media.ops, isNot(contains('remote:offer')));
    });
  });

  group('ending: media is always released', () {
    test('hang up: frame, tracks stopped, peer connection closed', () async {
      await started();
      await outgoingAnswered();
      calls.media.onState!(PeerState.connected);
      calls.provider.end();
      await pumpEvents();
      expect(calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(calls.media.tracksStopped, isTrue);
      expect(calls.media.closed, isTrue);
      expect(calls.provider.media, isNull);
      expect(calls.provider.connectedAt, isNull);
    });

    test('peer hangs up → media released, notice', () async {
      await started();
      await outgoingAnswered();
      signal({'type': 'HANGUP', 'callId': c1});
      await pumpEvents();
      expect(calls.media.closed, isTrue);
      expect(calls.notices.last.message, 'Görüşme karşı tarafça sonlandırıldı.');
    });

    test('sign-out (reset): hang-up frame before the socket closes, media released, no notice', () async {
      await started();
      await incomingAnswered(video: true);
      calls.provider.reset();
      await pumpEvents();
      expect(calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(calls.media.tracksStopped, isTrue);
      expect(calls.media.closed, isTrue);
      expect(calls.notices, isEmpty);
      expect(live.link.destinations, isEmpty);
      signal({'type': 'INCOMING_CALL', 'callId': c2, 'peerUserId': 5});
      expect(calls.provider.phase, CallPhase.idle, reason: 'no longer listening');
    });

    test('sign-out while ringing: reject / cancel', () async {
      await started();
      incoming();
      calls.provider.reset();
      expect(calls.sentTo, ['/app/rtc/$c1/reject']);
    });

    test('app to background: the call ends (hang up + notice)', () async {
      await started();
      await incomingAnswered();
      calls.provider.endForBackground();
      await pumpEvents();
      expect(calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(calls.media.tracksStopped, isTrue);
      expect(calls.notices.last.message, contains('arka plana'));
      calls.provider.endForBackground();
      expect(calls.notices, hasLength(1), reason: 'idle: nothing to end');
    });

    test('connection never comes up (no TURN): connect guard hangs up', () async {
      await started(connectGuard: const Duration(milliseconds: 40));
      await incomingAnswered();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(calls.notices.last.message, contains('Bağlantı kurulamadı'));
    });

    test('ICE failed → hang up', () async {
      await started();
      await outgoingAnswered();
      calls.media.onState!(PeerState.connected);
      calls.media.onState!(PeerState.failed);
      await pumpEvents();
      expect(calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(calls.notices.last.message, 'Bağlantı koptu.');
    });

    test('remote description rejected → call ends with an error', () async {
      await started();
      calls.setup = (m) => m.setRemoteError = Exception('bad sdp');
      await incomingAnswered();
      signal({'type': 'SDP', 'callId': c1, 'sdpType': 'offer', 'sdp': 'v=0 broken'});
      await pumpEvents();
      expect(calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(calls.notices.last.error, isTrue);
    });

    test('callbacks of an ended call\'s media are ignored', () async {
      await started();
      await incomingAnswered();
      final old = calls.media;
      calls.provider.end();
      final sentBefore = calls.sent.length;
      old.onIce!('candidate:late', '0', 0);
      old.onState!(PeerState.failed);
      await pumpEvents();
      expect(calls.sent.length, sentBefore);
      expect(calls.notices, isEmpty);
    });
  });

  group('controls', () {
    test('mic / camera / speaker / switch camera drive the media; camera controls need a camera', () async {
      await started();
      await outgoingAnswered(video: true);
      final p = calls.provider;
      p.toggleMic();
      expect((p.micOn, calls.media.mic), (false, false));
      p.toggleCamera();
      expect((p.camOn, calls.media.camera), (false, false));
      await p.switchCamera();
      expect(calls.media.switches, 0, reason: 'camera off');
      p.toggleCamera();
      await p.switchCamera();
      expect(calls.media.switches, 1);
      await p.toggleSpeaker();
      expect((p.speakerOn, calls.media.speaker), (false, false));
    });

    test('voice call: no camera toggle', () async {
      await started();
      await incomingAnswered(video: false);
      calls.provider.toggleCamera();
      expect(calls.media.camera, isNull);
      expect(calls.provider.hasLocalVideo, isFalse);
    });
  });

  test('reconnect: a cancelled dial\'s lost reply does not cancel the next call', () async {
    await started();
    await calls.provider.call(9, 'Ayşe', video: false);
    calls.provider.end(); // before RINGING
    live.link.drop();
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // backoff ~1 s
    expect(live.realtime.connected, isTrue);
    await calls.provider.call(10, 'Ali', video: false);
    signal({'type': 'RINGING', 'callId': c2});
    expect(calls.provider.ringing, isTrue);
    expect(calls.sentTo.where((d) => d.endsWith('/cancel')), isEmpty);
  });
}
