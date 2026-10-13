import 'dart:convert';
import 'dart:io';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_form_screen.dart';
import 'package:elly_mobile_app/screens/forms/form_fields_screen.dart';
import 'package:elly_mobile_app/screens/forms/form_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

/// Admin-created wizard form as GET /forms/{id} returns it (Jackson writes every POJO key, nulls included),
/// plus a field type and keys the app doesn't know.
Map<String, dynamic> _adminForm() =>
    jsonDecode(File('test/fixtures/form_admin_wizard.json').readAsStringSync()) as Map<String, dynamic>;

final _forms = ModulesConfig.byKey('forms');
const _save = ValueKey('crud_save_button');

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late List<http.Request> sent;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    sent = [];
    backend.ok('/mail-accounts/active', [
      {'id': 2, 'name': 'Bildirim', 'fromAddress': 'noreply@example.com'},
      {'id': 4, 'name': 'Satış', 'fromAddress': 'sales@example.com'},
    ]);
    for (final path in ['/forms', '/forms/7']) {
      backend.routes[path] = (req) {
        sent.add(req);
        return okData({'id': 7});
      };
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpForm(
    WidgetTester tester, {
    Map<String, dynamic>? form,
    List<String> perms = const ['forms:read', 'forms:create', 'forms:update', 'mail:read'],
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, perms));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
          home: GenericCrudFormScreen(module: _forms, initialData: form, apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
  }

  /// Error SnackBars sit over the bottom bars, so buttons are pressed directly (like the other form tests).
  Future<void> press(WidgetTester tester, Key key) async {
    tester.widget<ElevatedButton>(find.byKey(key)).onPressed!();
    await settle(tester);
  }

  Future<void> tapSave(WidgetTester tester) => press(tester, _save);

  Map<String, dynamic> body() => jsonDecode(sent.single.body) as Map<String, dynamic>;

  Future<void> pick(WidgetTester tester, Key dropdown, String item) async {
    await tester.ensureVisible(find.byKey(dropdown));
    await tester.tap(find.byKey(dropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  /// Field editor: fill id/label/type (+ options as label→value) and apply.
  Future<void> addField(
    WidgetTester tester, {
    required String id,
    required String label,
    String? type,
    Map<String, String> options = const {},
  }) async {
    await tester.tap(find.byKey(const ValueKey('add_field_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field_id')), id);
    await tester.enterText(find.byKey(const ValueKey('field_label')), label);
    if (type != null) await pick(tester, const ValueKey('field_type'), type);
    for (final (i, o) in options.entries.indexed) {
      await tester.tap(find.byKey(const ValueKey('add_option_button')));
      await tester.pump();
      await tester.enterText(find.byKey(ValueKey('option_label_$i')), o.key);
      await tester.enterText(find.byKey(ValueKey('option_value_$i')), o.value);
    }
    await press(tester, const ValueKey('field_apply_button'));
  }

  group('round trip (tenant renders the saved schema)', () {
    testWidgets('admin schema opened and saved untouched goes back byte for byte', (tester) async {
      final form = _adminForm();
      await pumpForm(tester, form: form);
      await tapSave(tester);

      expect(sent.single.method, 'PUT');
      expect(jsonEncode(body()['schema']), jsonEncode(_adminForm()['schema']));
      expect(body()['version'], 3);
      expect(body()['senderMailAccountId'], 2);
    });

    testWidgets('editing other form fields leaves the schema as it was', (tester) async {
      await pumpForm(tester, form: _adminForm());
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Yeni Başlık');
      await tapSave(tester);

      expect(body()['title'], 'Yeni Başlık');
      expect(jsonEncode(body()['schema']), jsonEncode(_adminForm()['schema']));
    });

    testWidgets('opening a field and applying without changes keeps it (unknown type and keys too)', (tester) async {
      await pumpForm(tester, form: _adminForm());
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      expect(find.byType(FormFieldsScreen), findsOneWidget);
      expect(find.textContaining('star_rating'), findsOneWidget, reason: 'unknown type listed as is');

      await tester.tap(find.byKey(const ValueKey('field_row_7')));
      await tester.pumpAndSettle();
      await press(tester, const ValueKey('field_apply_button'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(jsonEncode(body()['schema']), jsonEncode(_adminForm()['schema']));
    });

    testWidgets('editing one field normalizes only that field, the rest stays identical', (tester) async {
      await pumpForm(tester, form: _adminForm());
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field_row_7')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field_label')), 'Puanınız');
      await press(tester, const ValueKey('field_apply_button'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapSave(tester);

      final fields = body()['schema']['fields'] as List;
      final original = _adminForm()['schema']['fields'] as List;
      expect(jsonEncode(fields.sublist(0, 7)), jsonEncode(original.sublist(0, 7)));
      expect(fields[7], {...original[7] as Map, 'label': 'Puanınız'});
      expect(jsonEncode(body()['schema']['steps']), jsonEncode(_adminForm()['schema']['steps']));
      expect(body()['schema']['config'], _adminForm()['schema']['config']);
    });
  });

  group('builder', () {
    testWidgets('new form: add, reorder, condition, delete → admin-shaped schema', (tester) async {
      await pumpForm(tester);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'İletişim');
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();

      await addField(tester, id: 'name', label: 'Ad');
      await addField(
        tester,
        id: 'topic',
        label: 'Konu',
        type: 'Seçim Kutusu',
        options: {'Destek': 'support', 'Satış': 'sales'},
      );
      await addField(tester, id: 'temp', label: 'Geçici');

      // Condition on "Ad" watching "topic".
      await tester.tap(find.byKey(const ValueKey('field_row_0')));
      await tester.pumpAndSettle();
      await pick(tester, const ValueKey('condition_field'), 'Konu');
      await pick(tester, const ValueKey('condition_operator'), 'Eşit Değil');
      await tester.enterText(find.byKey(const ValueKey('condition_value')), 'sales');
      expect(find.text('Seçenek değerleri: support, sales'), findsOneWidget);
      await press(tester, const ValueKey('field_apply_button'));

      // Move "topic" first, delete "temp".
      tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorderItem!(1, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete_field_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_field_delete')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2 alan · 1 koşullu'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field_recipientEmail')), 'ops@example.com');
      await pick(tester, const ValueKey('field_senderMailAccountId_2'), '4 • Satış (sales@example.com)');
      await tapSave(tester);

      expect(sent.single.method, 'POST');
      expect(body(), {
        'title': 'İletişim',
        'schema': {
          'config': {'layout': 'vertical', 'submitLabel': 'Gönder'},
          'fields': [
            {
              'id': 'topic',
              'type': 'select',
              'label': 'Konu',
              'required': false,
              'options': [
                {'label': 'Destek', 'value': 'support'},
                {'label': 'Satış', 'value': 'sales'},
              ],
              'validation': null,
              'condition': null,
            },
            {
              'id': 'name',
              'type': 'text',
              'label': 'Ad',
              'required': false,
              'options': null,
              'validation': null,
              'condition': {'field': 'topic', 'operator': 'NOT_EQUALS', 'value': 'sales'},
            },
          ],
        },
        'active': true,
        'senderMailAccountId': 4,
        'recipientEmail': 'ops@example.com',
        'notificationSubject': '',
        'notificationEnabled': true,
      });
    });

    testWidgets('renaming a field id moves the conditions that watch it', (tester) async {
      await pumpForm(tester, form: _adminForm());
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field_row_2'))); // age
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field_id')), 'years');
      await press(tester, const ValueKey('field_apply_button'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapSave(tester);

      final fields = body()['schema']['fields'] as List;
      expect(fields[2]['id'], 'years');
      expect(fields[3]['condition'], {'field': 'years', 'operator': 'GT', 'value': 18});
    });

    testWidgets('field editor validates id, label and options; back with edits asks first', (tester) async {
      await pumpForm(tester, form: _adminForm());
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add_field_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('field_id')), 'email');
      await pick(tester, const ValueKey('field_type'), 'Radyo Buton');
      await press(tester, const ValueKey('field_apply_button'));
      expect(find.text('Bu ID zaten kullanılıyor'), findsOneWidget);
      expect(find.text('Etiket zorunludur'), findsOneWidget);
      expect(find.text('Seçim kutusu ve radyo buton için en az bir seçenek gereklidir'), findsOneWidget);
      expect(find.text('3 alan hatalı'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field_id')), '1bad');
      await press(tester, const ValueKey('field_apply_button'));
      expect(find.text('ID sadece harf, rakam ve alt çizgi içerebilir'), findsOneWidget);

      await tester.binding.handlePopRoute(); // system back on the full-screen editor
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm_leave_button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_leave_button')));
      await tester.pumpAndSettle();
      expect(find.byType(FieldEditScreen), findsNothing);
      expect(find.byType(FormFieldsScreen), findsOneWidget);
    });

    testWidgets('invalid regex and non-integer min are rejected', (tester) async {
      await pumpForm(tester, form: _adminForm());
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field_row_0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('validation_min')), '1.5');
      await tester.enterText(find.byKey(const ValueKey('validation_pattern')), '([a-z');
      await press(tester, const ValueKey('field_apply_button'));
      expect(find.text('Tam sayı girin'), findsOneWidget);
      expect(find.text('Geçersiz RegEx'), findsOneWidget);
    });

    testWidgets('save blocked without fields; wizard needs steps and every field on a step', (tester) async {
      await pumpForm(tester);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Boş');
      await tester.enterText(find.byKey(const ValueKey('field_recipientEmail')), 'ops@example.com');
      await pick(tester, const ValueKey('field_senderMailAccountId_2'), '2 • Bildirim (noreply@example.com)');
      await tapSave(tester);
      expect(sent, isEmpty);
      expect(find.text('En az bir alan eklemelisiniz'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await addField(tester, id: 'name', label: 'Ad');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await pick(tester, const ValueKey('schema_layout'), 'Sihirbaz (Çok Adımlı)');
      await tapSave(tester);
      expect(sent, isEmpty);
      expect(find.text('Sihirbaz modunda en az bir adım eklemelisiniz'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add_step_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('step_title')), 'Bilgiler');
      await tester.tap(find.byKey(const ValueKey('step_save')));
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(sent, isEmpty);
      expect(find.textContaining('Atanmamış alanlar: Ad'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field_row_0')));
      await tester.pumpAndSettle();
      await pick(tester, const ValueKey('field_step'), 'Bilgiler');
      await press(tester, const ValueKey('field_apply_button'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapSave(tester);

      final schema = body()['schema'] as Map<String, dynamic>;
      final step = (schema['steps'] as List).single as Map;
      expect(step['title'], 'Bilgiler');
      expect(step['description'], '');
      expect(step['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect((schema['fields'] as List).single['stepId'], step['id']);
      expect(schema['config'], {'layout': 'wizard', 'submitLabel': 'Gönder'});
    });

    testWidgets('leaving the wizard layout drops the steps from the payload (admin does too)', (tester) async {
      await pumpForm(tester, form: _adminForm());
      await pick(tester, const ValueKey('schema_layout'), 'Dikey (Tek Sayfa)');
      await tapSave(tester);

      final schema = body()['schema'] as Map<String, dynamic>;
      expect(schema.containsKey('steps'), isFalse);
      expect(schema['config'], {'layout': 'vertical', 'submitLabel': 'Başvur', 'theme': 'compact'});
    });

    testWidgets('steps can be reordered and edited', (tester) async {
      await pumpForm(tester, form: _adminForm());
      tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorderItem!(1, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('step_1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('step_title')), 'Kişisel');
      await tester.tap(find.byKey(const ValueKey('step_save')));
      await tester.pumpAndSettle();
      await tapSave(tester);

      final steps = body()['schema']['steps'] as List;
      expect(steps.map((s) => s['title']), ['Talep', 'Kişisel']);
      expect(steps[1]['description'], 'Sizi tanıyalım');
      expect(steps[1]['id'], '9b2f6c1e-1d2a-4c3b-8e7f-0a1b2c3d4e5f');
    });
  });

  group('notification settings (backend validateNotificationConfig)', () {
    testWidgets('sender + recipient required only while notifications are on', (tester) async {
      await pumpForm(tester);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Anket');
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await addField(tester, id: 'q', label: 'Soru');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapSave(tester);
      expect(sent, isEmpty);
      expect(find.text('Gönderici Mail Hesabı zorunlu'), findsOneWidget);
      expect(find.text('Alıcı E-posta zorunlu'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('field_notificationEnabled')));
      await tester.tap(find.byKey(const ValueKey('field_notificationEnabled')));
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(body()['notificationEnabled'], isFalse);
      expect(body().containsKey('senderMailAccountId'), isFalse);
    });

    testWidgets('sender not in the active list shows the current account; no mail:read → no request', (tester) async {
      await pumpForm(tester, form: {..._adminForm(), 'senderMailAccountId': 9}, perms: ['forms:update']);

      expect(backend.requestsTo('/mail-accounts/active'), isEmpty);
      expect(find.text('Mevcut hesap: Bildirim (noreply@example.com)'), findsOneWidget);
      await tapSave(tester);
      expect(body()['senderMailAccountId'], 9);
    });

    testWidgets('active accounts listed as "id • name (from)"', (tester) async {
      await pumpForm(tester, form: _adminForm());
      expect(find.text('2 • Bildirim (noreply@example.com)'), findsOneWidget);
    });
  });

  group('preview', () {
    Future<void> pumpPreview(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: FormPreviewScreen(title: 'Başvuru', schema: _adminForm()['schema'] as Map<String, dynamic>),
        ),
      );
    }

    testWidgets('conditions follow the inputs; steps as sections; payload has only visible fields', (tester) async {
      await pumpPreview(tester);
      expect(find.text('1. Kişisel Bilgiler'), findsOneWidget);
      expect(find.text('2. Talep'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview_company')), findsNothing);
      expect(find.byKey(const ValueKey('preview_interests')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('preview_age')), '30');
      await tester.pump();
      expect(find.byKey(const ValueKey('preview_company')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('preview_topic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Satış').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preview_interests')), findsOneWidget);
      await tester.tap(find.text('Mobil'));
      await tester.enterText(find.byKey(const ValueKey('preview_company')), 'Acme');
      await tester.enterText(find.byKey(const ValueKey('preview_age')), '17');
      await tester.pump();
      expect(find.byKey(const ValueKey('preview_company')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('preview_submit')));
      await tester.pumpAndSettle();
      final payload = jsonDecode(tester.widget<SelectableText>(find.byKey(const ValueKey('preview_payload'))).data!);
      expect(payload, {
        'name': '',
        'email': '',
        'age': 17,
        'topic': 'sales',
        'interests': ['mobile'],
        'kvkk': false,
        'rating': '',
      });
      expect(find.text('Başvur'), findsOneWidget);
    });
  });
}
