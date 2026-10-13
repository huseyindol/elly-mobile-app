import 'dart:async';
import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_form_screen.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_list_screen.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/crud_payload.dart';
import 'package:elly_mobile_app/widgets/save_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

/// Phase 2 added `requiredWhen`, `optionsPermission`, `currentOptionLabel`, `RecordLink`, `fieldDecoration`
/// and `SaveBar` to the generic CRUD engine for the forms module. These tests make sure the other modules
/// (pages, components, widgets, banners, posts, contents) still behave as in phase 1, and cover the generic
/// behaviour of the new options with a synthetic module.

const _key = ValueKey('crud_save_button');

/// Modules whose screens are the plain generic form (assets has its own screen, forms is the phase 2 module).
final _plainModules = [for (final key in ['pages', 'components', 'posts', 'contents', 'widgets', 'banners']) ModulesConfig.byKey(key)];

CrudModule get _forms => ModulesConfig.byKey('forms');

const _synthetic = CrudModule(
  title: 'Deneme',
  crudEndpoint: '/syn',
  listEndpoint: '/syn/list',
  icon: Icons.science_rounded,
  permissionKey: 'syn',
  payloadKeys: ['flag', 'reason', 'owner', 'team'],
  fields: [
    FieldConfig(key: 'flag', label: 'Bayrak', type: FieldType.boolean, defaultValue: false),
    FieldConfig(key: 'reason', label: 'Gerekçe', requiredWhen: {'flag': true}),
    FieldConfig(
      key: 'owner',
      label: 'Sahip',
      type: FieldType.dropdown,
      optionsEndpoint: '/owners',
      optionsPermission: 'owners:read',
      currentOptionLabel: _ownerLabel,
    ),
    FieldConfig(key: 'team', label: 'Takım', type: FieldType.dropdown, optionsEndpoint: '/teams'),
  ],
);

String? _ownerLabel(Map<String, dynamic>? record) => record?['ownerName'] as String?;

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    for (final module in ModulesConfig.allModules) {
      for (final field in module.fields) {
        if (field.relationEndpoint != null) backend.ok(field.relationEndpoint!, <Object>[]);
        if (field.optionsEndpoint != null) backend.ok(field.optionsEndpoint!, <Object>[]);
      }
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget Function(ApiService api) screen,
    List<String> perms, {
    Size size = const Size(800, 1600),
    ApiService? api,
    AuthProvider? provider,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final user = provider ?? auth;
    await tester.runAsync(() => backend.signIn(user, perms));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: user,
        child: MaterialApp(
          localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
          home: screen(api ?? backend.api),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpForm(
    WidgetTester tester,
    CrudModule module,
    List<String> perms, {
    Map<String, dynamic>? item,
    Size size = const Size(800, 1600),
  }) => pumpScreen(
    tester,
    (api) => GenericCrudFormScreen(module: module, initialData: item, apiService: api),
    perms,
    size: size,
  );

  Future<void> save(WidgetTester tester) async {
    tester.widget<ElevatedButton>(find.byKey(_key)).onPressed!();
    await settle(tester);
    await tester.pumpAndSettle();
  }

  /// Records [method] requests to [path] and answers `{id: 1}`.
  List<http.Request> capture(String path, String method) {
    final sent = <http.Request>[];
    backend.routes[path] = (req) {
      if (req.method != method) return http.Response('', 405);
      sent.add(req);
      return okData({'id': 1});
    };
    return sent;
  }

  Map<String, dynamic> record(CrudModule module) => switch (module.permissionKey) {
    'contents' => {'id': 1, 'contentType': 'skills', 'basicInfo': {'title': 'T'}, 'metadata': <String, dynamic>{}},
    'pages' => {'id': 1, 'slug': 'sl', 'title': 'T'},
    _ => {'id': 1, 'slug': 'sl', 'title': 'T', 'name': 'N'},
  };

  group('non-forms modules keep phase 1 behaviour', () {
    test('only the forms module uses the phase 2 options', () {
      for (final module in ModulesConfig.allModules) {
        final usesNew = module.recordLink != null ||
            module.forceDeleteSuffix != null ||
            module.fields.any(
              (f) => f.requiredWhen != null || f.optionsPermission != null || f.currentOptionLabel != null,
            );
        expect(usesNew, module.permissionKey == 'forms', reason: module.title);
      }
    });

    for (final module in _plainModules) {
      testWidgets('${module.permissionKey}: new form has the pinned save bar, no record link', (tester) async {
        await pumpForm(tester, module, ['${module.permissionKey}:create']);

        expect(find.byType(SaveBar), findsOneWidget);
        expect(tester.widget<ElevatedButton>(find.byKey(_key)).onPressed, isNotNull);
        expect(find.text('Kaydet'), findsOneWidget);
        expect(find.text('${module.title} · Yeni'), findsOneWidget);
        expect(find.byKey(const ValueKey('record_link_button')), findsNothing);
        await tester.pump(const Duration(seconds: 5)); // editor timers
      });

      testWidgets('${module.permissionKey}: edit form loads the record, save bar and no record link', (tester) async {
        final item = record(module);
        final detail = detailPath(module, item);
        if (detail != null) backend.ok(detail, item);
        await pumpForm(tester, module, ['${module.permissionKey}:update', '${module.permissionKey}:read'], item: item);

        expect(find.byType(SaveBar), findsOneWidget);
        expect(find.text('${module.title} · Düzenle'), findsOneWidget);
        expect(find.byKey(const ValueKey('record_link_button')), findsNothing);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('${module.permissionKey}: empty required fields → no request, "N alan hatalı"', (tester) async {
        final posted = capture(module.crudEndpoint, 'POST');
        await pumpForm(tester, module, ['${module.permissionKey}:create']);

        await save(tester);

        expect(posted, isEmpty);
        expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
        expect(find.textContaining(' alan hatalı'), findsOneWidget);
        await tester.pump(const Duration(seconds: 7));
      });

      testWidgets('${module.permissionKey}: required text field keeps "label *" and the filled decoration',
          (tester) async {
        await pumpForm(tester, module, ['${module.permissionKey}:create']);
        final first = module.fields.firstWhere(
          (f) => f.isRequired && const {FieldType.text, FieldType.longText}.contains(f.type),
        );

        final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(ValueKey('field_${first.key}')), matching: find.byType(TextField)),
        );
        expect(_labelText(field.decoration!), '${first.label} *');
        expect(field.decoration!.filled, isTrue);
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('list rows of a plain module have no record link; forms rows do', (tester) async {
      backend.ok('/pages/list', [
        {'id': 1, 'title': 'Ana', 'slug': 'ana'},
      ]);
      await pumpScreen(
        tester,
        (api) => GenericCrudListScreen(module: ModulesConfig.byKey('pages'), apiService: api),
        ['pages:read', 'pages:update', 'forms:read'],
      );
      expect(find.byKey(const ValueKey('record_link_1')), findsNothing);
      expect(find.byKey(const ValueKey('edit_1')), findsOneWidget);
    });

    testWidgets('remote dropdown without optionsPermission (banner folder filter) is still requested for anyone',
        (tester) async {
      backend.ok('/banners/list', <Object>[]);
      backend.ok('/banners/sub-folders', ['promo']);
      await pumpScreen(
        tester,
        (api) => GenericCrudListScreen(module: ModulesConfig.byKey('banners'), apiService: api),
        ['banners:read'],
      );
      expect(backend.requestsTo('/banners/sub-folders'), isNotEmpty);
    });
  });

  group('pinned save bar and loading lock', () {
    late Completer<int> gate;
    late List<http.Request> posts;
    late ApiService gatedApi;
    late AuthProvider gatedAuth;

    /// POST /pages waits for [gate] (the status it completes with); everything else goes to [backend].
    setUp(() {
      gate = Completer<int>();
      posts = [];
      gatedApi = ApiService(
        client: MockClient((req) async {
          final path = req.url.path.replaceFirst(RegExp(r'^.*/api/v1'), '');
          if (req.method == 'POST' && path == '/pages') {
            posts.add(req);
            final status = await gate.future;
            return status == 200 ? okData({'id': 1}) : jsonResponse({'message': 'Sunucu hatası'}, status);
          }
          final handler = backend.routes[path];
          return handler == null ? http.Response('', 404) : handler(req);
        }),
      );
      gatedAuth = AuthProvider(apiService: gatedApi);
    });

    Future<void> pumpPages(WidgetTester tester) => pumpScreen(
      tester,
      (api) => GenericCrudFormScreen(module: ModulesConfig.byKey('pages'), apiService: api),
      ['pages:create'],
      api: gatedApi,
      provider: gatedAuth,
    );

    testWidgets('saving: button disabled with a "Kaydediliyor" spinner; one request only; a failure unlocks',
        (tester) async {
      await pumpPages(tester);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Yeni');

      tester.widget<ElevatedButton>(find.byKey(_key)).onPressed!();
      await tester.pump();

      expect(tester.widget<ElevatedButton>(find.byKey(_key)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Kaydediliyor'), findsOneWidget);
      expect(find.text('Kaydet'), findsNothing);
      await tester.tap(find.byKey(_key), warnIfMissed: false);
      await settle(tester);
      expect(posts, hasLength(1), reason: 'a second tap while saving sends nothing');

      gate.complete(500);
      await settle(tester);
      await tester.pump();

      expect(find.text('Sunucu hatası'), findsOneWidget);
      expect(find.text('Kaydet'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(_key)).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('leaving while the save runs asks "Kayıt sürüyor"; "Kal" keeps the form', (tester) async {
      await pumpPages(tester);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Yeni');
      tester.widget<ElevatedButton>(find.byKey(_key)).onPressed!();
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // the spinner animates forever: no pumpAndSettle
      expect(find.text('Kayıt sürüyor'), findsOneWidget);
      await tester.tap(find.text('Kal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Kayıt sürüyor'), findsNothing);
      expect(find.byType(GenericCrudFormScreen), findsOneWidget);

      gate.complete(500);
      await settle(tester);
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('scroll to the invalid field', () {
    testWidgets('banners: a number error far below the fold is scrolled into view', (tester) async {
      const small = Size(400, 420);
      await pumpForm(tester, ModulesConfig.byKey('banners'), ['banners:create'], size: small);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Kampanya');
      final target = find.byKey(const ValueKey('field_orderIndex'));
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(tester.getRect(target).bottom, greaterThan(viewport.bottom), reason: 'precondition: below the fold');
      await tester.enterText(target, 'abc');
      await tester.pumpAndSettle(); // the focused field scrolls itself into view first
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(tester.getRect(target).top, greaterThan(viewport.bottom), reason: 'scrolled back to the top');

      await save(tester);

      expect(find.text('Sayı girin'), findsOneWidget);
      final rect = tester.getRect(target);
      expect(rect.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(find.textContaining(RegExp(r'^1 alan hatalı')), findsOneWidget);
    });

    testWidgets('forms: the schema error (no fields) is scrolled into view', (tester) async {
      backend.ok('/mail-accounts/active', <Object>[]);
      await pumpForm(tester, _forms, ['forms:create', 'mail:read'], size: const Size(400, 600));
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Boş form');
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(
        tester.getRect(find.byKey(const ValueKey('open_fields_button'))).bottom,
        greaterThan(viewport.bottom),
        reason: 'precondition: the editor card is below the fold',
      );

      await save(tester);

      final error = find.text('En az bir alan eklemelisiniz');
      expect(error, findsOneWidget);
      final rect = tester.getRect(error);
      expect(rect.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    });

    testWidgets('the first invalid field wins when several are invalid', (tester) async {
      await pumpForm(tester, ModulesConfig.byKey('banners'), ['banners:create'], size: const Size(400, 420));
      await tester.enterText(find.byKey(const ValueKey('field_orderIndex')), 'abc');
      await tester.pumpAndSettle(); // the focused field scrolls itself into view first
      await save(tester);

      expect(find.textContaining(RegExp(r'^2 alan hatalı')), findsOneWidget);
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(
        tester.getRect(find.byKey(const ValueKey('field_title'))).top,
        greaterThanOrEqualTo(viewport.top - 1),
        reason: 'title (first, required) is the one scrolled to',
      );
    });
  });

  group('generic requiredWhen / optionsPermission / currentOptionLabel / RecordLink', () {
    Finder labelOf(String key) => find.descendant(of: find.byKey(ValueKey('field_$key')), matching: find.byType(TextField));
    String? label(WidgetTester tester, String key) => _labelText(tester.widget<TextField>(labelOf(key)).decoration!);

    setUp(() {
      backend.ok('/owners', [
        {'id': 1, 'name': 'Ayşe'},
        {'id': 2, 'name': 'Ali'},
      ]);
      backend.ok('/teams', [
        {'id': 10, 'name': 'Web'},
      ]);
    });

    testWidgets('requiredWhen: star and validation follow the controlling value, not before', (tester) async {
      final posted = capture('/syn', 'POST');
      await pumpForm(tester, _synthetic, ['syn:create']);

      expect(label(tester, 'reason'), 'Gerekçe', reason: 'not required while the flag is off');
      await tester.tap(find.byKey(const ValueKey('field_flag')));
      await tester.pump();
      expect(label(tester, 'reason'), 'Gerekçe *');

      await save(tester);
      expect(posted, isEmpty);
      expect(find.text('Gerekçe zorunlu'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field_reason')), 'Test');
      await save(tester);
      final body = jsonDecode(posted.single.body) as Map<String, dynamic>;
      expect(body['flag'], isTrue);
      expect(body['reason'], 'Test');
    });

    testWidgets('requiredWhen off: an empty field saves', (tester) async {
      final posted = capture('/syn', 'POST');
      await pumpForm(tester, _synthetic, ['syn:create']);

      await save(tester);

      expect(find.text('Gerekçe zorunlu'), findsNothing);
      expect(posted, hasLength(1));
    });

    testWidgets('optionsPermission missing → endpoint not requested; no permission set on a field → always', (tester) async {
      await pumpForm(tester, _synthetic, ['syn:create']);

      expect(backend.requestsTo('/owners'), isEmpty);
      expect(backend.requestsTo('/teams'), hasLength(1), reason: 'no optionsPermission → loaded for everyone');
    });

    testWidgets('optionsPermission present → options loaded with their label key', (tester) async {
      await pumpForm(tester, _synthetic, ['syn:create', 'owners:read']);

      expect(backend.requestsTo('/owners'), hasLength(1));
      await tester.tap(find.byKey(const ValueKey('field_owner_2')));
      await tester.pumpAndSettle();
      expect(find.text('Ayşe'), findsOneWidget);
      expect(find.text('Ali'), findsOneWidget);
    });

    testWidgets('another module\'s permission does not unlock the options', (tester) async {
      await pumpForm(tester, _synthetic, ['syn:create', 'mail:read', 'owners:create']);
      expect(backend.requestsTo('/owners'), isEmpty);
    });

    testWidgets('option load failure shows "<alan> yüklenemedi" and the form stays usable', (tester) async {
      backend.routes['/owners'] = (_) => jsonResponse({'message': 'kapalı'}, 500);
      await pumpForm(tester, _synthetic, ['syn:create', 'owners:read']);

      expect(find.textContaining('Sahip yüklenemedi'), findsOneWidget);
      expect(find.byType(SaveBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('currentOptionLabel shows a stored value that is not among the options', (tester) async {
      await pumpForm(tester, _synthetic, ['syn:update', 'owners:read'], item: {'id': 5, 'owner': 9, 'ownerName': 'Eski Sahip'});

      expect(find.text('Eski Sahip'), findsOneWidget);
    });

    testWidgets('currentOptionLabel null → no bare id, but the stored value is still sent back', (tester) async {
      final put = capture('/syn/5', 'PUT');
      await pumpForm(tester, _synthetic, ['syn:update', 'owners:read'], item: {'id': 5, 'owner': 9});

      expect(find.text('9'), findsNothing);
      await save(tester);
      expect((jsonDecode(put.single.body) as Map)['owner'], 9);
    });

    testWidgets('currentOptionLabel is not used when the stored value is among the options', (tester) async {
      await pumpForm(tester, _synthetic, ['syn:update', 'owners:read'], item: {'id': 5, 'owner': 1, 'ownerName': 'Eski'});

      expect(find.text('Ayşe'), findsOneWidget);
      expect(find.text('Eski'), findsNothing);
    });

    group('RecordLink', () {
      final linked = CrudModule(
        title: 'Bağlı',
        crudEndpoint: '/lnk',
        listEndpoint: '/lnk/list',
        icon: Icons.link_rounded,
        permissionKey: 'lnk',
        payloadKeys: const ['title'],
        fields: const [FieldConfig(key: 'title', label: 'Başlık')],
        recordLink: RecordLink(
          label: 'Detay',
          icon: Icons.open_in_new_rounded,
          builder: (record, api) => Scaffold(body: Text('detay #${record['id']}')),
        ),
      );

      testWidgets('edit screen: shown only with the link permission and an existing record', (tester) async {
        await pumpForm(tester, linked, ['lnk:update']);
        expect(find.byKey(const ValueKey('record_link_button')), findsNothing, reason: 'new record');
      });

      testWidgets('edit screen without lnk:read has no link; with it, the link opens the record screen', (tester) async {
        await pumpForm(tester, linked, ['lnk:update'], item: {'id': 3, 'title': 'A'});
        expect(find.byKey(const ValueKey('record_link_button')), findsNothing);
      });

      testWidgets('edit screen with lnk:read opens the screen built for this record', (tester) async {
        await pumpForm(tester, linked, ['lnk:update', 'lnk:read'], item: {'id': 3, 'title': 'A'});
        await tester.tap(find.byKey(const ValueKey('record_link_button')));
        await tester.pumpAndSettle();
        expect(find.text('detay #3'), findsOneWidget);
      });

      testWidgets('list rows: link per record, permission gated, other rows unaffected', (tester) async {
        backend.ok('/lnk/list', [
          {'id': 3, 'title': 'A'},
          {'id': 4, 'title': 'B'},
        ]);
        await pumpScreen(tester, (api) => GenericCrudListScreen(module: linked, apiService: api), ['lnk:read']);
        expect(find.byKey(const ValueKey('record_link_3')), findsOneWidget);
        expect(find.byKey(const ValueKey('record_link_4')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('record_link_4')));
        await tester.pumpAndSettle();
        expect(find.text('detay #4'), findsOneWidget);
      });
    });
  });

  group('force delete is offered on 409 only', () {
    final form = {
      'id': 7,
      'title': 'Başvuru',
      'recipientEmail': 'a@b.com',
      'active': true,
      'version': 1,
      'schema': {'config': <String, dynamic>{}, 'fields': <Object>[]},
    };

    setUp(() {
      backend.ok('/forms/list', [form]);
      backend.ok('/mail-accounts/active', <Object>[]);
    });

    Future<void> deleteForm(WidgetTester tester) async {
      await pumpScreen(
        tester,
        (api) => GenericCrudListScreen(module: _forms, apiService: api),
        ['forms:read', 'forms:delete'],
      );
      await tester.tap(find.byKey(const ValueKey('delete_7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);
      await tester.pump();
    }

    for (final status in [400, 403, 404, 422, 500, 503]) {
      testWidgets('$status: message shown, no cascade dialog, no /force request', (tester) async {
        backend.routes['/forms/7'] = (_) => jsonResponse({'result': false, 'message': 'hata-$status'}, status);
        await deleteForm(tester);

        expect(find.text('İlişkili kayıtlar mevcut'), findsNothing);
        expect(find.text('Evet, Tümünü Sil'), findsNothing);
        expect(find.text('hata-$status'), findsOneWidget);
        expect(backend.requestsTo('/forms/7/force'), isEmpty);
        expect(backend.requests.where((r) => r.method == 'DELETE'), hasLength(1));
        await tester.pump(const Duration(seconds: 7));
      });
    }

    testWidgets('409 offers it; "Vazgeç" sends nothing more', (tester) async {
      backend.routes['/forms/7'] = (_) => jsonResponse({'result': false, 'message': 'related'}, 409);
      await deleteForm(tester);

      expect(find.text('İlişkili kayıtlar mevcut'), findsOneWidget);
      await tester.tap(find.text('Vazgeç').last);
      await tester.pumpAndSettle();

      expect(backend.requestsTo('/forms/7/force'), isEmpty);
      expect(backend.requests.where((r) => r.method == 'DELETE'), hasLength(1));
    });

    testWidgets('409 then a refused force delete (403) shows that error and does not reload the list',
        (tester) async {
      backend.routes['/forms/7'] = (_) => jsonResponse({'result': false, 'message': 'related'}, 409);
      backend.routes['/forms/7/force'] = (_) => jsonResponse({'result': false, 'message': 'Yetkiniz yok'}, 403);
      await deleteForm(tester);
      final listLoads = backend.requestsTo('/forms/list').length;

      await tester.tap(find.text('Evet, Tümünü Sil'));
      await settle(tester);
      await tester.pump();

      expect(find.text('Yetkiniz yok'), findsOneWidget);
      expect(backend.requests.where((r) => r.method == 'DELETE'), hasLength(2));
      expect(backend.requestsTo('/forms/list'), hasLength(listLoads));
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('a module without forceDeleteSuffix never offers it, even on 409', (tester) async {
      backend.ok('/posts/list', [
        {'id': 1, 'title': 'Birinci'},
      ]);
      backend.routes['/posts/1'] = (_) => jsonResponse({'result': false, 'message': 'ilişkili'}, 409);
      await pumpScreen(
        tester,
        (api) => GenericCrudListScreen(module: ModulesConfig.byKey('posts'), apiService: api),
        ['posts:read', 'posts:delete'],
      );
      await tester.tap(find.byKey(const ValueKey('delete_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);
      await tester.pump();

      expect(find.text('İlişkili kayıtlar mevcut'), findsNothing);
      expect(find.text('ilişkili'), findsOneWidget);
      expect(backend.requests.where((r) => r.method == 'DELETE'), hasLength(1));
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('SaveBar and fieldDecoration (shared parts)', () {
    Future<void> pumpBar(WidgetTester tester, SaveBar bar) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [bar]))));

    testWidgets('idle: default label and key, calls onPressed', (tester) async {
      var taps = 0;
      await pumpBar(tester, SaveBar(onPressed: () => taps++));
      await tester.tap(find.byKey(_key));
      expect(find.text('Kaydet'), findsOneWidget);
      expect(taps, 1);
    });

    testWidgets('loading: spinner with semantics label, onPressed ignored', (tester) async {
      var taps = 0;
      await pumpBar(tester, SaveBar(onPressed: () => taps++, loading: true));
      await tester.tap(find.byKey(_key), warnIfMissed: false);
      expect(taps, 0);
      expect(find.bySemanticsLabel('Kaydediliyor'), findsOneWidget);
      expect(find.text('Kaydet'), findsNothing);
    });

    testWidgets('custom label and key', (tester) async {
      await pumpBar(tester, SaveBar(onPressed: () {}, label: 'Uygula', buttonKey: const ValueKey('apply')));
      expect(find.text('Uygula'), findsOneWidget);
      expect(find.byKey(const ValueKey('apply')), findsOneWidget);
      expect(find.byKey(_key), findsNothing);
    });

    test('fieldDecoration: label / hint / helper, filled, 16 px borders, primary focus', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark);
      final d = fieldDecoration(scheme, label: 'Ad *', hint: 'ipucu', helper: 'yardım');

      expect(_labelText(d), 'Ad *');
      expect(
        ((d.label as Text).textSpan as TextSpan).children!.single,
        isA<TextSpan>().having((t) => t.semanticsLabel, 'semanticsLabel', ', zorunlu'),
        reason: 'screen readers say "zorunlu", not "star"',
      );
      expect(fieldDecoration(scheme, label: 'Ad').labelText, 'Ad');
      expect(d.hintText, 'ipucu');
      expect(d.helperText, 'yardım');
      expect(d.filled, isTrue);
      final enabled = d.enabledBorder as OutlineInputBorder;
      final focused = d.focusedBorder as OutlineInputBorder;
      expect(enabled.borderRadius, BorderRadius.circular(16));
      expect(focused.borderSide.color, scheme.primary);
      expect(fieldDecoration(scheme).labelText, isNull);
    });
  });
}

/// Label of a field decoration: plain `labelText`, or the rich label `fieldDecoration` builds for "… *".
String? _labelText(InputDecoration d) {
  final label = d.label;
  return d.labelText ?? (label is Text ? label.data ?? label.textSpan?.toPlainText(includeSemanticsLabels: false) : null);
}
