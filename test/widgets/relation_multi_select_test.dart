import 'package:elly_mobile_app/widgets/relation_multi_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late List<Object> selected;
  late List<List<Object>> changes;

  setUp(() {
    backend = FakeBackend();
    selected = [3];
    changes = [];
    backend.ok('/components/list', [
      {'id': 1, 'name': 'Hero'},
      {'id': 2, 'name': 'Footer'},
      {'id': 3, 'title': 'Galeri'},
    ]);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> pumpSelect(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => RelationMultiSelect(
              api: backend.api,
              label: 'Componentler',
              endpoint: '/components/list',
              labelKey: 'name|title',
              selectedIds: selected,
              onChanged: (ids) => setState(() {
                selected = ids;
                changes.add(ids);
              }),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder chip(Object id) => find.byKey(ValueKey('relation_chip_$id'));
  Finder option(Object id) => find.byKey(ValueKey('relation_option_$id'));

  testWidgets('initial ids are shown as chips with labels resolved from the endpoint', (tester) async {
    await pumpSelect(tester);

    expect(find.descendant(of: chip(3), matching: find.text('Galeri')), findsOneWidget);
    expect(backend.requestsTo('/components/list'), hasLength(1));
  });

  testWidgets('picking: existing order kept, new ids appended in list order; "Tamam" applies', (tester) async {
    await pumpSelect(tester);

    await tester.tap(find.byKey(const ValueKey('relation_pick_Componentler')));
    await tester.pumpAndSettle();
    await tester.tap(option(2));
    await tester.tap(option(1));
    await tester.pump();
    expect(find.text('Tamam (3)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('relation_done_button')));
    await tester.pumpAndSettle();

    expect(changes.single, [3, 1, 2]);
    expect(chip(1), findsOneWidget);
    expect(chip(2), findsOneWidget);
  });

  testWidgets('search in the sheet filters options; unchecking removes', (tester) async {
    await pumpSelect(tester);

    await tester.tap(find.byKey(const ValueKey('relation_pick_Componentler')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('relation_search_field')), 'gal');
    await tester.pump();
    expect(option(1), findsNothing);
    expect(option(3), findsOneWidget);

    await tester.tap(option(3));
    await tester.tap(find.byKey(const ValueKey('relation_done_button')));
    await tester.pumpAndSettle();

    expect(changes.single, isEmpty);
    expect(find.text('Seçili kayıt yok'), findsOneWidget);
  });

  testWidgets('dismissing the sheet changes nothing', (tester) async {
    await pumpSelect(tester);

    await tester.tap(find.byKey(const ValueKey('relation_pick_Componentler')));
    await tester.pumpAndSettle();
    await tester.tap(option(1));
    await tester.tapAt(const Offset(10, 10)); // barrier
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(chip(1), findsNothing);
  });

  testWidgets('chip delete removes the id', (tester) async {
    await pumpSelect(tester);

    await tester.tap(find.descendant(of: chip(3), matching: find.byTooltip('Kaldır')));
    await tester.pump();

    expect(changes.single, isEmpty);
  });

  testWidgets('options load failure: error + retry, picker hidden until loaded', (tester) async {
    backend.routes['/components/list'] = (_) => http.Response('', 500);
    await pumpSelect(tester);

    expect(find.text('Sunucu hatası (500)'), findsOneWidget);
    expect(find.byKey(const ValueKey('relation_pick_Componentler')), findsNothing);
    expect(
      find.descendant(of: chip(3), matching: find.text('#3')),
      findsOneWidget,
      reason: 'label unknown',
    );

    backend.ok('/components/list', [
      {'id': 3, 'name': 'Galeri'},
    ]);
    await tester.tap(find.byTooltip('Componentler yüklenemedi, tekrar dene'));
    await settle(tester);

    expect(find.byKey(const ValueKey('relation_pick_Componentler')), findsOneWidget);
    expect(find.descendant(of: chip(3), matching: find.text('Galeri')), findsOneWidget);
  });
}
