import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/chat/chat_conversation_screen.dart';
import 'package:elly_mobile_app/widgets/chat_message_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_realtime.dart';

/// `--dart-define=VERIFY_FINDINGS=true` runs the skipped BULGU tests (they fail today, proving the finding).
const _verify = bool.fromEnvironment('VERIFY_FINDINGS');

const g1 = '11111111-1111-4111-8111-111111111111';

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

/// ChatMessageText as the user sees it, and the conversation's confirm dialog for links.
void main() {
  final bidiAny = RegExp('[\u202A-\u202E\u2066-\u2069]');

  Future<List<Uri>> pumpText(WidgetTester tester, String text, {double width = 320}) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: ChatMessageText(text, onOpenLink: opened.add)),
            ),
          ),
        ),
      ),
    );
    return opened;
  }

  /// (text, link?) of the message paragraph — the first RichText inside ChatMessageText.
  List<(String, bool)> spans(WidgetTester tester) {
    final rich = tester.widget<RichText>(
      find.descendant(of: find.byType(ChatMessageText), matching: find.byType(RichText)).first,
    );
    final out = <(String, bool)>[];
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text != null) out.add((s.text!, s.recognizer is TapGestureRecognizer));
      return true;
    });
    return out;
  }

  String shown(WidgetTester tester) => spans(tester).map((s) => s.$1).join();

  testWidgets('plain text: one span, no link; entities / controls cleaned', (tester) async {
    await pumpText(tester, 'merhaba &amp; <i>x</i>\u0007');
    expect(spans(tester), [('merhaba & <i>x</i>', false)]);
  });

  testWidgets('only http(s) is tappable; every other scheme is inert text', (tester) async {
    await pumpText(
      tester,
      'a javascript:alert(1) b data:text/html,x c intent://x d file:///etc/passwd e tel:+90555 f https://elly.dev/x g http://a.co',
    );
    final links = spans(tester).where((s) => s.$2).map((s) => s.$1).toList();
    expect(links, ['https://elly.dev/x', 'http://a.co']);
    expect(shown(tester), contains('javascript:alert(1)'));
    expect(shown(tester), contains('file:///etc/passwd'));
  });

  testWidgets('tapping a link reports the exact parsed URI; tapping text around it does nothing', (tester) async {
    final opened = await pumpText(tester, 'bak HTTPS://ELLY.DEV/Path?q=1 ve devam');
    await tester.tapOnText(find.textRange.ofSubstring('bak'));
    await tester.tapOnText(find.textRange.ofSubstring('ve devam'));
    expect(opened, isEmpty);
    await tester.tapOnText(find.textRange.ofSubstring('HTTPS://ELLY.DEV/Path?q=1'));
    expect(opened, [Uri.parse('https://elly.dev/Path?q=1')]);
    expect(opened.single.scheme, 'https');
  });

  testWidgets('punycode host is handed over as typed; a raw homograph is not a link at all', (tester) async {
    final opened = await pumpText(tester, 'xn--pple-43d.com: https://xn--pple-43d.com/login | https://аpple.com/login');
    expect(spans(tester).where((s) => s.$2).map((s) => s.$1), ['https://xn--pple-43d.com/login']);
    await tester.tapOnText(find.textRange.ofSubstring('https://xn--pple-43d.com/login'));
    expect(opened.single.host, 'xn--pple-43d.com');
    await tester.tapOnText(find.textRange.ofSubstring('https://аpple.com/login'));
    expect(opened, hasLength(1), reason: 'the Cyrillic one is plain text');
  });

  testWidgets('no raw bidi control is ever rendered — inside or outside a link — all 9 are visible markers', (
    tester,
  ) async {
    for (final c in ['\u202A', '\u202B', '\u202C', '\u202D', '\u202E', '\u2066', '\u2067', '\u2068', '\u2069']) {
      await pumpText(tester, 'abc${c}def https://a.com/${c}fdp.exe');
      expect(bidiAny.hasMatch(shown(tester)), isFalse, reason: 'U+${c.codeUnitAt(0).toRadixString(16)}');
      expect(shown(tester), contains('⟨U+'));
      expect(spans(tester).where((s) => s.$2).single.$1, 'https://a.com/', reason: 'link ends at the marker');
    }
  });

  testWidgets('a link cut by the preview is the visible prefix; the full URL appears only after "Tümünü göster"', (
    tester,
  ) async {
    final url = 'https://elly.dev/${'p' * 60}';
    final opened = await pumpText(tester, '${'a' * 990} $url');
    final previewLink = spans(tester).where((s) => s.$2).single.$1;
    expect(url, startsWith(previewLink));
    expect(previewLink.length, lessThan(url.length), reason: 'what is underlined is what is shown');
    await tester.tapOnText(find.textRange.ofSubstring(previewLink));
    expect(opened.single.toString(), previewLink);

    await tester.tap(find.text('Tümünü göster'));
    await tester.pump();
    expect(spans(tester).where((s) => s.$2).single.$1, url);
    expect(find.text('Daha az göster'), findsOneWidget);
  });

  testWidgets('emoji straddling the 1000-unit preview limit: no broken character is rendered', (tester) async {
    for (final k in [998, 999, 1000]) {
      await pumpText(tester, '${'a' * k}😀😀 tail');
      expect(tester.takeException(), isNull);
      expect(wellFormed(shown(tester)), isTrue, reason: 'k=$k');
      expect(find.text('Tümünü göster'), findsOneWidget);
    }
  });

  testWidgets(
    'a lone surrogate already in the data renders without throwing',
    (tester) async {
      for (final bad in ['a\uD83Db', 'a\uDE00b', '${'a' * 999}\uD83D', '\uD83D\uD83D\uDE00']) {
        await pumpText(tester, bad);
        expect(tester.takeException(), isNull, reason: bad.codeUnits.toString());
      }
    },
    // BULGU (düşük): safeChatText iyi biçimli olmayan UTF-16'yı (tek başına vekil) temizlemiyor; Text.rich
    // "string is not well-formed UTF-16" ArgumentError atar (release'te mesaj satırı ErrorWidget olur). Backend
    // (PostgreSQL UTF-8) bunu normalde saklamaz; yine de WS/REST'ten gelen güvenilmez metin için U+FFFD'ye çevrilmeli.
    skip: !_verify,
  );

  testWidgets('one 4000-char unbroken word (backend maximum) in a narrow bubble: collapsed and expanded, no overflow', (
    tester,
  ) async {
    await pumpText(tester, 'W' * 4000, width: 120);
    expect(tester.takeException(), isNull);
    expect(shown(tester), '${'W' * 1000}…');
    await tester.tap(find.text('Tümünü göster'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(shown(tester), 'W' * 4000);
    await tester.ensureVisible(find.text('Daha az göster'));
    await tester.tap(find.text('Daha az göster'));
    await tester.pump();
    expect(shown(tester), '${'W' * 1000}…');
  });

  testWidgets('30 lines: 20 shown + "Tümünü göster"; many blank lines cannot make a tall bubble', (tester) async {
    await pumpText(tester, List.generate(30, (i) => 'satır $i').join('\n'));
    expect(shown(tester).split('\n'), hasLength(20));
    expect(find.text('Tümünü göster'), findsOneWidget);
    final blank = await pumpText(tester, 'x${'\n' * 3000}y');
    expect(shown(tester).split('\n').length, lessThanOrEqualTo(20));
    expect(blank, isEmpty);
  });

  testWidgets(
    'U+2028 line separators cannot make a tall bubble either (clipped like "\\n")',
    (tester) async {
      await pumpText(tester, List.generate(30, (i) => 'x').join('\n'));
      final newlineHeight = tester.getSize(find.byType(ChatMessageText)).height;
      await pumpText(tester, List.generate(400, (i) => 'x').join('\u2028'));
      final separatorHeight = tester.getSize(find.byType(ChatMessageText)).height;
      expect(separatorHeight, lessThanOrEqualTo(newlineHeight * 1.2));
    },
    skip: !_verify, // BULGU (düşük): U+2028/U+2029 satır sayımına girmiyor (bkz. chat_format_untrusted_test.dart).
  );

  group('confirm dialog in the conversation shows the exact URL (no hidden host)', () {
    late FakeBackend backend;
    late AuthProvider auth;
    late FakeRealtime live;
    late List<Uri> launched;

    setUp(() {
      backend = FakeBackend();
      auth = backend.newAuth();
      live = FakeRealtime(backend);
      launched = [];
      backend.ok('/chat/tenant/t1/groups', [
        {'id': g1, 'name': 'Ekip', 'type': 'GROUP', 'visibilityLevel': 1, 'tenantId': 't1'},
      ]);
      backend.ok('/chat/tenant/t1/groups/$g1/access', {'canRead': true, 'canWrite': true});
      backend.ok('/chat/tenant/t1/groups/$g1/bans', []);
    });

    tearDown(() => live.dispose());

    Future<void> pumpConversation(WidgetTester tester, String content) async {
      backend.ok('/chat/tenant/t1/groups/$g1/messages', [
        {
          'id': 'm1',
          'groupId': g1,
          'senderType': 'ADMIN',
          'senderId': 5,
          'senderUsername': 'ayse',
          'content': content,
          'contentType': 'TEXT',
          'createdAt': '2026-10-14T09:00:00Z',
        },
      ]);
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await backend.signIn(auth, ['chat:read'], roles: const ['ADMIN'], me: {'id': 7, 'username': 'ben'});
        live.realtime.start();
        await live.chat.open(myUserId: auth.userId, myLevel: auth.roleLevel);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ...live.providers,
          ],
          child: MaterialApp(
            theme: appTheme,
            home: ChatConversationScreen(
              groupId: g1,
              launcher: (uri) async {
                launched.add(uri);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    for (final (label, content, link, dialogHas, dialogLacks) in [
      (
        'punycode',
        'login: https://xn--pple-43d.com/a',
        'https://xn--pple-43d.com/a',
        'xn--pple-43d.com',
        'pple.com/a'.replaceFirst('p', 'а'),
      ),
      (
        'userinfo',
        'https://paypal.com@evil.com/login',
        'https://paypal.com@evil.com/login',
        'paypal.com@evil.com',
        'zzz',
      ),
      ('upper-case scheme/host', 'HTTP://EVIL.COM/A', 'HTTP://EVIL.COM/A', 'http://evil.com/A', 'HTTP://'),
      ('IPv6 literal', 'http://[::1]:8080/x', 'http://[::1]:8080/x', 'http://[::1]:8080/x', 'zzz'),
      ('backslash', r'https://paypal.com\@evil.com/p', r'https://paypal.com\@evil.com/p', 'paypal.com', 'zzz'),
    ]) {
      testWidgets('$label: the dialog shows what will open; cancel opens nothing; confirm opens exactly that', (
        tester,
      ) async {
        await pumpConversation(tester, content);
        await tester.tapOnText(find.textRange.ofSubstring(link));
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        final message = tester
            .widgetList<Text>(find.descendant(of: dialog, matching: find.byType(Text)))
            .map((t) => t.data ?? '')
            .join('\n');
        expect(message, contains(dialogHas));
        expect(message, isNot(contains(dialogLacks)));
        expect(message, contains('tarayıcıda açılacak'));
        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();
        expect(launched, isEmpty);

        await tester.tapOnText(find.textRange.ofSubstring(link));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
        await tester.pumpAndSettle();
        expect(launched, [Uri.parse(link)]);
      });
    }

    testWidgets('a message that only LOOKS like a link (other scheme / homograph) opens no dialog', (tester) async {
      await pumpConversation(tester, 'javascript:alert(1) intent://x https://аpple.com tel:+90555');
      for (final part in ['javascript:alert(1)', 'intent://x', 'https://аpple.com', 'tel:+90555']) {
        await tester.tapOnText(find.textRange.ofSubstring(part));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing, reason: part);
      }
      expect(launched, isEmpty);
    });
  });
}
