import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/chat_format.dart';

/// Untrusted chat text as plain text (never HTML/markdown): entities decoded, control characters dropped, bidi
/// controls visible ([safeChatText]); long text clipped with "Tümünü göster"; only http(s) URLs are links and
/// [onOpenLink] asks before leaving the app.
class ChatMessageText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color linkColor;
  final void Function(Uri uri) onOpenLink;

  const ChatMessageText(
    this.text, {
    super.key,
    this.style,
    this.linkColor = AppColors.primaryLight,
    required this.onOpenLink,
  });

  @override
  State<ChatMessageText> createState() => _ChatMessageTextState();
}

class _ChatMessageTextState extends State<ChatMessageText> {
  bool _expanded = false;
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _recognizer(Uri uri) {
    final r = TapGestureRecognizer()..onTap = () => widget.onOpenLink(uri);
    _recognizers.add(r);
    return r;
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final full = safeChatText(widget.text);
    final (preview, clipped) = clipChatText(full);
    final shown = _expanded ? full : preview;
    final linkStyle = TextStyle(color: widget.linkColor, decoration: TextDecoration.underline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: widget.style,
            children: [
              for (final (part, uri) in linkSegments(shown))
                if (uri == null)
                  TextSpan(text: part)
                else
                  TextSpan(text: part, style: linkStyle, recognizer: _recognizer(uri)),
            ],
          ),
        ),
        if (clipped)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 36)),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Daha az göster' : 'Tümünü göster'),
          ),
      ],
    );
  }
}
