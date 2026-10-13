/// Untrusted HTML (e-mail template preview) → a document that cannot run code or reach the network.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Preview Content-Security-Policy: nothing is fetched (no script, frame, plugin, stylesheet/font file or remote
/// image); inline styles and embedded `data:` images/fonts still render.
const previewCsp =
    "default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'";

// noscript: parsed here as raw text (scripting on) but as markup by the JavaScript-off WebView → its content
// would skip the attribute pass.
const _removedElements =
    'script, noscript, iframe, frame, frameset, object, embed, applet, portal, link, base, meta[http-equiv]';

const _urlAttributes = {
  'src', 'srcset', 'href', 'xlink:href', 'background', 'poster', 'action', 'formaction', 'data', 'ping', //
  'longdesc', 'cite', 'manifest', 'codebase', 'archive', 'lowsrc', 'dynsrc',
};

/// Defense in depth on top of the preview WebView's JavaScript being off and its navigations blocked
/// ([isPreviewNavigationAllowed]): scripts (and noscript), frames, plugins, `<link>`, `<base>` and `<meta http-equiv>` (refresh,
/// a second CSP) are removed; event handlers and URL attributes are dropped — links keep their look with
/// `href="#"`, only `data:image/` sources stay (so no DNS prefetch / link preview either); [previewCsp] and a
/// mobile viewport are the first things in `<head>`.
String safePreviewDocument(String html) {
  final document = html_parser.parse(html);
  for (final element in document.querySelectorAll(_removedElements)) {
    element.remove();
  }
  for (final element in document.querySelectorAll('*')) {
    for (final name in element.attributes.keys.toList()) {
      final attribute = '$name'.toLowerCase();
      final value = element.attributes[name]!.trim().toLowerCase();
      if (attribute.startsWith('on')) {
        element.attributes.remove(name);
      } else if (_urlAttributes.contains(attribute)) {
        if (attribute == 'src' && value.startsWith('data:image/')) continue;
        if (attribute == 'href' && const {'a', 'area'}.contains(element.localName)) {
          element.attributes[name] = '#';
        } else {
          element.attributes.remove(name);
        }
      }
    }
  }
  document.head!.nodes.insertAll(0, [
    Element.tag('meta')
      ..attributes['http-equiv'] = 'Content-Security-Policy'
      ..attributes['content'] = previewCsp,
    Element.tag('meta')
      ..attributes['name'] = 'viewport'
      ..attributes['content'] = 'width=device-width, initial-scale=1',
  ]);
  return document.outerHtml;
}

/// Only the preview's own initial load (`loadHtmlString` → about:blank) may navigate; links, form posts and
/// anything after the page finished loading are blocked.
bool isPreviewNavigationAllowed(String url, {required bool loaded}) => !loaded && url == 'about:blank';
