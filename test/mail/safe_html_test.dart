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
}
