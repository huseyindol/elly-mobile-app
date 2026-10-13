import 'package:elly_mobile_app/widgets/rich_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';

const _warning = ValueKey('rich_text_warning');
const _raw = ValueKey('rich_text_raw');
const _modeButton = ValueKey('rich_text_mode_button');

void main() {
  late FakeBackend backend;
  final key = GlobalKey<RichTextFieldState>();

  setUp(() => backend = FakeBackend());

  Future<void> pumpField(WidgetTester tester, String html, {bool canPickAssets = false}) async {
    // Wide enough for the whole (horizontally scrolling) toolbar, so the image button is hit-testable.
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichTextField(
              key: key,
              label: 'İçerik',
              initialHtml: html,
              api: backend.api,
              canPickAssets: canPickAssets,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String rawText(WidgetTester tester) => tester.widget<TextField>(find.byKey(_raw)).controller!.text;

  QuillController quill(WidgetTester tester) => tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  /// The editor leaves caret/focus timers behind.
  Future<void> drain(WidgetTester tester) => tester.pump(const Duration(seconds: 5));

  group('raw HTML fallback', () {
    const unsupported = '<p>x</p>\n<table class="t"><tr><td onclick="a()">1</td></tr></table>\n<script>go()</script>';

    testWidgets('unsupported body: warning + raw editor with the exact bytes; html getter returns them', (
      tester,
    ) async {
      await pumpField(tester, unsupported);

      expect(find.byKey(_warning), findsOneWidget);
      expect(find.byKey(_raw), findsOneWidget);
      expect(find.byType(QuillEditor), findsNothing);
      expect(rawText(tester), unsupported);
      expect(key.currentState!.isRawMode, isTrue);
      expect(key.currentState!.html, unsupported);
      expect(find.textContaining('ham HTML'), findsOneWidget, reason: 'warning explains why');
    });

    testWidgets('pretty-printed body (newline between blocks) is conservatively kept as raw HTML', (tester) async {
      const html = '<p>a</p>\n<p>b</p>';
      await pumpField(tester, html);

      expect(key.currentState!.isRawMode, isTrue, reason: 'text would change on conversion ("a b" vs "ab")');
      expect(find.byKey(_warning), findsOneWidget);
      expect(key.currentState!.html, html);
    });

    testWidgets('warning names the reason', (tester) async {
      await pumpField(tester, '<div>x</div>');
      expect(find.descendant(of: find.byKey(_warning), matching: find.textContaining('<div>')), findsOneWidget);
    });

    testWidgets('typing in raw mode changes the saved html verbatim (no normalisation)', (tester) async {
      await pumpField(tester, unsupported);
      const edited = '<div style="a">  raw   <b>x</b>\n</div>';
      await tester.enterText(find.byKey(_raw), edited);

      expect(key.currentState!.html, edited);
    });

    testWidgets('switching to the editor while still unsupported is refused and stays in raw mode', (tester) async {
      await pumpField(tester, unsupported);
      await tester.tap(find.byKey(_modeButton));
      await tester.pump();

      expect(find.textContaining('Editörde açılamaz'), findsOneWidget);
      expect(key.currentState!.isRawMode, isTrue);
      expect(find.byType(QuillEditor), findsNothing);
      expect(key.currentState!.html, unsupported);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('after cleaning the markup the switch opens the editor and drops the warning', (tester) async {
      await pumpField(tester, unsupported);
      const clean = '<h2>Başlık</h2><p>metin</p>';
      await tester.enterText(find.byKey(_raw), clean);
      await tester.tap(find.byKey(_modeButton));
      await tester.pump();

      expect(key.currentState!.isRawMode, isFalse);
      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.byKey(_warning), findsNothing);
      expect(key.currentState!.html, clean, reason: 'untouched after the switch → saved as typed');
      await drain(tester);
    });

    testWidgets('empty raw body switches to the editor', (tester) async {
      await pumpField(tester, '<table></table>');
      await tester.enterText(find.byKey(_raw), '');
      await tester.tap(find.byKey(_modeButton));
      await tester.pump();

      expect(key.currentState!.isRawMode, isFalse);
      expect(key.currentState!.html, '');
      await drain(tester);
    });
  });

  group('editor mode', () {
    testWidgets('Tiptap body opens in the editor without a warning', (tester) async {
      await pumpField(tester, '<h2>Başlık</h2><p>Merhaba <strong>dünya</strong></p>');

      expect(find.byType(QuillEditor), findsOneWidget);
      expect(find.byKey(_warning), findsNothing);
      expect(find.byKey(_raw), findsNothing);
      expect(key.currentState!.isRawMode, isFalse);
      await drain(tester);
    });

    testWidgets('untouched body is returned byte-for-byte, even when not in canonical Tiptap form', (tester) async {
      const html = '<ul><li>x</li></ul><p>b&nbsp;c</p>';
      await pumpField(tester, html);

      expect(key.currentState!.isRawMode, isFalse);
      expect(key.currentState!.html, html);
      await drain(tester);
    });

    testWidgets('empty body: editor, html stays empty', (tester) async {
      await pumpField(tester, '');
      expect(key.currentState!.isRawMode, isFalse);
      expect(key.currentState!.html, '');
      await drain(tester);
    });

    testWidgets('an edit turns the body into normalised Tiptap HTML', (tester) async {
      await pumpField(tester, '<p>a</p><ul><li>x</li></ul>');
      quill(tester).replaceText(1, 0, 'ZZ', null);
      await tester.pump();

      expect(key.currentState!.html, '<p>aZZ</p><ul><li><p>x</p></li></ul>');
      await drain(tester);
    });

    testWidgets('mode button: editor → HTML shows the untouched source, then HTML → editor reopens', (tester) async {
      const html = '<p>a</p><ul><li>b</li></ul>';
      await pumpField(tester, html);
      await tester.tap(find.byKey(_modeButton));
      await tester.pump();

      expect(key.currentState!.isRawMode, isTrue);
      expect(rawText(tester), html);
      expect(find.byKey(_warning), findsNothing, reason: 'user-chosen raw mode is not a warning case');

      await tester.tap(find.byKey(_modeButton));
      await tester.pump();
      expect(key.currentState!.isRawMode, isFalse);
      expect(key.currentState!.html, html);
      await drain(tester);
    });

    testWidgets('editor → HTML after an edit shows the normalised HTML', (tester) async {
      await pumpField(tester, '<p>a</p>');
      quill(tester).replaceText(1, 0, 'b', null);
      await tester.tap(find.byKey(_modeButton));
      await tester.pump();

      expect(rawText(tester), '<p>ab</p>');
      expect(key.currentState!.html, '<p>ab</p>');
      await drain(tester);
    });
  });

  group('image insertion', () {
    Future<void> openImageDialog(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Görsel ekle'));
      await tester.pumpAndSettle();
    }

    // BUG (reported): the alt text typed in the dialog never reaches the document — the `alt` attribute is
    // created with AttributeScope.ignore, which formatText does not apply.
    testWidgets('URL + alt are inserted as a Tiptap img', (tester) async {
      await pumpField(tester, '');
      await openImageDialog(tester);
      await tester.enterText(find.byKey(const ValueKey('rich_image_url')), ' https://api.example.com/assets/t/a.png ');
      await tester.enterText(find.byKey(const ValueKey('rich_image_alt')), 'Kapak görseli');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich_image_insert')));
      await tester.pumpAndSettle();

      expect(
        key.currentState!.html,
        '<img loading="lazy" class="tiptap-img" src="https://api.example.com/assets/t/a.png" alt="Kapak görseli">',
      );
      await drain(tester);
    });

    // BUG (reported): inserting at the caret of a non-empty line puts the embed in the same Delta line as the
    // text; opsToHtml only writes an image for a line that is a lone embed, so the image is silently dropped.
    for (final (name, caret) in [
      ('start of a text line', 0),
      ('middle of a text line', 2),
      ('end of a text line', 4),
    ]) {
      testWidgets('image inserted at the $name is kept in the saved html', (tester) async {
        await pumpField(tester, '<p>önce</p><p>sonra</p>');
        quill(tester).updateSelection(TextSelection.collapsed(offset: caret), ChangeSource.local);
        await openImageDialog(tester);
        await tester.enterText(find.byKey(const ValueKey('rich_image_url')), 'https://x.y/a.png');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('rich_image_insert')));
        await tester.pumpAndSettle();

        final html = key.currentState!.html;
        expect(html, contains('src="https://x.y/a.png"'));
        // A block image splits the line at the caret (like Tiptap); no text is lost.
        final text = html.replaceAll(RegExp('<[^>]+>'), '');
        expect(text, 'öncesonra');
        expect(RegExp('<img ').allMatches(html), hasLength(1));
        await drain(tester);
      });
    }

    testWidgets('URL only: img without alt', (tester) async {
      await pumpField(tester, '');
      await openImageDialog(tester);
      await tester.enterText(find.byKey(const ValueKey('rich_image_url')), 'https://x.y/a.png');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich_image_insert')));
      await tester.pumpAndSettle();

      expect(key.currentState!.html, contains('src="https://x.y/a.png">'));
      expect(key.currentState!.html, isNot(contains('alt=')));
      await drain(tester);
    });

    testWidgets('Ekle is disabled until a URL is typed', (tester) async {
      await pumpField(tester, '');
      await openImageDialog(tester);
      FilledButton insert() => tester.widget<FilledButton>(find.byKey(const ValueKey('rich_image_insert')));

      expect(insert().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('rich_image_url')), '   ');
      await tester.pump();
      expect(insert().onPressed, isNull, reason: 'blank is not a URL');
      await tester.enterText(find.byKey(const ValueKey('rich_image_url')), 'https://x.y/a.png');
      await tester.pump();
      expect(insert().onPressed, isNotNull);
      await drain(tester);
    });

    testWidgets('cancel leaves the body untouched (byte-for-byte)', (tester) async {
      const html = '<p>a</p><ul><li>b</li></ul>';
      await pumpField(tester, html);
      await openImageDialog(tester);
      await tester.enterText(find.byKey(const ValueKey('rich_image_url')), 'https://x.y/a.png');
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(key.currentState!.html, html);
      await drain(tester);
    });

    testWidgets('"Assetlerden seç" only with assets:read', (tester) async {
      await pumpField(tester, '');
      await openImageDialog(tester);
      expect(find.text('Assetlerden seç'), findsNothing);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      await drain(tester);

      await pumpField(tester, '<p>x</p>', canPickAssets: true);
      await openImageDialog(tester);
      expect(find.text('Assetlerden seç'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('an inserted image survives the HTML round trip (re-opens in the editor)', (tester) async {
      await pumpField(tester, '');
      await openImageDialog(tester);
      await tester.enterText(find.byKey(const ValueKey('rich_image_url')), 'https://x.y/a.png');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich_image_insert')));
      await tester.pumpAndSettle();
      final saved = key.currentState!.html;
      expect(saved, contains('<img '));

      await pumpField(tester, saved);
      expect(find.byKey(_warning), findsNothing);
      expect(key.currentState!.isRawMode, isFalse);
      expect(key.currentState!.html, saved);
      await drain(tester);
    });
  });
}
