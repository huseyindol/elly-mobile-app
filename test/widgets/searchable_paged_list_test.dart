import 'package:elly_mobile_app/widgets/searchable_paged_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<GlobalKey<SearchablePagedListState>> pumpList(
    WidgetTester tester, {
    required String endpoint,
    bool paged = false,
    int pageSize = 20,
    bool search = true,
  }) async {
    final key = GlobalKey<SearchablePagedListState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchablePagedList(
            key: key,
            api: backend.api,
            endpoint: endpoint,
            paged: paged,
            pageSize: pageSize,
            searchText: search ? (item) => '${item['name']}' : null,
            itemBuilder: (context, item) =>
                ListTile(key: ValueKey('row_${item['id']}'), title: Text('${item['name']}')),
          ),
        ),
      ),
    );
    await settle(tester);
    return key;
  }

  testWidgets('plain list endpoint: loads once, no paging params', (tester) async {
    backend.ok('/things/list', [
      {'id': 1, 'name': 'Elma'},
      {'id': 2, 'name': 'Armut'},
    ]);
    await pumpList(tester, endpoint: '/things/list');

    expect(find.text('Elma'), findsOneWidget);
    expect(find.text('Armut'), findsOneWidget);
    expect(backend.requestsTo('/things/list').single.url.queryParameters, isEmpty);
  });

  testWidgets('search filters loaded items case-insensitively and shows a no-match state', (tester) async {
    backend.ok('/things/list', [
      {'id': 1, 'name': 'Elma'},
      {'id': 2, 'name': 'Armut'},
    ]);
    await pumpList(tester, endpoint: '/things/list');

    await tester.enterText(find.byKey(const ValueKey('list_search_field')), 'ELM');
    await tester.pump();
    expect(find.text('Elma'), findsOneWidget);
    expect(find.text('Armut'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('list_search_field')), 'kiraz');
    await tester.pump();
    expect(find.text('Aramayla eşleşen kayıt yok.'), findsOneWidget);
    expect(backend.requestsTo('/things/list'), hasLength(1), reason: 'search is client-side');
  });

  testWidgets('searchText null hides the search box', (tester) async {
    backend.ok('/things/list', [
      {'id': 1, 'name': 'Elma'},
    ]);
    await pumpList(tester, endpoint: '/things/list', search: false);

    expect(find.byKey(const ValueKey('list_search_field')), findsNothing);
  });

  testWidgets('paged endpoint: keeps existing query, fetches the next page at the end, stops at last', (tester) async {
    backend.routes['/things/list/paged'] = (req) {
      final page = int.parse(req.url.queryParameters['page']!);
      return okData({
        'content': [
          for (var i = 0; i < (page == 0 ? 2 : 1); i++) {'id': page * 10 + i, 'name': 'P$page-$i'},
        ],
        'last': page == 1,
      });
    };
    await pumpList(tester, endpoint: '/things/list/paged?sort=id,desc', paged: true, pageSize: 2);
    // The footer of page 0 is on screen → page 1 is requested after the frame.
    await settle(tester);
    await settle(tester);

    final queries = [for (final r in backend.requestsTo('/things/list/paged')) r.url.queryParameters];
    expect(queries, [
      {'sort': 'id,desc', 'page': '0', 'size': '2'},
      {'sort': 'id,desc', 'page': '1', 'size': '2'},
    ]);
    expect(find.text('P0-0'), findsOneWidget);
    expect(find.text('P0-1'), findsOneWidget);
    expect(find.text('P1-0'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'last page → no footer');
  });

  testWidgets('next-page failure shows an inline retry that loads it', (tester) async {
    var failNext = true;
    backend.routes['/things/list/paged'] = (req) {
      final page = int.parse(req.url.queryParameters['page']!);
      if (page == 1 && failNext) return jsonResponse({'message': 'Sayfa hatası'}, 500);
      return okData({
        'content': [
          {'id': page, 'name': 'P$page'},
        ],
        'last': page == 1,
      });
    };
    await pumpList(tester, endpoint: '/things/list/paged', paged: true, pageSize: 1);
    await settle(tester);
    await settle(tester);

    expect(find.text('P0'), findsOneWidget);
    expect(find.text('Sayfa hatası'), findsOneWidget);

    failNext = false;
    await tester.tap(find.text('Tekrar Dene'));
    await settle(tester);
    await settle(tester);

    expect(find.text('P1'), findsOneWidget);
    expect(find.text('Sayfa hatası'), findsNothing);
  });

  testWidgets('error state with retry; empty state; reload() via the key', (tester) async {
    backend.routes['/things/list'] = (_) => http.Response('', 500);
    final key = await pumpList(tester, endpoint: '/things/list');

    expect(find.text('Sunucu hatası (500)'), findsOneWidget);
    expect(find.bySemanticsLabel('Yükleniyor'), findsNothing);

    backend.ok('/things/list', []);
    await tester.tap(find.text('Tekrar Dene'));
    await settle(tester);
    expect(find.text('Kayıt bulunamadı.'), findsOneWidget);

    backend.ok('/things/list', [
      {'id': 7, 'name': 'Yeni'},
    ]);
    await tester.runAsync(() => key.currentState!.reload());
    await tester.pump();
    expect(find.text('Yeni'), findsOneWidget);
    expect(backend.requestsTo('/things/list'), hasLength(3));
  });

  testWidgets('loading spinner has a semantics label', (tester) async {
    backend.ok('/things/list', []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchablePagedList(
            api: backend.api,
            endpoint: '/things/list',
            itemBuilder: (_, _) => const SizedBox(),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
    await settle(tester);
  });

  group('search', () {
    setUp(() {
      backend.ok('/things/list', [
        {'id': 1, 'name': 'İstanbul'},
        {'id': 2, 'name': 'Işık Sokak'},
        {'id': 3, 'name': 'Çiçek'},
      ]);
    });

    Finder field() => find.byKey(const ValueKey('list_search_field'));

    testWidgets('is Turkish-insensitive (foldTr): istanbul / ISIK / cicek', (tester) async {
      await pumpList(tester, endpoint: '/things/list');

      for (final (query, match) in [('istanbul', 'İstanbul'), ('ISIK', 'Işık Sokak'), ('cicek', 'Çiçek')]) {
        await tester.enterText(field(), query);
        await tester.pump();
        expect(find.text(match), findsOneWidget, reason: '"$query" → $match');
      }
    });

    testWidgets('has a label and a clear button only while filled', (tester) async {
      await pumpList(tester, endpoint: '/things/list');
      expect(find.text('Ara'), findsOneWidget);
      expect(find.byTooltip('Aramayı temizle'), findsNothing);

      await tester.enterText(field(), 'çiçek');
      await tester.pump();
      expect(find.text('İstanbul'), findsNothing);

      await tester.tap(find.byTooltip('Aramayı temizle'));
      await tester.pump();
      expect(find.text('İstanbul'), findsOneWidget);
      expect(find.text('Çiçek'), findsOneWidget);
      expect(find.byTooltip('Aramayı temizle'), findsNothing);
    });
  });

  testWidgets('paged + search: no automatic paging; "Daha fazla ara" loads the next page on request', (tester) async {
    // Page 0 is taller than the viewport, so its footer is off screen until the search shrinks the list.
    backend.routes['/things/list/paged'] = (req) {
      final page = int.parse(req.url.queryParameters['page']!);
      return okData({
        'content': page == 0
            ? [
                for (var i = 0; i < 30; i++) {'id': i, 'name': 'Elma $i'},
              ]
            : [
                {'id': 100, 'name': 'Kiraz'},
              ],
        'last': page == 1,
      });
    };
    await pumpList(tester, endpoint: '/things/list/paged', paged: true, pageSize: 30);
    expect(backend.requestsTo('/things/list/paged'), hasLength(1));

    await tester.enterText(find.byKey(const ValueKey('list_search_field')), 'kiraz');
    await tester.pump();
    await settle(tester);

    expect(backend.requestsTo('/things/list/paged'), hasLength(1), reason: 'searching must not page automatically');
    expect(find.text('Yüklenen kayıtlarda yok'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('list_search_more_button')));
    await settle(tester);

    expect(backend.requestsTo('/things/list/paged'), hasLength(2));
    expect(find.text('Kiraz'), findsOneWidget);
    expect(find.byKey(const ValueKey('list_search_more_button')), findsNothing, reason: 'last page reached');
  });

  testWidgets('a failed reload keeps the loaded items and shows a SnackBar', (tester) async {
    backend.ok('/things/list', [
      {'id': 1, 'name': 'Elma'},
    ]);
    final key = await pumpList(tester, endpoint: '/things/list');

    backend.routes['/things/list'] = (_) => jsonResponse({'message': 'Bağlantı yok'}, 500);
    await tester.runAsync(() => key.currentState!.reload());
    await tester.pump();

    expect(find.text('Elma'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsNothing);
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text('Yenilenemedi: Bağlantı yok')),
      findsOneWidget,
    );
  });

  testWidgets('default padding leaves room for a FAB under the last row', (tester) async {
    backend.ok('/things/list', [
      {'id': 1, 'name': 'Elma'},
    ]);
    await pumpList(tester, endpoint: '/things/list');

    final padding = tester.widget<ListView>(find.byType(ListView)).padding! as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(88));
  });
}
