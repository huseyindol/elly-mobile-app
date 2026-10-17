import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/call_provider.dart';
import '../services/call_machine.dart';
import '../widgets/app_drawer.dart' show avatarInitials;
import '../widgets/app_scaffold.dart' show AmbientBackground;
import '../widgets/info_note.dart';

/// Full-screen call UI (admin `IncomingCallModal` + `CallWindow`): incoming (reject / answer with voice or video),
/// outgoing (ringing, cancel), connecting/active (remote + own video, microphone, camera on/off and switch,
/// loudspeaker, hang up, duration). Pushed and removed by `AuthWrapper` as the call starts / ends; the back button
/// does not leave a call (it would leave the microphone on behind the app).
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
    fullscreenDialog: true,
    settings: const RouteSettings(name: 'call'),
    builder: (_) => const CallScreen(),
  );

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (context.read<CallProvider>().phase == CallPhase.incoming) HapticFeedback.vibrate();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<CallProvider>().connectedAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String _status(CallProvider call) => switch (call.phase) {
    CallPhase.incoming when call.answering => 'Bağlanıyor…',
    CallPhase.incoming => call.ringAll ? 'Gelen destek çağrısı' : 'Gelen çağrı',
    CallPhase.outgoing => call.ringing ? 'Çalıyor…' : 'Aranıyor…',
    CallPhase.connecting => 'Bağlanıyor…',
    CallPhase.active => 'Görüşmede',
    CallPhase.idle => 'Çağrı sona erdi',
  };

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final scheme = Theme.of(context).colorScheme;
    final media = call.media;
    final inCall = call.phase == CallPhase.connecting || call.phase == CallPhase.active;
    final showRemote = media != null && inCall && call.hasRemoteVideo;
    final showLocal = media != null && call.hasLocalVideo && call.camOn;
    final name = call.peerName.isNotEmpty
        ? call.peerName
        : (call.peerUserId != null ? 'Kullanıcı #${call.peerUserId}' : 'Bilinmeyen arayan');
    final status = _status(call);
    final since = call.connectedAt;
    final elapsed = since == null ? null : _clock(DateTime.now().difference(since));

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Phase changes (ringing → connecting → in call → …) are announced; the clock below is not.
        Semantics(
          liveRegion: true,
          child: Text(
            status,
            key: const ValueKey('call_status'),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.8), fontSize: 16),
          ),
        ),
        const SizedBox(height: 16),
        if (!showRemote) ...[
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: scheme.primary.withValues(alpha: 0.25),
              foregroundColor: AppColors.primaryLight,
              child: Text(avatarInitials(name), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          name,
          key: const ValueKey('call_peer'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (call.peerUserId != null)
          Text(
            'ID ${call.peerUserId}',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), fontFamily: 'monospace'),
          ),
        if (elapsed != null) ...[
          const SizedBox(height: 8),
          Semantics(
            label: 'Görüşme süresi $elapsed',
            excludeSemantics: true,
            child: Text(
              elapsed,
              key: const ValueKey('call_duration'),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 18),
            ),
          ),
        ],
      ],
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: '$status: $name',
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showRemote)
                Semantics(label: 'Karşı tarafın görüntüsü', image: true, child: media.remoteView())
              else
                const AmbientBackground(child: SizedBox.expand()),
              SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                        child: Column(
                          children: [
                            // Readable over the remote video too.
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: showRemote ? scheme.surface.withValues(alpha: 0.75) : null,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(padding: const EdgeInsets.all(12), child: info),
                            ),
                            if (call.phase == CallPhase.incoming && call.ringAll) ...[
                              const SizedBox(height: 16),
                              const InfoNote(
                                'Tenant sitesinden destek çağrısı: tüm çevrimiçi panel kullanıcılarında çalar, '
                                'ilk cevaplayan görüşmeyi alır.',
                              ),
                            ],
                            const Spacer(),
                            const SizedBox(height: 24),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: showRemote ? scheme.surface.withValues(alpha: 0.75) : null,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: _controls(call, scheme),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showLocal)
                PositionedDirectional(
                  top: MediaQuery.paddingOf(context).top + 16,
                  end: 16,
                  width: 104,
                  height: 148,
                  child: Semantics(
                    label: 'Kendi görüntünüz',
                    image: true,
                    child: ClipRRect(borderRadius: BorderRadius.circular(12), child: media.localView()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(CallProvider call, ColorScheme scheme) {
    final neutral = (scheme.surface, scheme.onSurface);
    final off = (scheme.errorContainer, scheme.onErrorContainer);
    final danger = (scheme.error, scheme.onError);
    final accept = (AppColors.success, scheme.surface);
    final ready = call.media != null;
    final buttons = switch (call.phase) {
      CallPhase.incoming => [
        _CallButton(
          key: const ValueKey('call_reject'),
          icon: Icons.call_end_rounded,
          label: 'Reddet',
          colors: danger,
          onPressed: call.end,
        ),
        _CallButton(
          key: const ValueKey('call_answer_audio'),
          icon: Icons.call_rounded,
          label: 'Sesli cevapla',
          colors: accept,
          onPressed: call.answering ? null : () => call.answer(video: false),
        ),
        _CallButton(
          key: const ValueKey('call_answer_video'),
          icon: Icons.videocam_rounded,
          label: 'Görüntülü cevapla',
          colors: accept,
          onPressed: call.answering ? null : () => call.answer(video: true),
        ),
      ],
      CallPhase.outgoing => [
        _CallButton(
          key: const ValueKey('call_cancel'),
          icon: Icons.call_end_rounded,
          label: 'İptal',
          colors: danger,
          onPressed: call.end,
        ),
      ],
      CallPhase.connecting || CallPhase.active => [
        _CallButton(
          key: const ValueKey('call_mic'),
          icon: call.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
          label: call.micOn ? 'Mikrofonu kapat' : 'Mikrofonu aç',
          colors: call.micOn ? neutral : off,
          onPressed: ready ? call.toggleMic : null,
        ),
        if (call.hasLocalVideo) ...[
          _CallButton(
            key: const ValueKey('call_camera'),
            icon: call.camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: call.camOn ? 'Kamerayı kapat' : 'Kamerayı aç',
            colors: call.camOn ? neutral : off,
            onPressed: ready ? call.toggleCamera : null,
          ),
          _CallButton(
            key: const ValueKey('call_switch_camera'),
            icon: Icons.cameraswitch_rounded,
            label: 'Kamerayı çevir',
            colors: neutral,
            onPressed: ready && call.camOn ? call.switchCamera : null,
          ),
        ],
        _CallButton(
          key: const ValueKey('call_speaker'),
          icon: call.speakerOn ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
          label: call.speakerOn ? 'Hoparlörü kapat' : 'Hoparlörü aç',
          colors: neutral,
          onPressed: ready ? call.toggleSpeaker : null,
        ),
        _CallButton(
          key: const ValueKey('call_hangup'),
          icon: Icons.call_end_rounded,
          label: 'Kapat',
          colors: danger,
          onPressed: call.end,
        ),
      ],
      CallPhase.idle => const <Widget>[],
    };
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 16, children: buttons);
  }
}

/// 64 dp round button with its label under it; one semantic node ("Mikrofonu kapat, düğme").
class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final (Color, Color) colors;
  final VoidCallback? onPressed;

  const _CallButton({super.key, required this.icon, required this.label, required this.colors, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final (background, foreground) = colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
                      child: Icon(icon, color: foreground, size: 30),
                    ),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
