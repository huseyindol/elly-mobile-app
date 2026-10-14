import 'dart:async';
import 'dart:convert';

import 'package:elly_mobile_app/providers/call_provider.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'fake_realtime.dart';

/// Fake peer connection + local media: records every operation; the test drives ICE / state / remote callbacks.
class FakeCallMedia implements CallMedia {
  /// Error to throw from [open] for the requested `video` flag (null: success).
  Object? Function(bool video)? openError;

  /// Holds [open] until completed (permission prompt still on screen).
  Completer<void>? openGate;

  final List<String> ops = [];
  bool opened = false;
  bool videoOpen = false;
  bool connected = false;
  bool closed = false;

  /// Holds [connect] until completed (peer connection still being created).
  Completer<void>? connectGate;

  /// Holds [setRemote] until completed (remote description still being applied).
  Completer<void>? setRemoteGate;

  /// true: [addIce] of that candidate throws (the platform refused it).
  bool Function(String candidate)? addIceError;

  /// [close] releases everything and then throws this (the provider must shrug it off).
  Object? closeError;

  /// The microphone/camera were released (tracks stopped).
  bool tracksStopped = false;

  /// Resources that are held right now. Anything still true after a call is over is a leak: microphone/camera
  /// tracks running, a peer connection open, video renderers undisposed.
  bool tracksLive = false;
  bool pcLive = false;
  bool renderersLive = false;

  /// Names of the resources still held (empty: everything was released).
  List<String> get leaks => [if (tracksLive) 'tracks', if (pcLive) 'peerConnection', if (renderersLive) 'renderers'];

  /// Remote ICE candidates / descriptions applied to this media, in order.
  List<String> get applied => [
    for (final o in ops)
      if (o.startsWith('ice:') || o.startsWith('remote:')) o,
  ];
  bool remoteVideo = false;
  Object? setRemoteError;
  List<Map<String, Object>>? iceServers;
  void Function(String candidate, String? sdpMid, int? sdpMLineIndex)? onIce;
  void Function(PeerState state)? onState;
  void Function()? onRemote;
  bool? mic;
  bool? camera;
  bool? speaker;
  int switches = 0;

  @override
  Future<void> open({required bool video}) async {
    ops.add('open:$video');
    if (openGate != null) await openGate!.future;
    final error = openError?.call(video);
    if (error != null) throw error;
    if (closed) {
      tracksStopped = true; // got the devices after close → released at once
      throw const CallMediaException(CallMediaError.other);
    }
    opened = true;
    tracksLive = true;
    videoOpen = video;
  }

  @override
  bool get hasVideo => opened && videoOpen && !closed;

  @override
  bool get hasRemoteVideo => remoteVideo;

  @override
  Future<void> connect({
    required List<Map<String, Object>> iceServers,
    required void Function(String candidate, String? sdpMid, int? sdpMLineIndex) onIce,
    required void Function(PeerState state) onState,
    required void Function() onRemote,
  }) async {
    ops.add('connect');
    if (connectGate != null) await connectGate!.future;
    if (closed) {
      // like the real media: closed while the connection was being created → nothing is left behind
      throw const CallMediaException(CallMediaError.other);
    }
    pcLive = true;
    renderersLive = true;
    this.iceServers = iceServers;
    this.onIce = onIce;
    this.onState = onState;
    this.onRemote = onRemote;
    connected = true;
  }

  @override
  Future<String> createOffer() async {
    ops.add('offer');
    return 'v=0 offer';
  }

  @override
  Future<String?> setRemote(String type, String sdp) async {
    ops.add('remote:$type');
    if (setRemoteGate != null) await setRemoteGate!.future;
    if (setRemoteError != null) throw setRemoteError!;
    return type == 'offer' ? 'v=0 answer' : null;
  }

  @override
  Future<void> addIce(String candidate, String? sdpMid, int? sdpMLineIndex) async {
    if (addIceError != null && addIceError!(candidate)) throw StateError('addCandidate failed: $candidate');
    ops.add('ice:$candidate');
  }

  @override
  void setMic(bool on) => mic = on;

  @override
  void setCamera(bool on) => camera = on;

  @override
  Future<void> switchCamera() async => switches++;

  @override
  Future<void> setSpeaker(bool on) async => speaker = on;

  @override
  Widget localView() => const SizedBox(key: ValueKey('fake_local_video'));

  @override
  Widget remoteView() => const SizedBox(key: ValueKey('fake_remote_video'));

  @override
  Future<void> close() async {
    ops.add('close');
    closed = true;
    if (opened) tracksStopped = true;
    tracksLive = false;
    pcLive = false;
    renderersLive = false;
    if (closeError != null) throw closeError!;
  }
}

/// [CallProvider] over a [FakeRealtime] and [FakeCallMedia]s (one per call).
class FakeCalls {
  final FakeRealtime live;

  /// Configures each new media before use.
  void Function(FakeCallMedia media)? setup;

  final Duration ringGuard;
  final Duration connectGuard;

  FakeCalls(this.live, {this.ringGuard = const Duration(seconds: 35), this.connectGuard = const Duration(seconds: 30)});

  late final CallProvider provider = CallProvider(
    realtime: live.realtime,
    mediaFactory: () {
      final m = FakeCallMedia();
      setup?.call(m);
      medias.add(m);
      return m;
    },
    ringGuard: ringGuard,
    connectGuard: connectGuard,
  );

  final List<FakeCallMedia> medias = [];
  FakeCallMedia get media => medias.last;

  final List<CallNotice> notices = [];
  StreamSubscription<CallNotice>? _sub;

  /// Records notices from now on.
  void listen() => _sub ??= provider.notices.listen(notices.add);

  /// `/app/rtc/...` frames sent on the current link: `[destination, decoded body or null]`.
  List<List<Object?>> get sent => [
    for (final (d, b) in live.link.sent)
      if (d.startsWith('/app/rtc')) [d, b.isEmpty ? null : jsonDecode(b)],
  ];

  List<String> get sentTo => [for (final s in sent) s[0] as String];

  void signal(int userId, Map<String, Object?> body) => live.push('/topic/user/$userId/rtc', body);

  List<SingleChildWidget> get providers => [ChangeNotifierProvider<CallProvider>.value(value: provider)];

  /// Every resource of every media this provider ever opened, still held (empty: nothing leaked).
  List<String> get leaks => [
    for (var i = 0; i < medias.length; i++)
      for (final l in medias[i].leaks) 'media#$i:$l',
  ];

  void dispose() {
    _sub?.cancel();
    provider.reset();
  }
}
