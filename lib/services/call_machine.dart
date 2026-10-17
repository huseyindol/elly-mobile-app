/// WebRTC call signalling state machine — the transitions of admin `call-store.ts` (backend `CallSessionService`),
/// without I/O: callers feed user actions and parsed signals, and carry out the returned [CallEffect]s (STOMP sends,
/// SDP/ICE for the peer connection, end notices). One call at a time; a second incoming call is rejected (busy).
///
/// Stricter than the admin where the admin trusts every frame: a signal is applied only for the current call id (a
/// foreign / stale call's ANSWERED, SDP or ICE is ignored), and the replies to a dial that the user cancelled before
/// RINGING arrived are matched by order and cancelled, so the callee does not keep ringing.
library;

import 'dart:convert';

import 'chat_format.dart';
import 'stomp_destinations.dart';

/// idle → outgoing | incoming (ringing) → connecting (answered, SDP/ICE) → active (media connected) → idle.
/// "Ended" is the way back to idle, with a [CallEnded] effect saying why.
enum CallPhase { idle, outgoing, incoming, connecting, active }

/// Backend `CallSignalType`.
const callSignalTypes = {
  'INCOMING_CALL',
  'RINGING',
  'ANSWERED',
  'CALL_TAKEN',
  'REJECTED',
  'CANCELLED',
  'HANGUP',
  'TIMEOUT',
  'UNAVAILABLE',
  'BUSY',
  'ERROR',
  'SDP',
  'ICE',
};

/// A session description is a few KB; anything far larger is not a real one.
const maxSdpLength = 64 * 1024;
const maxCandidateLength = 2048;

/// Backend `DtoCallSignal`, parsed defensively.
class CallSignal {
  final String type;
  final String? callId;
  final int? peerUserId;

  /// Backend's peer username (session identity, not caller-supplied text) as safe display text.
  final String peerName;
  final bool ringAll;
  final String? sdpType;
  final String? sdp;
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  /// ERROR / UNAVAILABLE / BUSY text (backend-written), as safe display text.
  final String? reason;

  const CallSignal(
    this.type, {
    this.callId,
    this.peerUserId,
    this.peerName = '',
    this.ringAll = false,
    this.sdpType,
    this.sdp,
    this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
    this.reason,
  });

  /// null for anything that is not a signal: bad JSON, unknown type, a call id that is not a UUID. Oversized or
  /// mistyped SDP/ICE fields are dropped (the signal then carries nothing to apply).
  static CallSignal? parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final json = decoded;
    final type = json['type'];
    if (type is! String || !callSignalTypes.contains(type)) return null;
    final callId = json['callId'];
    if (callId != null && (callId is! String || !isUuid(callId))) return null;
    String? str(String key, int max) {
      final v = json[key];
      return v is String && v.isNotEmpty && v.length <= max ? v : null;
    }

    final sdpType = str('sdpType', 6);
    final peer = json['peerUserId'];
    final index = json['sdpMLineIndex'];
    final reason = str('reason', 500);
    return CallSignal(
      type,
      callId: callId as String?,
      peerUserId: peer is int && peer > 0 ? peer : null,
      peerName: displayPeerName(str('peerDisplayName', 500) ?? ''),
      ringAll: json['ringAll'] == true,
      sdpType: sdpType == 'offer' || sdpType == 'answer' ? sdpType : null,
      sdp: str('sdp', maxSdpLength),
      candidate: str('candidate', maxCandidateLength),
      sdpMid: str('sdpMid', 64),
      sdpMLineIndex: index is int && index >= 0 && index < 64 ? index : null,
      reason: reason == null ? null : clipChatText(safeChatText(reason), maxChars: 200, maxLines: 3).$1,
    );
  }
}

/// One line, untrusted-text safe, at most 80 characters.
String displayPeerName(String name) =>
    clipChatText(safeChatText(name).replaceAll('\n', ' ').trim(), maxChars: 80, maxLines: 1).$1;

sealed class CallEffect {
  const CallEffect();
}

/// STOMP SEND; [body] is JSON-encoded (null → empty body, like the admin).
final class CallSend extends CallEffect {
  final String destination;
  final Map<String, Object?>? body;
  const CallSend(this.destination, [this.body]);

  @override
  String toString() => 'CallSend($destination, $body)';
}

/// The call is over; [message] for the user (null: the user ended it).
final class CallEnded extends CallEffect {
  final String? message;
  const CallEnded(this.message);

  @override
  String toString() => 'CallEnded($message)';
}

final class CallRemoteSdp extends CallEffect {
  final String type;
  final String sdp;
  const CallRemoteSdp(this.type, this.sdp);
}

final class CallRemoteIce extends CallEffect {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  const CallRemoteIce(this.candidate, this.sdpMid, this.sdpMLineIndex);
}

class CallMachine {
  CallPhase _phase = CallPhase.idle;
  String? _callId;
  bool _isCaller = false;
  bool _ringAll = false;
  int? _peerUserId;
  String _peerName = '';
  int? _calleeUserId;
  String? _groupId;
  bool _dialed = false;
  bool _answering = false;
  int _generation = 0;

  /// Dials whose reply (RINGING / BUSY / UNAVAILABLE / ERROR) had not arrived when the user cancelled. Replies come
  /// in dial order on the one connection, so the next replies belong to them.
  int _abandonedDials = 0;

  /// Recently ended call ids: a late ANSWERED for one is hung up, a late INCOMING_CALL for one ignored.
  final List<String> _ended = [];

  CallPhase get phase => _phase;
  String? get callId => _callId;
  bool get isCaller => _isCaller;
  bool get ringAll => _ringAll;
  int? get peerUserId => _peerUserId;
  String get peerName => _peerName;

  /// Own call: the dial frame went out (before that the microphone/camera is being opened).
  bool get dialed => _dialed;

  /// Incoming call: the user accepted (media opening / answer sent), waiting for ANSWERED.
  bool get answering => _answering;

  /// Changes whenever a call starts or ends: async work captures it and drops its result if it changed.
  int get generation => _generation;

  /// Starts an own call: outgoing, nothing sent yet — media opens first, then [dial]. False while in a call.
  bool begin(int calleeUserId, String peerName, {String? groupId}) {
    if (_phase != CallPhase.idle) return false;
    _generation++;
    _phase = CallPhase.outgoing;
    _isCaller = true;
    _calleeUserId = calleeUserId;
    _peerUserId = calleeUserId;
    _peerName = displayPeerName(peerName);
    _groupId = isUuid(groupId) ? groupId : null;
    return true;
  }

  List<CallEffect> dial(int generation) {
    if (generation != _generation || _phase != CallPhase.outgoing || _dialed) return const [];
    _dialed = true;
    return [
      CallSend(StompDest.rtcCall, {'calleeUserId': _calleeUserId, 'groupId': ?_groupId}),
    ];
  }

  /// The user accepts the ringing call (media opens next, then [confirmAnswer]). False if nothing is ringing.
  bool beginAnswer() {
    if (_phase != CallPhase.incoming || _answering) return false;
    _answering = true;
    return true;
  }

  List<CallEffect> confirmAnswer(int generation) {
    if (generation != _generation || _phase != CallPhase.incoming || !_answering) return const [];
    return [CallSend(StompDest.rtcAnswer(_callId!))];
  }

  /// The peer connection is up. False if this is not the connecting call any more.
  bool markConnected(int generation) {
    if (generation != _generation || _phase != CallPhase.connecting) return false;
    _phase = CallPhase.active;
    return true;
  }

  /// Ends the call from this side — cancel (own, ringing), reject (incoming) or hang up (answered) — with an
  /// optional [message] for the user (timeout, media failure, app sent to background …).
  List<CallEffect> end([String? message]) {
    final id = _callId;
    final effects = <CallEffect>[];
    switch (_phase) {
      case CallPhase.idle:
        return const [];
      case CallPhase.outgoing:
        if (id != null) {
          effects.add(CallSend(StompDest.rtcCancel(id)));
        } else if (_dialed) {
          _abandonedDials++; // its RINGING (when it comes) is cancelled
        }
      case CallPhase.incoming:
        // After an answer that the backend already took, the reject is ignored there; the ANSWERED that follows
        // is hung up ([_ended]).
        effects.add(CallSend(StompDest.rtcReject(id!)));
      case CallPhase.connecting || CallPhase.active:
        effects.add(CallSend(StompDest.rtcHangup(id!)));
    }
    _toIdle();
    effects.add(CallEnded(message));
    return effects;
  }

  /// Sign-out: the end frames only (no notice), pending dial replies forgotten.
  List<CallEffect> reset() {
    final effects = end().whereType<CallSend>().toList();
    _abandonedDials = 0;
    _ended.clear();
    return effects;
  }

  /// The STOMP session was replaced: replies to earlier dials were lost with the old one.
  void connectionReset() => _abandonedDials = 0;

  List<CallEffect> handle(CallSignal s) {
    final id = s.callId;
    final current = id != null && id == _callId;
    switch (s.type) {
      case 'INCOMING_CALL':
        if (id == null || current || _ended.contains(id)) return const []; // duplicate / stale
        if (_phase != CallPhase.idle) return [CallSend(StompDest.rtcReject(id))]; // busy: one call at a time
        _generation++;
        _phase = CallPhase.incoming;
        _callId = id;
        _isCaller = false;
        _ringAll = s.ringAll;
        _peerUserId = s.peerUserId;
        _peerName = s.peerName;
        return const [];

      case 'RINGING':
        if (id == null) return const [];
        if (_abandonedDials > 0) {
          _abandonedDials--;
          _remember(id);
          return [CallSend(StompDest.rtcCancel(id))];
        }
        if (_phase != CallPhase.outgoing || !_dialed || _callId != null) return const [];
        _callId = id;
        _adoptPeer(s);
        return const [];

      case 'BUSY' || 'UNAVAILABLE' || 'ERROR' when id == null:
        // The reply to a dial.
        if (_abandonedDials > 0) {
          _abandonedDials--;
          return const [];
        }
        if (_phase != CallPhase.outgoing || !_dialed || _callId != null) return const [];
        return _finish(s.reason ?? _fallbackReason(s.type));

      case 'ANSWERED':
        if (id == null) return const [];
        if (!current) return _ended.contains(id) ? [CallSend(StompDest.rtcHangup(id))] : const [];
        if (_phase == CallPhase.outgoing || (_phase == CallPhase.incoming && _answering)) {
          _phase = CallPhase.connecting;
          _adoptPeer(s);
          return const [];
        }
        // Signals go to the user, not the device: the same account answered somewhere else.
        if (_phase == CallPhase.incoming) return _finish('Çağrı başka bir cihazınızda cevaplandı.');
        return const [];

      case 'SDP':
        if (!current || !_inCall || s.sdpType == null || s.sdp == null) return const [];
        return [CallRemoteSdp(s.sdpType!, s.sdp!)];

      case 'ICE':
        if (!current || !_inCall || s.candidate == null) return const [];
        return [CallRemoteIce(s.candidate!, s.sdpMid, s.sdpMLineIndex)];

      case 'CALL_TAKEN':
        if (!current || _phase != CallPhase.incoming) return const [];
        return _finish(
          _ringAll ? 'Destek çağrısı başka bir panel kullanıcısı tarafından cevaplandı.' : 'Çağrı artık geçerli değil.',
        );

      case 'REJECTED':
        if (!current || _phase != CallPhase.outgoing) return const [];
        return _finish('Çağrı reddedildi.');

      case 'CANCELLED':
        if (!current || _phase != CallPhase.incoming) return const [];
        return _finish(_missed());

      case 'TIMEOUT':
        if (!current) return const [];
        if (_phase == CallPhase.outgoing) return _finish('Cevap yok.');
        if (_phase == CallPhase.incoming) return _finish(_missed());
        return const [];

      case 'HANGUP':
        if (!current || !_inCall) return const [];
        return _finish('Görüşme karşı tarafça sonlandırıldı.');

      default: // BUSY / UNAVAILABLE / ERROR for a call id
        if (!current) return const [];
        return _finish(s.reason ?? _fallbackReason(s.type));
    }
  }

  bool get _inCall => _phase == CallPhase.connecting || _phase == CallPhase.active;

  String _missed() => _peerName.isEmpty ? 'Cevapsız çağrı.' : 'Cevapsız çağrı: $_peerName';

  static String _fallbackReason(String type) => switch (type) {
    'BUSY' => 'Kullanıcı meşgul.',
    'UNAVAILABLE' => 'Kullanıcı müsait değil.',
    _ => 'Çağrı hatası.',
  };

  void _adoptPeer(CallSignal s) {
    _peerUserId = s.peerUserId ?? _peerUserId;
    if (s.peerName.isNotEmpty) _peerName = s.peerName;
  }

  List<CallEffect> _finish(String? message) {
    _toIdle();
    return [CallEnded(message)];
  }

  void _remember(String id) {
    _ended.add(id);
    if (_ended.length > 16) _ended.removeAt(0);
  }

  void _toIdle() {
    if (_callId != null) _remember(_callId!);
    _generation++;
    _phase = CallPhase.idle;
    _callId = null;
    _isCaller = false;
    _ringAll = false;
    _peerUserId = null;
    _peerName = '';
    _calleeUserId = null;
    _groupId = null;
    _dialed = false;
    _answering = false;
  }
}
