import 'dart:async';

import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/widgets/searchable_paged_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_backend.dart';

/// `SearchablePagedList.onLoad`: the raw response of every successful (re)load of the FIRST page - used for the
/// "Toplam N kayıt" line and status filters of the e-mail logs. Never for next pages, failures or stale loads.
class _Call {
  final Uri url;
  final Completer<http.Response> completer = Completer();
  _Call(this.url);
  int get page => int.tryParse(url.queryParameters['page'] ?? '') ?? -1;

  void ok(Object data) => completer.complete(okData(data));
  void fail([String message = 'patladı']) => completer.complete(jsonResponse({'message': message}, 500));
}

void main() {
  late List<_Call> calls;
  late ApiService api;
  late List<dynamic> loaded;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    calls = [];
    loaded = [];
    api = ApiService(
      client: MockClient((req) {
        final c = _Call(req.url);
        calls.add(c);
        return c.completer.future;
      }),
    );
  });

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }

  _Call take({int? page}) {
    final c = page == null ? calls.first : calls.firstWhere((c) => c.page == page);
    calls.remove(c);
    return c;
  }

  Map<String, dynamic> pageOf(int n, {bool last = true, int total = 5, Object? extra}) => {
    'content': [
      {'id': n, 'name': 'Kayıt $n'},
    ],
    'last': last,
    'totalElements': total,
    'extra': ?extra,
  };

  Future<GlobalKey<SearchablePagedListState>> pump(
    WidgetTester tester, {
    bool paged = true,
    String endpoint = '/things/paged?sort=id,desc',
    bool search = false,
    Widget Function(Widget list)? wrap,
  }) async {
    final key = GlobalKey<SearchablePagedListState>();
    final list = SearchablePagedList(
      key: key,
      api: api,
      endpoint: endpoint,
      paged: paged,
      pageSize: 1,
      onLoad: loaded.add,
      searchText: search ? (item) => '${item['name']}' : null,
      itemBuilder: (context, item) => ListTile(key: ValueKey('row_${item['id']}'), title: Text('${item['name']}')),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: wrap == null ? list : wrap(list))));
    return key;
  }

  testWidgets('first load: called once with the untouched response, after the rows are built', (tester) async {
    await pump(tester);
    expect(loaded, isEmpty, reason: 'nothing before the response');
    final response = pageOf(
      1,
      extra: {
        'filters': ['A', 'B'],
      },
    );
    take().ok(response);
    await flush(tester);

    expect(loaded, [response]);
    expect(find.byKey(const ValueKey('row_1')), findsOneWidget);
  });

  testWidgets('a non-paged endpoint (plain list) passes the List itself', (tester) async {
    await pump(tester, paged: false, endpoint: '/things/list');
    final data = [
      {'id': 1, 'name': 'a'},
      {'id': 2, 'name': 'b'},
    ];
    take().ok(data);
    await flush(tester);
    expect(loaded, [data]);
  });

  testWidgets('next pages do not call onLoad (it would reset the total / filter options)', (tester) async {
    await pump(tester);
    take(page: 0).ok(pageOf(1, last: false));
    await flush(tester);
    expect(loaded, hasLength(1));

    // The footer asks for page 1 once built; answer it.
    await tester.pump();
    await flush(tester);
    take(page: 1).ok(pageOf(2));
    await flush(tester);

    expect(find.byKey(const ValueKey('row_2')), findsOneWidget, reason: 'page 2 really loaded');
    expect(loaded, hasLength(1), reason: 'still only the first page');
  });

  testWidgets('every reload() calls it again, in order; searching does not', (tester) async {
    final key = await pump(tester, search: true);
    take().ok(pageOf(1, total: 1));
    await flush(tester);

    unawaited(key.currentState!.reload());
    await tester.pump();
    take().ok(pageOf(7, total: 2));
    await flush(tester);

    await tester.enterText(find.byKey(const ValueKey('list_search_field')), 'kayıt');
    await tester.pump();
    expect(calls, isEmpty, reason: 'search is client side');

    expect([for (final d in loaded) (d as Map)['totalElements']], [1, 2]);
  });

  testWidgets('a failed first load does not call it (the ErrorView shows)', (tester) async {
    await pump(tester);
    take().fail('sunucu yok');
    await flush(tester);

    expect(loaded, isEmpty);
    expect(find.textContaining('sunucu yok'), findsOneWidget);
  });

  testWidgets('a failed reload keeps the rows and the previous total; onLoad is not called for it', (tester) async {
    final key = await pump(tester);
    take().ok(pageOf(1, total: 9));
    await flush(tester);

    unawaited(key.currentState!.reload());
    await tester.pump();
    take().fail();
    await flush(tester);

    expect(loaded, hasLength(1));
    expect((loaded.single as Map)['totalElements'], 9);
    expect(find.byKey(const ValueKey('row_1')), findsOneWidget);
  });

  testWidgets('a superseded load is dropped: its late response never reaches onLoad', (tester) async {
    final key = await pump(tester);
    final stale = take(); // first load, still in flight
    unawaited(key.currentState!.reload());
    await tester.pump();
    final fresh = take();

    fresh.ok(pageOf(2, total: 2));
    await flush(tester);
    stale.ok(pageOf(1, total: 1));
    await flush(tester);

    expect([for (final d in loaded) (d as Map)['totalElements']], [2]);
    expect(find.byKey(const ValueKey('row_2')), findsOneWidget);
    expect(find.byKey(const ValueKey('row_1')), findsNothing);
  });

  testWidgets('disposed before the response: no onLoad, no exception', (tester) async {
    await pump(tester);
    final inFlight = take();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('başka ekran'))));
    inFlight.ok(pageOf(1));
    await flush(tester);

    expect(loaded, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the parent may setState from onLoad (total line) without a framework error', (tester) async {
    var total = 'Toplam ?';
    late StateSetter parentSetState;
    final key = GlobalKey<SearchablePagedListState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              parentSetState = setState;
              return Column(
                children: [
                  Text(total),
                  Expanded(
                    child: SearchablePagedList(
                      key: key,
                      api: api,
                      endpoint: '/things/paged',
                      paged: true,
                      onLoad: (d) => parentSetState(() => total = 'Toplam ${(d as Map)['totalElements']}'),
                      itemBuilder: (context, item) => Text('${item['name']}'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    take().ok(pageOf(1, total: 42));
    await flush(tester);

    expect(find.text('Toplam 42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without onLoad nothing breaks (it is optional)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchablePagedList(
            api: api,
            endpoint: '/things/paged',
            paged: true,
            itemBuilder: (context, item) => Text('${item['name']}'),
          ),
        ),
      ),
    );
    take().ok(pageOf(1));
    await flush(tester);
    expect(find.text('Kayıt 1'), findsOneWidget);
  });
}
