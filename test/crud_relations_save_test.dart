import 'dart:convert';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_form_screen.dart';
import 'package:elly_mobile_app/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

/// The edit form must never send a payload that wipes relations (backend null/[] = clear for
/// components & widgets): when the detail record cannot be loaded the form does not open at all.

const _saveKey = ValueKey('crud_save_button');

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    for (final path in ['/components/list/summary', '/banners/list/summary', '/widgets/list/summary', '/forms/list']) {
      backend.ok(path, <Object>[]);
    }
    backend.ok('/posts/list/summary', <Object>[]);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> pumpForm(WidgetTester tester, CrudModule module, Map<String, dynamic>? item) async {
    await tester.runAsync(() => backend.signIn(auth, ['${module.permissionKey}:update']));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
          home: GenericCrudFormScreen(module: module, initialData: item, apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
  }

  /// Records PUT/POST bodies to [path] (other methods → previous route).
  List<http.Request> capture(String path, {String method = 'PUT'}) {
    final sent = <http.Request>[];
    final previous = backend.routes[path];
    backend.routes[path] = (req) {
      if (req.method != method) return previous?.call(req) ?? http.Response('', 404);
      sent.add(req);
      return okData({'id': 1});
    };
    return sent;
  }

  Future<void> save(WidgetTester tester) async {
    tester.widget<ElevatedButton>(find.byKey(_saveKey)).onPressed!();
    await settle(tester);
  }

  bool wroteAnything() => backend.requests.any((r) => r.method != 'GET');

  Map<String, dynamic> body(List<http.Request> sent) => jsonDecode(sent.single.body) as Map<String, dynamic>;

  final failures = <String, http.Response Function(http.Request)>{
    '500 server error': (_) => jsonResponse({'result': false, 'message': 'boom'}, 500),
    '404 not found': (_) => http.Response('', 404),
    'null data': (_) => jsonResponse({'result': true, 'data': null}, 200),
    'list instead of a record': (_) => okData(<Object>[]),
  };

  for (final entry in {
    'components': {'id': 3, 'name': 'Slider', 'type': 'BANNER', 'bannerIds': <Object>[]},
    'widgets': {'id': 5, 'name': 'W', 'type': 'POST'},
    'pages': {'id': 7, 'slug': 'hakkimda'},
  }.entries) {
    final module = ModulesConfig.byKey(entry.key);
    final detailPathValue = switch (entry.key) {
      'pages' => '/pages/hakkimda',
      _ => '/${entry.key}/${entry.value['id']}',
    };
    for (final failure in failures.entries) {
      testWidgets('${entry.key} edit, detail ${failure.key}: error view, no save button, no write request', (
        tester,
      ) async {
        backend.routes[detailPathValue] = failure.value;
        await pumpForm(tester, module, entry.value);

        expect(find.byType(ErrorView), findsOneWidget);
        expect(find.byKey(_saveKey), findsNothing, reason: 'nothing to save from partial list data');
        expect(backend.requests.where((r) => r.method != 'GET'), isEmpty);
        await tester.pump(const Duration(seconds: 7));
      });
    }
  }

  testWidgets('component edit: retry after a failed detail load opens the form and sends the relations', (
    tester,
  ) async {
    var healthy = false;
    backend.routes['/components/3'] = (req) => healthy
        ? okData({
            'id': 3,
            'name': 'Slider',
            'type': 'BANNER',
            'pageIds': [7],
            'banners': [
              {'id': 11},
            ],
          })
        : jsonResponse({'result': false, 'message': 'boom'}, 500);
    final sent = capture('/components/3');
    await pumpForm(tester, ModulesConfig.byKey('components'), {'id': 3});
    expect(find.byKey(_saveKey), findsNothing);

    healthy = true;
    await tester.tap(find.text('Tekrar Dene'));
    await settle(tester);
    await save(tester);

    expect(body(sent)['bannerIds'], [11]);
    expect(body(sent)['pageIds'], [7]);
  });

  testWidgets('component edit: ids come from the detail record, not from the (relation-less) list item', (
    tester,
  ) async {
    backend.ok('/components/3', {
      'id': 3,
      'name': 'Slider',
      'type': 'WIDGET',
      'pageIds': [7],
      'widgets': [
        {'id': 21},
        {'id': 22},
      ],
    });
    final sent = capture('/components/3');
    // List rows (toDtoComponentSimple) carry no relations at all.
    await pumpForm(tester, ModulesConfig.byKey('components'), {'id': 3, 'name': 'Slider', 'type': 'WIDGET'});
    await save(tester);

    final b = body(sent);
    expect(b['widgetIds'], [21, 22]);
    expect(b['bannerIds'], <Object>[]);
    expect(b['formIds'], <Object>[]);
    expect(b['pageIds'], [7]);
  });

  testWidgets('component edit: relation option catalog fails → saved ids are still the record ids', (tester) async {
    backend.routes['/banners/list/summary'] = (_) => jsonResponse({'result': false, 'message': 'x'}, 500);
    backend.ok('/components/3', {
      'id': 3,
      'name': 'Slider',
      'type': 'BANNER',
      'pageIds': [7],
      'banners': [
        {'id': 11},
      ],
    });
    final sent = capture('/components/3');
    await pumpForm(tester, ModulesConfig.byKey('components'), {'id': 3});
    await save(tester);

    expect(body(sent)['bannerIds'], [11], reason: 'a failed option list must not drop the selected ids');
    expect(body(sent)['pageIds'], [7]);
  });

  testWidgets('widget edit: untouched POST widget sends posts back and banners []', (tester) async {
    backend.ok('/widgets/5', {
      'id': 5,
      'name': 'W',
      'type': 'POST',
      'posts': [
        {'id': 31},
      ],
    });
    final sent = capture('/widgets/5');
    await pumpForm(tester, ModulesConfig.byKey('widgets'), {'id': 5});
    await save(tester);

    expect(body(sent)['postIds'], [31]);
    expect(body(sent)['bannerIds'], <Object>[]);
  });

  testWidgets('page edit: detail without components + untouched selection → componentIds not sent', (tester) async {
    backend.ok('/pages/bos', {'id': 9, 'title': 'Boş', 'slug': 'bos'});
    final sent = capture('/pages/9');
    await pumpForm(tester, ModulesConfig.byKey('pages'), {'id': 9, 'slug': 'bos'});
    await save(tester);

    expect(body(sent).containsKey('componentIds'), isFalse);
    expect(body(sent)['title'], 'Boş');
  });

  testWidgets('no write happens without pressing save (loading the form is read-only)', (tester) async {
    backend.ok('/components/3', {'id': 3, 'name': 'S', 'type': 'BANNER'});
    await pumpForm(tester, ModulesConfig.byKey('components'), {'id': 3});

    expect(find.byKey(_saveKey), findsOneWidget);
    expect(wroteAnything(), isFalse);
  });
}
