import 'package:flutter/material.dart';

/// "Ara" button with a voice / video choice (admin member list: "Görüntülü ara"). [onCall] gets `video`.
class CallMenuButton extends StatelessWidget {
  final String tooltip;
  final void Function(bool video) onCall;

  const CallMenuButton({super.key, required this.tooltip, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: tooltip,
      icon: const Icon(Icons.call_outlined),
      onSelected: onCall,
      itemBuilder: (_) => const [
        PopupMenuItem(
          key: ValueKey('call_menu_audio'),
          value: false,
          child: ListTile(leading: Icon(Icons.call_rounded), title: Text('Sesli ara')),
        ),
        PopupMenuItem(
          key: ValueKey('call_menu_video'),
          value: true,
          child: ListTile(leading: Icon(Icons.videocam_rounded), title: Text('Görüntülü ara')),
        ),
      ],
    );
  }
}
