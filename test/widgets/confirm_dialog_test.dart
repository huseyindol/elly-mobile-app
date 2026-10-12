import 'package:elly_mobile_app/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Future<bool>> open(WidgetTester tester, {bool destructive = false}) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showConfirmDialog(
              context,
              title: 'Silinsin mi?',
              message: '"X" kalıcı olarak silinecek.',
              confirmLabel: 'Sil',
              destructive: destructive,
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

  Color? confirmColor(WidgetTester tester) => tester
      .widget<ElevatedButton>(find.byKey(const ValueKey('confirm_dialog_button')))
      .style
      ?.backgroundColor
      ?.resolve({});

  testWidgets('confirm → true', (tester) async {
    final result = await open(tester);
    expect(find.text('Silinsin mi?'), findsOneWidget);

    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel → false', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('barrier dismiss → false', (tester) async {
    final result = await open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('destructive variant has a red confirm button', (tester) async {
    await open(tester, destructive: true);
    expect(confirmColor(tester), Colors.redAccent);
  });

  testWidgets('default variant is not red', (tester) async {
    await open(tester);
    expect(confirmColor(tester), isNot(Colors.redAccent));
  });
}
