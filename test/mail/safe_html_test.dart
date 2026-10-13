import 'package:elly_mobile_app/services/safe_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  group('safePreviewDocument (template HTML is untrusted)', () {
    const hostile = '''
<!DOCTYPE html><html><head>
<meta http-equiv="refresh" content="0;url=https://evil.example">
<meta http-equiv="Content-Security-Policy" content="default-src *">
<base href="https://evil.example/">
<link rel="stylesheet" href="https://evil.example/a.css"><link rel="dns-prefetch" href="//evil.example">
<script>alert(1)</script><style>p { color: red; }</style>
</head><body onload="steal()" style="margin:0">
<noscript><img src="https://evil.example/ns.png"></noscript>
<iframe src="https://evil.example"></iframe><object data="https://evil.example/x"></object><embed src="x.swf">
<img src="https://evil.example/track.png" srcset="https://evil.example/2x.png 2x" onerror="x()" alt="Logo">
<img src="data:image/png;base64,iVBORw0KGgo=" alt="Gömülü">
<table background="https://evil.example/bg.png"><tr><td>Hücre</td></tr></table>
<a href="javascript:alert(1)" style="color:#6366f1">Bağlantı</a><a href="https://example.com" ping="https://evil.example">Site</a>
<form action="https://evil.example/post"><button formaction="https://evil.example/b">Gönder</button></form>
<svg><image href="https://evil.example/s.png"/><use xlink:href="https://evil.example/u.svg#a"/></svg>
<video poster="https://evil.example/p.png"></video>
<p>Merhaba Ahmet</p>
</body></html>''';

    late final String out = safePreviewDocument(hostile);
    late final doc = html_parser.parse(out);

    test('our CSP is the first element of <head>, then the viewport; other http-equiv metas are gone', () {
      final head = doc.head!.children;
      expect(head[0].attributes['http-equiv'], 'Content-Security-Policy');
      expect(head[0].attributes['content'], previewCsp);
      expect(head[1].attributes['name'], 'viewport');
      expect(doc.querySelectorAll('meta[http-equiv]'), hasLength(1));
      expect(previewCsp, startsWith("default-src 'none';"));
      expect(previewCsp, isNot(contains('script-src')));
      expect(previewCsp, contains('img-src data:'));
    });

    test('no script, noscript, frame, plugin, link or base survives', () {
      for (final tag in ['script', 'noscript', 'iframe', 'object', 'embed', 'link', 'base']) {
        expect(doc.querySelectorAll(tag), isEmpty, reason: tag);
      }
    });

    test('no event handler and no remote URL left anywhere', () {
      expect(out, isNot(contains('evil.example')));
      expect(out, isNot(contains('javascript:')));
      for (final e in doc.querySelectorAll('*')) {
        expect(e.attributes.keys.where((k) => '$k'.startsWith('on')), isEmpty, reason: e.localName);
      }
    });

    test('links keep their look but point nowhere; data: images and styling stay', () {
      final links = doc.querySelectorAll('a');
      expect(links.map((a) => a.attributes['href']), ['#', '#']);
      expect(links.first.attributes['style'], 'color:#6366f1');
      final images = doc.querySelectorAll('img');
      expect(images.map((i) => i.attributes['src']), [null, 'data:image/png;base64,iVBORw0KGgo=']);
      expect(images.first.attributes['alt'], 'Logo');
      expect(doc.querySelector('style')!.text, contains('color: red'));
      expect(doc.body!.attributes['style'], 'margin:0');
      expect(out, contains('Merhaba Ahmet'));
      expect(out, contains('Hücre'));
    });

    test('a bare fragment gets a full document with the CSP', () {
      final fragment = html_parser.parse(safePreviewDocument('<p>Selam</p>'));
      expect(fragment.head!.children.first.attributes['content'], previewCsp);
      expect(fragment.body!.text, 'Selam');
    });
  });

  test('navigation: only the initial about:blank load', () {
    expect(isPreviewNavigationAllowed('about:blank', loaded: false), isTrue);
    expect(isPreviewNavigationAllowed('about:blank', loaded: true), isFalse, reason: 'form post / reload later');
    expect(isPreviewNavigationAllowed('about:blank#', loaded: false), isFalse);
    expect(isPreviewNavigationAllowed('https://example.com', loaded: false), isFalse);
    expect(isPreviewNavigationAllowed('data:text/html,x', loaded: false), isFalse);
  });

  group('limits (DoS): checked before parsing', () {
    test('over 1 MB → too big', () {
      final html = '<p>${'a' * (maxPreviewBytes + 1)}</p>';
      expect(previewLimitError(html), contains('çok büyük'));
      final out = safePreviewDocument(html);
      expect(out, contains('Önizleme için çok büyük'));
      expect(out, contains(previewCsp));
      expect(out.length, lessThan(1000));
    });

    test('nesting deeper than the limit → too complex, returned at once', () {
      final html = '<div>' * (maxPreviewDepth + 1);
      expect(previewLimitError(html), contains('çok karmaşık'));
      final sw = Stopwatch()..start();
      expect(safePreviewDocument('<div>' * 100000), contains('Önizleme için çok karmaşık'));
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('implied end tags (p, li, td, tr…), void and self-closed elements do not count as nesting', () {
      final rows = '<table>${'<tr><td><p>x<br><img src=x><span/>' * (maxPreviewDepth * 2)}</table>';
      expect(previewLimitError(rows), isNull);
      expect(previewLimitError('${'<div>' * 100}${'</div>' * 100}' * 50), isNull, reason: 'siblings, not depth');
    });

    test('the error document escapes its message', () {
      expect(previewErrorDocument('<b>&'), contains('&lt;b>&amp;'));
    });
  });

  group('mXSS defenses', () {
    test('svg, math and SVG animation elements are removed with their content', () {
      final doc = html_parser.parse(
        safePreviewDocument(
          '<p>a</p><svg><style>x</style><text>t</text></svg><math><mi>m</mi></math>'
          '<animate attributeName=href values=javascript:x></animate><set attributeName=onclick to=x></set><p>b</p>',
        ),
      );
      for (final tag in ['svg', 'math', 'animate', 'set', 'style', 'mi', 'text']) {
        expect(doc.querySelectorAll(tag), isEmpty, reason: tag);
      }
      expect(doc.body!.text, 'ab');
    });

    test('the output is a fixed point: sanitising it again changes nothing', () {
      for (final html in [
        '<form><math><mtext></form><form><mglyph><style></math><img src onerror=alert(1)>',
        '<svg></p><style><a id="</style><img src=1 onerror=alert(1)>">',
        '<!DOCTYPE html><html><head><meta name=viewport content=x><title>t</title></head><body>x</body></html>',
        '<p>Merhaba</p>',
      ]) {
        final once = safePreviewDocument(html);
        expect(safePreviewDocument(once), once, reason: html);
        expect(RegExp('name="viewport"').allMatches(once), hasLength(1), reason: 'own viewport only');
      }
    });
  });

  group('cleanCss', () {
    test('plain styling is unchanged', () {
      for (final css in ['color:#6366f1;padding:8px 16px', '.btn{display:inline-block;background:#fff}', '']) {
        expect(cleanCss(css), css);
      }
    });

    test('@import dropped, remote / script url() → none, data:image url kept', () {
      expect(cleanCss('@import url(https://e.x/a.css); p{color:red}'), ' p{color:red}');
      expect(cleanCss('@IMPORT "//e.x/b.css"'), '');
      expect(cleanCss('background:url(https://e.x/p.png)'), 'background:none');
      expect(cleanCss("background:url( 'javascript:alert(1)' )"), 'background:none');
      expect(cleanCss('background:url("data:image/png;base64,AA==")'), 'background:url("data:image/png;base64,AA==")');
      expect(cleanCss('background:url(data:text/html,x)'), 'background:none');
    });

    test('expression(), behavior, -moz-binding disarmed', () {
      for (final css in ['width:expression(alert(1))', 'behavior: url(x.htc)', '-moz-binding:url(x.xml#a)']) {
        final out = cleanCss(css).toLowerCase();
        expect(out, isNot(contains('expression(')), reason: css);
        expect(out, isNot(contains('behavior:')), reason: css);
        expect(out, isNot(contains('-moz-binding:')), reason: css);
        expect(out, isNot(contains('url(')), reason: css);
      }
    });

    test('CSS escapes and comments cannot hide url( / @import', () {
      for (final css in [
        r'background:u\72l(https://e.x/a.png)',
        r'background:\75\72\6c(https://e.x/a.png)',
        'background:u/**/rl(https://e.x/a.png)',
        r'@\69mport "https://e.x/a.css";',
        r'background:url\(x)',
      ]) {
        final out = cleanCss(css).toLowerCase();
        expect(out, isNot(contains('e.x')), reason: css);
        expect(out, isNot(contains('@import')), reason: css);
      }
    });

    test('applied to style attributes and <style> blocks', () {
      final doc = html_parser.parse(
        safePreviewDocument('<style>@import "x.css";p{color:red}</style><div style="background:url(//e.x/p)">x</div>'),
      );
      expect(doc.querySelector('style')!.text, 'p{color:red}');
      expect(doc.querySelector('div')!.attributes['style'], 'background:none');
    });
  });
}
