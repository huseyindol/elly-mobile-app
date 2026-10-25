import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/call_machine.dart';
import '../services/call_media.dart';
import '../services/incoming_call_service.dart';
import '../services/realtime_service.dart';
import '../services/stomp_destinations.dart';
import '../services/webrtc_call_media.dart';

/// A message for the user about the call (shown as a SnackBar by `AuthWrapper`).
class CallNotice {
  final String message;
  final bool error;

  /// Offer the app's system settings (microphone/camera permission refused).
  final bool openSettings;
  const CallNotice(this.message, {this.error = false, this.openSettings = false});
}

/// Admin `call-store` + `useWebRTCCall`: panel-to-panel calls (started from the chat member list) and answering a
/// tenant support call (ring-all). Signalling over the app's one STOMP connection ([RealtimeService]) on
/// `/topic/user/{myId}/rtc` + `/app/rtc/*`; transitions in the pure [CallMachine].
///
/// Media opens only on the user's own action — dialling or accepting — and **before** the dial/answer frame goes
/// out: a refused permission never claims a ring-all call from the other panel users (the call is rejected instead)
/// and never leaves a callee ringing for a caller without a microphone. Media is closed whenever the call leaves
/// [CallPhase.connecting]/[CallPhase.active] or a ringing state of its own — end, sign-out, app in background.
class CallProvider extends ChangeNotifier {
  final RealtimeService realtime;
  final CallMedia Function() _newMedia;

  /// Backend rings 30 s; a lost TIMEOUT frame must not ring forever.
  final Duration ringGuard;

  /// Answered but no media connection yet (no TURN: some NATs never connect).
  final Duration connectGuard;

  CallProvider({
    required this.realtime,
    CallMedia Function()? mediaFactory,
    this.ringGuard = const Duration(seconds: 35),
    this.connectGuard = const Duration(seconds: 30),
  }) : _newMedia = mediaFactory ?? WebrtcCallMedia.new;

  /// C3: Default STUN + optional TURN server configured via `--dart-define=TURN_URL=...`
  /// (`TURN_USERNAME`, `TURN_CREDENTIAL`).
  static const String _turnUrl = String.fromEnvironment('TURN_URL');
  static const String _turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const String _turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  static List<Map<String, Object>> get iceServers => [
    const {'urls': 'stun:stun.l.google.com:19302'},
    if (_turnUrl.isNotEmpty)
      {
        'urls': _turnUrl,
        if (_turnUsername.isNotEmpty) 'username': _turnUsername,
        if (_turnCredential.isNotEmpty) 'credential': _turnCredential,
      },
  ];
  static const maxPendingIce = 100;

  final _machine = CallMachine();
  final _notices = StreamController<CallNotice>.broadcast();
  RealtimeSubscription? _sub;
  int? _userId;
  int _seenSeq = 0;

  CallMedia? _media;
  Future<void> _queue = Future.value();
  bool _remoteSet = false;
  final List<CallRemoteIce> _pendingIce = [];
  Timer? _guard;
  DateTime? _connectedAt;
  bool _micOn = true;
  bool _camOn = false;
  bool _speakerOn = false;
  CallPhase _lastPhase = CallPhase.idle;
  int _lastGeneration = 0;

  // ── read ──
  Stream<CallNotice> get notices => _notices.stream;
  CallPhase get phase => _machine.phase;
  bool get isCaller => _machine.isCaller;
  bool get ringAll => _machine.ringAll;
  String get peerName => _machine.peerName;
  int? get peerUserId => _machine.peerUserId;
  bool get dialed => _machine.dialed;
  bool get ringing => _machine.dialed && _machine.callId != null;
  bool get answering => _machine.answering;

  /// Local media is open (preview / controls available).
  bool get mediaReady => _mediaReady;
  bool _mediaReady = false;
  CallMedia? get media => _mediaReady ? _media : null;
  bool get hasLocalVideo => _mediaReady && (_media?.hasVideo ?? false);
  bool get hasRemoteVideo => _mediaReady && (_media?.hasRemoteVideo ?? false);
  bool get micOn => _micOn;
  bool get camOn => _camOn;
  bool get speakerOn => _speakerOn;
  DateTime? get connectedAt => _connectedAt;

  // ── lifecycle ──

  /// Signed in as [userId]: listen for call signals (idempotent).
  void start(int userId) {
    if (_userId == userId) return;
    reset();
    _userId = userId;
    _seenSeq = realtime.connectionSeq;
    _sub = realtime.subscribe(StompDest.userRtc(userId), _onFrame);
    realtime.addListener(_onRealtime);
  }

  /// Sign-out (before the connection closes): ends any call — the peer is told, media is closed — silently.
  void reset() {
    if (_userId != null) realtime.removeListener(_onRealtime);
    _sub?.cancel();
    _sub = null;
    _userId = null;
    _apply(_machine.reset());
  }

  /// The app left the foreground: the OS stops background capture without a call service and the socket closes
  /// (`RealtimeService.setForeground(false)`), so the call ends — call this first, while the frame can still go out.
  void endForBackground() {
    if (phase == CallPhase.idle) return;
    _endWith(const CallNotice('Uygulama arka plana geçtiği için görüşme sonlandırıldı.'));
  }

  @override
  void dispose() {
    reset();
    _notices.close();
    super.dispose();
  }

  // ── user actions ──

  /// Calls panel user [userId] ([groupId]: the chat group it was started from — members skip the role hierarchy).
  Future<void> call(int userId, String name, {String? groupId, required bool video}) async {
    if (_userId == null || userId == _userId) return;
    if (!realtime.connected) {
      _notify(
        const CallNotice('Canlı bağlantı yok; arama başlatılamadı. Bağlantı kurulunca tekrar deneyin.', error: true),
      );
      return;
    }
    if (!_machine.begin(userId, name, groupId: groupId)) {
      _notify(const CallNotice('Zaten bir görüşmedesiniz.'));
      return;
    }
    _sync();
    final generation = _machine.generation;
    if (!await _openMedia(generation, video)) return;
    _apply(_machine.dial(generation));
  }

  /// Accepts the ringing call (with or without the camera).
  Future<void> answer({required bool video}) async {
    if (phase != CallPhase.incoming || answering) return;
    if (!realtime.connected) {
      _notify(const CallNotice('Canlı bağlantı yok; çağrı cevaplanamadı.', error: true));
      return;
    }
    _machine.beginAnswer();
    final generation = _machine.generation;
    notifyListeners();
    if (!await _openMedia(generation, video)) return;
    _apply(_machine.confirmAnswer(generation));
  }

  /// Reject (incoming) · cancel (own, ringing) · hang up (answered).
  void end() => _apply(_machine.end());

  void toggleMic() {
    final m = media;
    if (m == null) return;
    _micOn = !_micOn;
    m.setMic(_micOn);
    notifyListeners();
  }

  void toggleCamera() {
    final m = media;
    if (m == null || !m.hasVideo) return;
    _camOn = !_camOn;
    m.setCamera(_camOn);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final m = media;
    if (m == null || !m.hasVideo || !_camOn) return;
    try {
      await m.switchCamera();
    } catch (_) {
      _notify(const CallNotice('Kamera değiştirilemedi.', error: true));
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    final m = media;
    if (m == null) return;
    _speakerOn = !_speakerOn;
    notifyListeners();
    try {
      await m.setSpeaker(_speakerOn);
    } catch (_) {
      if (_media != m) return;
      _speakerOn = !_speakerOn;
      _notify(const CallNotice('Ses çıkışı değiştirilemedi.', error: true));
      notifyListeners();
    }
  }

  // ── internals ──

  void _onRealtime() {
    if (realtime.connectionSeq == _seenSeq) return;
    _seenSeq = realtime.connectionSeq;
    _machine.connectionReset();
  }

  void _onFrame(String body) {
    final signal = CallSignal.parse(body);
    if (signal != null) _apply(_machine.handle(signal));
  }

  void _send(String destination, [Map<String, Object?>? body]) =>
      realtime.send(destination, body == null ? '' : jsonEncode(body));

  void _notify(CallNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  void _endWith(CallNotice notice) {
    _apply(_machine.end());
    _notify(notice);
  }

  void _apply(List<CallEffect> effects) {
    for (final e in effects) {
      switch (e) {
        case CallSend(:final destination, :final body):
          _send(destination, body);
        case CallEnded(:final message):
          if (message != null) _notify(CallNotice(message));
        case CallRemoteSdp(:final type, :final sdp):
          final callId = _machine.callId!;
          final generation = _machine.generation;
          _enqueue((m) async {
            final answer = await m.setRemote(type, sdp);
            if (generation != _machine.generation || _media != m) return;
            _remoteSet = true;
            final pending = List.of(_pendingIce);
            _pendingIce.clear();
            for (final c in pending) {
              if (generation != _machine.generation || _media != m) return;
              await m.addIce(c.candidate, c.sdpMid, c.sdpMLineIndex).catchError((_) {});
            }
            if (answer != null && generation == _machine.generation && _media == m) {
              _send(StompDest.rtcSdp(callId), {'sdpType': 'answer', 'sdp': answer});
            }
          });
        case CallRemoteIce():
          _enqueue((m) async {
            if (!_remoteSet) {
              if (_pendingIce.length < maxPendingIce) _pendingIce.add(e);
              return;
            }
            await m.addIce(e.candidate, e.sdpMid, e.sdpMLineIndex).catchError((_) {});
          });
      }
    }
    _sync();
  }

  /// Media work in arrival order, dropped once its call is over.
  void _enqueue(Future<void> Function(CallMedia media) op) {
    final media = _media;
    final generation = _machine.generation;
    if (media == null) return;
    _queue = _queue.then((_) async {
      if (generation != _machine.generation || _media != media) return;
      try {
        await op(media);
      } catch (_) {
        if (generation == _machine.generation) {
          _endWith(const CallNotice('Görüşme bağlantısı kurulamadı.', error: true));
        }
      }
    });
  }

  /// Housekeeping after a transition: media teardown, guards, the caller's offer.
  void _sync() {
    final phase = _machine.phase;
    final generation = _machine.generation;
    final changed = phase != _lastPhase || generation != _lastGeneration;
    final newCall = generation != _lastGeneration;
    _lastPhase = phase;
    _lastGeneration = generation;
    if (changed) {
      switch (phase) {
        case CallPhase.idle:
          unawaited(IncomingCallService.endNativeCall());
          _teardown();
        case CallPhase.outgoing || CallPhase.incoming:
          if (newCall) {
            _arm(ringGuard, phase == CallPhase.outgoing ? 'Cevap yok.' : null);
            if (phase == CallPhase.incoming && _machine.callId != null) {
              unawaited(
                IncomingCallService.showIncomingCall(
                  callId: _machine.callId!,
                  callerName: _machine.peerName,
                  callerUserId: _machine.peerUserId,
                  ringAll: _machine.ringAll,
                ),
              );
            }
          }
        case CallPhase.connecting:
          _arm(connectGuard, 'Bağlantı kurulamadı. Ağınız doğrudan bağlantıya izin vermiyor olabilir.');
          if (_machine.isCaller) {
            final callId = _machine.callId!;
            final generation = _machine.generation;
            _enqueue((m) async {
              final offer = await m.createOffer();
              if (generation != _machine.generation || _media != m) return;
              _send(StompDest.rtcSdp(callId), {'sdpType': 'offer', 'sdp': offer});
            });
          }
        case CallPhase.active:
          _guard?.cancel();
          _connectedAt = DateTime.now();
      }
    }
    notifyListeners();
  }

  void _arm(Duration after, String? message) {
    _guard?.cancel();
    final generation = _machine.generation;
    _guard = Timer(after, () {
      if (generation != _machine.generation) return;
      final missed = phase == CallPhase.incoming
          ? (peerName.isEmpty ? 'Cevapsız çağrı.' : 'Cevapsız çağrı: $peerName')
          : null;
      _endWith(CallNotice(message ?? missed ?? 'Çağrı sonlandı.'));
    });
  }

  Future<bool> _openMedia(int generation, bool video) async {
    final media = _newMedia();
    _media = media;
    String? fallback;
    try {
      try {
        await media.open(video: video);
      } on CallMediaException {
        if (!video) rethrow;
        await media.open(video: false); // camera refused / missing → audio only (admin)
      }
      if (video && !media.hasVideo) fallback = 'Kamera açılamadı — sesli devam ediliyor.';
      if (generation != _machine.generation) throw const CallMediaException(CallMediaError.other);
      await media.connect(
        iceServers: iceServers,
        onIce: (candidate, sdpMid, index) => _onLocalIce(generation, candidate, sdpMid, index),
        onState: (state) => _onPeerState(generation, state),
        onRemote: () {
          if (generation == _machine.generation) notifyListeners();
        },
      );
      if (generation != _machine.generation) throw const CallMediaException(CallMediaError.other);
    } catch (e) {
      if (_media == media) _media = null;
      unawaited(media.close().catchError((_) {}));
      if (generation == _machine.generation) {
        final (text, settings) = mediaErrorText(e);
        _endWith(CallNotice(text, error: true, openSettings: settings));
      }
      return false;
    }
    _mediaReady = true;
    _micOn = true;
    _camOn = media.hasVideo;
    _speakerOn = media.hasVideo; // video calls on the loudspeaker, voice calls on the earpiece
    unawaited(media.setSpeaker(_speakerOn).catchError((_) {}));
    if (fallback != null) _notify(CallNotice(fallback));
    notifyListeners();
    return true;
  }

  void _onLocalIce(int generation, String candidate, String? sdpMid, int? index) {
    final callId = _machine.callId;
    if (generation != _machine.generation || callId == null) return;
    if (phase != CallPhase.connecting && phase != CallPhase.active) return;
    _send(StompDest.rtcIce(callId), {'candidate': candidate, 'sdpMid': sdpMid, 'sdpMLineIndex': index});
  }

  void _onPeerState(int generation, PeerState state) {
    if (generation != _machine.generation) return;
    switch (state) {
      case PeerState.connected:
        if (_machine.markConnected(generation)) _sync();
      case PeerState.failed:
        _endWith(
          CallNotice(
            phase == CallPhase.active
                ? 'Bağlantı koptu.'
                : 'Bağlantı kurulamadı. Ağınız doğrudan bağlantıya izin vermiyor olabilir.',
            error: true,
          ),
        );
      case PeerState.connecting || PeerState.disconnected || PeerState.closed:
        break; // "disconnected" may recover; a dead peer ends in "failed" or HANGUP
    }
  }

  void _teardown() {
    _guard?.cancel();
    _guard = null;
    final media = _media;
    _media = null;
    _mediaReady = false;
    _remoteSet = false;
    _pendingIce.clear();
    _connectedAt = null;
    _micOn = true;
    _camOn = false;
    _speakerOn = false;
    if (media != null) unawaited(media.close().catchError((_) {}));
  }
}
