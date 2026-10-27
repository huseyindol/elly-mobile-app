import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_media.dart';

/// [CallMedia] on flutter_webrtc (admin `useWebRTCCall`: getUserMedia → RTCPeerConnection, unified plan). Not
/// unit-tested (platform channels); the call logic around it is, through a fake.
class WebrtcCallMedia implements CallMedia {
  MediaStream? _local;
  MediaStream? _remote;
  RTCPeerConnection? _pc;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _renderers = false;
  bool _closed = false;
  bool _front = true;

  @override
  Future<void> open({required bool video}) async {
    final MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video ? {'facingMode': 'user'} : false,
      });
    } catch (e) {
      throw CallMediaException.from(e);
    }
    if (_closed) {
      // The call ended while the permission prompt / camera start was pending.
      await _stop(stream);
      throw const CallMediaException(CallMediaError.other);
    }
    for (final t in stream.getAudioTracks()) {
      t.enabled = true;
    }
    _local = stream;
  }

  @override
  bool get hasVideo => _local?.getVideoTracks().isNotEmpty ?? false;

  @override
  bool get hasRemoteVideo => _remote?.getVideoTracks().isNotEmpty ?? false;

  @override
  Future<void> connect({
    required List<Map<String, Object>> iceServers,
    required void Function(String candidate, String? sdpMid, int? sdpMLineIndex) onIce,
    required void Function(PeerState state) onState,
    required void Function() onRemote,
  }) async {
    final local = _local;
    if (_closed || local == null) throw const CallMediaException(CallMediaError.other);
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _renderers = true;
    _localRenderer.srcObject = local;
    final pc = await createPeerConnection({'iceServers': iceServers, 'sdpSemantics': 'unified-plan'});
    if (_closed) {
      await pc.close();
      await _disposeRenderers();
      throw const CallMediaException(CallMediaError.other);
    }
    _pc = pc;
    pc.onIceCandidate = (c) {
      final candidate = c.candidate;
      if (candidate != null && candidate.isNotEmpty) onIce(candidate, c.sdpMid, c.sdpMLineIndex);
    };
    pc.onIceConnectionState = (s) => onState(switch (s) {
      RTCIceConnectionState.RTCIceConnectionStateConnected ||
      RTCIceConnectionState.RTCIceConnectionStateCompleted => PeerState.connected,
      RTCIceConnectionState.RTCIceConnectionStateFailed => PeerState.failed,
      RTCIceConnectionState.RTCIceConnectionStateDisconnected => PeerState.disconnected,
      RTCIceConnectionState.RTCIceConnectionStateClosed => PeerState.closed,
      _ => PeerState.connecting,
    });
    pc.onTrack = (e) {
      if (_closed) return;
      e.track.enabled = true;
      if (e.streams.isNotEmpty) {
        _remote = e.streams.first;
        for (final t in _remote!.getAudioTracks()) {
          t.enabled = true;
        }
        _remoteRenderer.srcObject = _remote;
      }
      onRemote();
    };
    for (final track in local.getTracks()) {
      await pc.addTrack(track, local);
    }
  }

  @override
  Future<String> createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    return offer.sdp!;
  }

  @override
  Future<String?> setRemote(String type, String sdp) async {
    final pc = _pc!;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    if (type != 'offer') return null;
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer.sdp;
  }

  @override
  Future<void> addIce(String candidate, String? sdpMid, int? sdpMLineIndex) =>
      _pc!.addCandidate(RTCIceCandidate(candidate, sdpMid, sdpMLineIndex));

  @override
  void setMic(bool on) {
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  @override
  void setCamera(bool on) {
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  @override
  Future<void> switchCamera() async {
    final track = _local?.getVideoTracks().firstOrNull;
    if (track == null) return;
    _front = await Helper.switchCamera(track);
  }

  @override
  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Widget localView() =>
      RTCVideoView(_localRenderer, mirror: _front, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);

  @override
  Widget remoteView() => RTCVideoView(_remoteRenderer);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final pc = _pc;
    _pc = null;
    if (pc != null) {
      pc
        ..onIceCandidate = null
        ..onIceConnectionState = null
        ..onTrack = null;
    }
    final local = _local;
    _local = null;
    _remote = null;
    // Tracks first: the camera/microphone indicator must go off even if closing the connection throws.
    try {
      if (local != null) await _stop(local);
    } finally {
      try {
        await pc?.close();
      } catch (_) {}
      await _disposeRenderers();
    }
  }

  Future<void> _disposeRenderers() async {
    if (!_renderers) return;
    _renderers = false;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  static Future<void> _stop(MediaStream stream) async {
    for (final t in stream.getTracks()) {
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }
}
