import 'dart:async';

import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/call_rig.dart';

/// Every signal is scoped to the current call id: a foreign / stale / id-less ANSWERED, SDP, ICE, HANGUP, CALL_TAKEN
/// (… every type) changes nothing — no phase change, no frame, no peer-connection operation, no notice — and cannot be
/// used to cut, hijack or feed the call that is on. A second INCOMING_CALL is rejected as busy; a duplicate delivery
/// of the same INCOMING_CALL never opens a second call.

Map<String, Object?> _sig(String type, String? id, [Map<String, Object?> more = const {}]) => {
  'type': type,
  'callId': id,
  ...more,
};

/// A foreign call's frames for every signal type (SDP both ways, ICE with a candidate).
List<Map<String, Object?>> _foreign(String id, {bool ringing = true}) => [
  _sig('ANSWERED', id, {'peerUserId': 5}),
  if (ringing) _sig('RINGING', id, {'peerUserId': 5}),
  _sig('SDP', id, {'sdpType': 'offer', 'sdp': 'v=0 injected offer'}),
  _sig('SDP', id, {'sdpType': 'answer', 'sdp': 'v=0 injected answer'}),
  _sig('ICE', id, {'candidate': 'candidate:injected', 'sdpMid': '0', 'sdpMLineIndex': 0}),
  _sig('HANGUP', id),
  _sig('CALL_TAKEN', id),
  _sig('REJECTED', id),
  _sig('CANCELLED', id),
  _sig('TIMEOUT', id),
  _sig('BUSY', id, {'reason': 'x'}),
  _sig('UNAVAILABLE', id, {'reason': 'x'}),
  _sig('ERROR', id, {'reason': 'x'}),
];

class _State {
  final String name;
  final CallPhase phase;
  final Future<void> Function(CallRig r) setup;

  /// A RINGING without call id is the reply to our dial: nothing distinguishes a "foreign" one here.
  final bool ringingIsOurReply;
  const _State(this.name, this.phase, this.setup, {this.ringingIsOurReply = false});
}

final _states = <_State>[
  _State('outgoing, dialed, RINGING not received yet', CallPhase.outgoing, (r) async {
    await r.provider.call(9, 'Ayşe', video: true);
  }, ringingIsOurReply: true),
  _State('outgoing, ringing', CallPhase.outgoing, (r) async {
    await r.provider.call(9, 'Ayşe', video: true);
    r.signal(_sig('RINGING', c1, {'peerUserId': 9}));
  }),
  _State('incoming, ringing', CallPhase.incoming, (r) async {
    r.incoming();
  }),
  _State('incoming, answering', CallPhase.incoming, (r) async {
    r.incoming(ringAll: true);
    await r.provider.answer(video: true);
  }),
  _State('connecting', CallPhase.connecting, (r) async {
    r.incoming();
    await r.provider.answer(video: false);
    r.signal(_sig('ANSWERED', c1, {'peerUserId': 5}));
    await flush();
  }),
  _State('active', CallPhase.active, (r) async {
    await r.provider.call(9, 'Ayşe', video: true);
    r.signal(_sig('RINGING', c1, {'peerUserId': 9}));
    r.signal(_sig('ANSWERED', c1, {'peerUserId': 9}));
    await flush();
    r.calls.media.onState!(PeerState.connected);
  }),
];

void main() {
  late CallRig rig;

  setUp(() async {
    rig = CallRig();
    await rig.start();
  });

  tearDown(() => rig.dispose());

  group('a foreign call id changes nothing', () {
    for (final state in _states) {
      test(state.name, () async {
        await state.setup(rig);
        expect(rig.provider.phase, state.phase);
        final sent = List.of(rig.calls.sentTo);
        final ops = [for (final m in rig.calls.medias) List.of(m.ops)];
        final notices = rig.calls.notices.length;

        for (final frame in _foreign(c2, ringing: !state.ringingIsOurReply)) {
          rig.signal(frame);
          await flush();
          expect(rig.provider.phase, state.phase, reason: '${frame['type']} of a foreign call moved the phase');
        }
        expect(rig.calls.sentTo, sent, reason: 'no reply, hang-up or answer frame for a foreign call');
        expect([for (final m in rig.calls.medias) m.ops], ops, reason: 'peer connection untouched');
        for (final m in rig.calls.medias) {
          expect(m.applied, isEmpty, reason: 'no foreign SDP / ICE reached the peer connection');
        }
        expect(rig.calls.notices, hasLength(notices), reason: 'no notice for a foreign call');
        expect(rig.provider.media == null, state.phase == CallPhase.incoming && !rig.provider.answering);
      });
    }

    test('the real call still works afterwards (foreign noise did not consume its state)', () async {
      await _states[4].setup(rig); // connecting c1
      for (final f in _foreign(c2)) {
        rig.signal(f);
      }
      rig.signal(_sig('SDP', c1, {'sdpType': 'offer', 'sdp': 'v=0 real offer'}));
      rig.signal(_sig('ICE', c1, {'candidate': 'candidate:real', 'sdpMid': '0', 'sdpMLineIndex': 0}));
      await flush();
      expect(rig.calls.media.applied, ['remote:offer', 'ice:candidate:real']);
      expect(rig.calls.sent.last, [
        '/app/rtc/$c1/sdp',
        {'sdpType': 'answer', 'sdp': 'v=0 answer'},
      ]);
      rig.signal(_sig('HANGUP', c1));
      await flush();
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.leaks, isEmpty);
    });
  });

  group('frames without a call id', () {
    for (final state in _states.where((s) => s.phase != CallPhase.outgoing)) {
      test('ignored in: ${state.name}', () async {
        await state.setup(rig);
        final sent = List.of(rig.calls.sentTo);
        final ops = [for (final m in rig.calls.medias) List.of(m.ops)];
        for (final type in callSignalTypes) {
          rig.signal({
            'type': type,
            'sdpType': 'offer',
            'sdp': 'v=0 nobody',
            'candidate': 'candidate:nobody',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
            'reason': 'x',
            'peerUserId': 5,
          });
          await flush();
          expect(rig.provider.phase, state.phase, reason: '$type without a call id moved the phase');
        }
        expect(rig.calls.sentTo, sent);
        expect([for (final m in rig.calls.medias) m.ops], ops);
      });
    }

    test('an id-less BUSY / UNAVAILABLE / ERROR is only ever the reply to our own dial', () async {
      // not dialed yet (permission prompt open): not a reply
      final prompt = Completer<void>();
      rig.calls.setup = (m) => m.openGate = prompt;
      final calling = rig.provider.call(9, 'Ayşe', video: true);
      await flush();
      rig.signal({'type': 'BUSY', 'reason': 'x'});
      await flush();
      expect(rig.provider.phase, CallPhase.outgoing, reason: 'a reply to a dial that was never sent');
      prompt.complete();
      await calling;
      // dialed: it is the reply
      rig.signal({'type': 'UNAVAILABLE', 'reason': 'Kullanıcı müsait değil.'});
      await flush();
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.notices.last.message, 'Kullanıcı müsait değil.');
      expect(rig.leaks, isEmpty);
    });
  });

  group('ended calls (stale / replayed frames)', () {
    Future<void> endC1ThenStartC2Active() async {
      await _states[5].setup(rig); // active c1 (we called)
      rig.signal(_sig('HANGUP', c1));
      await flush();
      expect(rig.provider.phase, CallPhase.idle);
      rig.incoming(id: c2);
      await rig.provider.answer(video: false);
      rig.signal(_sig('ANSWERED', c2, {'peerUserId': 5}));
      await flush();
      rig.calls.medias.last.onState!(PeerState.connected);
      expect(rig.provider.phase, CallPhase.active);
    }

    test('c1 is over, c2 is active: no stale c1 frame touches c2', () async {
      await endC1ThenStartC2Active();
      final sent = List.of(rig.calls.sentTo);
      final ops = List.of(rig.calls.media.ops);
      final old = rig.calls.medias.first;
      final oldOps = List.of(old.ops);
      for (final f in [
        _sig('SDP', c1, {'sdpType': 'offer', 'sdp': 'v=0 stale'}),
        _sig('ICE', c1, {'candidate': 'candidate:stale', 'sdpMid': '0', 'sdpMLineIndex': 0}),
        _sig('HANGUP', c1),
        _sig('CALL_TAKEN', c1),
        _sig('CANCELLED', c1),
        _sig('TIMEOUT', c1),
        _sig('REJECTED', c1),
        _sig('RINGING', c1),
        _sig('BUSY', c1),
        _sig('INCOMING_CALL', c1, {'peerUserId': 5}),
      ]) {
        rig.signal(f);
        await flush();
      }
      expect(rig.provider.phase, CallPhase.active);
      expect(rig.calls.sentTo, sent, reason: 'nothing is sent for a finished call, and no busy-reject of its replay');
      expect(rig.calls.media.ops, ops);
      expect(old.ops, oldOps, reason: 'the finished call\'s media is not reused');
      expect(rig.calls.medias, hasLength(2));
    });

    test(
      'a late ANSWERED of the finished call is hung up (cancel ↔ answer race); the active call is untouched',
      () async {
        await endC1ThenStartC2Active();
        final ops = List.of(rig.calls.media.ops);
        rig.signal(_sig('ANSWERED', c1, {'peerUserId': 9}));
        await flush();
        expect(rig.calls.sentTo.last, '/app/rtc/$c1/hangup');
        expect(rig.provider.phase, CallPhase.active);
        expect(rig.calls.media.ops, ops);
        expect(rig.calls.medias.last.leaks, isNotEmpty, reason: 'c2\'s media is still live');
      },
    );

    test('a replayed INCOMING_CALL of a finished call does not ring again (redelivery after hang-up)', () async {
      rig.incoming();
      await rig.provider.answer(video: false);
      rig.signal(_sig('ANSWERED', c1, {'peerUserId': 5}));
      await flush();
      rig.provider.end();
      await flush();
      for (var i = 0; i < 3; i++) {
        rig.incoming();
        await flush();
      }
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.calls.medias, hasLength(1));
      expect(rig.leaks, isEmpty);
    });

    test('an unanswered, cancelled call replayed does not ring again either', () async {
      rig.incoming();
      rig.signal(_sig('CANCELLED', c1));
      rig.incoming();
      await flush();
      expect(rig.provider.phase, CallPhase.idle);
    });

    test('the last 16 finished call ids are remembered', () async {
      String id(int i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
      for (var i = 0; i < 16; i++) {
        rig.incoming(id: id(i));
        rig.signal(_sig('CANCELLED', id(i)));
      }
      for (var i = 0; i < 16; i++) {
        rig.incoming(id: id(i));
        expect(rig.provider.phase, CallPhase.idle, reason: 'replay of call #$i rang');
      }
    });
  });

  group('one call at a time', () {
    test(
      'INCOMING_CALL while a call is on → that call is rejected (busy), ours is not affected, in every state',
      () async {
        for (final state in _states) {
          await rig.dispose();
          rig = CallRig();
          await rig.start();
          await state.setup(rig);
          final ops = [for (final m in rig.calls.medias) List.of(m.ops)];
          final leaksBefore = List.of(rig.leaks);
          rig.incoming(id: c2, from: 6, name: 'baska');
          await flush();
          expect(rig.calls.sentTo.last, '/app/rtc/$c2/reject', reason: state.name);
          expect(rig.calls.sentTo.where((d) => d.contains(c2)).toSet(), {'/app/rtc/$c2/reject'}, reason: state.name);
          expect(rig.provider.phase, state.phase, reason: state.name);
          expect(rig.provider.peerUserId, isNot(6), reason: '${state.name}: the busy caller is not adopted');
          expect(rig.provider.peerName, isNot('baska'), reason: state.name);
          expect(
            [for (final m in rig.calls.medias) m.ops],
            ops,
            reason: '${state.name}: no media for the rejected call',
          );
          expect(rig.leaks, leaksBefore, reason: state.name);
          rig.provider.reset();
        }
      },
    );

    test('a flood of INCOMING_CALLs while busy: each is rejected, none opens media or moves the call', () async {
      await _states[5].setup(rig); // active
      final ids = [for (var i = 0; i < 25; i++) '00000000-0000-4000-8000-${(1000 + i).toString().padLeft(12, '0')}'];
      for (final id in ids) {
        rig.incoming(id: id, from: 6);
      }
      await flush();
      expect(rig.calls.sentTo.where((d) => d.endsWith('/reject')), hasLength(ids.length));
      expect(rig.provider.phase, CallPhase.active);
      expect(rig.calls.medias, hasLength(1));
      expect(rig.provider.peerUserId, 9);
    });

    test('after the busy reject, the rejected call\'s later frames are foreign (ignored)', () async {
      await _states[5].setup(rig); // active c1
      rig.incoming(id: c2);
      final sent = List.of(rig.calls.sentTo);
      for (final f in _foreign(c2)) {
        rig.signal(f);
      }
      await flush();
      expect(rig.calls.sentTo, sent);
      expect(rig.provider.phase, CallPhase.active);
    });

    test(
      'INCOMING_CALL while idle but a media is still being opened for our own dial → busy, not a second media',
      () async {
        final prompt = Completer<void>();
        rig.calls.setup = (m) => m.openGate = prompt;
        final calling = rig.provider.call(9, 'Ayşe', video: true);
        await flush();
        rig.incoming(id: c2);
        await flush();
        expect(rig.calls.sentTo, ['/app/rtc/$c2/reject']);
        expect(rig.calls.medias, hasLength(1));
        prompt.complete();
        await calling;
        expect(rig.calls.sentTo, ['/app/rtc/$c2/reject', '/app/rtc/call'], reason: 'ours is dialed after the prompt');
        rig.provider.end();
        await flush();
        expect(rig.leaks, isEmpty);
      },
    );
  });

  group('duplicate delivery of the same INCOMING_CALL', () {
    test('while ringing: one ringing call, no busy reject, one media when answered', () async {
      for (var i = 0; i < 5; i++) {
        rig.incoming();
      }
      await flush();
      expect(rig.provider.phase, CallPhase.incoming);
      expect(rig.calls.sent, isEmpty, reason: 'the duplicate is not "busy"');
      await rig.provider.answer(video: false);
      expect(rig.calls.medias, hasLength(1));
      expect(rig.calls.sentTo, ['/app/rtc/$c1/answer']);
    });

    test('in every later state (answering, connecting, active): no reject, no second media, call unchanged', () async {
      for (final state in _states.where((s) => s.phase != CallPhase.outgoing)) {
        await rig.dispose();
        rig = CallRig();
        await rig.start();
        await state.setup(rig);
        final sent = List.of(rig.calls.sentTo);
        final medias = rig.calls.medias.length;
        for (var i = 0; i < 3; i++) {
          rig.incoming();
        }
        await flush();
        expect(rig.calls.sentTo, sent, reason: state.name);
        expect(rig.calls.medias, hasLength(medias), reason: state.name);
        expect(rig.provider.phase, state.phase, reason: state.name);
        rig.provider.reset();
      }
    });

    test('a duplicate that arrives while the permission prompt is open does not restart or double-answer', () async {
      final prompt = Completer<void>();
      rig.calls.setup = (m) => m.openGate = prompt;
      rig.incoming();
      final answering = rig.provider.answer(video: true);
      await flush();
      rig.incoming();
      unawaited(rig.provider.answer(video: true)); // double tap on "answer"
      await flush();
      prompt.complete();
      await answering;
      await flush();
      expect(rig.calls.sentTo, ['/app/rtc/$c1/answer']);
      expect(rig.calls.medias, hasLength(1));
      rig.provider.reset();
      await flush();
      expect(rig.leaks, isEmpty);
    });

    test('our own outgoing call id echoed back as INCOMING_CALL does not create a second call', () async {
      await _states[1].setup(rig); // outgoing ringing c1
      rig.incoming(id: c1, from: 9);
      await flush();
      expect(rig.provider.phase, CallPhase.outgoing);
      expect(rig.provider.isCaller, isTrue);
      expect(rig.calls.sentTo, ['/app/rtc/call']);
      expect(rig.calls.medias, hasLength(1));
    });
  });
}
