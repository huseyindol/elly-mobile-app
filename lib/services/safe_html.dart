/// Untrusted HTML (e-mail template preview) → a document that cannot run code or reach the network.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Preview Content-Security-Policy: nothing is fetched (no script, frame, plugin, stylesheet/font file or remote
/// image); inline styles and embedded `data:` images/fonts still render.
const previewCsp =
    "default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'";

/// Input limits: parsing + serialising is quadratic in nesting depth (10k nested tags ≈ 12 s), so bigger, deeper
/// or tag-heavier input is not previewed at all. Real e-mail templates stay far below both.
const maxPreviewBytes = 1024 * 1024;
const maxPreviewDepth = 2000; // ≈0.5 s per pass, in a background isolate
const maxPreviewTags = 10000; // flat 10k tags ≈ 0.5 s per pass; deep 10k would be ≈ 12 s

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

/// Why [html] is not previewed (too big / too many tags / too deeply nested), or null. Cheap: no DOM is built.
String? previewLimitError(String html) {
  if (html.length > maxPreviewBytes) return 'Önizleme için çok büyük (en fazla 1 MB).';
  // Independent of the estimator below: every element the parser creates comes from a `<letter` start tag
  // (plus a bounded number of implied ones), so this caps the parser's work whatever the estimator misses.
  if (_startTag.allMatches(html).length > maxPreviewTags ||
      estimatedNestingDepth(html, stopAbove: maxPreviewDepth) > maxPreviewDepth) {
    return 'Önizleme için çok karmaşık (öğe sayısı ya da iç içelik çok fazla).';
  }
  return null;
}

final _startTag = RegExp('<[a-zA-Z]');
final _commentEnd = RegExp('--!?>');

const _voidElements = {
  'area', 'base', 'basefont', 'bgsound', 'br', 'col', 'embed', 'frame', 'hr', 'image', 'img', 'input', //
  'keygen', 'link', 'meta', 'param', 'source', 'track', 'wbr',
};

/// Content is text up to `</name` (html package: noscript too, it parses with scripting on).
const _rawTextElements = {
  'script',
  'style',
  'textarea',
  'title',
  'xmp',
  'iframe',
  'noembed',
  'noframes',
  'noscript',
  'plaintext',
};

/// HTML "special" elements (+ MathML/SVG integration points): an end tag walking the stack stops at them and is
/// ignored (`<span><div></span>` keeps both open).
const _specialElements = {
  'address', 'applet', 'area', 'article', 'aside', 'base', 'basefont', 'bgsound', 'blockquote', 'body', 'br', //
  'button', 'caption', 'center', 'col', 'colgroup', 'dd', 'details', 'dir', 'div', 'dl', 'dt', 'embed',
  'fieldset', 'figcaption', 'figure', 'footer', 'form', 'frame', 'frameset', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'head', 'header', 'hgroup', 'hr', 'html', 'iframe', 'img', 'input', 'keygen', 'li', 'link', 'listing', 'main',
  'marquee', 'menu', 'meta', 'nav', 'noembed', 'noframes', 'noscript', 'object', 'ol', 'p', 'param', 'plaintext',
  'pre', 'script', 'search', 'section', 'select', 'source', 'style', 'summary', 'table', 'tbody', 'td',
  'template', 'textarea', 'tfoot', 'th', 'thead', 'title', 'tr', 'track', 'ul', 'wbr', 'xmp', 'mi', 'mo', 'mn',
  'ms', 'mtext', 'annotation-xml', 'foreignobject', 'desc',
};

/// Start tags that close an open `<p>` in button scope.
const _closesP = {
  'address', 'article', 'aside', 'blockquote', 'center', 'details', 'dialog', 'dir', 'div', 'dl', 'fieldset', //
  'figcaption', 'figure', 'footer', 'header', 'hgroup', 'main', 'menu', 'nav', 'ol', 'p', 'search', 'section',
  'summary', 'ul', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'listing', 'form', 'table', 'hr', 'xmp', 'dd', 'dt',
  'li',
};
const _buttonScope = {
  'applet', 'caption', 'html', 'table', 'td', 'th', 'marquee', 'object', 'template', 'button', 'mi', 'mo', 'mn', //
  'ms', 'mtext', 'annotation-xml', 'foreignobject', 'desc', 'title', 'svg', 'math',
};

/// Start tags that make the parser leave SVG/MathML content (pop to HTML) — `font` only with color/face/size.
const _breakoutElements = {
  'b', 'big', 'blockquote', 'body', 'br', 'center', 'code', 'dd', 'div', 'dl', 'dt', 'em', 'embed', 'h1', 'h2', //
  'h3', 'h4', 'h5', 'h6', 'head', 'hr', 'i', 'img', 'li', 'listing', 'menu', 'meta', 'nobr', 'ol', 'p', 'pre',
  'ruby', 's', 'small', 'span', 'strong', 'strike', 'sub', 'sup', 'table', 'tt', 'u', 'ul', 'var',
};

const _tableParts = {'caption', 'col', 'colgroup', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr'};

/// Foreign elements whose children are parsed as HTML again.
const _integrationPoints = {'foreignobject', 'desc', 'title', 'mi', 'mo', 'mn', 'ms', 'mtext', 'annotation-xml'};

bool _isAsciiLetter(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
bool _isSpace(int c) => c == 32 || c == 9 || c == 10 || c == 12 || c == 13;

/// Estimate of the element nesting depth the html package's parser builds for [html], without building it. It
/// tokenises tags like the WHATWG tokenizer (comments incl. `<!-->`, bogus comments, quoted attributes, raw text
/// up to its end tag, `/>` ignored on HTML elements) and keeps a stack of open names: end tags only pop to a
/// matching open element and stop at "special" ones (unmatched / blocked end tags never lower the depth),
/// implied end tags (`p`, `li`, `td`, `tr`, `option`) are applied only where the parser surely applies them.
/// Where unsure it keeps elements open, so it errs high. Stops counting above [stopAbove].
int estimatedNestingDepth(String html, {int stopAbove = 1 << 30}) {
  final stack = <String>[];
  final foreignStack = <bool>[]; // element is SVG/MathML (foreign content rules: `/>` closes, no raw text…)
  var max = 0;
  final n = html.length;
  var i = 0;

  void push(String name, bool foreign) {
    stack.add(name);
    foreignStack.add(foreign);
    if (stack.length > max) max = stack.length;
  }

  void popTo(int index) {
    stack.length = index;
    foreignStack.length = index;
  }

  // Like the parser's "adjusted current node": inside SVG/MathML unless at an integration point.
  bool inForeign() => stack.isNotEmpty && foreignStack.last && !_integrationPoints.contains(stack.last);

  /// Index of [names] walking down from the top, stopping (→ -1) at [stopAt] elements.
  int find(bool Function(String) match, bool Function(String) stopAt) {
    for (var k = stack.length - 1; k >= 0; k--) {
      if (match(stack[k])) return k;
      if (stopAt(stack[k])) return -1;
    }
    return -1;
  }

  int skipTo(String needle, int from) {
    final at = html.indexOf(needle, from);
    return at < 0 ? n : at + needle.length;
  }

  while (i < n && max <= stopAbove) {
    final lt = html.indexOf('<', i);
    if (lt < 0 || lt + 1 >= n) break;
    final c = html.codeUnitAt(lt + 1);
    if (c == 0x21 /* ! */ ) {
      if (html.startsWith('<!--', lt)) {
        if (html.startsWith('<!-->', lt)) {
          i = lt + 5;
        } else if (html.startsWith('<!--->', lt)) {
          i = lt + 6;
        } else {
          final end = _commentEnd.allMatches(html, lt + 4).firstOrNull;
          i = end == null ? n : end.end;
        }
      } else if (inForeign() && html.startsWith('<![CDATA[', lt)) {
        i = skipTo(']]>', lt + 9);
      } else {
        i = skipTo('>', lt + 2); // doctype / bogus comment
      }
      continue;
    }
    if (c == 0x3F /* ? */ ) {
      i = skipTo('>', lt + 2);
      continue;
    }
    final closing = c == 0x2F /* / */;
    final nameStart = closing ? lt + 2 : lt + 1;
    if (nameStart >= n || !_isAsciiLetter(html.codeUnitAt(nameStart))) {
      // `</>` is dropped, `</9…` is a bogus comment, `<9` is text.
      i = closing ? skipTo('>', nameStart) : lt + 1;
      continue;
    }
    // Tag name, then attributes (quoted values only right after `=`); EOF inside a tag drops it.
    var j = nameStart;
    while (j < n) {
      final ch = html.codeUnitAt(j);
      if (_isSpace(ch) || ch == 0x2F || ch == 0x3E) break;
      j++;
    }
    final name = html.substring(nameStart, j).toLowerCase();
    var selfClosing = false;
    var complete = false;
    var fontBreakout = false; // <font color|face|size> leaves foreign content
    while (j < n) {
      final ch = html.codeUnitAt(j);
      if (ch == 0x3E) {
        complete = true;
        j++;
        break;
      }
      if (_isSpace(ch)) {
        j++;
        continue;
      }
      if (ch == 0x2F) {
        selfClosing = j + 1 < n && html.codeUnitAt(j + 1) == 0x3E;
        j++;
        continue;
      }
      // attribute name (a leading `=` belongs to it)
      final attrStart = j;
      j++;
      while (j < n) {
        final a = html.codeUnitAt(j);
        if (_isSpace(a) || a == 0x2F || a == 0x3E || a == 0x3D) break;
        j++;
      }
      if (name == 'font' && const {'color', 'face', 'size'}.contains(html.substring(attrStart, j).toLowerCase())) {
        fontBreakout = true;
      }
      var k = j;
      while (k < n && _isSpace(html.codeUnitAt(k))) {
        k++;
      }
      if (k < n && html.codeUnitAt(k) == 0x3D /* = */ ) {
        k++;
        while (k < n && _isSpace(html.codeUnitAt(k))) {
          k++;
        }
        if (k < n && (html.codeUnitAt(k) == 0x22 || html.codeUnitAt(k) == 0x27)) {
          final end = html.indexOf(String.fromCharCode(html.codeUnitAt(k)), k + 1);
          j = end < 0 ? n : end + 1;
        } else {
          while (k < n) {
            final v = html.codeUnitAt(k);
            if (_isSpace(v) || v == 0x3E) break;
            k++;
          }
          j = k;
        }
      }
    }
    i = j;
    if (!complete) break; // EOF in a tag: the parser emits nothing more

    if (closing) {
      if (const {'html', 'head', 'body'}.contains(name)) continue; // never pops the tree (after-body modes)
      if (name == 'form' && !inForeign()) {
        // The parser removes only the form element itself; its open children stay.
        final at = find((s) => s == 'form', _buttonScope.contains);
        if (at >= 0) {
          stack.removeAt(at);
          foreignStack.removeAt(at);
        }
        continue;
      }
      final tablePart = !inForeign() && const {'table', 'tbody', 'thead', 'tfoot', 'tr', 'td', 'th'}.contains(name);
      final at = tablePart
          // Table end tags close through the cell / row content (table scope).
          ? find(
              (s) => s == name || (name == 'td' && s == 'th') || (name == 'th' && s == 'td'),
              (s) => const {'html', 'template'}.contains(s) || (name != 'table' && s == 'table'),
            )
          : find((s) => s == name, _specialElements.contains);
      if (at >= 0) popTo(at);
      continue;
    }
    if (inForeign() && (_breakoutElements.contains(name) || fontBreakout)) {
      while (inForeign()) {
        popTo(stack.length - 1);
      }
    }
    if (inForeign()) {
      if (!selfClosing) push(name, true); // `/>` closes foreign elements
      continue;
    }
    // html/head/body: created once by the parser, later tags only merge attributes. Table parts outside a table
    // are dropped (in body: parse error, ignored).
    if (const {'html', 'head', 'body'}.contains(name)) continue;
    final inTemplate = stack.contains('template');
    if (_tableParts.contains(name) && !inTemplate && !stack.contains('table')) continue;
    // Template contents switch insertion modes the estimate doesn't model: no implied end tags there (errs high).
    if (!inTemplate) _impliedEndTags(name, find, popTo, stack);
    // Implied table sections/rows the parser inserts (`<table><td>` → table > tbody > tr > td).
    final cell = name == 'td' || name == 'th';
    if (!inTemplate && (cell || name == 'tr') && stack.isNotEmpty && stack.last == 'table') push('tbody', false);
    if (!inTemplate && cell && stack.isNotEmpty && const {'tbody', 'thead', 'tfoot'}.contains(stack.last)) {
      push('tr', false);
    }
    if (_voidElements.contains(name)) continue;
    final foreign = name == 'svg' || name == 'math';
    if (foreign && selfClosing) continue; // `<svg/>` closes; on HTML elements `/>` is ignored (`<div/>` stays open)
    push(name, foreign);
    if (!foreign && _rawTextElements.contains(name)) {
      if (name == 'plaintext') break;
      // Text up to the first `</name` + space, `/` or `>` (case-insensitive), like the tokenizer.
      final end = RegExp('</$name[\\t\\n\\f\\r />]', caseSensitive: false).allMatches(html, i).firstOrNull;
      if (end == null) break;
      i = end.start;
    }
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

/// Implied end tags the parser surely applies before inserting the start tag [name] (HTML content, outside
/// templates): `<p>` closed by block starts, `li`/`dd`/`dt`, `option`, cells and rows, a `<table>` directly in a table.
void _impliedEndTags(
  String name,
  int Function(bool Function(String) match, bool Function(String) stopAt) find,
  void Function(int index) popTo,
  List<String> stack,
) {
  if (_closesP.contains(name)) {
    final p = find((s) => s == 'p', _buttonScope.contains);
    if (p >= 0) popTo(p);
  }
  if (name == 'li' || name == 'dd' || name == 'dt') {
    final same = name == 'li' ? const {'li'} : const {'dd', 'dt'};
    final at = find(same.contains, (s) => _specialElements.contains(s) && !const {'address', 'div', 'p'}.contains(s));
    if (at >= 0) popTo(at);
  } else if (name == 'option' && stack.isNotEmpty && stack.last == 'option') {
    popTo(stack.length - 1);
  } else if (name == 'td' || name == 'th') {
    final at = find((s) => s == 'td' || s == 'th', (s) => const {'tr', 'table', 'template', 'html'}.contains(s));
    if (at >= 0) popTo(at);
  } else if (name == 'tr') {
    final at = find((s) => s == 'tr', (s) => const {'table', 'template', 'html'}.contains(s));
    if (at >= 0) popTo(at);
  }
  if (name == 'table') {
    // `<table>` while in a table (not in a cell/caption) closes that table first.
    final at = find((s) => const {'table', 'td', 'th', 'caption'}.contains(s), (s) => s == 'html');
    if (at >= 0 && stack[at] == 'table') popTo(at);
  }
}

/// [safePreviewDocument] in a background isolate that is killed after [timeout] → null. The hard backstop for
/// hostile markup the cheap limits ([previewLimitError]) don't catch: the UI never waits longer, the CPU is freed.
Future<String?> sanitizePreviewInBackground(String html, {Duration timeout = const Duration(seconds: 5)}) async {
  final port = ReceivePort();
  final isolate = await Isolate.spawn(_sanitizeEntry, (port.sendPort, html), onError: port.sendPort);
  try {
    final result = await port.first.timeout(timeout);
    return result is String ? result : null;
  } on TimeoutException {
    return null;
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _sanitizeEntry((SendPort, String) args) => args.$1.send(safePreviewDocument(args.$2));

/// Only the preview's own initial load (`loadHtmlString` → about:blank) may navigate; links, form posts and
/// anything after the page finished loading are blocked.
bool isPreviewNavigationAllowed(String url, {required bool loaded}) => !loaded && url == 'about:blank';
