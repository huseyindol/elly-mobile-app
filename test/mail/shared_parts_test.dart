import 'package:elly_mobile_app/widgets/confirm_dialog.dart';
import 'package:elly_mobile_app/widgets/searchable_paged_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';

/// Shared pieces extended for the communication screens: 204 responses, typed confirmation, list onLoad.
void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend());

  group('ApiService', () {
    test('204 No Content is a success with no data', () async {
      backend.routes['/email-templates/a'] = (_) => http.Response('', 204);
      expect(await backend.api.delete('/email-templates/a'), isNull);
    });

    test('other empty responses are still errors', () async {
      backend.routes['/x'] = (_) => http.Response('', 200);
      await expectLater(backend.api.get('/x'), throwsA(isA<Object>()));
    });
  });

  group('showConfirmDialog(requiredText:)', () {
    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showConfirmDialog(
                context,
                title: 'Sil',
                message: 'Kalıcı',
                destructive: true,
                requiredText: 'welcome-mail',
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

    ElevatedButton confirm(WidgetTester tester) =>
        tester.widget<ElevatedButton>(find.byKey(const ValueKey('confirm_dialog_button')));

    testWidgets('locked until the exact text is typed (surrounding spaces ignored)', (tester) async {
      final result = await open(tester);
      expect(find.text('Onaylamak için "welcome-mail" yazın'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('confirm_dialog_text')), 'Welcome-mail');
      await tester.pump();
      expect(confirm(tester).onPressed, isNull, reason: 'case sensitive');

      await tester.enterText(find.byKey(const ValueKey('confirm_dialog_text')), ' welcome-mail ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm_dialog_button')));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('cancel → false', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });

  testWidgets('SearchablePagedList.onLoad gets every first-page response', (tester) async {
    var n = 0;
    backend.routes['/things'] = (_) => okData({
      'content': [
        {'id': ++n, 'name': 'x'},
      ],
      'last': true,
      'totalElements': n,
    });
    final loaded = <dynamic>[];
    final key = GlobalKey<SearchablePagedListState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchablePagedList(
            key: key,
            api: backend.api,
            endpoint: '/things',
            paged: true,
            onLoad: loaded.add,
            itemBuilder: (_, item) => Text('${item['id']}'),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.runAsync(() => key.currentState!.reload());
    await tester.pump();

    expect([for (final d in loaded) (d as Map)['totalElements']], [1, 2]);
  });
}
