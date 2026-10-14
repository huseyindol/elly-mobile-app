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

  /// The microphone/camera were released (tracks stopped).
  bool tracksStopped = false;
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
    if (setRemoteError != null) throw setRemoteError!;
    return type == 'offer' ? 'v=0 answer' : null;
  }

  @override
  Future<void> addIce(String candidate, String? sdpMid, int? sdpMLineIndex) async => ops.add('ice:$candidate');

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

  void dispose() {
    _sub?.cancel();
    provider.reset();
  }
}
