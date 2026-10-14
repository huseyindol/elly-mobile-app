import 'package:flutter/widgets.dart';

/// Peer connection state, reduced to what the call needs.
enum PeerState { connecting, connected, disconnected, failed, closed }

enum CallMediaError { denied, notFound, inUse, other }

/// Microphone/camera could not be opened.
class CallMediaException implements Exception {
  final CallMediaError kind;
  const CallMediaException(this.kind);

  /// flutter_webrtc reports getUserMedia failures as text carrying the DOMException name (Android
  /// "DOMException, NotAllowedError", iOS "NotAllowedError").
  factory CallMediaException.from(Object error) {
    final text = '$error';
    if (text.contains('NotAllowedError') || text.contains('ermission')) {
      return const CallMediaException(CallMediaError.denied);
    }
    if (text.contains('NotFoundError')) return const CallMediaException(CallMediaError.notFound);
    if (text.contains('NotReadableError')) return const CallMediaException(CallMediaError.inUse);
    return const CallMediaException(CallMediaError.other);
  }

  @override
  String toString() => 'CallMediaException($kind)';
}

/// User text for a media failure; `settings`: the permission was refused, offer the app's system settings.
(String, bool) mediaErrorText(Object error) {
  final kind = error is CallMediaException ? error.kind : CallMediaError.other;
  return switch (kind) {
    CallMediaError.denied => ('Mikrofon/kamera izni verilmedi. İzni cihaz ayarlarından açabilirsiniz.', true),
    CallMediaError.notFound => ('Mikrofon veya kamera bulunamadı.', false),
    CallMediaError.inUse => ('Mikrofon/kamera başka bir uygulama tarafından kullanılıyor.', false),
    CallMediaError.other => ('Mikrofon/kamera açılamadı.', false),
  };
}

/// One call's local media + peer connection. Production: `WebrtcCallMedia` (flutter_webrtc); tests: a fake.
/// [close] must be safe to call at any time, also while [open] is still pending (the stream it then gets is
/// stopped at once) — the microphone and camera must never stay on after a call.
abstract class CallMedia {
  /// Microphone (+ camera). Throws [CallMediaException]. Asks the OS permission on first use.
  Future<void> open({required bool video});

  /// A local video track exists (the camera opened).
  bool get hasVideo;

  /// The peer sends video.
  bool get hasRemoteVideo;

  /// Creates the peer connection with the opened tracks.
  Future<void> connect({
    required List<Map<String, Object>> iceServers,
    required void Function(String candidate, String? sdpMid, int? sdpMLineIndex) onIce,
    required void Function(PeerState state) onState,
    required void Function() onRemote,
  });

  /// Local offer (set as the local description).
  Future<String> createOffer();

  /// Applies the peer's description; for an offer returns the local answer (set as the local description).
  Future<String?> setRemote(String type, String sdp);

  Future<void> addIce(String candidate, String? sdpMid, int? sdpMLineIndex);

  void setMic(bool on);
  void setCamera(bool on);
  Future<void> switchCamera();
  Future<void> setSpeaker(bool on);

  Widget localView();
  Widget remoteView();

  /// Stops every track, closes the peer connection, releases the renderers. Idempotent.
  Future<void> close();
}
