import 'dart:convert';

import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:flutter_test/flutter_test.dart';

const c1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const c2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const c3 = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const g1 = '11111111-1111-4111-8111-111111111111';

CallSignal sig(
  String type, {
  String? id,
  int? peer,
  String? name,
  bool ringAll = false,
  String? sdpType,
  String? sdp,
  String? candidate,
  String? reason,
}) => CallSignal.parse(
  jsonEncode({
    'type': type,
    'callId': id,
    'peerUserId': peer,
    'peerDisplayName': name,
    'ringAll': ringAll,
    'sdpType': sdpType,
    'sdp': sdp,
    'candidate': candidate,
    'sdpMid': candidate == null ? null : '0',
    'sdpMLineIndex': candidate == null ? null : 0,
    'reason': reason,
  }),
)!;

List<String> sends(List<CallEffect> effects) => [for (final e in effects.whereType<CallSend>()) e.destination];
List<String?> ended(List<CallEffect> effects) => [for (final e in effects.whereType<CallEnded>()) e.message];

void main() {
  late CallMachine m;
  setUp(() => m = CallMachine());

  /// Own call c1 to user 9, ringing.
  void ringingOut({String id = c1}) {
    m.begin(9, 'Ayşe', groupId: g1);
    m.dial(m.generation);
    m.handle(sig('RINGING', id: id, peer: 9, name: 'ayse'));
  }

  /// Incoming call c1 from user 5.
  void ringingIn({String id = c1, bool ringAll = false}) =>
      m.handle(sig('INCOMING_CALL', id: id, peer: 5, name: 'mehmet', ringAll: ringAll));

  void inCall({bool caller = true}) {
    if (caller) {
      ringingOut();
    } else {
      ringingIn();
      m.beginAnswer();
      m.confirmAnswer(m.generation);
    }
    m.handle(sig('ANSWERED', id: c1, peer: caller ? 9 : 5, name: caller ? 'ayse' : 'mehmet'));
  }

  group('CallSignal.parse (untrusted frame)', () {
    test('rejects non-signals: bad JSON, not an object, unknown type, non-UUID call id', () {
      for (final body in [
        '',
        'x',
        '[]',
        '"INCOMING_CALL"',
        '{}',
        '{"type":"RING"}',
        '{"type":7}',
        '{"type":"incoming_call","callId":"$c1"}',
        '{"type":"INCOMING_CALL","callId":"$c1/answer"}',
        '{"type":"INCOMING_CALL","callId":"../$c1"}',
        '{"type":"INCOMING_CALL","callId":"*"}',
        '{"type":"INCOMING_CALL","callId":"$c1 "}',
        '{"type":"INCOMING_CALL","callId":12}',
      ]) {
        expect(CallSignal.parse(body), isNull, reason: body);
      }
    });

    test('backend DtoCallSignal fields; a null call id is kept (dial replies)', () {
      final s = sig('INCOMING_CALL', id: c1, peer: 5, name: 'mehmet', ringAll: true);
      expect((s.type, s.callId, s.peerUserId, s.peerName, s.ringAll), ('INCOMING_CALL', c1, 5, 'mehmet', true));
      expect(sig('BUSY', reason: 'Kullanıcı meşgul').callId, isNull);
      expect(sig('BUSY', reason: 'Kullanıcı meşgul').reason, 'Kullanıcı meşgul');
    });

    test('display texts are safe: bidi visible, control/new lines removed, clipped', () {
      final s = sig('INCOMING_CALL', id: c1, name: 'evil\u202Etxt.exe\n\u0007second line ${'x' * 200}');
      expect(s.peerName, isNot(contains('\u202E')));
      expect(s.peerName, contains('⟨U+202E⟩'));
      expect(s.peerName, isNot(contains('\n')));
      expect(s.peerName, isNot(contains('\u0007')));
      expect(s.peerName.length, lessThanOrEqualTo(81));
      expect(sig('ERROR', reason: '<b>x</b>&amp;\u202E').reason, '<b>x</b>&⟨U+202E⟩');
    });

    test('SDP/ICE fields are dropped when malformed or oversized (nothing to apply)', () {
      expect(sig('SDP', id: c1, sdpType: 'pranswer', sdp: 'v=0').sdpType, isNull);
      expect(sig('SDP', id: c1, sdpType: 'offer', sdp: 'v' * (maxSdpLength + 1)).sdp, isNull);
      expect(sig('ICE', id: c1, candidate: 'c' * (maxCandidateLength + 1)).candidate, isNull);
      final bad = CallSignal.parse(jsonEncode({'type': 'ICE', 'callId': c1, 'candidate': 'c', 'sdpMLineIndex': -1}))!;
      expect(bad.sdpMLineIndex, isNull);
      expect(
        CallSignal.parse(jsonEncode({'type': 'INCOMING_CALL', 'callId': c1, 'ringAll': 'true'}))!.ringAll,
        isFalse,
      );
      expect(
        CallSignal.parse(jsonEncode({'type': 'INCOMING_CALL', 'callId': c1, 'peerUserId': '5'}))!.peerUserId,
        isNull,
      );
    });
  });

  group('outgoing (admin startCall → RINGING → ANSWERED)', () {
    test('begin opens nothing on the wire; dial sends DtoCallStart once', () {
      expect(m.begin(9, 'Ayşe', groupId: g1), isTrue);
      expect(m.phase, CallPhase.outgoing);
      expect(m.isCaller, isTrue);
      expect(m.dialed, isFalse);
      final effects = m.dial(m.generation);
      expect(effects.single, isA<CallSend>());
      final send = effects.single as CallSend;
      expect(send.destination, '/app/rtc/call');
      expect(send.body, {'calleeUserId': 9, 'groupId': g1});
      expect(m.dial(m.generation), isEmpty, reason: 'second dial');
      expect(m.begin(10, 'x'), isFalse, reason: 'one call at a time');
    });

    test('groupId only when it is a UUID', () {
      m.begin(9, 'Ayşe', groupId: 'g1/../x');
      expect((m.dial(m.generation).single as CallSend).body, {'calleeUserId': 9});
    });

    test('RINGING adopts the call id and backend peer name; ANSWERED → connecting; connected → active', () {
      m.begin(9, 'Ayşe (üye listesi)');
      expect(m.handle(sig('RINGING', id: c1)), isEmpty, reason: 'not dialed yet → ignored');
      expect(m.callId, isNull);
      m.dial(m.generation);
      m.handle(sig('RINGING', id: c1, peer: 9, name: 'ayse'));
      expect((m.callId, m.peerName, m.phase), (c1, 'ayse', CallPhase.outgoing));
      final gen = m.generation;
      expect(m.handle(sig('ANSWERED', id: c1, peer: 9, name: 'ayse')), isEmpty);
      expect(m.phase, CallPhase.connecting);
      expect(m.markConnected(gen - 1), isFalse);
      expect(m.markConnected(gen), isTrue);
      expect(m.phase, CallPhase.active);
      expect(m.markConnected(gen), isFalse);
    });

    test('a second RINGING (other call id) does not replace the call', () {
      ringingOut();
      m.handle(sig('RINGING', id: c2));
      expect(m.callId, c1);
    });

    test('terminal replies: REJECTED, TIMEOUT, BUSY / UNAVAILABLE / ERROR (null id) with the backend reason', () {
      ringingOut();
      expect(ended(m.handle(sig('REJECTED', id: c1))), ['Çağrı reddedildi.']);
      expect(m.phase, CallPhase.idle);

      ringingOut(id: c2);
      expect(ended(m.handle(sig('TIMEOUT', id: c2))), ['Cevap yok.']);

      for (final (type, reason, text) in [
        ('BUSY', 'Kullanıcı meşgul', 'Kullanıcı meşgul'),
        ('UNAVAILABLE', 'Kullanıcı çevrimdışı', 'Kullanıcı çevrimdışı'),
        ('ERROR', 'Bu kullanıcıyı arama yetkiniz yok', 'Bu kullanıcıyı arama yetkiniz yok'),
        ('ERROR', null, 'Çağrı hatası.'),
      ]) {
        m.begin(9, 'Ayşe');
        m.dial(m.generation);
        expect(ended(m.handle(sig(type, reason: reason))), [text], reason: type);
        expect(m.phase, CallPhase.idle);
      }
    });

    test('a null-id reply before dialing (or while idle) is ignored', () {
      expect(m.handle(sig('BUSY')), isEmpty);
      m.begin(9, 'Ayşe');
      expect(m.handle(sig('ERROR', reason: 'x')), isEmpty);
      expect(m.phase, CallPhase.outgoing);
    });
  });

  group('incoming (INCOMING_CALL → answer → ANSWERED)', () {
    test('rings with the backend identity; answer is two-step (media first)', () {
      ringingIn(ringAll: true);
      expect((m.phase, m.callId, m.peerUserId, m.peerName, m.ringAll), (CallPhase.incoming, c1, 5, 'mehmet', true));
      expect(m.isCaller, isFalse);
      expect(m.confirmAnswer(m.generation), isEmpty, reason: 'not accepted yet');
      expect(m.beginAnswer(), isTrue);
      expect(m.beginAnswer(), isFalse);
      expect(m.answering, isTrue);
      expect(m.confirmAnswer(m.generation - 1), isEmpty, reason: 'stale generation');
      expect(sends(m.confirmAnswer(m.generation)), ['/app/rtc/$c1/answer']);
      m.handle(sig('ANSWERED', id: c1, peer: 5, name: 'mehmet'));
      expect(m.phase, CallPhase.connecting);
    });

    test('CANCELLED / TIMEOUT → missed call notice; CALL_TAKEN (ring-all) → taken notice', () {
      ringingIn();
      expect(ended(m.handle(sig('CANCELLED', id: c1))), ['Cevapsız çağrı: mehmet']);
      ringingIn(id: c2);
      expect(ended(m.handle(sig('TIMEOUT', id: c2))), ['Cevapsız çağrı: mehmet']);
      ringingIn(id: c3, ringAll: true);
      m.beginAnswer();
      expect(ended(m.handle(sig('CALL_TAKEN', id: c3))), [
        'Destek çağrısı başka bir panel kullanıcısı tarafından cevaplandı.',
      ]);
      expect(m.phase, CallPhase.idle);
    });

    test('ANSWERED while still ringing here = the same account answered on another device', () {
      ringingIn();
      final effects = m.handle(sig('ANSWERED', id: c1, peer: 5));
      expect(sends(effects), isEmpty, reason: 'nothing to hang up: the other device has the call');
      expect(ended(effects), ['Çağrı başka bir cihazınızda cevaplandı.']);
      expect(m.phase, CallPhase.idle);
    });

    test('INCOMING_CALL without an id is ignored; a duplicate of the ringing call is not answered as busy', () {
      expect(m.handle(sig('INCOMING_CALL', peer: 5)), isEmpty);
      expect(m.phase, CallPhase.idle);
      ringingIn();
      expect(m.handle(sig('INCOMING_CALL', id: c1, peer: 5)), isEmpty);
      expect(m.phase, CallPhase.incoming);
    });
  });

  group('busy: one call at a time (admin auto-reject)', () {
    final phases = <String, void Function()>{
      'outgoing (preparing)': () => m.begin(9, 'x'),
      'outgoing (ringing)': () => ringingOut(),
      'incoming': () => ringingIn(),
      'incoming (answering)': () {
        ringingIn();
        m.beginAnswer();
      },
      'connecting': () => inCall(),
      'active': () {
        inCall();
        m.markConnected(m.generation);
      },
    };
    for (final e in phases.entries) {
      test('second INCOMING_CALL during ${e.key} → reject that call, keep ours', () {
        e.value();
        final before = (m.phase, m.callId, m.generation);
        expect(sends(m.handle(sig('INCOMING_CALL', id: c2, peer: 6))), ['/app/rtc/$c2/reject']);
        expect((m.phase, m.callId, m.generation), before);
      });
    }
  });

  group('signals of another / an old call are ignored', () {
    test('foreign call id during a call: no transition, no SDP/ICE effect', () {
      inCall();
      final before = (m.phase, m.callId, m.generation);
      for (final s in [
        sig('SDP', id: c2, sdpType: 'offer', sdp: 'v=0 evil'),
        sig('ICE', id: c2, candidate: 'candidate:evil'),
        sig('ANSWERED', id: c2),
        sig('HANGUP', id: c2),
        sig('REJECTED', id: c2),
        sig('CANCELLED', id: c2),
        sig('TIMEOUT', id: c2),
        sig('CALL_TAKEN', id: c2),
        sig('ERROR', id: c2, reason: 'x'),
        sig('RINGING', id: c2),
        sig('BUSY'),
      ]) {
        expect(m.handle(s), isEmpty, reason: s.type);
      }
      expect((m.phase, m.callId, m.generation), before);
    });

    test('SDP/ICE only once answered (not while ringing, not while idle)', () {
      expect(m.handle(sig('SDP', id: c1, sdpType: 'offer', sdp: 'v=0')), isEmpty);
      ringingOut();
      expect(m.handle(sig('SDP', id: c1, sdpType: 'answer', sdp: 'v=0')), isEmpty);
      expect(m.handle(sig('ICE', id: c1, candidate: 'candidate:1')), isEmpty);
      m.handle(sig('ANSWERED', id: c1));
      final sdp = m.handle(sig('SDP', id: c1, sdpType: 'answer', sdp: 'v=0 a')).single as CallRemoteSdp;
      expect((sdp.type, sdp.sdp), ('answer', 'v=0 a'));
      final ice = m.handle(sig('ICE', id: c1, candidate: 'candidate:1')).single as CallRemoteIce;
      expect((ice.candidate, ice.sdpMid, ice.sdpMLineIndex), ('candidate:1', '0', 0));
      expect(
        m.handle(sig('SDP', id: c1, sdpType: 'offer')),
        isEmpty,
        reason: 'no sdp text',
      );
      expect(m.handle(sig('ICE', id: c1)), isEmpty, reason: 'no candidate');
    });

    test('after the call ended its frames do nothing; a late ANSWERED is hung up; a late INCOMING_CALL ignored', () {
      inCall();
      m.end();
      expect(m.handle(sig('SDP', id: c1, sdpType: 'offer', sdp: 'v=0')), isEmpty);
      expect(m.handle(sig('HANGUP', id: c1)), isEmpty);
      expect(sends(m.handle(sig('ANSWERED', id: c1))), ['/app/rtc/$c1/hangup']);
      expect(m.handle(sig('INCOMING_CALL', id: c1, peer: 5)), isEmpty);
      expect(m.phase, CallPhase.idle);
      expect(m.handle(sig('ANSWERED', id: c3)), isEmpty, reason: 'never ours');
    });
  });

  group('ending from this side', () {
    test('cancel / reject / hang up by phase; the user ending it gives no notice', () {
      m.begin(9, 'x');
      expect(sends(m.end()), isEmpty, reason: 'nothing dialed yet');

      ringingOut();
      var e = m.end();
      expect(sends(e), ['/app/rtc/$c1/cancel']);
      expect(ended(e), [null]);

      ringingIn(id: c2);
      expect(sends(m.end()), ['/app/rtc/$c2/reject']);

      inCall();
      expect(sends(m.end('Uygulama arka plana geçti')), ['/app/rtc/$c1/hangup']);
      expect(m.end(), isEmpty, reason: 'idle');
    });

    test('reset (sign-out): end frames only, no notice', () {
      inCall();
      m.markConnected(m.generation);
      final effects = m.reset();
      expect(effects, everyElement(isA<CallSend>()));
      expect(sends(effects), ['/app/rtc/$c1/hangup']);
      expect(m.phase, CallPhase.idle);
      expect(m.reset(), isEmpty);
    });

    test('generation changes when a call starts or ends', () {
      final g0 = m.generation;
      m.begin(9, 'x');
      final g1 = m.generation;
      m.end();
      final g2 = m.generation;
      ringingIn();
      expect({g0, g1, g2, m.generation}, hasLength(4));
    });
  });

  group('races', () {
    test('both sides call each other: our dial is busy-rejected, their call is rejected as busy (admin)', () {
      // We dialed 5; 5 dialed us at the same moment. The backend marked us busy for their call and answers our
      // dial with BUSY ("Zaten bir çağrıdasınız").
      m.begin(5, 'mehmet');
      m.dial(m.generation);
      expect(sends(m.handle(sig('INCOMING_CALL', id: c2, peer: 5))), ['/app/rtc/$c2/reject']);
      expect(ended(m.handle(sig('BUSY', reason: 'Zaten bir çağrıdasınız'))), ['Zaten bir çağrıdasınız']);
      expect(m.phase, CallPhase.idle);
    });

    test('both sides call each other, other order: our BUSY reply first, then their call rings here', () {
      m.begin(5, 'mehmet');
      m.dial(m.generation);
      m.handle(sig('BUSY', reason: 'Kullanıcı meşgul'));
      m.handle(sig('INCOMING_CALL', id: c2, peer: 5, name: 'mehmet'));
      expect((m.phase, m.callId), (CallPhase.incoming, c2));
    });

    test('cancel vs answer (caller): cancel sent; if the answer won, the late ANSWERED is hung up', () {
      ringingOut();
      expect(sends(m.end()), ['/app/rtc/$c1/cancel']);
      expect(sends(m.handle(sig('ANSWERED', id: c1, peer: 9))), ['/app/rtc/$c1/hangup']);
      expect(m.phase, CallPhase.idle);
    });

    test('cancel vs answer (callee): CANCELLED while accepting ends it; the answer\'s CALL_TAKEN is ignored', () {
      ringingIn();
      m.beginAnswer();
      m.confirmAnswer(m.generation);
      expect(ended(m.handle(sig('CANCELLED', id: c1))), ['Cevapsız çağrı: mehmet']);
      expect(m.handle(sig('CALL_TAKEN', id: c1)), isEmpty);
      expect(m.phase, CallPhase.idle);
    });

    test('cancel vs answer (callee), answer won: ANSWERED → connecting', () {
      ringingIn();
      m.beginAnswer();
      m.confirmAnswer(m.generation);
      m.handle(sig('ANSWERED', id: c1, peer: 5));
      expect(m.phase, CallPhase.connecting);
    });

    test('cancelled before RINGING: the dial\'s RINGING is cancelled, the next call is not affected', () {
      m.begin(9, 'x');
      m.dial(m.generation);
      expect(sends(m.end()), isEmpty, reason: 'call id unknown yet');
      m.begin(10, 'y');
      m.dial(m.generation);
      expect(sends(m.handle(sig('RINGING', id: c1))), ['/app/rtc/$c1/cancel'], reason: 'reply to the cancelled dial');
      expect(m.callId, isNull);
      expect(m.handle(sig('RINGING', id: c2)), isEmpty);
      expect((m.phase, m.callId), (CallPhase.outgoing, c2));
      expect(sends(m.handle(sig('ANSWERED', id: c1))), ['/app/rtc/$c1/hangup'], reason: 'the ghost was answered');
      expect(m.callId, c2);
    });

    test('cancelled before the reply and the reply is BUSY: consumed, nothing sent', () {
      m.begin(9, 'x');
      m.dial(m.generation);
      m.end();
      expect(m.handle(sig('BUSY', reason: 'Kullanıcı meşgul')), isEmpty);
      ringingOut(id: c2);
      expect(m.callId, c2);
    });

    test('reconnect forgets pending dial replies (lost with the old session)', () {
      m.begin(9, 'x');
      m.dial(m.generation);
      m.end();
      m.connectionReset();
      ringingOut(id: c2);
      expect(m.callId, c2, reason: 'not mistaken for the lost reply');
    });

    test('timeout arrives after the user answered (backend: no answer processed) → missed', () {
      ringingIn();
      m.beginAnswer();
      expect(ended(m.handle(sig('TIMEOUT', id: c1))), ['Cevapsız çağrı: mehmet']);
    });

    test('CALL_TAKEN outside ringing is ignored; a non-ring-all CALL_TAKEN says the call is gone', () {
      inCall(caller: false);
      expect(m.handle(sig('CALL_TAKEN', id: c1)), isEmpty);
      expect(m.phase, CallPhase.connecting);
      m.end();
      ringingIn(id: c2);
      m.beginAnswer();
      expect(ended(m.handle(sig('CALL_TAKEN', id: c2))), ['Çağrı artık geçerli değil.']);
    });

    test('HANGUP from the peer while connecting or active', () {
      inCall();
      expect(ended(m.handle(sig('HANGUP', id: c1))), ['Görüşme karşı tarafça sonlandırıldı.']);
      expect(m.phase, CallPhase.idle);
    });
  });
}
