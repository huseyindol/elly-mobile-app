import 'dart:async';

import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/call_rig.dart';

/// Client guards vs. the backend's own timeouts, on a fake clock: ringing 35 s on our side (backend rings 30 s and
/// sends TIMEOUT), 30 s from ANSWERED to a media connection. Whichever fires first ends the call once, releases the
/// media, and the other one is harmless.
const _ring = Duration(seconds: 35);
const _backendTimeout = Duration(seconds: 30);

Map<String, Object?> _sig(String type, String id, [Map<String, Object?> more = const {}]) => {
  'type': type,
  'callId': id,
  ...more,
};

void _fake(String name, void Function(FakeAsync async, CallRig rig) body) {
  test(name, () {
    fakeAsync((async) {
      final rig = CallRig();
      rig.startSync(async.flushMicrotasks);
      async.flushMicrotasks();
      expect(rig.live.realtime.connected, isTrue, reason: 'the fake socket is up');
      body(async, rig);
      rig.provider.reset();
      async.flushMicrotasks();
      expect(rig.leaks, isEmpty, reason: 'whatever the test did, nothing is held at the end');
      rig.live.realtime.stop();
      rig.calls.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty, reason: 'no guard timer outlives the session');
    });
  });
}

void _outgoingRinging(FakeAsync async, CallRig rig) {
  rig.provider.call(9, 'Ayşe', video: true);
  async.flushMicrotasks();
  rig.signal(_sig('RINGING', c1, {'peerUserId': 9}));
  async.flushMicrotasks();
}

void _answerAndConnect(FakeAsync async, CallRig rig, {String id = c1}) {
  rig.incoming(id: id);
  rig.provider.answer(video: false);
  async.flushMicrotasks();
  rig.signal(_sig('ANSWERED', id, {'peerUserId': 5}));
  async.flushMicrotasks();
}

void main() {
  group('outgoing ring (client 35 s, backend 30 s)', () {
    _fake('the backend TIMEOUT at 30 s ends it once; the 35 s guard later does nothing', (async, rig) {
      _outgoingRinging(async, rig);
      async.elapse(_backendTimeout);
      expect(rig.provider.phase, CallPhase.outgoing, reason: 'the client waits for the backend\'s word');
      rig.signal(_sig('TIMEOUT', c1));
      async.flushMicrotasks();
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.notices.map((n) => n.message), ['Cevap yok.']);
      expect(rig.leaks, isEmpty);
      final sent = List.of(rig.calls.sentTo);

      async.elapse(const Duration(seconds: 60));
      expect(rig.calls.notices, hasLength(1), reason: 'the old guard is cancelled: no second "Cevap yok."');
      expect(rig.calls.sentTo, sent, reason: 'and no stray cancel frame for the finished call');
      expect(sent, ['/app/rtc/call'], reason: 'the backend ended it: nothing to cancel');
    });

    _fake('TIMEOUT lost: nothing before 35 s, then exactly one cancel and the media is released', (async, rig) {
      _outgoingRinging(async, rig);
      async.elapse(_ring - const Duration(milliseconds: 1));
      expect(rig.provider.phase, CallPhase.outgoing, reason: '34.999 s');
      expect(rig.calls.media.leaks, isNotEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(rig.provider.phase, CallPhase.idle, reason: '35 s');
      expect(rig.calls.sentTo, ['/app/rtc/call', '/app/rtc/$c1/cancel']);
      expect(rig.calls.notices.single.message, 'Cevap yok.');
      expect(rig.leaks, isEmpty);
      async.elapse(const Duration(minutes: 5));
      expect(rig.calls.sentTo, hasLength(2));
    });

    _fake('no RINGING ever: ends at 35 s; a RINGING that shows up later is cancelled (the callee stops ringing)', (
      async,
      rig,
    ) {
      rig.provider.call(9, 'Ayşe', video: false);
      async.flushMicrotasks();
      async.elapse(_ring);
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.sentTo, ['/app/rtc/call'], reason: 'no call id yet: nothing to cancel');
      rig.signal(_sig('RINGING', c1, {'peerUserId': 9}));
      async.flushMicrotasks();
      expect(rig.calls.sentTo, ['/app/rtc/call', '/app/rtc/$c1/cancel']);
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.leaks, isEmpty);
    });

    _fake('TIMEOUT at 30 s, a new call at 31 s: the first call\'s 35 s mark does not touch the second', (async, rig) {
      _outgoingRinging(async, rig);
      async.elapse(_backendTimeout);
      rig.signal(_sig('TIMEOUT', c1));
      async.elapse(const Duration(seconds: 1));
      rig.provider.call(10, 'Ali', video: false); // 31 s
      async.flushMicrotasks();
      rig.signal(_sig('RINGING', c2, {'peerUserId': 10}));
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 5)); // 36 s: past the first call's guard
      expect(rig.provider.phase, CallPhase.outgoing, reason: 'the second call is on its own clock');
      expect(rig.calls.medias.last.leaks, isNotEmpty);
      async.elapse(_ring - const Duration(seconds: 5) - const Duration(milliseconds: 1)); // 65.999 s
      expect(rig.provider.phase, CallPhase.outgoing);
      async.elapse(const Duration(milliseconds: 1)); // 31 s + 35 s
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.sentTo.last, '/app/rtc/$c2/cancel');
      expect(rig.calls.sentTo.where((d) => d.endsWith('/cancel')), ['/app/rtc/$c2/cancel']);
      expect(rig.leaks, isEmpty);
    });

    _fake('the user cancels at 20 s: guard cancelled, and 35 s later nothing happens', (async, rig) {
      _outgoingRinging(async, rig);
      async.elapse(const Duration(seconds: 20));
      rig.provider.end();
      async.flushMicrotasks();
      expect(rig.calls.sentTo.last, '/app/rtc/$c1/cancel');
      async.elapse(const Duration(minutes: 2));
      expect(rig.calls.sentTo.where((d) => d.endsWith('/cancel')), hasLength(1));
      expect(rig.calls.notices, isEmpty);
    });

    _fake('a socket drop and reconnect during the ring does not restart the 35 s clock', (async, rig) {
      _outgoingRinging(async, rig);
      async.elapse(const Duration(seconds: 10));
      rig.live.link.drop();
      async.elapse(const Duration(milliseconds: 1500)); // backoff ≈ 1 s, then CONNECTED
      expect(rig.live.realtime.connected, isTrue);
      expect(rig.provider.phase, CallPhase.outgoing, reason: 'a signalling blip does not end a ringing call');
      async.elapse(const Duration(seconds: 23)); // 34.5 s
      expect(rig.provider.phase, CallPhase.outgoing);
      async.elapse(const Duration(seconds: 1)); // 35.5 s
      expect(rig.provider.phase, CallPhase.idle, reason: 'ended at 35 s from the start, not from the reconnect');
      expect(rig.calls.sentTo.last, '/app/rtc/$c1/cancel', reason: 'sent on the new link');
      expect(rig.leaks, isEmpty);
    });

    _fake(
      'the permission prompt outlives the ring guard: the call ends, the late stream is dropped, nothing is dialed',
      (async, rig) {
        final prompt = Completer<void>();
        rig.calls.setup = (m) => m.openGate = prompt;
        rig.provider.call(9, 'Ayşe', video: true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 40));
        expect(rig.provider.phase, CallPhase.idle);
        prompt.complete(); // the user finally taps "Allow"
        async.flushMicrotasks();
        expect(rig.calls.sent, isEmpty, reason: 'never dialed: the callee never rang');
        expect(rig.calls.media.tracksLive, isFalse);
        expect(rig.calls.media.closed, isTrue);
        expect(rig.leaks, isEmpty);
      },
    );
  });

  group('incoming ring', () {
    _fake('the backend TIMEOUT at 30 s: one missed-call notice, no reject; the 35 s guard is silent', (async, rig) {
      rig.incoming();
      async.elapse(_backendTimeout);
      expect(rig.provider.phase, CallPhase.incoming);
      rig.signal(_sig('TIMEOUT', c1));
      async.flushMicrotasks();
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.notices.map((n) => n.message), ['Cevapsız çağrı: mehmet']);
      async.elapse(const Duration(minutes: 2));
      expect(rig.calls.notices, hasLength(1));
      expect(rig.calls.sent, isEmpty);
    });

    _fake('TIMEOUT lost: at 35 s it is rejected locally once, "Cevapsız çağrı"', (async, rig) {
      rig.incoming();
      async.elapse(_ring - const Duration(milliseconds: 1));
      expect(rig.provider.phase, CallPhase.incoming);
      async.elapse(const Duration(milliseconds: 1));
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.sentTo, ['/app/rtc/$c1/reject']);
      expect(rig.calls.notices.single.message, 'Cevapsız çağrı: mehmet');
      expect(rig.calls.medias, isEmpty);
    });

    _fake('a duplicate INCOMING_CALL does not restart the clock', (async, rig) {
      rig.incoming();
      async.elapse(const Duration(seconds: 20));
      rig.incoming(); // redelivery
      async.elapse(const Duration(seconds: 14, milliseconds: 999));
      expect(rig.provider.phase, CallPhase.incoming);
      async.elapse(const Duration(milliseconds: 1));
      expect(rig.provider.phase, CallPhase.idle, reason: '35 s after the first delivery');
    });

    _fake('the permission prompt outlives the ring guard: rejected, never answered, the late stream is dropped', (
      async,
      rig,
    ) {
      final prompt = Completer<void>();
      rig.calls.setup = (m) => m.openGate = prompt;
      rig.incoming(ringAll: true);
      rig.provider.answer(video: true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 40));
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.sentTo, ['/app/rtc/$c1/reject']);
      prompt.complete();
      async.flushMicrotasks();
      expect(rig.calls.sentTo, ['/app/rtc/$c1/reject'], reason: 'no /answer after the call is gone');
      expect(rig.leaks, isEmpty);
      expect(rig.calls.media.opened, isFalse);
    });

    _fake('answered at 29 s, the backend\'s 30 s TIMEOUT wins (answer lost the race): missed, media released', (
      async,
      rig,
    ) {
      rig.incoming();
      async.elapse(const Duration(seconds: 29));
      rig.provider.answer(video: true);
      async.flushMicrotasks();
      expect(rig.calls.sentTo, ['/app/rtc/$c1/answer']);
      async.elapse(const Duration(seconds: 1));
      rig.signal(_sig('TIMEOUT', c1));
      async.flushMicrotasks();
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.leaks, isEmpty);
      async.elapse(const Duration(minutes: 2));
      expect(rig.calls.sentTo, [
        '/app/rtc/$c1/answer',
      ], reason: 'no reject / hang-up of a call the backend already ended');
      expect(rig.calls.notices.map((n) => n.message), ['Cevapsız çağrı: mehmet']);
    });
  });

  group('answered, no media connection yet (30 s)', () {
    _fake('the ring guard is replaced by the connect guard at ANSWERED: 35 s does not end it, 30 s later does', (
      async,
      rig,
    ) {
      rig.incoming();
      async.elapse(const Duration(seconds: 12));
      rig.provider.answer(video: false);
      async.flushMicrotasks();
      rig.signal(_sig('ANSWERED', c1, {'peerUserId': 5}));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 23)); // 35 s after INCOMING_CALL
      expect(rig.provider.phase, CallPhase.connecting, reason: 'the old ring guard must be gone');
      async.elapse(const Duration(seconds: 7) - const Duration(milliseconds: 1)); // 29.999 s after ANSWERED
      expect(rig.provider.phase, CallPhase.connecting);
      async.elapse(const Duration(milliseconds: 1));
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(rig.calls.notices.last.message, contains('Bağlantı kurulamadı'));
      expect(rig.leaks, isEmpty);
    });

    _fake('the same for the caller (35 s ring, then 30 s from ANSWERED)', (async, rig) {
      _outgoingRinging(async, rig);
      async.elapse(const Duration(seconds: 33));
      rig.signal(_sig('ANSWERED', c1, {'peerUserId': 9}));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 29));
      expect(rig.provider.phase, CallPhase.connecting, reason: '62 s after dialing, 29 s after ANSWERED');
      async.elapse(const Duration(seconds: 1));
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.sentTo.last, '/app/rtc/$c1/hangup');
      expect(rig.leaks, isEmpty);
    });

    _fake('connecting at 29 s disarms the guard: the call stays up for minutes', (async, rig) {
      _answerAndConnect(async, rig);
      async.elapse(const Duration(seconds: 29));
      rig.calls.media.onState!(PeerState.connected);
      expect(rig.provider.phase, CallPhase.active);
      async.elapse(const Duration(minutes: 30));
      expect(rig.provider.phase, CallPhase.active);
      expect(rig.calls.media.leaks, isNotEmpty, reason: 'still talking');
      expect(rig.calls.sentTo, ['/app/rtc/$c1/answer']);
      expect(rig.provider.connectedAt, isNotNull);
    });

    _fake('ICE "disconnected" is not the end (it may recover); the guard still applies while connecting', (async, rig) {
      _answerAndConnect(async, rig);
      rig.calls.media.onState!(PeerState.disconnected);
      async.elapse(const Duration(seconds: 29));
      expect(rig.provider.phase, CallPhase.connecting);
      async.elapse(const Duration(seconds: 1));
      expect(rig.provider.phase, CallPhase.idle);
    });

    _fake('the peer hangs up at 29.999 s: ended by the signal once, the guard never adds a second hang-up', (
      async,
      rig,
    ) {
      _answerAndConnect(async, rig);
      async.elapse(const Duration(seconds: 29, milliseconds: 999));
      rig.signal(_sig('HANGUP', c1));
      async.flushMicrotasks();
      expect(rig.provider.phase, CallPhase.idle);
      async.elapse(const Duration(minutes: 1));
      expect(rig.calls.sentTo, ['/app/rtc/$c1/answer']);
      expect(rig.calls.notices.map((n) => n.message), ['Görüşme karşı tarafça sonlandırıldı.']);
    });
  });

  group('configured durations', () {
    test('custom guards are honoured to the millisecond', () {
      fakeAsync((async) {
        final rig = CallRig(ringGuard: const Duration(seconds: 3), connectGuard: const Duration(seconds: 2));
        rig.startSync(async.flushMicrotasks);
        async.flushMicrotasks();
        rig.incoming();
        async.elapse(const Duration(milliseconds: 2999));
        expect(rig.provider.phase, CallPhase.incoming);
        async.elapse(const Duration(milliseconds: 1));
        expect(rig.provider.phase, CallPhase.idle);
        rig.live.realtime.stop();
        rig.calls.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
