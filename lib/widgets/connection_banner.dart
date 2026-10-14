import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/realtime_service.dart';

/// Strip while the live connection is down (admin: "Bağlantı kesildi. Yeniden bağlanılıyor..."). Sending still works
/// (REST), so the text says so. Short drops (≤ [graceDelay], e.g. returning to the foreground) show nothing; the strip
/// starts neutral and turns to the error color after [errorDelay]. "Şimdi dene" skips the backoff wait.
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({super.key});

  static const graceDelay = Duration(seconds: 2);
  static const errorDelay = Duration(seconds: 10);
  static const message = 'Canlı güncellemeler duraksadı; mesaj gönderebilirsiniz. Yeniden bağlanılıyor…';

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  RealtimeService? _realtime;
  Timer? _graceTimer;
  Timer? _errorTimer;
  bool _visible = false;
  bool _error = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final realtime = context.read<RealtimeService>();
    if (realtime == _realtime) return;
    _realtime?.removeListener(_update);
    _realtime = realtime..addListener(_update);
    _update();
  }

  @override
  void dispose() {
    _realtime?.removeListener(_update);
    _graceTimer?.cancel();
    _errorTimer?.cancel();
    super.dispose();
  }

  void _update() {
    if (_realtime!.connected) {
      _graceTimer?.cancel();
      _errorTimer?.cancel();
      _graceTimer = _errorTimer = null;
      if (_visible || _error) setState(() => _visible = _error = false);
      return;
    }
    _graceTimer ??= Timer(ConnectionBanner.graceDelay, () {
      if (mounted) setState(() => _visible = true);
    });
    _errorTimer ??= Timer(ConnectionBanner.errorDelay, () {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final fg = _error ? scheme.onErrorContainer : scheme.onSurface;
    return Semantics(
      liveRegion: true, // announced once when it appears (never for short drops)
      child: Container(
        key: const ValueKey('chat_connection_banner'),
        color: _error ? scheme.errorContainer : scheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ConnectionBanner.message, style: TextStyle(color: fg, fontSize: 13)),
            ),
            TextButton(
              key: const ValueKey('chat_connection_retry'),
              style: TextButton.styleFrom(foregroundColor: fg),
              onPressed: _realtime!.retryNow,
              child: const Text('Şimdi dene'),
            ),
          ],
        ),
      ),
    );
  }
}
