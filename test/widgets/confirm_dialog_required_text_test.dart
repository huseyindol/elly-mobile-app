import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `showConfirmDialog(requiredText:)` (admin `DestructiveConfirmDialog`): the confirm button unlocks only on the
/// exact text. Comparison rule in code: `typed.trim() == requiredText` - case sensitive, inner characters exact.
void main() {
  const key = 'welcome-mail';
  const confirmKey = ValueKey('confirm_dialog_button');
  const textKey = ValueKey('confirm_dialog_text');

  Future<Future<bool>> open(WidgetTester tester, {String? required = key}) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showConfirmDialog(
              context,
              title: 'Template silinsin mi?',
              message: 'Kalıcı olarak silinecek.',
              confirmLabel: 'Sil',
              destructive: true,
              requiredText: required,
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    return result;
  }

  bool enabled(WidgetTester tester) => tester.widget<ElevatedButton>(find.byKey(confirmKey)).onPressed != null;

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(textKey), text);
    await tester.pump();
  }

  testWidgets('opens locked, with the text field focused and the required text in the label', (tester) async {
    await open(tester);
    expect(enabled(tester), isFalse);
    expect(find.text('Onaylamak için "$key" yazın'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(textKey));
    expect(field.autofocus, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('wrong text keeps it locked: partial, longer, other case, inner spaces, look-alike characters', (
    tester,
  ) async {
    await open(tester);
    for (final wrong in [
      '',
      ' ',
      'w',
      'welcome',
      'welcome-mai',
      'elcome-mail',
      'welcome-mail2',
      'xwelcome-mail',
      'welcome-mail welcome-mail',
      'Welcome-mail',
      'WELCOME-MAIL',
      'welcome-Mail',
      'welcome mail',
      'welcome- mail',
      'wel come-mail',
      'welcome_mail',
      'welcome–mail', // en dash
      'welcome‑mail', // non-breaking hyphen
      'wеlcome-mail', // Cyrillic е
      'welcome-mail​', // zero-width space
      '​welcome-mail',
      'welcome-mail\u0000',
    ]) {
      await type(tester, wrong);
      expect(enabled(tester), isFalse, reason: 'typed "${wrong.replaceAll('​', '<ZWSP>')}"');
    }
  });

  testWidgets('only leading / trailing whitespace around the exact text is tolerated', (tester) async {
    await open(tester);
    for (final ok in [key, ' $key', '$key ', '  $key  ', '\t$key']) {
      await type(tester, ok);
      expect(enabled(tester), isTrue, reason: '"$ok"');
    }
  });

  testWidgets('the lock comes back when the text stops matching', (tester) async {
    await open(tester);
    await type(tester, key);
    expect(enabled(tester), isTrue);
    await type(tester, 'welcome-mai');
    expect(enabled(tester), isFalse);
    await type(tester, key);
    expect(enabled(tester), isTrue);
    await type(tester, '');
    expect(enabled(tester), isFalse);
  });

  testWidgets('tapping the locked button does nothing: dialog stays open, no result', (tester) async {
    final result = await open(tester);
    await type(tester, 'Welcome-Mail');
    await tester.tap(find.byKey(confirmKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Template silinsin mi?'), findsOneWidget);

    var completed = false;
    unawaited(result.then((_) => completed = true));
    await tester.pump();
    expect(completed, isFalse);

    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('exact text → confirm returns true', (tester) async {
    final result = await open(tester);
    await type(tester, ' $key ');
    await tester.tap(find.byKey(confirmKey));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel and barrier dismiss are false even when the right text was typed', (tester) async {
    var result = await open(tester);
    await type(tester, key);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);

    result = await open(tester);
    await type(tester, key);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('regex characters in the required text are literal', (tester) async {
    await open(tester, required: 'a.b*(c)');
    await type(tester, 'axb*(c)');
    expect(enabled(tester), isFalse);
    await type(tester, 'a.b*(c)');
    expect(enabled(tester), isTrue);
  });

  testWidgets('Turkish dotted / dotless i is not folded (exact, case-sensitive)', (tester) async {
    await open(tester, required: 'İstanbul-şablonu');
    for (final wrong in ['istanbul-şablonu', 'Istanbul-şablonu', 'ISTANBUL-ŞABLONU', 'İstanbul-Şablonu']) {
      await type(tester, wrong);
      expect(enabled(tester), isFalse, reason: wrong);
    }
    await type(tester, 'İstanbul-şablonu');
    expect(enabled(tester), isTrue);
  });

  testWidgets('without requiredText there is no text field and confirm is enabled at once', (tester) async {
    await open(tester, required: null);
    expect(find.byKey(textKey), findsNothing);
    expect(enabled(tester), isTrue);
  });

  testWidgets('a fresh dialog starts empty (typed text is not carried over)', (tester) async {
    var result = await open(tester);
    await type(tester, key);
    await tester.tap(find.byKey(confirmKey));
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    result = await open(tester);
    expect(tester.widget<TextField>(find.byKey(textKey)).controller?.text ?? '', isEmpty);
    expect(enabled(tester), isFalse);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}

void unawaited(Future<void> f) {}
