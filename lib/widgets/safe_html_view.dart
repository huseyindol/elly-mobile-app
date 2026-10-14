import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/safe_html.dart';
import 'state_views.dart';

/// Renders untrusted HTML (e-mail preview) like the admin's `<iframe sandbox="">`: JavaScript off, every
/// navigation after the initial load blocked, and [safePreviewDocument] (CSP: no network request at all), which
/// runs in a background isolate killed after 5 s (parsing hostile markup can be slow). Key it by [html] to render new content.
class SafeHtmlView extends StatefulWidget {
  final String html;
  final String semanticsLabel;

  const SafeHtmlView({super.key, required this.html, this.semanticsLabel = 'E-posta önizlemesi'});

  @override
  State<SafeHtmlView> createState() => _SafeHtmlViewState();
}

class _SafeHtmlViewState extends State<SafeHtmlView> {
  WebViewController? _controller;
  bool _loaded = false;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final document = await sanitizePreviewInBackground(widget.html);
    if (!mounted) return;
    if (document == null) return setState(() => _timedOut = true);
    setState(
      () => _controller = WebViewController()
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
        ..loadHtmlString(document),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_timedOut) {
      return const EmptyView(
        icon: Icons.warning_amber_rounded,
        message: 'Önizleme için çok karmaşık (hazırlama süresi aşıldı).',
      );
    }
    if (controller == null) return const LoadingView(label: 'Önizleme hazırlanıyor');
    return Semantics(
      label: widget.semanticsLabel,
      child: WebViewWidget(controller: controller),
    );
  }
}
