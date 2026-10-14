import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/realtime_service.dart';

/// "Bağlantı yok" strip while the live connection is down (admin: "Bağlantı kesildi. Yeniden bağlanılıyor...").
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final realtime = context.watch<RealtimeService>();
    if (realtime.connected) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('chat_connection_banner'),
        color: scheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                realtime.connectionSeq == 0 ? 'Canlı bağlantı kuruluyor…' : 'Bağlantı kesildi. Yeniden bağlanılıyor…',
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
