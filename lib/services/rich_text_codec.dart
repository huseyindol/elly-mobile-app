import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// HTML ↔ Quill Delta (ops JSON) for the subset elly-admin's Tiptap editor produces
/// (StarterKit + Image): p, h1–h6, ul/ol > li > p (nested lists), blockquote > p, pre > code, hr, img,
/// br and the marks strong/b, em/i, s/del/strike, u, code, a[href].
///
/// Strict on purpose: anything else (table, iframe, div, span, style/class attributes, …) throws
/// [UnsupportedHtmlException] so the editor can fall back to raw HTML instead of silently dropping it.
/// Pure Dart (no Flutter) so it is unit-testable.
///
/// Own codec instead of `flutter_quill_delta_from_html`: on Tiptap output that package dropped inline
/// `<code>`, code-block line breaks and `img alt`, and merged paragraphs after `<br>`/`<hr>`.

class UnsupportedHtmlException implements Exception {
  final String reason;
  const UnsupportedHtmlException(this.reason);
  @override
  String toString() => reason;
}

/// Result of [analyzeHtml]: [ops] when the body can be edited losslessly, otherwise [problem].
class RichTextAnalysis {
  final List<Map<String, dynamic>>? ops;
  final String? problem;
  const RichTextAnalysis._(this.ops, this.problem);
  bool get supported => ops != null;
}

/// Soft line break (`<br>`) inside a line. Quill's "\n" ends a block, so `<br>` is kept as U+2028.
const lineSeparator = ' ';

/// Delta block attribute carrying the `language-xx` class of a code block (not a Quill attribute;
/// flutter_quill keeps unknown attributes as-is).
const codeLangAttr = 'code-lang';

const _inlineKeys = ['bold', 'italic', 'strike', 'underline', 'code', 'link'];
const _blockKeys = ['header', 'list', 'indent', 'blockquote', 'code-block', codeLangAttr];
const _imageAttrs = ['alt', 'title', 'width', 'height'];
const _markTags = {
  'strong': 'bold',
  'b': 'bold',
  'em': 'italic',
  'i': 'italic',
  's': 'strike',
  'del': 'strike',
  'strike': 'strike',
  'u': 'underline',
  'code': 'code',
};

/// Can [html] be edited in the rich editor without losing anything?
/// Checks the subset (strict parse), then that ops → HTML → ops is stable and the visible text survives.
RichTextAnalysis analyzeHtml(String html) {
  try {
    final ops = htmlToOps(html);
    final again = opsToHtml(ops);
    if (jsonEncode(htmlToOps(again)) != jsonEncode(ops)) {
      return const RichTextAnalysis._(null, 'Dönüşüm sonrası yapı değişiyor');
    }
    if (_plainText(html) != _plainText(again)) {
      return const RichTextAnalysis._(null, 'Dönüşüm sonrası metin değişiyor');
    }
    return RichTextAnalysis._(ops, null);
  } on UnsupportedHtmlException catch (e) {
    return RichTextAnalysis._(null, e.reason);
  }
}

String _plainText(String html) =>
    html_parser.parseFragment(html).text!.replaceAll(lineSeparator, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

// ---------------------------------------------------------------- HTML → ops

List<Map<String, dynamic>> htmlToOps(String html) {
  final out = _OpsBuilder();
  if (html.trim().isEmpty) return (out..line(const {})).ops;
  final fragment = html_parser.parseFragment(html);
  String? previousGroup; // blockquote/pre/ul/ol: two adjacent ones would merge on save
  for (final node in fragment.nodes) {
    if (node is dom.Text) {
      if (node.text.trim().isEmpty) continue;
      throw const UnsupportedHtmlException('Blok dışında metin (HTML olmayan içerik)');
    }
    if (node is! dom.Element) continue; // comments
    final tag = node.localName!;
    if (const {'blockquote', 'pre', 'ul', 'ol'}.contains(tag) && tag == previousGroup) {
      throw UnsupportedHtmlException('Art arda iki <$tag>');
    }
    previousGroup = tag;
    _block(node, out);
  }
  if (out.ops.isEmpty) out.line(const {});
  return out.ops;
}

void _block(dom.Element el, _OpsBuilder out) {
  final tag = el.localName!;
  switch (tag) {
    case 'p':
      _noAttrs(el);
      _inline(el.nodes, const {}, out);
      out.line(const {});
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      _noAttrs(el);
      _inline(el.nodes, const {}, out);
      out.line({'header': int.parse(tag.substring(1))});
    case 'ul' || 'ol':
      _list(el, 0, out);
    case 'blockquote':
      _noAttrs(el);
      for (final child in _elements(el)) {
        if (child.localName != 'p') throw UnsupportedHtmlException('<blockquote> içinde <${child.localName}>');
        _noAttrs(child);
        _inline(child.nodes, const {}, out);
        out.line({'blockquote': true});
      }
    case 'pre':
      _noAttrs(el);
      final children = el.children;
      final code = children.length == 1 && children.single.localName == 'code' ? children.single : null;
      if (children.isNotEmpty && (code == null || el.nodes.length != 1)) {
        throw const UnsupportedHtmlException('<pre> içinde <code> dışı içerik');
      }
      String? lang;
      if (code != null) {
        if (code.children.isNotEmpty) throw const UnsupportedHtmlException('Kod bloğu içinde biçim');
        final classes = code.attributes.entries.where((a) => a.key != 'class').toList();
        final cls = code.attributes['class'];
        if (classes.isNotEmpty || (cls != null && !RegExp(r'^language-[\w+#-]+$').hasMatch(cls))) {
          throw const UnsupportedHtmlException('Kod bloğunda desteklenmeyen öznitelik');
        }
        lang = cls?.substring('language-'.length);
      }
      for (final line in (code ?? el).text.split('\n')) {
        if (line.isNotEmpty) out.text(line, const {});
        out.line({'code-block': true, codeLangAttr: ?lang});
      }
    case 'hr':
      _noAttrs(el);
      out.embed({'divider': 'hr'}, const {});
      out.line(const {});
    case 'img':
      _image(el, out);
      out.line(const {});
    default:
      throw UnsupportedHtmlException('<$tag> desteklenmiyor');
  }
}

void _list(dom.Element list, int depth, _OpsBuilder out) {
  _noAttrs(list);
  final type = list.localName == 'ol' ? 'ordered' : 'bullet';
  for (final li in _elements(list)) {
    if (li.localName != 'li') throw UnsupportedHtmlException('<${list.localName}> içinde <${li.localName}>');
    _noAttrs(li);
    final paragraphs = li.children.where((e) => e.localName == 'p').toList();
    if (paragraphs.length > 1) throw const UnsupportedHtmlException('Birden fazla paragraflı liste öğesi');
    final inline = <dom.Node>[];
    final nested = <dom.Element>[];
    for (final node in li.nodes) {
      if (node is dom.Element && (node.localName == 'ul' || node.localName == 'ol')) {
        nested.add(node);
      } else if (node is dom.Element && node.localName == 'p') {
        _noAttrs(node);
        inline.addAll(node.nodes);
      } else if (nested.isNotEmpty && !(node is dom.Text && node.text.trim().isEmpty)) {
        throw const UnsupportedHtmlException('Alt listeden sonra metin');
      } else {
        inline.add(node);
      }
    }
    _inline(inline, const {}, out);
    out.line({'list': type, 'indent': ?(depth == 0 ? null : depth)});
    for (final sub in nested) {
      _list(sub, depth + 1, out);
    }
  }
}

void _inline(List<dom.Node> nodes, Map<String, dynamic> marks, _OpsBuilder out) {
  for (final node in nodes) {
    if (node is dom.Text) {
      final text = node.text.replaceAll('\n', ' ');
      if (text.isNotEmpty) out.text(text, marks);
      continue;
    }
    if (node is! dom.Element) continue;
    final tag = node.localName!;
    if (tag == 'br') {
      _noAttrs(node);
      out.text(lineSeparator, marks);
    } else if (tag == 'a') {
      final href = node.attributes['href'];
      if (href == null || node.attributes.keys.any((k) => !const {'href', 'target', 'rel'}.contains(k))) {
        throw const UnsupportedHtmlException('Desteklenmeyen bağlantı öznitelikleri');
      }
      _inline(node.nodes, {...marks, 'link': href}, out);
    } else if (_markTags.containsKey(tag)) {
      _noAttrs(node);
      _inline(node.nodes, {...marks, _markTags[tag]!: true}, out);
    } else if (tag == 'img') {
      throw const UnsupportedHtmlException('Satır içi görsel');
    } else {
      throw UnsupportedHtmlException('<$tag> desteklenmiyor');
    }
  }
}

void _image(dom.Element img, _OpsBuilder out) {
  final src = img.attributes['src'];
  final allowed = {..._imageAttrs, 'src', 'loading', 'class'};
  if (src == null || src.isEmpty || img.attributes.keys.any((k) => !allowed.contains(k))) {
    throw const UnsupportedHtmlException('Desteklenmeyen görsel öznitelikleri');
  }
  out.embed(
    {'image': src},
    {
      for (final key in _imageAttrs)
        if (img.attributes[key] != null) key: img.attributes[key],
    },
  );
}

List<dom.Element> _elements(dom.Element el) {
  for (final node in el.nodes) {
    if (node is dom.Text && node.text.trim().isNotEmpty) {
      throw UnsupportedHtmlException('<${el.localName}> içinde doğrudan metin');
    }
  }
  return el.children;
}

void _noAttrs(dom.Element el) {
  if (el.attributes.isNotEmpty) throw UnsupportedHtmlException('<${el.localName}> öznitelikleri desteklenmiyor');
}

/// Builds normalized ops: sorted attribute keys, adjacent text with equal attributes merged.
class _OpsBuilder {
  final ops = <Map<String, dynamic>>[];

  static Map<String, dynamic>? _attrs(Map<String, dynamic> attrs) =>
      attrs.isEmpty ? null : Map.fromEntries(attrs.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

  void text(String text, Map<String, dynamic> attrs) => _add(text, _attrs(attrs));
  void line(Map<String, dynamic> attrs) => _add('\n', _attrs(attrs));
  void embed(Map<String, String> value, Map<String, dynamic> attrs) =>
      ops.add({'insert': value, 'attributes': ?_attrs(attrs)});

  void _add(String text, Map<String, dynamic>? attrs) {
    final last = ops.isEmpty ? null : ops.last;
    if (last != null && last['insert'] is String && jsonEncode(last['attributes']) == jsonEncode(attrs)) {
      last['insert'] = '${last['insert']}$text';
    } else {
      ops.add({'insert': text, 'attributes': ?attrs});
    }
  }
}

// ---------------------------------------------------------------- ops → HTML

class _Line {
  final segments = <({Object insert, Map<String, dynamic> attrs})>[];
  Map<String, dynamic> attrs = const {};
  int indent = 0;
  bool get isList => attrs['list'] != null;
  Map<String, dynamic>? get soleEmbed =>
      segments.length == 1 && segments.single.insert is Map ? segments.single.insert as Map<String, dynamic> : null;
}

/// Tiptap-shaped HTML (same tags/attributes elly-admin's editor writes). Empty document → ''.
/// Attributes outside the subset (pasted colors, alignment, …) are dropped.
String opsToHtml(List<Map<String, dynamic>> ops) {
  final lines = <_Line>[];
  var current = _Line();
  for (final op in ops) {
    final insert = op['insert'];
    final attrs = Map<String, dynamic>.from(op['attributes'] as Map? ?? const {});
    if (insert is String) {
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) current.segments.add((insert: parts[i], attrs: _pick(attrs, _inlineKeys)));
        if (i < parts.length - 1) {
          lines.add(current..attrs = _pick(attrs, _blockKeys));
          current = _Line();
        }
      }
    } else if (insert is Map) {
      current.segments.add((insert: Map<String, dynamic>.from(insert), attrs: attrs));
    }
  }
  if (current.segments.isNotEmpty) lines.add(current);
  if (lines.every((l) => l.segments.isEmpty && l.attrs.isEmpty)) return '';

  // A list item can only be one level deeper than the previous one.
  for (var i = 0; i < lines.length; i++) {
    final wanted = (lines[i].attrs['indent'] as num?)?.toInt() ?? 0;
    lines[i].indent = !lines[i].isList || i == 0 || !lines[i - 1].isList ? 0 : wanted.clamp(0, lines[i - 1].indent + 1);
  }

  final html = StringBuffer();
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final embed = line.soleEmbed;
    if (line.attrs['code-block'] != null) {
      final lang = line.attrs[codeLangAttr];
      final code = <String>[];
      while (i < lines.length && lines[i].attrs['code-block'] != null) {
        code.add(lines[i++].segments.map((s) => s.insert is String ? s.insert as String : '').join());
      }
      final cls = lang == null ? '' : ' class="language-${_escape(lang.toString())}"';
      html.write('<pre><code$cls>${_escape(code.join('\n'))}</code></pre>');
      continue;
    }
    if (line.isList) {
      i = _listHtml(lines, i, 0, html);
      continue;
    }
    if (line.attrs['blockquote'] != null) {
      html.write('<blockquote>');
      while (i < lines.length && lines[i].attrs['blockquote'] != null && !lines[i].isList) {
        html.write('<p>${_inlineHtml(lines[i++])}</p>');
      }
      html.write('</blockquote>');
      continue;
    }
    final header = line.attrs['header'];
    if (header != null) {
      html.write('<h$header>${_inlineHtml(line)}</h$header>');
    } else if (embed != null && embed['image'] != null) {
      final a = line.segments.single.attrs;
      final extra = [
        for (final k in _imageAttrs)
          if (a[k] != null) ' $k="${_escape(a[k].toString())}"',
      ].join();
      html.write('<img loading="lazy" class="tiptap-img" src="${_escape(embed['image'].toString())}"$extra>');
    } else if (embed != null && embed['divider'] != null) {
      html.write('<hr>');
    } else {
      html.write('<p>${_inlineHtml(line)}</p>');
    }
    i++;
  }
  return html.toString();
}

int _listHtml(List<_Line> lines, int start, int depth, StringBuffer html) {
  final type = lines[start].attrs['list'];
  final tag = type == 'ordered' ? 'ol' : 'ul';
  html.write('<$tag>');
  var i = start;
  while (i < lines.length && lines[i].isList && lines[i].indent == depth && lines[i].attrs['list'] == type) {
    html.write('<li><p>${_inlineHtml(lines[i++])}</p>');
    while (i < lines.length && lines[i].isList && lines[i].indent > depth) {
      i = _listHtml(lines, i, depth + 1, html);
    }
    html.write('</li>');
  }
  html.write('</$tag>');
  return i;
}

String _inlineHtml(_Line line) {
  final out = StringBuffer();
  for (final s in line.segments) {
    if (s.insert is! String) continue; // embeds share a line only with nothing (Quill block embeds)
    var text = _escape(s.insert as String).replaceAll(lineSeparator, '<br>');
    final a = s.attrs;
    if (a['code'] == true) text = '<code>$text</code>';
    if (a['underline'] == true) text = '<u>$text</u>';
    if (a['strike'] == true) text = '<s>$text</s>';
    if (a['italic'] == true) text = '<em>$text</em>';
    if (a['bold'] == true) text = '<strong>$text</strong>';
    if (a['link'] != null) {
      text = '<a target="_blank" rel="noopener noreferrer nofollow" href="${_escape(a['link'].toString())}">$text</a>';
    }
    out.write(text);
  }
  return out.toString();
}

Map<String, dynamic> _pick(Map<String, dynamic> attrs, List<String> keys) => {
  for (final k in keys)
    if (attrs[k] != null && attrs[k] != false) k: attrs[k],
};

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
