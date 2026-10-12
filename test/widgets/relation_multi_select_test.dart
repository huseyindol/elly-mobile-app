import 'package:elly_mobile_app/widgets/relation_multi_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late List<List<Object>> changes;
  late GlobalKey<FormState> formKey;
  late List<List<Object>?> saved;

  setUp(() {
    backend = FakeBackend();
    changes = [];
    saved = [];
    formKey = GlobalKey<FormState>();
    backend.ok('/components/list', [
      {'id': 1, 'name': 'Hero'},
      {'id': 2, 'name': 'Footer'},
      {'id': 3, 'title': 'Galeri'},
      {'id': 4, 'name': 'Işıklı Başlık'},
    ]);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> pumpSelect(
    WidgetTester tester, {
    String endpoint = '/components/list',
    bool paged = false,
    List<Object> initial = const [3],
    bool isRequired = false,
    int maxChips = 6,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: RelationMultiSelect(
              api: backend.api,
              label: 'Componentler',
              endpoint: endpoint,
              paged: paged,
              labelKey: 'name|title',
              initialValue: initial,
              isRequired: isRequired,
              maxChips: maxChips,
              onChanged: changes.add,
              onSaved: saved.add,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder chip(Object id) => find.byKey(ValueKey('relation_chip_$id'));
  Finder option(Object id) => find.byKey(ValueKey('relation_option_$id'));
  Finder pickButton() => find.byKey(const ValueKey('relation_pick_Componentler'));

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(pickButton());
    await tester.pumpAndSettle();
  }

  testWidgets('initial ids are shown as chips with labels resolved from the endpoint', (tester) async {
    await pumpSelect(tester);

    expect(find.descendant(of: chip(3), matching: find.text('Galeri')), findsOneWidget);
    expect(backend.requestsTo('/components/list'), hasLength(1));
  });

  testWidgets('picking: existing order kept, new ids appended in list order; "Tamam" applies', (tester) async {
    await pumpSelect(tester);

    await openSheet(tester);
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

  testWidgets('sheet search is Turkish-insensitive (foldTr); unchecking removes', (tester) async {
    await pumpSelect(tester);

    await openSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('relation_search_field')), 'ISIKLI');
    await tester.pump();
    expect(option(4), findsOneWidget, reason: '"ISIKLI" matches "Işıklı Başlık"');
    expect(option(1), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('relation_search_field')), 'gal');
    await tester.pump();
    await tester.tap(option(3));
    await tester.tap(find.byKey(const ValueKey('relation_done_button')));
    await tester.pumpAndSettle();

    expect(changes.single, isEmpty);
    expect(find.text('Seçili kayıt yok'), findsOneWidget);
  });

  testWidgets('dismissing the sheet changes nothing', (tester) async {
    await pumpSelect(tester);

    await openSheet(tester);
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

  testWidgets('more than maxChips: first N chips + "+K daha" that opens the sheet', (tester) async {
    await pumpSelect(tester, initial: [1, 2, 3, 4], maxChips: 2);

    expect(chip(1), findsOneWidget);
    expect(chip(2), findsOneWidget);
    expect(chip(3), findsNothing);
    expect(find.text('+2 daha'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('relation_more_chip')));
    await tester.pumpAndSettle();
    expect(find.text('Tamam (4)'), findsOneWidget);
  });

  group('as a FormField', () {
    testWidgets('isRequired: validate fails on an empty selection and passes after picking', (tester) async {
      await pumpSelect(tester, initial: const [], isRequired: true);

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('En az bir Componentler seçin'), findsOneWidget);

      await openSheet(tester);
      await tester.tap(option(1));
      await tester.tap(find.byKey(const ValueKey('relation_done_button')));
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('En az bir Componentler seçin'), findsNothing);
    });

    testWidgets('save() hands the current ids to onSaved; reset() restores initialValue', (tester) async {
      await pumpSelect(tester);
      await tester.tap(find.descendant(of: chip(3), matching: find.byTooltip('Kaldır')));
      await tester.pump();

      formKey.currentState!.save();
      expect(saved.single, isEmpty);

      formKey.currentState!.reset();
      await tester.pump();
      expect(chip(3), findsOneWidget);
      formKey.currentState!.save();
      expect(saved.last, [3]);
    });
  });

  testWidgets('paged endpoint: every page is fetched so labels of later pages resolve', (tester) async {
    backend.routes['/posts/list/paged'] = (req) {
      final page = int.parse(req.url.queryParameters['page']!);
      return okData({
        'content': [
          {'id': page + 10, 'title': 'Yazı $page'},
        ],
        'last': page == 2,
      });
    };
    await pumpSelect(tester, endpoint: '/posts/list/paged?sort=id,asc', paged: true, initial: [12]);
    await settle(tester);

    final queries = [for (final r in backend.requestsTo('/posts/list/paged')) r.url.queryParameters];
    expect(queries.map((q) => q['page']), ['0', '1', '2']);
    expect(queries.every((q) => q['size'] == '100' && q['sort'] == 'id,asc'), isTrue);
    expect(find.descendant(of: chip(12), matching: find.text('Yazı 2')), findsOneWidget);
  });

  testWidgets('endpoint change reloads the options (didUpdateWidget)', (tester) async {
    backend.ok('/widgets/list', [
      {'id': 3, 'name': 'Widget Üç'},
    ]);
    await pumpSelect(tester);
    expect(find.descendant(of: chip(3), matching: find.text('Galeri')), findsOneWidget);

    await pumpSelect(tester, endpoint: '/widgets/list');

    expect(backend.requestsTo('/widgets/list'), hasLength(1));
    expect(find.descendant(of: chip(3), matching: find.text('Widget Üç')), findsOneWidget);
  });

  testWidgets('options load failure: error + retry, picker hidden until loaded', (tester) async {
    backend.routes['/components/list'] = (_) => http.Response('', 500);
    await pumpSelect(tester);

    expect(find.text('Sunucu hatası (500)'), findsOneWidget);
    expect(pickButton(), findsNothing);
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

    expect(pickButton(), findsOneWidget);
    expect(find.descendant(of: chip(3), matching: find.text('Galeri')), findsOneWidget);
  });
}
