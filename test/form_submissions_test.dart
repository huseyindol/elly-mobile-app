import 'dart:convert';
import 'dart:io';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_form_screen.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_list_screen.dart';
import 'package:elly_mobile_app/screens/forms/form_submissions_screen.dart';
import 'package:elly_mobile_app/services/text_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

Map<String, dynamic> _form() =>
    jsonDecode(File('test/fixtures/form_admin_wizard.json').readAsStringSync()) as Map<String, dynamic>;

final _forms = ModulesConfig.byKey('forms');

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  final submissions = [
    {
      'id': 12,
      'formDefinitionId': 7,
      'formTitle': 'Başvuru Formu',
      'submittedAt': '2026-02-14T09:05:00',
      'payload': {
        'name': 'Ayşe',
        'topic': 'sales',
        'interests': ['web', 'mobile'],
        'kvkk': true,
        'age': null,
        'legacy_note': 'eski alan',
      },
    },
    {
      'id': 11,
      'formDefinitionId': 7,
      'submittedAt': '2026-02-13T18:30:00',
      'payload': {'name': 'Ali'},
    },
  ];

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.routes['/forms/7/submissions/paged'] = (_) => okData({'content': submissions, 'last': true});
    backend.ok('/forms/7/submissions/count', 2);
    backend.ok('/forms/list', [_form()]);
    backend.ok('/mail-accounts/active', <Object>[]);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, Widget home, List<String> perms) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, perms));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates, home: home),
      ),
    );
    await settle(tester);
  }

  testWidgets('newest first, paged, count header, values with schema labels', (tester) async {
    await pump(tester, FormSubmissionsScreen(form: _form(), apiService: backend.api), ['forms:read']);

    final request = backend.requestsTo('/forms/7/submissions/paged').single.url;
    expect(request.queryParametersAll['sort'], ['submittedAt,desc']);
    expect(request.queryParameters['page'], '0');
    expect(find.text('Başvuru Formu · 2 yanıt'), findsOneWidget);
    expect(find.text(formatDateTimeTr('2026-02-14T09:05:00')), findsOneWidget);
    expect(find.text('#12'), findsOneWidget);
    expect(find.text('Ad Soyad: Ayşe'), findsOneWidget);
    expect(find.text('Yaş: —'), findsOneWidget, reason: 'present but null → —');
    expect(find.text('Konu: Satış'), findsOneWidget, reason: 'option value → label');
    expect(find.text('+2 alan'), findsOneWidget);
  });

  testWidgets('detail: every schema field in form order, then payload keys the schema lacks', (tester) async {
    await pump(tester, FormSubmissionsScreen(form: _form(), apiService: backend.api), ['forms:read']);
    await tester.tap(find.byKey(const ValueKey('submission_12')));
    await tester.pumpAndSettle();

    expect(find.text('Yanıt #12'), findsOneWidget);
    expect(find.text('Web, Mobil'), findsOneWidget);
    expect(find.text('Evet'), findsOneWidget);
    expect(find.text('legacy_note'), findsOneWidget);
    expect(find.text('eski alan'), findsOneWidget);
    expect(find.text('Şirket'), findsNothing, reason: 'not in the payload');
    final labels = [for (final t in tester.widgetList<Text>(find.byType(Text))) t.data]
        .where((d) => ['Ad Soyad', 'Yaş', 'Konu', 'İlgi Alanları', 'legacy_note'].contains(d))
        .toList();
    expect(labels, ['Ad Soyad', 'Yaş', 'Konu', 'İlgi Alanları', 'legacy_note']);
  });

  testWidgets('no submissions → empty state', (tester) async {
    backend.routes['/forms/7/submissions/paged'] = (_) => okData({'content': <Object>[], 'last': true});
    backend.ok('/forms/7/submissions/count', 0);
    await pump(tester, FormSubmissionsScreen(form: _form(), apiService: backend.api), ['forms:read']);
    expect(find.text('Henüz yanıt yok.'), findsOneWidget);
  });

  group('forms list', () {
    testWidgets('row shows admin columns and opens the submissions', (tester) async {
      await pump(tester, GenericCrudListScreen(module: _forms, apiService: backend.api), ['forms:read']);

      expect(find.text('v3 · Gönderici: Bildirim'), findsOneWidget);
      expect(find.text('Bildirim: Açık'), findsOneWidget);
      expect(find.text('Aktif'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record_link_7')));
      await settle(tester);
      expect(find.byType(FormSubmissionsScreen), findsOneWidget);
    });

    testWidgets('409 on delete offers the cascade delete (admin ForceDeleteFormModal)', (tester) async {
      final deletes = <String>[];
      backend.routes['/forms/7'] = (req) {
        deletes.add(req.url.path);
        return jsonResponse({'result': false, 'message': 'Cannot perform operation due to related records'}, 409);
      };
      backend.routes['/forms/7/force'] = (req) {
        deletes.add(req.url.path);
        return okData(true);
      };
      await pump(tester, GenericCrudListScreen(module: _forms, apiService: backend.api), [
        'forms:read',
        'forms:delete',
      ]);

      await tester.tap(find.byKey(const ValueKey('delete_7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);
      expect(find.text('İlişkili kayıtlar mevcut'), findsOneWidget);
      await tester.tap(find.text('Evet, Tümünü Sil'));
      await settle(tester);

      expect(deletes, [endsWith('/forms/7'), endsWith('/forms/7/force')]);
    });

    testWidgets('other delete errors are shown, no cascade offer', (tester) async {
      backend.routes['/forms/7'] = (_) => jsonResponse({'result': false, 'message': 'boom'}, 500);
      await pump(tester, GenericCrudListScreen(module: _forms, apiService: backend.api), [
        'forms:read',
        'forms:delete',
      ]);

      await tester.tap(find.byKey(const ValueKey('delete_7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);
      expect(find.text('İlişkili kayıtlar mevcut'), findsNothing);
      expect(find.text('boom'), findsOneWidget);
      expect(backend.requestsTo('/forms/7/force'), isEmpty);
      await tester.pump(const Duration(seconds: 7));
    });
  });

  testWidgets('edit screen links to the submissions of the record', (tester) async {
    await pump(tester, GenericCrudFormScreen(module: _forms, initialData: _form(), apiService: backend.api), [
      'forms:read',
      'forms:update',
    ]);
    await tester.tap(find.byKey(const ValueKey('record_link_button')));
    await settle(tester);
    expect(find.byType(FormSubmissionsScreen), findsOneWidget);
    expect(backend.requestsTo('/forms/7/submissions/paged'), hasLength(1));
  });

  testWidgets('new form: no submissions link', (tester) async {
    await pump(tester, GenericCrudFormScreen(module: _forms, apiService: backend.api), ['forms:read', 'forms:create']);
    expect(find.byKey(const ValueKey('record_link_button')), findsNothing);
  });

  test('formatDateTimeTr: local dd.MM.yyyy HH:mm', () {
    expect(formatDateTimeTr('2026-02-14T09:05:00'), '14.02.2026 09:05');
    expect(formatDateTimeTr('nope'), '');
    expect(formatDateTimeTr(null), '');
  });

  test('submissionPayload tolerates a missing payload', () {
    expect(submissionPayload({'id': 1}), isEmpty);
  });
}
