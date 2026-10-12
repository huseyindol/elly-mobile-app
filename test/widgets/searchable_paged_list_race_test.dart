import 'dart:async';

import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/widgets/searchable_paged_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_backend.dart';

/// A request the test answers by hand, to control the order responses arrive in.
class _Pending {
  final int page;
  final Completer<http.Response> _completer = Completer();
  _Pending(this.page);

  void respond(String prefix, {required bool last, int count = 1}) => _completer.complete(
    okData({
      'content': [
        for (var i = 0; i < count; i++) {'id': '$prefix$i', 'name': '$prefix$i'},
      ],
      'last': last,
    }),
  );

  void fail(String message) => _completer.complete(jsonResponse({'message': message}, 500));
}

void main() {
  late List<_Pending> pending;
  late ApiService api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    pending = [];
    api = ApiService(
      client: MockClient((req) {
        final p = _Pending(int.parse(req.url.queryParameters['page']!));
        pending.add(p);
        return p._completer.future;
      }),
    );
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  /// Oldest unanswered request for [page].
  _Pending take(int page) {
    final p = pending.firstWhere((p) => p.page == page);
    pending.remove(p);
    return p;
  }

  Future<GlobalKey<SearchablePagedListState>> pumpList(WidgetTester tester) async {
    final key = GlobalKey<SearchablePagedListState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchablePagedList(
            key: key,
            api: api,
            endpoint: '/things/list/paged',
            paged: true,
            pageSize: 1,
            itemBuilder: (context, item) =>
                ListTile(key: ValueKey('row_${item['id']}'), title: Text('${item['name']}')),
          ),
        ),
      ),
    );
    return key;
  }

  /// List showing page 0 ("A0", more pages exist) with the page-1 request in flight.
  Future<GlobalKey<SearchablePagedListState>> listWithNextPageInFlight(WidgetTester tester) async {
    final key = await pumpList(tester);
    await settle(tester); // let the first request reach the client
    take(0).respond('A', last: false);
    await settle(tester); // page 0 rendered → footer built → page 1 requested
    await settle(tester);
    expect(find.text('A0'), findsOneWidget);
    expect(pending.map((p) => p.page), [1], reason: 'only the next page is in flight');
    return key;
  }

  testWidgets('reload() while the next page is loading: the late old page-1 response is ignored', (tester) async {
    final key = await listWithNextPageInFlight(tester);
    final stalePage1 = take(1);

    unawaited(key.currentState!.reload());
    await settle(tester);
    take(0).respond('B', last: true);
    await settle(tester);
    expect(find.text('B0'), findsOneWidget);
    expect(find.text('A0'), findsNothing, reason: 'reload replaces the old items');

    // The pre-reload next-page request finally answers.
    stalePage1.respond('STALE', last: true);
    await settle(tester);
    await settle(tester);

    expect(find.text('STALE0'), findsNothing, reason: 'stale page must not leak into the reloaded list');
    expect(find.text('B0'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'reloaded list is on its last page');
    expect(pending, isEmpty, reason: 'no further page requested after the reload');
  });

  testWidgets('stale page-1 response arriving before the reload response is ignored too', (tester) async {
    final key = await listWithNextPageInFlight(tester);
    final stalePage1 = take(1);

    unawaited(key.currentState!.reload());
    await settle(tester);
    final newPage0 = take(0);

    stalePage1.respond('STALE', last: true);
    await settle(tester);
    expect(find.text('STALE0'), findsNothing);

    newPage0.respond('B', last: false);
    await settle(tester);
    await settle(tester);

    expect(find.text('B0'), findsOneWidget);
    expect(find.text('STALE0'), findsNothing);
    // _page was reset by the reload: the next request is page 1 again (not page 2).
    expect(pending.map((p) => p.page), [1]);
    take(1).respond('C', last: true);
    await settle(tester);
    await settle(tester);
    expect(find.text('C0'), findsOneWidget);
    expect(find.text('STALE0'), findsNothing);
  });

  testWidgets('a stale next-page failure after reload() does not show a retry footer', (tester) async {
    final key = await listWithNextPageInFlight(tester);
    final stalePage1 = take(1);

    unawaited(key.currentState!.reload());
    await settle(tester);
    take(0).respond('B', last: true);
    await settle(tester);

    stalePage1.fail('Eski sayfa hatası');
    await settle(tester);

    expect(find.text('Eski sayfa hatası'), findsNothing);
    expect(find.text('Tekrar Dene'), findsNothing);
    expect(find.text('B0'), findsOneWidget);
  });

  testWidgets('a superseded reload response is ignored; the newest reload wins', (tester) async {
    final key = await pumpList(tester);
    await settle(tester);
    take(0).respond('A', last: true);
    await settle(tester);

    unawaited(key.currentState!.reload());
    await settle(tester);
    unawaited(key.currentState!.reload());
    await settle(tester);
    final firstRequest = take(0);
    final secondRequest = take(0);

    secondRequest.respond('NEW', last: true);
    await settle(tester);
    firstRequest.respond('OLD', last: true);
    await settle(tester);

    expect(find.text('NEW0'), findsOneWidget);
    expect(find.text('OLD0'), findsNothing, reason: 'an older reload finishing last must not overwrite');
  });

  testWidgets('a superseded reload failure does not replace the list with an error', (tester) async {
    final key = await pumpList(tester);
    await settle(tester);
    take(0).respond('A', last: true);
    await settle(tester);

    unawaited(key.currentState!.reload());
    await settle(tester);
    unawaited(key.currentState!.reload());
    await settle(tester);
    final firstRequest = take(0);
    final secondRequest = take(0);

    secondRequest.respond('NEW', last: true);
    await settle(tester);
    firstRequest.fail('Eski hata');
    await settle(tester);

    expect(find.text('Eski hata'), findsNothing);
    expect(find.text('NEW0'), findsOneWidget);
  });

  testWidgets('without reload, the in-flight next page is appended after the existing items', (tester) async {
    await listWithNextPageInFlight(tester);

    take(1).respond('B', last: true);
    await settle(tester);
    await settle(tester);

    expect(find.text('A0'), findsOneWidget);
    expect(find.text('B0'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('reload() keeps the old items visible while it is loading (pull-to-refresh)', (tester) async {
    final key = await listWithNextPageInFlight(tester);
    take(1).respond('B', last: true);
    await settle(tester);
    await settle(tester);

    unawaited(key.currentState!.reload());
    await settle(tester);
    expect(find.text('A0'), findsOneWidget);
    expect(find.text('B0'), findsOneWidget);

    take(0).respond('C', last: true);
    await settle(tester);
    expect(find.text('C0'), findsOneWidget);
    expect(find.text('A0'), findsNothing);
    expect(find.text('B0'), findsNothing);
  });

  testWidgets('a thin progress bar shows while reload() runs over loaded items', (tester) async {
    final key = await pumpList(tester);
    await settle(tester);
    take(0).respond('A', last: true);
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    unawaited(key.currentState!.reload());
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('A0'), findsOneWidget);

    take(0).respond('B', last: true);
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
