/// Untrusted HTML (e-mail template preview) → a document that cannot run code or reach the network.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Preview Content-Security-Policy: nothing is fetched (no script, frame, plugin, stylesheet/font file or remote
/// image); inline styles and embedded `data:` images/fonts still render.
const previewCsp =
    "default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'";

/// Input limits: parsing + serialising is quadratic in nesting depth (10k nested tags ≈ 12 s), so bigger or deeper
/// input is not previewed at all. Real e-mail templates stay far below both.
const maxPreviewBytes = 1024 * 1024;
const maxPreviewDepth = 2000; // ≈0.5 s per pass, in a background isolate

// noscript: parsed here as raw text (scripting on) but as markup by the JavaScript-off WebView → its content would
// skip the attribute pass. svg/math: the html package parses <style> inside foreign content differently from
// browsers (mutation XSS), and e-mail clients hardly support them. SVG animation elements can write any attribute
// at runtime (href=javascript:, on*) — listed too in case they appear outside <svg>.
const _removedElements = {
  'script', 'noscript', 'iframe', 'frame', 'frameset', 'object', 'embed', 'applet', 'portal', 'link', 'base', //
  'svg', 'math', 'animate', 'set', 'animatetransform', 'animatemotion', 'animatecolor',
};

const _urlAttributes = {
  'src', 'srcset', 'href', 'xlink:href', 'background', 'poster', 'action', 'formaction', 'data', 'ping', //
  'longdesc', 'cite', 'manifest', 'codebase', 'archive', 'lowsrc', 'dynsrc', 'srcdoc',
};

/// Why [html] is not previewed (too big / too deeply nested), or null.
String? previewLimitError(String html) {
  if (html.length > maxPreviewBytes) return 'Önizleme için çok büyük (en fazla 1 MB).';
  if (_nestingDepth(html) > maxPreviewDepth) return 'Önizleme için çok karmaşık (iç içe öğe sayısı çok fazla).';
  return null;
}

// Elements whose end tag is optional / implied (the parser closes them on the next sibling) and void elements
// don't nest, so they are not counted.
const _flatElements = {
  'p', 'li', 'dt', 'dd', 'tr', 'td', 'th', 'option', 'optgroup', 'thead', 'tbody', 'tfoot', 'colgroup', 'rb', //
  'rt', 'rp', 'html', 'head', 'body', 'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'source', 'track', 'wbr',
};
final _tag = RegExp(r'<(/?)([a-zA-Z][^\s/>]*)[^>]*?(/?)>');

/// Cheap upper estimate of the element nesting depth, without parsing.
int _nestingDepth(String html) {
  var depth = 0;
  var max = 0;
  for (final m in _tag.allMatches(html)) {
    if (_flatElements.contains(m[2]!.toLowerCase()) || m[3] == '/') continue;
    depth = m[1] == '/' ? (depth > 0 ? depth - 1 : 0) : depth + 1;
    if (depth > max) max = depth;
  }
  return max;
}

/// Document shown instead of a preview that can't be made safe / is over the limits.
String previewErrorDocument(String message) =>
    '<!DOCTYPE html><html><head><meta http-equiv="Content-Security-Policy" content="$previewCsp"></head>'
    '<body><p>${message.replaceAll('&', '&amp;').replaceAll('<', '&lt;')}</p></body></html>';

/// Defense in depth on top of the preview WebView's JavaScript being off and its navigations blocked
/// ([isPreviewNavigationAllowed]):
/// - over [maxPreviewBytes] / [maxPreviewDepth] → [previewErrorDocument];
/// - scripts (and noscript), frames, plugins, svg/math, SVG animation, `<link>`, `<base>` and `<meta http-equiv>`
///   (refresh, a second CSP) are removed;
/// - event handlers and URL attributes are dropped — links keep their look with `href="#"`, only `data:image/`
///   sources stay (so no DNS prefetch / link preview either);
/// - CSS (`style` attributes and `<style>`): `@import`, non-`data:` `url()`, `expression()`, `behavior`,
///   `-moz-binding` are neutralised (after decoding CSS escapes and comments);
/// - [previewCsp] and a mobile viewport are the first things in `<head>`.
/// The result is parsed and sanitised again until it no longer changes (a parser differential could otherwise
/// turn sanitised markup into live markup); no fixed point in a few rounds → [previewErrorDocument].
/// Run it off the UI isolate (`compute`) — see SafeHtmlView.
String safePreviewDocument(String html) {
  final limit = previewLimitError(html);
  if (limit != null) return previewErrorDocument(limit);
  var current = _sanitizeOnce(html);
  for (var round = 0; round < 3; round++) {
    final next = _sanitizeOnce(current);
    if (next == current) return current;
    current = next;
  }
  return previewErrorDocument('Önizleme güvenli hâle getirilemedi.');
}

String _sanitizeOnce(String html) {
  final document = html_parser.parse(html);
  for (final element in document.querySelectorAll('*').toList()) {
    final name = element.localName!.toLowerCase();
    final viewport = name == 'meta' && '${element.attributes['name']}'.toLowerCase() == 'viewport';
    if (_removedElements.contains(name) ||
        (name == 'meta' && element.attributes.containsKey('http-equiv')) ||
        viewport) {
      element.remove();
    }
  }
  for (final element in document.querySelectorAll('*')) {
    if (element.localName == 'style') element.text = cleanCss(element.text);
    for (final name in element.attributes.keys.toList()) {
      final attribute = '$name'.toLowerCase();
      final value = element.attributes[name]!.trim().toLowerCase();
      if (attribute.startsWith('on')) {
        element.attributes.remove(name);
      } else if (attribute == 'style') {
        element.attributes[name] = cleanCss(element.attributes[name]!);
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

final _cssEscape = RegExp(r'\\([0-9a-fA-F]{1,6})\s?|\\(.)', dotAll: true);
final _cssComment = RegExp(r'/\*[\s\S]*?(\*/|$)');
final _cssImport = RegExp(r'@import[^;]*;?', caseSensitive: false);
final _cssRemoteUrl = RegExp(
  r'''url\(\s*(?!['"]?\s*data:image/)(?:"[^"]*"|'[^']*'|[^)'"]*)\s*\)?''',
  caseSensitive: false,
);
final _cssActive = RegExp(r'expression\s*\(|behavior\s*:|-moz-binding\s*:', caseSensitive: false);

/// CSS without anything that could load or run something: escapes and comments decoded/removed first, then
/// `@import` rules dropped, `url()` other than `data:image/` → `none`, `expression(`/`behavior:`/`-moz-binding:`
/// disarmed. Plain styling passes through unchanged.
String cleanCss(String css) {
  if (!css.contains(RegExp(r'[\\/@]|url|expression|behavior|binding', caseSensitive: false))) return css;
  final decoded = css
      .replaceAllMapped(_cssEscape, (m) {
        if (m[1] == null) return m[2]!;
        final code = int.parse(m[1]!, radix: 16);
        return code == 0 || code > 0x10FFFF ? '\uFFFD' : String.fromCharCode(code);
      })
      .replaceAll(_cssComment, '');
  return decoded
      .replaceAll(_cssImport, '')
      .replaceAll(_cssRemoteUrl, 'none')
      .replaceAllMapped(_cssActive, (m) => 'x-${m[0]!.replaceAll(RegExp(r'[(:]'), '')}-blocked:');
}

/// Only the preview's own initial load (`loadHtmlString` → about:blank) may navigate; links, form posts and
/// anything after the page finished loading are blocked.
bool isPreviewNavigationAllowed(String url, {required bool loaded}) => !loaded && url == 'about:blank';
