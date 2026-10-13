import 'dart:convert';

import 'package:elly_mobile_app/services/rich_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiptap (StarterKit + Image) output shapes. Complements rich_text_codec_test.dart (one big sample)
/// with one fixture per structure so a failure names the structure that broke.

const _img = '<img loading="lazy" class="tiptap-img" src="https://api.example.com/assets/t/a.png"';

/// name → canonical Tiptap HTML. Must come back byte-for-byte from opsToHtml(htmlToOps(x)).
final _canonical = <String, String>{
  'paragraph with all marks':
      '<p><strong>b</strong> <em>i</em> <s>s</s> <u>u</u> <code>c</code> <strong><em>bi</em></strong></p>',
  'headings h1-h6': '<h1>1</h1><h2>2</h2><h3>3</h3><h4>4</h4><h5>5</h5><h6>6</h6>',
  'bullet list': '<ul><li><p>a</p></li><li><p>b</p></li></ul>',
  'ordered list': '<ol><li><p>a</p></li><li><p>b</p></li></ol>',
  'three-level nested list': '<ul><li><p>1</p><ul><li><p>2</p><ul><li><p>3</p></li></ul></li></ul></li></ul>',
  'ordered inside bullet inside ordered':
      '<ol><li><p>a</p><ul><li><p>b</p><ol><li><p>c</p></li></ol></li></ul></li><li><p>d</p></li></ol>',
  'nested list siblings after a deep item': '<ul><li><p>a</p><ul><li><p>b</p><ul><li><p>c</p></li></ul></li><li><p>d</p></li></ul></li><li><p>e</p></li></ul>',
  'list item with marks': '<ul><li><p><strong>b</strong> and <a target="_blank" rel="noopener noreferrer nofollow" href="https://x.y">l</a></p></li></ul>',
  'bullet list then ordered list (different types do not merge)':
      '<ul><li><p>a</p></li></ul><ol><li><p>b</p></li></ol>',
  'list, paragraph, list': '<ul><li><p>a</p></li></ul><p>mid</p><ul><li><p>b</p></li></ul>',
  'multi-paragraph blockquote': '<blockquote><p>q1</p><p>q2</p><p>q3</p></blockquote>',
  'blockquote with marks': '<blockquote><p><em>q</em> <code>c</code></p></blockquote>',
  'blockquote, paragraph, blockquote': '<blockquote><p>a</p></blockquote><p>x</p><blockquote><p>b</p></blockquote>',
  'code block with language': '<pre><code class="language-dart">void main() {\n  print(1);\n}</code></pre>',
  'code block without language': '<pre><code>plain</code></pre>',
  'code block with blank lines': '<pre><code class="language-js">a\n\n\nb</code></pre>',
  'code block with special chars':
      '<pre><code class="language-html">&lt;div class=&quot;a&quot;&gt;&amp;&lt;/div&gt;</code></pre>',
  'language with symbols':
      '<pre><code class="language-c++">int x;</code></pre><p>sep</p><pre><code class="language-c#">int y;</code></pre>',
  'inline code with entities': '<p><code>a &lt; b &amp;&amp; c &gt; d</code></p>',
  'inline code inside bold': '<p><strong><code>both</code></strong></p>',
  'image with alt': '<p>before</p>$_img alt="Kapak"><p>after</p>',
  'image with alt and title': '$_img alt="A" title="T">',
  'image with quotes in alt': '$_img alt="He said &quot;hi&quot;">',
  'image without alt': '$_img>',
  'hr between paragraphs': '<p>a</p><hr><p>b</p>',
  'consecutive hr': '<p>a</p><hr><hr><p>b</p>',
  'hr first and last': '<hr><p>a</p><hr>',
  'br inside paragraph': '<p>a<br>b</p>',
  'several br and trailing br': '<p>a<br>b<br>c<br></p>',
  'br inside a heading': '<h2>a<br>b</h2>',
  'br inside list item and blockquote': '<ul><li><p>a<br>b</p></li></ul><blockquote><p>q<br>r</p></blockquote>',
  'empty paragraphs are kept': '<p>a</p><p></p><p></p><p>b</p>',
  'paragraph after br paragraph stays separate': '<p>a<br></p><p>b</p>',
  'paragraph after hr stays separate': '<p>a</p><hr><p>b</p><p>c</p>',
  'link with query and ampersand':
      '<p><a target="_blank" rel="noopener noreferrer nofollow" href="https://x.com/?a=1&amp;b=2">l</a></p>',
  'bold link': '<p><a target="_blank" rel="noopener noreferrer nofollow" href="https://x.y"><strong>l</strong></a></p>',
  'turkish text and emoji': '<p>Şirket çalışanları İstanbul\'da toplandı ğüşiöç ĞÜŞİÖÇ 🎉</p>',
  'text entities': '<p>a &lt; b &amp; c &gt; d</p>',
  'leading and inner double spaces': '<p>a  b</p>',
};

String _roundTrip(String html) => opsToHtml(htmlToOps(html));

/// ops → html → ops must be stable (nothing lost on the way back into the editor).
void _expectStable(String html) {
  final ops = htmlToOps(html);
  expect(jsonEncode(htmlToOps(opsToHtml(ops))), jsonEncode(ops));
}

void main() {
  group('Tiptap output survives htmlToOps → opsToHtml', () {
    for (final c in _canonical.entries) {
      test('${c.key}: byte-identical', () {
        expect(analyzeHtml(c.value).supported, isTrue, reason: analyzeHtml(c.value).problem);
        expect(_roundTrip(c.value), c.value);
      });
    }

    test('bold/italic markup written by other editors (b, i, strike, del) is normalised to Tiptap tags', () {
      expect(
        _roundTrip('<p><b>x</b> <i>y</i> <strike>z</strike> <del>w</del></p>'),
        '<p><strong>x</strong> <em>y</em> <s>z</s> <s>w</s></p>',
      );
    });

    test('quotes in text come back escaped but mean the same', () {
      _expectStable('<p>say "hi"</p>');
      expect(htmlToOps('<p>say "hi"</p>'), htmlToOps(_roundTrip('<p>say "hi"</p>')));
    });

    test('li without <p> is normalised to Tiptap form <li><p>', () {
      expect(
        _roundTrip('<ul><li>a<ul><li>b</li></ul></li></ul>'),
        '<ul><li><p>a</p><ul><li><p>b</p></li></ul></li></ul>',
      );
    });

    test('newlines inside a paragraph are whitespace, not line breaks', () {
      expect(htmlToOps('<p>a\nb</p>').first, {'insert': 'a b\n'});
    });
  });

  group('ops carry what the editor needs', () {
    test('code block: every line is its own code-block line carrying the language', () {
      final ops = htmlToOps('<pre><code class="language-dart">a\n\nb</code></pre>');
      const attrs = {'code-block': true, 'code-lang': 'dart'};
      expect(ops, [
        {'insert': 'a'},
        {'insert': '\n\n', 'attributes': attrs}, // equal neighbours are merged
        {'insert': 'b'},
        {'insert': '\n', 'attributes': attrs},
      ]);
    });

    test('code block without language has no code-lang attribute', () {
      expect(htmlToOps('<pre><code>x</code></pre>').last, {
        'insert': '\n',
        'attributes': {'code-block': true},
      });
    });

    test('inline code is a mark, text around it is plain', () {
      expect(htmlToOps('<p>a <code>b</code> c</p>'), [
        {'insert': 'a '},
        {
          'insert': 'b',
          'attributes': {'code': true},
        },
        {'insert': ' c\n'},
      ]);
    });

    test('image keeps alt and title as attributes, in the same line as nothing else', () {
      expect(htmlToOps('$_img alt="A" title="T">'), [
        {
          'insert': {'image': 'https://api.example.com/assets/t/a.png'},
          'attributes': {'alt': 'A', 'title': 'T'},
        },
        {'insert': '\n'},
      ]);
    });

    test('br is a soft break (U+2028) inside one line; the paragraph after hr/br is a separate line', () {
      expect(htmlToOps('<p>a<br>b</p><hr><p>c</p>'), [
        {'insert': 'a${lineSeparator}b\n'},
        {
          'insert': {'divider': 'hr'},
        },
        {'insert': '\nc\n'},
      ]);
    });

    test('multi-paragraph blockquote: one blockquote line per paragraph', () {
      expect(htmlToOps('<blockquote><p>a</p><p>b</p></blockquote>'), [
        {'insert': 'a'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
        {'insert': 'b'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ]);
    });

    test('nested list: indent grows with the depth, ordered/bullet kept per level', () {
      expect(htmlToOps('<ol><li><p>a</p><ul><li><p>b</p></li></ul></li></ol>'), [
        {'insert': 'a'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'b'},
        {
          'insert': '\n',
          'attributes': {'indent': 1, 'list': 'bullet'},
        },
      ]);
    });
  });

  group('unsupported content is detected (→ raw HTML mode, nothing parsed away)', () {
    final unsupported = <String, String>{
      'table': '<table><thead><tr><th>h</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>',
      'table after paragraph': '<p>x</p><table><tr><td>1</td></tr></table>',
      'iframe': '<iframe src="https://www.youtube.com/embed/x" width="560"></iframe>',
      'iframe inside paragraph': '<p>x<iframe src="https://y"></iframe></p>',
      'div wrapper': '<div><p>x</p></div>',
      'div with class': '<div class="wrapper">x</div>',
      'span': '<p>a <span>b</span></p>',
      'span with style': '<p><span style="color:red">x</span></p>',
      'style attribute on p': '<p style="text-align:center">x</p>',
      'style attribute on h2': '<h2 style="color:red">x</h2>',
      'class attribute on p': '<p class="lead">x</p>',
      'class attribute on ul': '<ul class="list"><li><p>x</p></li></ul>',
      'class attribute on li': '<ul><li class="item"><p>x</p></li></ul>',
      'class attribute on blockquote': '<blockquote class="q"><p>x</p></blockquote>',
      'class attribute on hr': '<hr class="thick">',
      'style tag': '<style>p{color:red}</style><p>x</p>',
      'script tag': '<script>alert(1)</script>',
      'script after content': '<p>x</p><script src="https://evil/x.js"></script>',
      'script inside paragraph': '<p>x<script>alert(1)</script></p>',
      'onclick on p': '<p onclick="alert(1)">x</p>',
      'onclick on a': '<p><a href="https://x" onclick="alert(1)">x</a></p>',
      'onmouseover on strong': '<p><strong onmouseover="alert(1)">x</strong></p>',
      'onerror on img': '<img src="x.png" onerror="alert(1)">',
      'onload on img': '<img src="x.png" onload="alert(1)">',
      'onclick on h1': '<h1 onclick="x()">t</h1>',
      'onclick on li': '<ul><li onclick="x()"><p>x</p></li></ul>',
      'onclick on pre code': '<pre><code onclick="x()">x</code></pre>',
      'img without src': '<img alt="x">',
      'img with empty src': '<img src="" alt="x">',
      'img with srcset': '<img src="x.png" srcset="y.png 2x">',
      'inline image': '<p>a <img src="x.png"> b</p>',
      'link without href': '<p><a name="x">y</a></p>',
      'link with title': '<p><a href="x" title="t">x</a></p>',
      'link with class': '<p><a href="x" class="btn">x</a></p>',
      'sup / sub': '<p>x<sup>2</sup> y<sub>1</sub></p>',
      'mark': '<p><mark>x</mark></p>',
      'font': '<p><font color="red">x</font></p>',
      'ordered list start': '<ol start="3"><li><p>x</p></li></ol>',
      'task list input': '<ul><li><input type="checkbox"> x</li></ul>',
      'multi paragraph list item': '<ul><li><p>a</p><p>b</p></li></ul>',
      'text after nested list': '<ul><li><p>a</p><ul><li><p>b</p></li></ul>tail</li></ul>',
      'heading inside blockquote': '<blockquote><h2>x</h2></blockquote>',
      'list inside blockquote': '<blockquote><ul><li><p>x</p></li></ul></blockquote>',
      'formatted code block': '<pre><code><strong>x</strong></code></pre>',
      'pre without code but with markup': '<pre><b>x</b></pre>',
      'code with unknown class': '<pre><code class="hljs">x</code></pre>',
      'code with extra attribute': '<pre><code class="language-js" data-x="1">x</code></pre>',
      'top-level br': '<p>x</p><br>',
      'top-level text': 'merhaba',
      'markdown': '# Başlık\n\n- madde',
      'top-level inline element': '<strong>x</strong>',
      'figure': '<figure><img src="x.png"><figcaption>c</figcaption></figure>',
      'video': '<video src="x.mp4"></video>',
      'button': '<button>x</button>',
      'form': '<form><input name="a"></form>',
      'object / embed': '<object data="x"></object>',
      'adjacent blockquotes': '<blockquote><p>a</p></blockquote><blockquote><p>b</p></blockquote>',
      'adjacent lists of the same type': '<ul><li><p>a</p></li></ul><ul><li><p>b</p></li></ul>',
      'adjacent code blocks': '<pre><code>a</code></pre><pre><code>b</code></pre>',
    };

    for (final c in unsupported.entries) {
      test('${c.key} → unsupported with a reason', () {
        final analysis = analyzeHtml(c.value);
        expect(analysis.supported, isFalse);
        expect(analysis.ops, isNull);
        expect(analysis.problem, isNotEmpty);
      });
    }

    test('htmlToOps throws UnsupportedHtmlException carrying the reason', () {
      expect(
        () => htmlToOps('<div>x</div>'),
        throwsA(isA<UnsupportedHtmlException>().having((e) => e.reason, 'reason', contains('div'))),
      );
      expect(
        () => htmlToOps('<p onclick="x()">x</p>'),
        throwsA(isA<UnsupportedHtmlException>().having((e) => e.reason, 'reason', contains('öznitelik'))),
      );
    });

    // BUG (reported): the codec keeps any href as-is, so a body that contains an executable link is
    // opened in the editor and saved back with it. Raw HTML mode (+ warning) is the stated contract
    // for risky content; Tiptap itself refuses javascript: links.
    for (final href in [
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      ' javascript:alert(1)',
      'java\tscript:alert(1)',
    ]) {
      test('href="$href" → unsupported', () {
        expect(analyzeHtml('<p><a href="$href">x</a></p>').supported, isFalse);
      });
    }

    test('safe schemes stay editable (https, http, mailto, tel, relative, anchor)', () {
      for (final href in [
        'https://x.y/a?b=1',
        'http://x.y',
        'mailto:a@b.c',
        'tel:+90555',
        '/sayfa',
        '#bolum',
        'sayfa.html',
      ]) {
        expect(analyzeHtml('<p><a href="$href">x</a></p>').supported, isTrue, reason: href);
      }
    });

    test('empty and whitespace-only bodies are editable', () {
      expect(analyzeHtml('').supported, isTrue);
      expect(analyzeHtml('   \n ').supported, isTrue);
    });

    test('unsupported verdict does not depend on where the offending node sits in a long document', () {
      final doc =
          '${_canonical['headings h1-h6']}${_canonical['three-level nested list']}<table><tr><td>1</td></tr></table>';
      expect(analyzeHtml(doc).supported, isFalse);
      expect(analyzeHtml('<table><tr><td>1</td></tr></table>${_canonical['headings h1-h6']}').supported, isFalse);
    });
  });
}
