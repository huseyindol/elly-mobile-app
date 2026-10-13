import 'dart:convert';
import 'dart:io';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_form_screen.dart';
import 'package:elly_mobile_app/screens/forms/form_fields_screen.dart';
import 'package:elly_mobile_app/services/form_schema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

/// Edge cases of the form builder that `forms_builder_test.dart` / `form_schema_test.dart` leave out:
/// deleting wizard steps, chained / cyclic condition targets, option lists, min/max and regex.

Map<String, dynamic> _adminForm() =>
    jsonDecode(File('test/fixtures/form_admin_wizard.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _f(String id, {String? watches, Object? value = 'x', String op = 'EQUALS'}) => {
  'id': id,
  'type': 'text',
  'label': id.toUpperCase(),
  'condition': watches == null ? null : {'field': watches, 'operator': op, 'value': value},
};


void main() {
  group('renameConditionTarget: chains and cycles', () {
    test('only the conditions that watch the renamed field move, a chain stays intact', () {
      // c watches b, b watches a. Renaming a must not drag c along.
      final fields = [_f('a'), _f('b', watches: 'a'), _f('c', watches: 'b')];
      renameConditionTarget(fields, 'a', 'x');

      expect(fields[1]['condition']['field'], 'x');
      expect(fields[2]['condition']['field'], 'b');
    });

    test('a two-field cycle terminates; each rename moves exactly the opposite condition', () {
      final fields = [_f('a', watches: 'b'), _f('b', watches: 'a')];

      renameConditionTarget(fields, 'a', 'c');
      expect(fields[0]['condition']['field'], 'b');
      expect(fields[1]['condition']['field'], 'c');

      renameConditionTarget(fields, 'b', 'd');
      expect(fields[0]['condition']['field'], 'd');
      expect(fields[1]['condition']['field'], 'c');
    });

    test('renaming a field that watches itself keeps it self-referencing under the new id', () {
      final fields = [_f('a', watches: 'a')];
      fields[0]['id'] = 'x'; // what the editor does before renameConditionTarget runs
      renameConditionTarget(fields, 'a', 'x');
      expect(fields[0]['condition']['field'], 'x');
    });

    test('operator and typed value of a moved condition are untouched', () {
      final fields = [_f('a'), _f('b', watches: 'a', value: 18, op: 'GT')];
      renameConditionTarget(fields, 'a', 'x');
      expect(fields[1]['condition'], {'field': 'x', 'operator': 'GT', 'value': 18});
    });

    test('empty old id (new field), same id, non-map and null conditions are no-ops', () {
      final fields = [
        _f('a'),
        {'id': 'b', 'condition': 'garbage'},
        {'id': 'c'},
        _f('d', watches: ''),
      ];
      final before = jsonEncode(fields);
      renameConditionTarget(fields, '', 'x');
      renameConditionTarget(fields, 'a', 'a');
      renameConditionTarget(fields, 'zzz', 'x');
      expect(jsonEncode(fields), before);
    });

    test('a cycle never hangs the evaluator: both fields hidden until a value matches', () {
      final a = _f('a', watches: 'b');
      final b = _f('b', watches: 'a');
      expect(isFormFieldVisible(a, {}), isFalse);
      expect(isFormFieldVisible(b, {}), isFalse);
      expect(isFormFieldVisible(a, {'b': 'x'}), isTrue);
      expect(isFormFieldVisible(b, {'b': 'x'}), isFalse);
    });

    test('dependentFields: direct watchers only, ignores broken conditions', () {
      final fields = [_f('a'), _f('b', watches: 'a'), _f('c', watches: 'b'), {'id': 'd', 'condition': 5}];
      expect(dependentFields(fields, 'a').map((f) => f['id']), ['b']);
      expect(dependentFields(fields, 'c'), isEmpty);
    });
  });

  group('schemaError: wizard after steps are deleted', () {
    Map<String, dynamic> wizard(List<Map<String, dynamic>> fields, Object? steps) => {
      'config': {'layout': 'wizard'},
      'fields': fields,
      'steps': ?steps,
    };

    test('fields pointing at a removed step are listed with their labels', () {
      final schema = wizard(
        [
          {'id': 'a', 'label': 'Ad', 'stepId': 's1'},
          {'id': 'b', 'label': 'Yaş', 'stepId': 's2'},
          {'id': 'c', 'label': '  ', 'stepId': 's2'},
        ],
        [
          {'id': 's1', 'title': 'Bir'},
        ],
      );
      expect(schemaError(schema), contains('Atanmamış alanlar: Yaş, Başlıksız Alan'));
      expect(schemaError(schema), isNot(contains('Ad')));
    });

    test('all steps deleted → the step message comes first, not the per-field one', () {
      final schema = wizard([
        {'id': 'a', 'label': 'Ad', 'stepId': 's1'},
      ], <Object>[]);
      expect(schemaError(schema), 'Sihirbaz modunda en az bir adım eklemelisiniz');
    });

    test('no fields wins over a missing step; steps of a non-wizard layout are not checked', () {
      expect(schemaError(wizard(<Map<String, dynamic>>[], null)), 'En az bir alan eklemelisiniz');
      expect(
        schemaError({
          'config': {'layout': 'vertical'},
          'fields': [
            {'id': 'a', 'label': 'Ad', 'stepId': 'gone'},
          ],
        }),
        isNull,
      );
    });

    test('empty / null stepId and malformed step entries do not count as a step', () {
      final schema = wizard(
        [
          {'id': 'a', 'label': 'Ad', 'stepId': ''},
          {'id': 'b', 'label': 'Soyad'},
        ],
        ['not a map', null, 3],
      );
      expect(schemaError(schema), 'Sihirbaz modunda en az bir adım eklemelisiniz');
    });
  });

  group('normalizeField: option and validation edges', () {
    test('only blank option rows → options null; blank rows next to real ones are dropped', () {
      expect(
        normalizeField({
          'type': 'select',
          'options': [
            {'label': '', 'value': ''},
            {'label': ' ', 'value': 'x'},
          ],
        })['options'],
        isNull,
      );
      final kept = normalizeField({
        'type': 'radio',
        'options': [
          {'label': 'A', 'value': 'a'},
          {'label': '', 'value': ''},
          {'label': 'B', 'value': 0},
        ],
      })['options'];
      expect(kept, [
        {'label': 'A', 'value': 'a'},
        {'label': 'B', 'value': 0},
      ]);
    });

    test('min 0 is a real limit (kept), empty pattern with no limits drops validation', () {
      expect(
        normalizeField({
          'type': 'number',
          'validation': {'min': 0, 'max': null, 'pattern': null},
        })['validation'],
        isNotNull,
      );
      expect(
        normalizeField({
          'type': 'number',
          'validation': {'min': null, 'max': null, 'pattern': ''},
        })['validation'],
        isNull,
      );
    });
  });

  group('field editor (widget)', () {
    late FakeBackend backend;
    late AuthProvider auth;
    late List<http.Request> sent;

    setUp(() {
      backend = FakeBackend();
      auth = backend.newAuth();
      sent = [];
      backend.ok('/mail-accounts/active', [
        {'id': 2, 'name': 'Bildirim', 'fromAddress': 'noreply@example.com'},
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

    Future<void> pumpForm(WidgetTester tester, {Map<String, dynamic>? form}) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(
        () => backend.signIn(auth, ['forms:read', 'forms:create', 'forms:update', 'mail:read']),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
            home: GenericCrudFormScreen(module: ModulesConfig.byKey('forms'), initialData: form, apiService: backend.api),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> press(WidgetTester tester, Key key) async {
      tester.widget<ElevatedButton>(find.byKey(key)).onPressed!();
      await settle(tester);
    }

    Future<void> save(WidgetTester tester) => press(tester, const ValueKey('crud_save_button'));

    Map<String, dynamic> body() => jsonDecode(sent.single.body) as Map<String, dynamic>;
    List<dynamic> savedFields() => (body()['schema'] as Map)['fields'] as List;

    Future<void> pick(WidgetTester tester, Key dropdown, String item) async {
      await tester.ensureVisible(find.byKey(dropdown));
      await tester.tap(find.byKey(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    Future<void> openFields(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
    }

    Future<void> back(WidgetTester tester) async {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    Future<void> openField(WidgetTester tester, int row) async {
      await tester.tap(find.byKey(ValueKey('field_row_$row')));
      await tester.pumpAndSettle();
    }

    Future<void> deleteStep(WidgetTester tester, int index) async {
      await tester.tap(find.byTooltip('Adımı sil').at(index));
      await tester.pumpAndSettle();
    }

    /// New form with notifications off (no sender / recipient needed) and a title.
    Future<void> pumpNewForm(WidgetTester tester) async {
      await pumpForm(tester);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Test');
      await tester.ensureVisible(find.byKey(const ValueKey('field_notificationEnabled')));
      await tester.tap(find.byKey(const ValueKey('field_notificationEnabled')));
      await tester.pumpAndSettle();
    }

    Future<void> startField(WidgetTester tester, String id, String label, {String? type}) async {
      await tester.tap(find.byKey(const ValueKey('add_field_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field_id')), id);
      await tester.enterText(find.byKey(const ValueKey('field_label')), label);
      if (type != null) await pick(tester, const ValueKey('field_type'), type);
    }

    Future<void> addOption(WidgetTester tester, int i, String label, String value) async {
      await tester.tap(find.byKey(const ValueKey('add_option_button')));
      await tester.pump();
      await tester.enterText(find.byKey(ValueKey('option_label_$i')), label);
      await tester.enterText(find.byKey(ValueKey('option_value_$i')), value);
    }

    group('wizard steps', () {
      testWidgets('deleting a step warns with its field count; the fields keep the dead stepId and save is blocked',
          (tester) async {
        await pumpForm(tester, form: _adminForm());
        await deleteStep(tester, 1); // "Talep": company, topic, interests, kvkk, rating

        expect(find.text('Adım silinsin mi?'), findsOneWidget);
        expect(find.textContaining('Bu adımdaki 5 alan bir adıma yeniden atanmalı'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('confirm_step_delete')));
        await tester.pumpAndSettle();
        expect(find.text('Adımlar (1)'), findsOneWidget);

        await save(tester);
        expect(sent, isEmpty);
        expect(
          find.textContaining('Atanmamış alanlar: Şirket, Konu, İlgi Alanları, KVKK metnini onaylıyorum, Puan'),
          findsOneWidget,
        );
      });

      testWidgets('cancelling the step delete keeps everything; a step without fields deletes without a count',
          (tester) async {
        await pumpForm(tester, form: _adminForm());
        await deleteStep(tester, 0);
        await tester.tap(find.text('Vazgeç'));
        await tester.pumpAndSettle();
        expect(find.text('Adımlar (2)'), findsOneWidget);

        await save(tester);
        expect(jsonEncode(body()['schema']), jsonEncode(_adminForm()['schema']));
      });

      testWidgets('orphaned fields are flagged in the list, the editor offers the missing step, reassigning clears it',
          (tester) async {
        await pumpForm(tester, form: _adminForm());
        await deleteStep(tester, 1);
        await tester.tap(find.byKey(const ValueKey('confirm_step_delete')));
        await tester.pumpAndSettle();

        await openFields(tester);
        expect(find.textContaining('Adım atanmadı'), findsNWidgets(5));
        await openField(tester, 3); // company
        expect(find.text('Bilinmeyen adım'), findsOneWidget);
        await pick(tester, const ValueKey('field_step'), 'Kişisel Bilgiler');
        await press(tester, const ValueKey('field_apply_button'));
        expect(find.textContaining('Adım atanmadı'), findsNWidgets(4));
        await back(tester);

        await save(tester);
        expect(sent, isEmpty);
        expect(find.textContaining('Atanmamış alanlar: Konu'), findsOneWidget);
        expect(find.textContaining('Şirket,'), findsNothing, reason: 'reassigned field no longer listed');
      });

      testWidgets('deleting every step → "en az bir adım"; field editor no longer offers a step picker',
          (tester) async {
        await pumpForm(tester, form: _adminForm());
        await deleteStep(tester, 1);
        await tester.tap(find.byKey(const ValueKey('confirm_step_delete')));
        await tester.pumpAndSettle();
        await deleteStep(tester, 0);
        await tester.tap(find.byKey(const ValueKey('confirm_step_delete')));
        await tester.pumpAndSettle();
        expect(find.text('Adımlar (0)'), findsOneWidget);

        await save(tester);
        expect(sent, isEmpty);
        expect(find.text('Sihirbaz modunda en az bir adım eklemelisiniz'), findsOneWidget);

        await openFields(tester);
        await openField(tester, 0);
        expect(find.byKey(const ValueKey('field_step')), findsNothing);
      });
    });

    group('id rename with conditions', () {
      testWidgets('a cycle (age watches company, company watches age) follows both renames', (tester) async {
        final form = _adminForm();
        final fields = (form['schema'] as Map)['fields'] as List;
        (fields[2] as Map)['condition'] = {'field': 'company', 'operator': 'EQUALS', 'value': 'acme'};
        await pumpForm(tester, form: form);
        await openFields(tester);

        await openField(tester, 2); // age → years
        await tester.enterText(find.byKey(const ValueKey('field_id')), 'years');
        await press(tester, const ValueKey('field_apply_button'));
        await openField(tester, 3); // company → firm
        await tester.enterText(find.byKey(const ValueKey('field_id')), 'firm');
        await press(tester, const ValueKey('field_apply_button'));
        await back(tester);
        await save(tester);

        final saved = savedFields();
        expect(saved[2]['id'], 'years');
        expect(saved[3]['id'], 'firm');
        expect(saved[2]['condition'], {'field': 'firm', 'operator': 'EQUALS', 'value': 'acme'});
        expect(saved[3]['condition'], {'field': 'years', 'operator': 'GT', 'value': 18});
      });

      testWidgets('renaming a watched select moves the condition of the field that watches it', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 4); // topic → subject
        await tester.enterText(find.byKey(const ValueKey('field_id')), 'subject');
        await press(tester, const ValueKey('field_apply_button'));
        await back(tester);
        await save(tester);

        expect(savedFields()[5]['condition'], {'field': 'subject', 'operator': 'EQUALS', 'value': 'sales'});
      });

      testWidgets('editing a field without touching the id leaves every condition as it was', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 2);
        await tester.enterText(find.byKey(const ValueKey('field_label')), 'Yaşınız');
        await press(tester, const ValueKey('field_apply_button'));
        await back(tester);
        await save(tester);

        expect(savedFields()[3]['condition'], {'field': 'age', 'operator': 'GT', 'value': 18});
      });
    });

    group('options', () {
      testWidgets('rows that are all blank do not satisfy "at least one option"', (tester) async {
        await pumpNewForm(tester);
        await openFields(tester);
        await startField(tester, 'q', 'Soru', type: 'Seçim Kutusu');
        await tester.tap(find.byKey(const ValueKey('add_option_button')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('add_option_button')));
        await tester.pump();
        await press(tester, const ValueKey('field_apply_button'));

        expect(find.text('Seçim kutusu ve radyo buton için en az bir seçenek gereklidir'), findsOneWidget);
        expect(find.byType(FieldEditScreen), findsOneWidget);
      });

      testWidgets('half-filled rows are flagged on the missing side', (tester) async {
        await pumpNewForm(tester);
        await openFields(tester);
        await startField(tester, 'q', 'Soru', type: 'Radyo Buton');
        await addOption(tester, 0, 'Evet', '');
        await addOption(tester, 1, '', 'no');
        await press(tester, const ValueKey('field_apply_button'));

        expect(find.text('Değer girin'), findsOneWidget);
        expect(find.text('Etiket girin'), findsOneWidget);
        expect(find.byType(FieldEditScreen), findsOneWidget);
      });

      testWidgets('a blank row between real ones is dropped from the saved schema', (tester) async {
        await pumpNewForm(tester);
        await openFields(tester);
        await startField(tester, 'q', 'Soru', type: 'Çoklu Seçim (Checkbox Group)');
        await addOption(tester, 0, 'A', 'a');
        await tester.tap(find.byKey(const ValueKey('add_option_button')));
        await tester.pump();
        await addOption(tester, 2, 'C', 'c');
        await press(tester, const ValueKey('field_apply_button'));
        await back(tester);
        await save(tester);

        expect(savedFields().single['options'], [
          {'label': 'A', 'value': 'a'},
          {'label': 'C', 'value': 'c'},
        ]);
      });

      testWidgets('switching an option type to text drops the options', (tester) async {
        await pumpNewForm(tester);
        await openFields(tester);
        await startField(tester, 'q', 'Soru', type: 'Seçim Kutusu');
        await addOption(tester, 0, 'A', 'a');
        await press(tester, const ValueKey('field_apply_button'));

        await openField(tester, 0);
        await pick(tester, const ValueKey('field_type'), 'Metin');
        expect(find.byKey(const ValueKey('options_section')), findsNothing);
        await press(tester, const ValueKey('field_apply_button'));
        await back(tester);
        await save(tester);

        final field = savedFields().single as Map;
        expect(field['type'], 'text');
        expect(field['options'], isNull);
      });
    });

    group('validation limits and pattern', () {
      testWidgets('clearing min and max of a field without pattern removes its validation', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 0); // name: min 2, max 100
        await tester.enterText(find.byKey(const ValueKey('validation_min')), '');
        await tester.enterText(find.byKey(const ValueKey('validation_max')), '');
        await press(tester, const ValueKey('field_apply_button'));
        await back(tester);
        await save(tester);

        expect(savedFields()[0]['validation'], isNull);
      });

      testWidgets('negative and zero limits are valid integers, stored as numbers', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 0);
        await tester.enterText(find.byKey(const ValueKey('validation_min')), '-5');
        await tester.enterText(find.byKey(const ValueKey('validation_max')), '0');
        await press(tester, const ValueKey('field_apply_button'));
        await back(tester);
        await save(tester);

        expect(savedFields()[0]['validation'], {'min': -5, 'max': 0, 'pattern': null});
      });

      testWidgets('exponent / decimal limits are rejected (backend Integer)', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 0);
        await tester.enterText(find.byKey(const ValueKey('validation_min')), '1e3');
        await tester.enterText(find.byKey(const ValueKey('validation_max')), '2.0');
        await press(tester, const ValueKey('field_apply_button'));

        expect(find.text('Tam sayı girin'), findsNWidgets(2));
        expect(find.byType(FieldEditScreen), findsOneWidget);
      });

      testWidgets('an invalid regex blocks "Uygula" until fixed, then the valid pattern is stored', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 0);
        await tester.enterText(find.byKey(const ValueKey('validation_pattern')), r'(\d');
        await press(tester, const ValueKey('field_apply_button'));
        expect(find.text('Geçersiz RegEx'), findsOneWidget);
        expect(find.byType(FieldEditScreen), findsOneWidget);

        await tester.enterText(find.byKey(const ValueKey('validation_pattern')), r'^[A-Za-z ]+$');
        await press(tester, const ValueKey('field_apply_button'));
        expect(find.byType(FieldEditScreen), findsNothing);
        await back(tester);
        await save(tester);

        expect(savedFields()[0]['validation'], {'min': 2, 'max': 100, 'pattern': r'^[A-Za-z ]+$'});
      });

      testWidgets('an invalid regex never reaches the saved schema when the editor is abandoned', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 0);
        await tester.enterText(find.byKey(const ValueKey('validation_pattern')), '[a-');
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('confirm_leave_button')));
        await tester.pumpAndSettle();
        await back(tester);
        await save(tester);

        expect(jsonEncode(body()['schema']), jsonEncode(_adminForm()['schema']));
      });

      // KNOWN BUG (skip): form_fields_screen.dart yalnız tam sayı ve RegEx doğruluyor; min>max kabul ediliyor.
      // Admin de doğrulamıyor ama tenant formu hiçbir değerle gönderilemez hale gelir.
      testWidgets('min greater than max is rejected', (tester) async {
        await pumpForm(tester, form: _adminForm());
        await openFields(tester);
        await openField(tester, 0);
        await tester.enterText(find.byKey(const ValueKey('validation_min')), '50');
        await tester.enterText(find.byKey(const ValueKey('validation_max')), '5');
        await press(tester, const ValueKey('field_apply_button'));

        expect(find.byType(FieldEditScreen), findsOneWidget, reason: 'min 50 / max 5 can never be satisfied');
      }, skip: true); // BULGU: FieldEditScreen min>max'i kabul ediyor (admin de doğrulamıyor)
    });
  });
}
