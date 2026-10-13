import 'package:elly_mobile_app/services/rich_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// What elly-admin's Tiptap editor (StarterKit + Image) writes.
const _tiptap =
    '<h2>Başlık</h2>'
    '<p>Merhaba <strong>kalın</strong> <em>italik</em> <s>çizili</s> <u>alt</u> <code>kod</code> '
    '<a target="_blank" rel="noopener noreferrer nofollow" href="https://x.com/?a=1&amp;b=2">link</a></p>'
    '<ul><li><p>bir</p><ul><li><p>iç içe</p></li></ul></li><li><p>iki</p></li></ul>'
    '<ol><li><p>a</p></li></ol>'
    '<blockquote><p>q1</p><p>q2</p></blockquote>'
    '<img loading="lazy" class="tiptap-img" src="https://api.example.com/assets/x.png" alt="Kapak">'
    '<pre><code class="language-dart">void main() {\n  print(1 &lt; 2);\n}</code></pre>'
    '<p>satır<br>iki</p>'
    '<hr>'
    '<p></p>'
    '<p>son</p>';

/// `contains` on a List compares with `==` (identity for maps); compare deeply instead.
Matcher _has(Object op) => contains(equals(op));

void main() {
  group('htmlToOps', () {
    test('maps the Tiptap subset to Quill ops', () {
      final ops = htmlToOps(_tiptap);
      expect(ops.first, {'insert': 'Başlık'});
      expect(ops[1], {
        'insert': '\n',
        'attributes': {'header': 2},
      });
      expect(
        ops,
        _has({
          'insert': 'kod',
          'attributes': {'code': true},
        }),
      );
      expect(
        ops,
        _has({
          'insert': 'link',
          'attributes': {'link': 'https://x.com/?a=1&b=2'},
        }),
      );
      expect(
        ops,
        _has({
          'insert': '\n',
          'attributes': {'indent': 1, 'list': 'bullet'},
        }),
      );
      expect(
        ops,
        _has({
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        }),
      );
      expect(
        ops,
        _has({
          'insert': '\n',
          'attributes': {'blockquote': true},
        }),
      );
      expect(
        ops,
        _has({
          'insert': {'image': 'https://api.example.com/assets/x.png'},
          'attributes': {'alt': 'Kapak'},
        }),
      );
      expect(ops, _has({'insert': '  print(1 < 2);'}));
      expect(
        ops,
        _has({
          'insert': '\n',
          'attributes': {'code-block': true, 'code-lang': 'dart'},
        }),
      );
      expect(ops, _has({'insert': 'satır${lineSeparator}iki\n'}));
      expect(
        ops,
        _has({
          'insert': {'divider': 'hr'},
        }),
      );
      expect(ops.last, {'insert': '\n\nson\n'}, reason: 'line after <hr>, empty <p> kept as an empty line');
    });

    test('empty body → single empty line', () {
      expect(htmlToOps(''), [
        {'insert': '\n'},
      ]);
      expect(htmlToOps('  \n'), [
        {'insert': '\n'},
      ]);
    });

    test('mark nesting order does not matter (attributes are normalized)', () {
      expect(htmlToOps('<p><em><strong>x</strong></em></p>'), htmlToOps('<p><strong><em>x</em></strong></p>'));
    });
  });

  group('opsToHtml', () {
    test('Tiptap HTML survives a round trip', () {
      final html = opsToHtml(htmlToOps(_tiptap));
      expect(htmlToOps(html), htmlToOps(_tiptap));
      expect(html, contains('<ul><li><p>bir</p><ul><li><p>iç içe</p></li></ul></li><li><p>iki</p></li></ul>'));
      expect(html, contains('<blockquote><p>q1</p><p>q2</p></blockquote>'));
      expect(html, contains('<pre><code class="language-dart">void main() {\n  print(1 &lt; 2);\n}</code></pre>'));
      expect(
        html,
        contains('<img loading="lazy" class="tiptap-img" src="https://api.example.com/assets/x.png" alt="Kapak">'),
      );
      expect(html, contains('<p>satır<br>iki</p><hr><p></p><p>son</p>'));
      expect(html, contains('href="https://x.com/?a=1&amp;b=2"'));
    });

    test('empty document → empty string (like the admin editor)', () {
      expect(
        opsToHtml([
          {'insert': '\n'},
        ]),
        '',
      );
    });

    test('list indent jumps are clamped to one level', () {
      final html = opsToHtml([
        {'insert': 'a'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet', 'indent': 2},
        },
        {'insert': 'b'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet', 'indent': 3},
        },
      ]);
      expect(html, '<ul><li><p>a</p><ul><li><p>b</p></li></ul></li></ul>');
    });

    test('mixed list types and nested switches', () {
      const html =
          '<ul><li><p>a</p><ul><li><p>b</p></li></ul><ol><li><p>c</p></li></ol></li></ul><ol><li><p>d</p></li></ol>';
      expect(opsToHtml(htmlToOps(html)), html);
    });

    test('a list line that is also a blockquote does not hang', () {
      final html = opsToHtml([
        {'insert': 'x'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet', 'blockquote': true},
        },
      ]);
      expect(html, '<ul><li><p>x</p></li></ul>');
    });

    test('attributes outside the subset (pasted color, align) are dropped', () {
      expect(
        opsToHtml([
          {
            'insert': 'x',
            'attributes': {'color': '#ff0000', 'bold': true},
          },
          {
            'insert': '\n',
            'attributes': {'align': 'center'},
          },
        ]),
        '<p><strong>x</strong></p>',
      );
    });
  });

  group('analyzeHtml (unsupported content detection)', () {
    test('Tiptap output and an empty body are editable', () {
      expect(analyzeHtml(_tiptap).supported, isTrue);
      expect(analyzeHtml('').supported, isTrue);
    });

    for (final c in {
      'table': '<table><tr><td>1</td></tr></table>',
      'iframe': '<p>x</p><iframe src="https://y"></iframe>',
      'div': '<div>x</div>',
      'span with style': '<p><span style="color:red">x</span></p>',
      'paragraph class': '<p class="lead">x</p>',
      'aligned paragraph': '<p style="text-align:center">x</p>',
      'plain text / markdown': '# Başlık\n\nmetin',
      'top-level inline': 'merhaba <strong>x</strong>',
      'inline image': '<p>a <img src="x.png"> b</p>',
      'image with style': '<img src="x.png" style="width:50%">',
      'link with title': '<p><a href="x" title="t">x</a></p>',
      'sup': '<p>x<sup>2</sup></p>',
      'formatted code block': '<pre><code><strong>x</strong></code></pre>',
      'ordered list start': '<ol start="3"><li><p>x</p></li></ol>',
      'multi paragraph list item': '<ul><li><p>a</p><p>b</p></li></ul>',
      'heading in blockquote': '<blockquote><h2>x</h2></blockquote>',
      'adjacent blockquotes (would merge)': '<blockquote><p>a</p></blockquote><blockquote><p>b</p></blockquote>',
      'adjacent lists (would merge)': '<ul><li><p>a</p></li></ul><ul><li><p>b</p></li></ul>',
    }.entries) {
      test('${c.key} → raw HTML fallback', () {
        final result = analyzeHtml(c.value);
        expect(result.supported, isFalse);
        expect(result.problem, isNotEmpty);
      });
    }

    test('li without <p> is accepted (Tiptap adds the <p> on save)', () {
      expect(analyzeHtml('<ul><li>a</li><li>b <em>c</em></li></ul>').supported, isTrue);
    });
  });
}
