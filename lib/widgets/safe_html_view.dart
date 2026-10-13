import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/safe_html.dart';

/// Renders untrusted HTML (e-mail preview) like the admin's `<iframe sandbox="">`: JavaScript off, every
/// navigation after the initial load blocked, and [safePreviewDocument] (CSP: no network request at all).
/// Key it by [html] to render new content.
class SafeHtmlView extends StatefulWidget {
  final String html;
  final String semanticsLabel;

  const SafeHtmlView({super.key, required this.html, this.semanticsLabel = 'E-posta önizlemesi'});

  @override
  State<SafeHtmlView> createState() => _SafeHtmlViewState();
}

class _SafeHtmlViewState extends State<SafeHtmlView> {
  late final WebViewController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white) // e-mails assume a white page
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => isPreviewNavigationAllowed(request.url, loaded: _loaded)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) => _loaded = true,
        ),
      )
      ..loadHtmlString(safePreviewDocument(widget.html));
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticsLabel,
    child: WebViewWidget(controller: _controller),
  );
}
