import 'dart:math';

import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/chat_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Untrusted chat text rules beyond `chat_format_test.dart`: every bidi / control code point, encoded forms,
/// surrogate-safe clipping at every boundary, link detection as a property (only ASCII http(s), the opened URL is
/// exactly the visible text), upload-path pattern edge cases.
void main() {
  const bidi = ['\u202A', '\u202B', '\u202C', '\u202D', '\u202E', '\u2066', '\u2067', '\u2068', '\u2069'];
  final bidiAny = RegExp('[\u202A-\u202E\u2066-\u2069]');

  /// No unpaired UTF-16 surrogate (what would crash selectable / editable text, Phase 4 clipText bug).
  bool wellFormed(String s) {
    final u = s.codeUnits;
    for (var i = 0; i < u.length; i++) {
      final c = u[i];
      if (c >= 0xD800 && c <= 0xDBFF) {
        if (i + 1 >= u.length || u[i + 1] < 0xDC00 || u[i + 1] > 0xDFFF) return false;
        i++;
      } else if (c >= 0xDC00 && c <= 0xDFFF) {
        return false;
      }
    }
    return true;
  }

  group('safeChatText: bidi and control characters', () {
    test('each of the 9 bidi controls becomes a visible ⟨U+XXXX⟩ marker, in any position', () {
      for (final c in bidi) {
        final hex = c.codeUnitAt(0).toRadixString(16).toUpperCase();
        expect(safeChatText('a${c}b'), 'a⟨U+$hex⟩b');
        expect(safeChatText(c), '⟨U+$hex⟩');
        expect(safeChatText('$c$c'), '⟨U+$hex⟩⟨U+$hex⟩');
        expect(safeChatText('x&#x${hex.toLowerCase()};y'), 'x⟨U+$hex⟩y', reason: 'entity-encoded $hex');
        expect(safeChatText('x&#${c.codeUnitAt(0)};y'), 'x⟨U+$hex⟩y', reason: 'decimal entity $hex');
      }
    });

    test('no raw bidi control survives anything, even a mix of entities, controls and text', () {
      final rnd = Random(7);
      const pieces = [
        'a',
        ' ',
        '\n',
        '&#x202e;',
        '&amp;',
        '&#8238;',
        '\u202E',
        '\u2066',
        '\u0000',
        '&lt;',
        '\u0085',
        'é',
        '😀',
      ];
      for (var i = 0; i < 500; i++) {
        final text = List.generate(rnd.nextInt(40), (_) => pieces[rnd.nextInt(pieces.length)]).join();
        expect(bidiAny.hasMatch(safeChatText(text)), isFalse, reason: text);
      }
    });

    test('C0 (except tab / LF / CR→LF), DEL and C1 are dropped — raw and entity-encoded', () {
      for (var c = 0; c <= 0x9F; c++) {
        if ((c > 0x1F && c < 0x7F)) continue;
        final raw = String.fromCharCode(c);
        final keeps = c == 0x09 || c == 0x0A || c == 0x0D;
        final out = safeChatText('a${raw}b');
        expect(out, keeps ? (c == 0x0D ? 'a\nb' : 'a${raw}b') : 'ab', reason: 'U+${c.toRadixString(16)}');
        if (c != 0) {
          expect(safeChatText('a&#$c;b'), keeps ? (c == 0x0D ? 'a\nb' : 'a${raw}b') : 'ab', reason: 'entity &#$c;');
        }
      }
    });

    test('entities are decoded exactly once; literal look-alikes stay literal', () {
      expect(safeChatText('&amp;#x202E;'), '&#x202E;', reason: 'not a bidi control, just the text the sender typed');
      expect(safeChatText('&amp;lt;script&amp;gt;'), '&lt;script&gt;');
      expect(safeChatText('&#x00000041;'), '&#x00000041;', reason: 'over-long numeric entity is not decoded');
      expect(safeChatText('&AMP; &Lt; &#65 &#;'), '&AMP; &Lt; &#65 &#;');
      expect(safeChatText('&#xFFFFFF; &#x110000; &#xD800; &#xDFFF; &#0;'), '� � � � �');
      expect(safeChatText('&#x1F600;'), '😀');
    });

    test('invalid code points never produce a lone surrogate', () {
      for (final e in ['&#xD800;', '&#xDBFF;', '&#xDC00;', '&#xDFFF;', '&#55357;', '&#56832;', '&#1114112;']) {
        expect(wellFormed(safeChatText('a${e}b')), isTrue, reason: e);
      }
    });

    test('zero-width characters pass through as is but never become part of a link', () {
      const zw = ['\u200B', '\u200C', '\u200D', '\u2060', '\uFEFF'];
      for (final c in zw) {
        expect(safeChatText('a${c}b'), 'a${c}b');
        final segments = linkSegments(safeChatText('https://a.com$c.evil.com/x'));
        final link = segments.firstWhere((s) => s.$2 != null);
        expect(
          link.$1,
          'https://a.com',
          reason: 'the link ends at the zero-width char (U+${c.codeUnitAt(0).toRadixString(16)})',
        );
        expect(link.$2!.host, 'a.com');
      }
    });

    test('a 4000-character worst-case message is processed instantly', () {
      final sw = Stopwatch()..start();
      final hostile = '&#x202E;&amp;\u0000http://' * 300;
      for (var i = 0; i < 20; i++) {
        final (clipped, _) = clipChatText(safeChatText(hostile));
        linkSegments(clipped);
      }
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test(
      'U+2028 / U+2029 are line breaks to the renderer: they must count as lines when clipping',
      () {
        final text = List.generate(30, (i) => 'satır $i').join('\u2028');
        final (clipped, cut) = clipChatText(safeChatText(text));
        expect(cut, isTrue);
        expect(RegExp('[\n\u2028\u2029]').allMatches(clipped).length, lessThan(20));
      },
    );
  });

  group('clipChatText: surrogate-safe at every boundary', () {
    final emoji = ['😀', '👍🏽', '👨\u200D👩\u200D👧', '🇹🇷', '𝒜', '😀😀😀'];

    for (final max in [1000, 140, 10]) {
      test('emoji / ZWJ / flags / astral chars straddling maxChars=$max never leave a lone surrogate', () {
        for (final e in emoji) {
          for (var k = max - 8; k <= max + 2; k++) {
            if (k < 0) continue;
            final text = '${'a' * k}$e${'b' * 20}';
            final (out, cut) = clipChatText(text, maxChars: max);
            expect(wellFormed(out), isTrue, reason: 'k=$k emoji=${e.codeUnits}');
            if (text.length > max) {
              expect(cut, isTrue);
              expect(out.length, lessThanOrEqualTo(max + 1), reason: 'at most maxChars + "…"');
              expect(out.endsWith('…'), isTrue);
            }
          }
        }
      });
    }

    test('text made only of astral characters is cut on a pair boundary at both parities', () {
      for (final prefix in ['', 'a']) {
        final text = prefix + '😀' * 800;
        final (out, cut) = clipChatText(text);
        expect(cut, isTrue);
        expect(wellFormed(out), isTrue);
        expect(out.length, lessThanOrEqualTo(1001));
      }
    });

    test('the "cut" flag and limits are exact: 1000 chars / 20 lines pass, one more does not', () {
      expect(clipChatText('a' * 1000), ('a' * 1000, false));
      expect(clipChatText('a' * 1001).$2, isTrue);
      final twenty = List.filled(20, 'x').join('\n');
      expect(clipChatText(twenty), (twenty, false));
      expect(clipChatText('$twenty\nx').$2, isTrue);
      expect(clipChatText('\n' * 5000).$2, isTrue);
      expect(clipChatText('\n' * 5000).$1.length, lessThan(30));
      expect(clipChatText('').$2, isFalse);
    });

    test('one huge unbroken word is cut fast and ends with the ellipsis; trailing blanks never precede it', () {
      final (out, cut) = clipChatText('W' * 1000000);
      expect(cut, isTrue);
      expect(out, '${'W' * 1000}…');
      final (spaced, _) = clipChatText('${'a' * 990}${' ' * 30}tail');
      expect(spaced, '${'a' * 990}…');
    });

    test('malformed input (a lone surrogate already in the text) does not throw', () {
      for (final bad in [
        '\uD83D',
        '\uDE00',
        'a\uD83D',
        '${'a' * 999}\uD83D',
        '${'a' * 999}\uD83Db',
        '\uDE00${'a' * 1200}',
      ]) {
        expect(() => clipChatText(bad), returnsNormally, reason: bad.codeUnits.toString());
        expect(() => safeChatText(bad), returnsNormally);
      }
    });

    test('banner clipping (140 chars / 2 lines) of an untrusted title + message stays well-formed and bidi-free', () {
      final text = safeChatText(['${'a' * 130}\u202E😀😀😀', 'm\nn\no'].join(': '));
      final (out, _) = clipChatText(text, maxChars: 140, maxLines: 2);
      expect(wellFormed(out), isTrue);
      expect(bidiAny.hasMatch(out), isFalse);
      expect(out.split('\n').length, lessThanOrEqualTo(2));
    });
  });

  group('linkSegments: only ASCII http(s), and the opened URL is exactly the visible text', () {
    bool hasLink(String text) => linkSegments(text).any((s) => s.$2 != null);

    test('every other scheme is plain text — any case, any wrapper', () {
      const schemes = [
        'javascript:alert(1)',
        'JaVaScRiPt:alert(1)',
        'java\nscript:alert(1)',
        'javascript://example.com/%0Aalert(1)',
        'vbscript:msgbox(1)',
        'data:text/html,<script>alert(1)</script>',
        'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==',
        'intent://scan/#Intent;scheme=zxing;end',
        'intent:#Intent;action=android.intent.action.VIEW;end',
        'file:///etc/passwd',
        'FILE://host/share',
        'tel:+905551112233',
        'mailto:a@b.co',
        'sms:+90555?body=x',
        'ftp://x.com/a',
        'ws://x.com',
        'wss://x.com',
        'content://com.android.contacts',
        'market://details?id=x',
        'itms-services://?action=download-manifest&url=x',
        'blob:null/5f9d1f0e-aaaa-bbbb-cccc-0123456789ab',
        'about:blank',
        'view-source:x',
        'chrome://settings',
        'whatsapp://send?text=x',
        'tg://resolve?domain=x',
        'otpauth://totp/x?secret=ABC',
        '//evil.com/x',
        'www.evil.com',
        'evil.com/login',
      ];
      for (final s in schemes) {
        for (final text in [s, 'bak $s sonra', '($s)', '$s.', '"$s"']) {
          expect(hasLink(text), isFalse, reason: text);
        }
      }
    });

    test('malformed http(s) is plain text: no host, wrong separators, spaces, full-width punctuation', () {
      for (final s in [
        'http://',
        'https://',
        'http:///x.com',
        'http://:80/x',
        'http:/x.com',
        'http//x.com',
        'hxxp://x.com',
        'h t t p://x.com',
        'https ://x.com',
        'https:// x.com',
        'https：//x.com',
        'https:／／x.com',
        'ｈｔｔｐｓ://x.com',
      ]) {
        expect(hasLink(s), isFalse, reason: s);
      }
    });

    test(
      'a link stops at the first non-ASCII / space / quote / angle bracket: the opened URL is only the ASCII prefix',
      () {
        Uri? only(String t) => linkSegments(t).firstWhere((s) => s.$2 != null).$2;
        expect(only('https://evil。com/x'), Uri.parse('https://evil'));
        expect(only('https://exаmple.com/x'), Uri.parse('https://ex'));
        expect(only('https://a.com/ü'), Uri.parse('https://a.com/'));
        expect(only('https://a.com/x"y'), Uri.parse('https://a.com/x'));
        expect(only('<https://a.com>'), Uri.parse('https://a.com'));
        expect(only('https://a.com/a b'), Uri.parse('https://a.com/a'));
        expect(only('https://a.com\n/b'), Uri.parse('https://a.com'));
        expect(only('https://a.com/\u202Ex'), Uri.parse('https://a.com/'));
      },
    );

    test('bidi controls of a link\'s surroundings are markers by then: no raw bidi in any segment', () {
      for (final c in bidi) {
        final segments = linkSegments(safeChatText('x https://a.com/${c}fdp.exe y'));
        expect(segments.any((s) => bidiAny.hasMatch(s.$1)), isFalse);
        expect(segments.firstWhere((s) => s.$2 != null).$1, 'https://a.com/');
      }
    });

    test('punycode host stays as typed (no Unicode conversion that could hide the look-alike)', () {
      final link = linkSegments('https://xn--pple-43d.com/login').single;
      expect(link.$1, 'https://xn--pple-43d.com/login');
      expect(link.$2!.host, 'xn--pple-43d.com');
      expect(link.$2.toString(), 'https://xn--pple-43d.com/login');
      expect(
        linkSegments('https://аpple.com').every((s) => s.$2 == null),
        isTrue,
        reason: 'raw Cyrillic is not a link',
      );
    });

    test('userinfo ("https://paypal.com@evil.com") is part of the shown text; the host is the real one', () {
      final link = linkSegments('https://paypal.com@evil.com/login').single;
      expect(link.$1, 'https://paypal.com@evil.com/login');
      expect(link.$2!.host, 'evil.com');
      expect(link.$2!.userInfo, 'paypal.com');
    });

    test('property: random hostile text — segments rebuild the input; every link is ASCII http(s) with a host', () {
      final rnd = Random(99);
      const pieces = [
        'http://',
        'https://',
        'HTTPS://',
        'javascript:',
        'a.com',
        'ünï.com',
        'xn--abc.com',
        '/p?q=1&r=2#f',
        ' ',
        '\n',
        '\u202E',
        '\u200B',
        '"',
        "'",
        '(',
        ')',
        '.',
        ',',
        '@',
        '[::1]',
        ':8080',
        '%41',
        '\\',
        '<',
        '>',
        '😀',
        '。',
        'データ',
      ];
      for (var i = 0; i < 3000; i++) {
        final text = List.generate(rnd.nextInt(14), (_) => pieces[rnd.nextInt(pieces.length)]).join();
        final segments = linkSegments(text);
        expect(segments.map((s) => s.$1).join(), text, reason: 'lossless: $text');
        for (final (raw, uri) in segments) {
          if (uri == null) continue;
          expect(raw, matches(RegExp(r'^https?://', caseSensitive: false)), reason: text);
          expect(raw.codeUnits.every((c) => c > 0x20 && c < 0x7F), isTrue, reason: 'ASCII printable only: $raw');
          expect(const ['http', 'https'], contains(uri.scheme), reason: text);
          expect(uri.host, isNotEmpty, reason: text);
          expect(raw.contains(RegExp('["<>]')), isFalse, reason: raw);
          expect(Uri.parse(raw), uri, reason: 'the URL opened is the one shown');
        }
      }
    });

    test('pathological repetition is linear: 5000 "http://" and one 100k-char URL', () {
      final sw = Stopwatch()..start();
      expect(linkSegments('http://' * 5000).map((s) => s.$1).join(), 'http://' * 5000);
      expect(linkSegments('https://a.com/${'x' * 100000}').where((s) => s.$2 != null), hasLength(1));
      expect(linkSegments('${'https://' * 2000}a.com'), isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('chatFilePath / chatFileUrl: only our own upload paths', () {
    String? file(String content, {String? fileUrl, String type = 'FILE'}) =>
        chatFilePath(contentType: type, fileUrl: fileUrl, content: content);

    test('valid shapes', () {
      for (final p in ['assets/chat/a.png', 'assets/chat/2026/10/x_y-z.PDF', 'assets/x', 'assets/a/b/c/d.tar.gz']) {
        expect(file(p), p);
        expect(file('  $p\n'), p, reason: 'content is trimmed');
        expect(file('ignored', fileUrl: p), p);
      }
    });

    test('everything else is shown as text, not as a file', () {
      for (final p in [
        '',
        ' ',
        'assets',
        'assets/',
        '/assets/chat/a.png',
        'ASSETS/chat/a.png',
        'Assets/chat/a.png',
        'xassets/chat/a.png',
        'assets\\chat\\a.png',
        'assets/chat/../a.png',
        'assets/../etc/passwd',
        'assets/chat/..',
        'assets/chat/a..png',
        'assets/chat/%2e%2e/a',
        'assets/chat/a%2Fb',
        'assets/chat/a b.png',
        'assets/chat/a\tb',
        'assets/chat/a\nb.png',
        'assets/chat/a\u0000.png',
        'assets/chat/a?x=1',
        'assets/chat/a#x',
        'assets/chat/a;b',
        'assets/chat/é.png',
        'assets/chat/ａ.png',
        'assets/chat/a\u202Egnp.exe',
        'assets/chat/a\u200B.png',
        'file:///assets/chat/a.png',
        'https://evil.com/assets/chat/a.png',
        '//evil.com/assets/chat/a.png',
        'javascript:alert(1)//assets/chat/a.png',
        'data:text/html,assets/chat/a.png',
      ]) {
        expect(file(p), isNull, reason: p.codeUnits.toString());
      }
    });

    test('an invalid fileUrl wins over a valid content (fail-closed); only FILE / IMAGE are files', () {
      expect(file('assets/chat/ok.png', fileUrl: 'https://evil.com/x.png'), isNull);
      expect(file('assets/chat/ok.png', fileUrl: ' assets/chat/ok.png'), isNull, reason: 'fileUrl is not trimmed');
      expect(
        file('assets/chat/ok.png', fileUrl: ''),
        'assets/chat/ok.png',
        reason: 'empty fileUrl falls back to content',
      );
      for (final t in ['TEXT', 'SYSTEM', 'image', 'file', '', 'FILE ']) {
        expect(file('assets/chat/ok.png', type: t), isNull, reason: t);
      }
      expect(file('assets/chat/ok.png', type: 'IMAGE'), 'assets/chat/ok.png');
    });

    test('every accepted path resolves on the API origin under /assets/ — never another host', () {
      final origin = Uri.parse(ApiService.baseUrl).origin;
      for (final p in ['assets/chat/a.png', 'assets//evil.com/x', 'assets/./x', 'assets/chat/a.b.c']) {
        final path = file(p)!;
        final uri = Uri.parse(chatFileUrl(path));
        expect(uri.origin, origin, reason: p);
        expect(uri.path, startsWith('/assets/'), reason: p);
        expect(uri.userInfo, isEmpty);
      }
    });

    test('image detection: by extension only, SVG / double extension / query are not images', () {
      expect(isImagePath('assets/chat/a.png'), isTrue);
      expect(isImagePath('assets/chat/a.JPG'), isTrue);
      expect(isImagePath('assets/chat/a.webp'), isTrue);
      expect(isImagePath('assets/chat/a.avif'), isTrue);
      for (final p in [
        'assets/chat/a.svg',
        'assets/chat/a.svgz',
        'assets/chat/a.png.exe',
        'assets/chat/a.html',
        'assets/chat/png',
        'assets/chat/a.png?x',
      ]) {
        expect(isImagePath(p), isFalse, reason: p);
      }
    });
  });
}
