import 'dart:async';

import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/call_rig.dart';

/// Privacy: whatever way a call ends, the microphone / camera tracks are stopped, the peer connection is closed
/// and the renderers are disposed (`FakeCallMedia.leaks`). Every state a call can be in × every way it can end.
/// Nothing here touches a network: fake STOMP link + fake media.

/// A state the call is in. [setup] drives the rig there; [gate]: the permission prompt / peer-connection creation is
/// still pending (completed by the test after the call ended); [forbidden]: a frame that must never go out
/// (nothing was dialed / answered yet).
class _State {
  final String name;
  final Future<void> Function(CallRig r, _Pending p) setup;
  final String? forbidden;

  /// The peer connection exists (ICE state callbacks are live).
  final bool hasPc;

  /// Signal that makes the peer end it (null: the peer cannot end it in this state).
  final Map<String, Object?>? peerEnds;
  final Map<String, Object?>? timeout;
  final Map<String, Object?>? taken;
  const _State(this.name, this.setup, {this.forbidden, this.hasPc = false, this.peerEnds, this.timeout, this.taken});
}

class _Pending {
  final gate = Completer<void>();
  Future<void>? action;
  bool gated = false;
}

Map<String, Object?> _sig(String type, [String id = c1]) => {'type': type, 'callId': id};

final _states = <_State>[
  _State('outgoing: permission prompt still open (nothing dialed)', (r, p) async {
    p.gated = true;
    r.calls.setup = (m) => m.openGate = p.gate;
    p.action = r.provider.call(9, 'Ayşe', video: true);
    await flush();
  }, forbidden: '/app/rtc/call'),
  _State('outgoing: peer connection being created (nothing dialed)', (r, p) async {
    p.gated = true;
    r.calls.setup = (m) => m.connectGate = p.gate;
    p.action = r.provider.call(9, 'Ayşe', video: true);
    await flush();
  }, forbidden: '/app/rtc/call'),
  _State(
    'outgoing: dialed, no RINGING yet',
    (r, p) async {
      await r.provider.call(9, 'Ayşe', video: true);
    },
    peerEnds: {'type': 'BUSY', 'reason': 'Kullanıcı meşgul'},
    hasPc: true,
  ),
  _State(
    'outgoing: ringing',
    (r, p) async {
      await r.provider.call(9, 'Ayşe', video: true);
      r.signal({..._sig('RINGING'), 'peerUserId': 9, 'peerDisplayName': 'ayse'});
    },
    peerEnds: _sig('REJECTED'),
    timeout: _sig('TIMEOUT'),
    hasPc: true,
  ),
  _State(
    'incoming: ringing (no media may exist)',
    (r, p) async {
      r.incoming();
    },
    peerEnds: _sig('CANCELLED'),
    timeout: _sig('TIMEOUT'),
    taken: _sig('CALL_TAKEN'),
  ),
  _State(
    'incoming: answering, permission prompt still open',
    (r, p) async {
      p.gated = true;
      r.calls.setup = (m) => m.openGate = p.gate;
      r.incoming(ringAll: true);
      p.action = r.provider.answer(video: true);
      await flush();
    },
    forbidden: '/answer',
    peerEnds: _sig('CANCELLED'),
    timeout: _sig('TIMEOUT'),
    taken: _sig('CALL_TAKEN'),
  ),
  _State(
    'incoming: answering, peer connection being created',
    (r, p) async {
      p.gated = true;
      r.calls.setup = (m) => m.connectGate = p.gate;
      r.incoming(ringAll: true);
      p.action = r.provider.answer(video: true);
      await flush();
    },
    forbidden: '/answer',
    peerEnds: _sig('CANCELLED'),
    timeout: _sig('TIMEOUT'),
    taken: _sig('CALL_TAKEN'),
  ),
  _State(
    'incoming: answer sent, waiting for ANSWERED',
    (r, p) async {
      r.incoming(ringAll: true);
      await r.provider.answer(video: true);
    },
    peerEnds: _sig('CANCELLED'),
    timeout: _sig('TIMEOUT'),
    taken: _sig('CALL_TAKEN'),
    hasPc: true,
  ),
  _State(
    'connecting (we called)',
    (r, p) async {
      await r.provider.call(9, 'Ayşe', video: true);
      r.signal(_sig('RINGING'));
      r.signal(_sig('ANSWERED'));
      await flush();
    },
    peerEnds: _sig('HANGUP'),
    hasPc: true,
  ),
  _State(
    'connecting (we answered)',
    (r, p) async {
      r.incoming();
      await r.provider.answer(video: true);
      r.signal(_sig('ANSWERED'));
      await flush();
    },
    peerEnds: _sig('HANGUP'),
    hasPc: true,
  ),
  _State(
    'active (we called)',
    (r, p) async {
      await r.provider.call(9, 'Ayşe', video: true);
      r.signal(_sig('RINGING'));
      r.signal(_sig('ANSWERED'));
      await flush();
      r.calls.media.onState!(PeerState.connected);
    },
    peerEnds: _sig('HANGUP'),
    hasPc: true,
  ),
  _State(
    'active (we answered, with remote video)',
    (r, p) async {
      r.incoming();
      await r.provider.answer(video: true);
      r.signal(_sig('ANSWERED'));
      await flush();
      r.calls.media.remoteVideo = true;
      r.calls.media.onRemote!();
      r.calls.media.onState!(PeerState.connected);
    },
    peerEnds: _sig('HANGUP'),
    hasPc: true,
  ),
];

/// A way the call ends; [applies] says whether it exists in a state.
class _Cause {
  final String name;
  final bool Function(_State s) applies;
  final Future<void> Function(CallRig r, _State s) run;
  const _Cause(this.name, this.run, {this.applies = _always});
}

bool _always(_State s) => true;

final _causes = <_Cause>[
  _Cause('user ends it (cancel / reject / hang up)', (r, s) async => r.provider.end()),
  _Cause('sign-out (reset)', (r, s) async => r.provider.reset()),
  _Cause('session change A → B (start another user id)', (r, s) async => r.provider.start(8)),
  _Cause('app goes to background', (r, s) async => r.provider.endForBackground()),
  _Cause('ICE failed', (r, s) async => r.calls.media.onState!(PeerState.failed), applies: (s) => s.hasPc),
  _Cause(
    'peer ends it (REJECTED / CANCELLED / BUSY / HANGUP)',
    (r, s) async => r.signal(s.peerEnds!),
    applies: (s) => s.peerEnds != null,
  ),
  _Cause('backend TIMEOUT', (r, s) async => r.signal(s.timeout!), applies: (s) => s.timeout != null),
  _Cause(
    'CALL_TAKEN (someone else answered the support call)',
    (r, s) async => r.signal(s.taken!),
    applies: (s) => s.taken != null,
  ),
  _Cause('STOMP drops and reconnects, then the user ends it', (r, s) async {
    await r.dropAndReconnect();
    r.provider.end();
  }),
  _Cause('STOMP drops and stays down, then sign-out', (r, s) async {
    r.live.link.drop();
    await flush();
    r.provider.reset();
  }),
  _Cause('CallProvider.dispose', (r, s) async {
    r.providerDisposed = true;
    r.provider.dispose();
  }),
];

void main() {
  late CallRig rig;

  setUp(() async {
    rig = CallRig();
    await rig.start();
  });

  tearDown(() => rig.dispose());

  for (final state in _states) {
    group(state.name, () {
      for (final cause in _causes.where((c) => c.applies(state))) {
        test(cause.name, () async {
          final pending = _Pending();
          await state.setup(rig, pending);
          if (state.name.startsWith('incoming: ringing')) {
            expect(rig.calls.medias, isEmpty, reason: 'ringing opens no microphone/camera');
          }
          expect(rig.provider.phase, isNot(CallPhase.idle), reason: 'the scenario starts in a call');

          await cause.run(rig, state);
          // The late stream / connection of a pending prompt arrives after the call is over: released at once.
          if (pending.gated) pending.gate.complete();
          await pending.action;
          await flush();

          expect(rig.leaks, isEmpty, reason: 'tracks stopped, peer connection closed, renderers disposed');
          for (final m in rig.calls.medias) {
            expect(m.closed, isTrue, reason: 'close() was called on every media that was created');
            expect(m.tracksLive, isFalse);
          }
          if (!rig.providerDisposed) {
            expect(rig.provider.phase, CallPhase.idle);
            expect(rig.provider.media, isNull);
            expect(rig.provider.mediaReady, isFalse);
            expect(rig.provider.connectedAt, isNull);
          }
          if (state.forbidden != null) {
            expect(
              rig.calls.sentTo.where((d) => d.endsWith(state.forbidden!)),
              isEmpty,
              reason: 'the call ended before it was ${state.forbidden == '/answer' ? 'answered' : 'dialed'}',
            );
          }
        });
      }
    });
  }

  group('ending frees the way for the next call', () {
    test('a permission prompt that outlives its call does not touch the next call', () async {
      final first = Completer<void>();
      rig.calls.setup = (m) {
        if (rig.calls.medias.isEmpty) m.openGate = first;
      };
      final firstCall = rig.provider.call(9, 'Ayşe', video: true);
      await flush();
      rig.provider.end(); // user cancels while the OS prompt is still on screen
      final secondCall = rig.provider.call(10, 'Ali', video: false);
      await flush();
      expect(rig.calls.medias, hasLength(2));
      first.complete(); // the first prompt finally resolves
      await firstCall;
      await secondCall;
      await flush();

      expect(rig.calls.medias[0].tracksLive, isFalse, reason: 'late stream of the cancelled call stopped at once');
      expect(rig.calls.medias[0].closed, isTrue);
      expect(rig.calls.medias[1].leaks, ['tracks', 'peerConnection', 'renderers'], reason: 'second call is live');
      expect(rig.provider.phase, CallPhase.outgoing);
      expect(rig.calls.sentTo, ['/app/rtc/call'], reason: 'only the second call was dialed');
      expect(rig.calls.sent.single[1], {'calleeUserId': 10});

      rig.provider.end();
      await flush();
      expect(rig.leaks, isEmpty);
    });

    test('same for an answer: the first prompt resolving late does not answer or keep anything', () async {
      final first = Completer<void>();
      rig.calls.setup = (m) {
        if (rig.calls.medias.isEmpty) m.openGate = first;
      };
      rig.incoming(id: c1);
      final firstAnswer = rig.provider.answer(video: true);
      await flush();
      rig.signal(_sig('CANCELLED', c1));
      rig.incoming(id: c2);
      final secondAnswer = rig.provider.answer(video: false);
      await flush();
      first.complete();
      await firstAnswer;
      await secondAnswer;
      await flush();

      expect(rig.calls.sentTo, ['/app/rtc/$c2/answer']);
      expect(rig.calls.medias[0].leaks, isEmpty);
      rig.provider.reset();
      await flush();
      expect(rig.leaks, isEmpty);
    });

    test('end() twice / reset() after end() close each media once, never throw', () async {
      await rig.provider.call(9, 'Ayşe', video: true);
      rig.provider.end();
      rig.provider.end();
      rig.provider.reset();
      rig.provider.endForBackground();
      await flush();
      expect(rig.calls.medias, hasLength(1));
      expect(rig.calls.media.ops.where((o) => o == 'close'), hasLength(1));
      expect(rig.leaks, isEmpty);
    });

    test('a media whose close() throws is still released, and the next call works', () async {
      rig.calls.setup = (m) => m.closeError = StateError('platform channel gone');
      await rig.provider.call(9, 'Ayşe', video: true);
      rig.provider.end();
      await flush();
      expect(rig.leaks, isEmpty);
      rig.calls.setup = null;
      await rig.provider.call(10, 'Ali', video: false);
      expect(rig.provider.phase, CallPhase.outgoing);
      rig.provider.end();
      await flush();
      expect(rig.leaks, isEmpty);
    });

    test('opening the media fails (device busy): the half-open media is released, no frame goes out', () async {
      rig.calls.setup = (m) => m.openError = (_) => const CallMediaException(CallMediaError.inUse);
      await rig.provider.call(9, 'Ayşe', video: false);
      await flush();
      expect(rig.calls.sent, isEmpty);
      expect(rig.leaks, isEmpty);
      expect(rig.calls.medias.single.closed, isTrue);
    });
  });

  group('STOMP outage while a call is on', () {
    test(
      'socket drops mid-call: media stays up (the call is peer-to-peer), the later end() frame uses the new link',
      () async {
        await _states.firstWhere((s) => s.name == 'active (we called)').setup(rig, _Pending());
        await rig.dropAndReconnect();
        expect(rig.provider.phase, CallPhase.active, reason: 'a signalling blip must not cut a working call');
        expect(rig.calls.media.leaks, isNotEmpty);
        rig.provider.end();
        await flush();
        expect(rig.calls.sentTo, ['/app/rtc/$c1/hangup'], reason: 'sent on the reconnected link');
        expect(rig.leaks, isEmpty);
      },
    );

    test(
      'a call that cannot signal any more (socket down): ending still releases the media, nothing is thrown',
      () async {
        await _states.firstWhere((s) => s.name == 'active (we called)').setup(rig, _Pending());
        rig.live.link.drop();
        await flush();
        expect(rig.live.realtime.connected, isFalse);
        rig.provider.end();
        await flush();
        expect(rig.leaks, isEmpty);
        expect(rig.provider.phase, CallPhase.idle);
      },
    );

    test('while the socket is down: no new call, no answer, no media opened', () async {
      rig.incoming();
      rig.live.link.drop();
      await flush();
      await rig.provider.answer(video: true);
      await rig.provider.call(9, 'Ayşe', video: true);
      expect(rig.calls.medias, isEmpty, reason: 'no microphone for a call that cannot be signalled');
      expect(rig.provider.phase, CallPhase.incoming);
    });

    test('reconnect does not resurrect or double a finished call\'s media', () async {
      await _states.firstWhere((s) => s.name == 'connecting (we answered)').setup(rig, _Pending());
      rig.provider.end();
      await flush();
      await rig.dropAndReconnect();
      await rig.dropAndReconnect();
      expect(rig.calls.medias, hasLength(1));
      expect(rig.leaks, isEmpty);
      expect(rig.provider.phase, CallPhase.idle);
    });
  });

  group('session change', () {
    test('A → B: A\'s call is hung up and released, B does not inherit it, A\'s topic is dead', () async {
      await _states.firstWhere((s) => s.name == 'active (we answered, with remote video)').setup(rig, _Pending());
      rig.provider.start(8);
      await flush();
      expect(rig.calls.sentTo, ['/app/rtc/$c1/answer', '/app/rtc/$c1/hangup']);
      expect(rig.leaks, isEmpty);
      expect(rig.provider.phase, CallPhase.idle);
      expect(rig.live.link.destinations, {'/topic/user/8/rtc'});
      // frames for A are dropped, frames for B work
      rig.signal({..._sig('INCOMING_CALL', c2), 'peerUserId': 5}, user: me);
      expect(rig.provider.phase, CallPhase.idle);
      rig.incoming(id: c2, user: 8);
      expect(rig.provider.phase, CallPhase.incoming);
      expect(rig.calls.medias, hasLength(1), reason: 'B\'s ringing opened nothing');
    });

    test('same user id again is a no-op: a running call is not cut', () async {
      await _states.firstWhere((s) => s.name == 'active (we called)').setup(rig, _Pending());
      rig.provider.start(me);
      rig.provider.start(me);
      await flush();
      expect(rig.provider.phase, CallPhase.active);
      expect(rig.calls.media.leaks, isNotEmpty);
    });

    test('late frames of the signed-out session\'s call never reach the next session', () async {
      await _states.firstWhere((s) => s.name == 'connecting (we called)').setup(rig, _Pending());
      final old = rig.calls.media;
      rig.provider.reset();
      rig.provider.start(8);
      rig.incoming(id: c2, user: 8);
      await rig.provider.answer(video: false);
      rig.signal(_sig('ANSWERED', c2), user: 8);
      await flush();
      final sentBefore = List.of(rig.calls.sentTo);
      final opsBefore = List.of(rig.calls.media.ops);
      // A's leftovers: SDP/HANGUP of the old call (to A's dead topic and, worst case, to B's) and old media callbacks
      for (final user in [me, 8]) {
        rig.signal({..._sig('SDP', c1), 'sdpType': 'answer', 'sdp': 'v=0 old'}, user: user);
        rig.signal(_sig('HANGUP', c1), user: user);
        rig.signal({..._sig('ICE', c1), 'candidate': 'candidate:old', 'sdpMid': '0', 'sdpMLineIndex': 0}, user: user);
      }
      old.onState!(PeerState.failed);
      old.onIce!('candidate:old', '0', 0);
      await flush();
      expect(old.applied, isEmpty);
      expect(rig.calls.sentTo, sentBefore, reason: 'no new frame for the old call');
      expect(rig.calls.media.ops, opsBefore, reason: 'B\'s media untouched');
      expect(rig.provider.phase, CallPhase.connecting, reason: 'B\'s call continues');
      expect(rig.calls.medias.last.leaks, isNotEmpty);
    });
  });
}
