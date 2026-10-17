import 'dart:async';

import 'package:elly_mobile_app/providers/call_provider.dart';
import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/call_rig.dart';

/// Remote ICE candidates that arrive before the remote description are buffered (≤ 100) and applied right after it,
/// in arrival order; the buffer and the apply queue belong to one call and never leak into the next.
Map<String, Object?> _ice(String id, String candidate) => {
  'type': 'ICE',
  'callId': id,
  'candidate': candidate,
  'sdpMid': '0',
  'sdpMLineIndex': 0,
};
Map<String, Object?> _sdp(String id, String type) => {'type': 'SDP', 'callId': id, 'sdpType': type, 'sdp': 'v=0 $type'};

void main() {
  late CallRig rig;

  setUp(() async {
    rig = CallRig();
    await rig.start();
  });

  tearDown(() => rig.dispose());

  /// We answered c1 and the caller's ANSWERED came: connecting, no remote description yet.
  Future<void> answered({String id = c1}) async {
    rig.incoming(id: id);
    await rig.provider.answer(video: false);
    rig.signal({'type': 'ANSWERED', 'callId': id, 'peerUserId': 5});
    await flush();
  }

  List<String> iceOps(List<String> applied) => [
    for (final o in applied)
      if (o.startsWith('ice:')) o.substring(4),
  ];

  group('limit of ${CallProvider.maxPendingIce}', () {
    for (final n in [1, 99, 100, 101, 102, 250]) {
      test('$n candidates before the offer: the first ${n > 100 ? 100 : n} are applied after it, in order', () async {
        await answered();
        for (var i = 0; i < n; i++) {
          rig.signal(_ice(c1, 'c$i'));
        }
        await flush();
        expect(rig.calls.media.applied, isEmpty, reason: 'nothing is applied before the remote description');

        rig.signal(_sdp(c1, 'offer'));
        await flush();
        final applied = rig.calls.media.applied;
        expect(applied.first, 'remote:offer', reason: 'remote description first');
        expect(iceOps(applied), [for (var i = 0; i < (n > 100 ? 100 : n); i++) 'c$i'], reason: 'arrival order, capped');
        if (n > 100) expect(applied, isNot(contains('ice:c100')), reason: 'the 101st is dropped');
        expect(rig.provider.phase, CallPhase.connecting, reason: 'overflow is not an error');
      });
    }

    test('candidates after the remote description are applied directly, past the cap', () async {
      await answered();
      rig.signal(_sdp(c1, 'offer'));
      await flush();
      for (var i = 0; i < 150; i++) {
        rig.signal(_ice(c1, 'late$i'));
      }
      await flush();
      expect(iceOps(rig.calls.media.applied), [for (var i = 0; i < 150; i++) 'late$i']);
    });

    test('the buffer is drained once: it does not count against later candidates or replay them', () async {
      await answered();
      for (var i = 0; i < 100; i++) {
        rig.signal(_ice(c1, 'early$i'));
      }
      rig.signal(_sdp(c1, 'offer'));
      await flush();
      expect(iceOps(rig.calls.media.applied), hasLength(100));
      rig.signal(_sdp(c1, 'offer')); // renegotiation / duplicate offer
      rig.signal(_ice(c1, 'after'));
      await flush();
      final ice = iceOps(rig.calls.media.applied);
      expect(ice.where((c) => c.startsWith('early')), hasLength(100), reason: 'applied exactly once');
      expect(ice.last, 'after');
    });
  });

  group('order', () {
    test('ICE, ICE, SDP, ICE, ICE → remote, then 1, 2, 3, 4', () async {
      await answered();
      rig.signal(_ice(c1, '1'));
      rig.signal(_ice(c1, '2'));
      rig.signal(_sdp(c1, 'offer'));
      rig.signal(_ice(c1, '3'));
      rig.signal(_ice(c1, '4'));
      await flush();
      expect(rig.calls.media.applied, ['remote:offer', 'ice:1', 'ice:2', 'ice:3', 'ice:4']);
      expect(rig.calls.sent.last, [
        '/app/rtc/$c1/sdp',
        {'sdpType': 'answer', 'sdp': 'v=0 answer'},
      ]);
    });

    test('while the remote description is still being applied, later candidates wait behind it', () async {
      await answered();
      final gate = Completer<void>();
      rig.calls.media.setRemoteGate = gate;
      rig.signal(_ice(c1, 'a'));
      rig.signal(_sdp(c1, 'offer'));
      rig.signal(_ice(c1, 'b')); // arrives while setRemote is in flight
      rig.signal(_ice(c1, 'c'));
      await flush();
      expect(rig.calls.media.applied, ['remote:offer'], reason: 'serial queue: nothing overtakes the description');
      gate.complete();
      await flush();
      expect(rig.calls.media.applied, ['remote:offer', 'ice:a', 'ice:b', 'ice:c']);
    });

    test('caller side: candidates that beat the answer SDP are applied after it', () async {
      await rig.provider.call(9, 'Ayşe', video: false);
      rig.signal({'type': 'RINGING', 'callId': c1, 'peerUserId': 9});
      rig.signal({'type': 'ANSWERED', 'callId': c1, 'peerUserId': 9});
      await flush();
      rig.signal(_ice(c1, 'early'));
      await flush();
      expect(iceOps(rig.calls.media.applied), isEmpty);
      rig.signal(_sdp(c1, 'answer'));
      await flush();
      expect(rig.calls.media.applied, ['remote:answer', 'ice:early']);
      expect(
        rig.calls.sentTo.where((d) => d.endsWith('/sdp')),
        hasLength(1),
        reason: 'only our offer; no reply to an answer',
      );
    });

    test('candidates before ANSWERED / while ringing are not buffered at all (nothing to apply them to)', () async {
      rig.incoming();
      rig.signal(_ice(c1, 'too-early'));
      await flush();
      await rig.provider.answer(video: false);
      rig.signal({'type': 'ANSWERED', 'callId': c1, 'peerUserId': 5});
      rig.signal(_sdp(c1, 'offer'));
      await flush();
      expect(rig.calls.media.applied, ['remote:offer'], reason: 'a candidate from the ringing phase was not kept');
    });

    test('a candidate the platform refuses is skipped; the others and the call carry on', () async {
      await answered();
      rig.calls.media.addIceError = (c) => c == 'bad';
      rig.signal(_ice(c1, 'ok1'));
      rig.signal(_ice(c1, 'bad'));
      rig.signal(_ice(c1, 'ok2'));
      rig.signal(_sdp(c1, 'offer'));
      rig.signal(_ice(c1, 'bad'));
      rig.signal(_ice(c1, 'ok3'));
      await flush();
      expect(rig.calls.media.applied, ['remote:offer', 'ice:ok1', 'ice:ok2', 'ice:ok3']);
      expect(rig.provider.phase, CallPhase.connecting);
      expect(rig.calls.notices, isEmpty);
    });

    test('candidate fields pass through untouched (missing sdpMid / index allowed)', () async {
      await answered();
      rig.signal({'type': 'ICE', 'callId': c1, 'candidate': 'candidate:no-mid'});
      rig.signal(_sdp(c1, 'offer'));
      await flush();
      expect(rig.calls.media.applied, ['remote:offer', 'ice:candidate:no-mid']);
    });
  });

  group('the buffer is per call', () {
    test('call 1 ends with candidates buffered → call 2 never sees them', () async {
      await answered(id: c1);
      for (var i = 0; i < 5; i++) {
        rig.signal(_ice(c1, 'old$i'));
      }
      await flush();
      rig.provider.end();
      await flush();

      await answered(id: c2);
      rig.signal(_sdp(c2, 'offer'));
      await flush();
      expect(rig.calls.medias, hasLength(2));
      expect(rig.calls.medias[1].applied, ['remote:offer'], reason: 'no candidate of call 1 leaked into call 2');
      expect(rig.calls.medias[0].applied, isEmpty, reason: 'the finished call\'s media was not used');
    });

    test('a full buffer (100) of call 1 does not eat call 2\'s allowance', () async {
      await answered(id: c1);
      for (var i = 0; i < 120; i++) {
        rig.signal(_ice(c1, 'old$i'));
      }
      await flush();
      rig.provider.end();
      await flush();
      await answered(id: c2);
      for (var i = 0; i < 100; i++) {
        rig.signal(_ice(c2, 'new$i'));
      }
      rig.signal(_sdp(c2, 'offer'));
      await flush();
      expect(iceOps(rig.calls.medias[1].applied), [for (var i = 0; i < 100; i++) 'new$i']);
    });

    test('hang-up by the peer, sign-out, background and ICE failure all clear the buffer', () async {
      final ends = <String, void Function()>{
        'peer hangup': () => rig.signal({'type': 'HANGUP', 'callId': c1}),
        'sign-out': () => rig.provider.reset(),
        'background': () => rig.provider.endForBackground(),
        'ICE failed': () => rig.calls.media.onState!(PeerState.failed),
      };
      for (final e in ends.entries) {
        await rig.dispose();
        rig = CallRig();
        await rig.start();
        await answered(id: c1);
        rig.signal(_ice(c1, 'stale'));
        await flush();
        e.value();
        await flush();
        expect(rig.provider.phase, CallPhase.idle, reason: e.key);
        if (e.key == 'sign-out') rig.provider.start(me);
        await answered(id: c2);
        rig.signal(_sdp(c2, 'offer'));
        await flush();
        expect(rig.calls.medias.last.applied, [
          'remote:offer',
        ], reason: '${e.key}: stale candidate replayed into the next call');
        rig.provider.reset();
      }
    });

    test('candidates queued behind a slow setRemote are dropped if the call ends meanwhile', () async {
      await answered();
      final gate = Completer<void>();
      rig.calls.media.setRemoteGate = gate;
      rig.signal(_sdp(c1, 'offer'));
      rig.signal(_ice(c1, 'queued'));
      await flush();
      final old = rig.calls.media;
      rig.provider.end();
      gate.complete();
      await flush();
      expect(old.applied, ['remote:offer'], reason: 'no addCandidate on a closed peer connection');
      expect(old.leaks, isEmpty);
    });
  });

  group('a slow setRemote of a finished call must not corrupt the next call', () {
    /// Call 1's offer is being applied (hangs), the user hangs up, call 2 starts and its early candidate arrives.
    Future<(Completer<void>, List<String>)> staleSetRemote() async {
      await answered(id: c1);
      final gate = Completer<void>();
      rig.calls.media.setRemoteGate = gate;
      rig.signal(_sdp(c1, 'offer')); // setRemote of call 1 hangs
      await flush();
      rig.provider.end(); // hang up meanwhile
      await answered(id: c2);
      final sentBefore = List.of(rig.calls.sentTo);
      rig.signal(_ice(c2, 'new-early')); // call 2's candidate beats call 2's offer
      await flush();
      return (gate, sentBefore);
    }

    test('call 2 keeps its early candidate until ITS remote description (never addCandidate before it)', () async {
      final (gate, _) = await staleSetRemote();
      gate.complete(); // call 1's setRemote finally returns
      await flush();
      rig.signal(_sdp(c2, 'offer'));
      await flush();
      expect(rig.calls.medias[1].applied, [
        'remote:offer',
        'ice:new-early',
      ], reason: 'WebRTC rejects a candidate added before the remote description: it would be lost');
    });

    test('no answer SDP is sent for the call that was hung up', () async {
      final (gate, sentBefore) = await staleSetRemote();
      gate.complete();
      await flush();
      expect(
        rig.calls.sentTo.skip(sentBefore.length).where((d) => d.contains(c1)),
        isEmpty,
        reason: 'a frame for a finished call id',
      );
    });
  });
}
