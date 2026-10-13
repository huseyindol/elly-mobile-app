import 'dart:convert';
import 'dart:io';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_form_screen.dart';
import 'package:elly_mobile_app/screens/forms/form_fields_screen.dart';
import 'package:elly_mobile_app/screens/forms/form_submissions_screen.dart';
import 'package:elly_mobile_app/widgets/reorder_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

/// Review fixes of phase 2: non-drag reordering (visible + screen reader), undo, SnackBars above the save
/// bar, validation of a new field, live re-validation of the schema, empty sender explanation.

Map<String, dynamic> _adminForm() =>
    jsonDecode(File('test/fixtures/form_admin_wizard.json').readAsStringSync()) as Map<String, dynamic>;

final _forms = ModulesConfig.byKey('forms');

List<Map<String, dynamic>> _three() => [
  {'id': 'a', 'type': 'text', 'label': 'Bir', 'required': true},
  {'id': 'b', 'type': 'text', 'label': 'İki', 'required': false},
  {'id': 'c', 'type': 'text', 'label': 'Üç', 'required': false},
];

void main() {
  group('field list (FormFieldsScreen)', () {
    late List<List<Map<String, dynamic>>> emitted;

    Future<void> pumpList(WidgetTester tester, [List<Map<String, dynamic>>? fields]) async {
      emitted = [];
      await tester.pumpWidget(
        MaterialApp(
          home: FormFieldsScreen(fields: fields ?? _three(), steps: const [], onChanged: emitted.add),
        ),
      );
    }

    List<Object?> ids() => [for (final f in emitted.last) f['id']];

    testWidgets('screen reader: "Yukarı taşı" / "Aşağı taşı" on the row move it', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);

      final row = find.semantics.byPredicate(
        (n) => n.label.contains('İki') && n.getSemanticsData().customSemanticsActionIds!.isNotEmpty,
      );
      tester.semantics.customAction(row, moveUpAction);
      await tester.pumpAndSettle();
      expect(ids(), ['b', 'a', 'c']);

      final moved = find.semantics.byPredicate(
        (n) => n.label.contains('Bir') && n.getSemanticsData().customSemanticsActionIds!.isNotEmpty,
      );
      tester.semantics.customAction(moved, moveDownAction);
      await tester.pumpAndSettle();
      expect(ids(), ['b', 'c', 'a']);
      handle.dispose();
    });

    testWidgets('first row has no "Yukarı taşı", last row no "Aşağı taşı"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);
      List<String> actions(String label) {
        final node = find.semantics
            .byPredicate((n) => n.label.contains(label) && n.getSemanticsData().customSemanticsActionIds!.isNotEmpty)
            .evaluate()
            .single;
        return [
          for (final id in node.getSemanticsData().customSemanticsActionIds!)
            CustomSemanticsAction.getAction(id)!.label!,
        ];
      }

      expect(actions('Bir'), contains('Aşağı taşı'));
      expect(actions('Bir'), isNot(contains('Yukarı taşı')));
      expect(actions('Üç'), contains('Yukarı taşı'));
      expect(actions('Üç'), isNot(contains('Aşağı taşı')));
      handle.dispose();
    });

    testWidgets('drag handle: hidden from screen readers, 48 dp target', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);
      final drag = find.byIcon(Icons.drag_handle_rounded).first;
      final size = tester.getSize(find.ancestor(of: drag, matching: find.byType(SizedBox)).first);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.ancestor(of: drag, matching: find.byType(ExcludeSemantics)), findsOneWidget);
      handle.dispose();
    });

    testWidgets('visible "Taşı" menu moves a row; undo restores the order', (tester) async {
      await pumpList(tester);
      await tester.tap(find.byKey(const ValueKey('move_field_2')));
      await tester.pumpAndSettle();
      expect(find.text('Aşağı taşı'), findsNothing, reason: 'last row cannot go down');
      await tester.tap(find.text('Yukarı taşı'));
      await tester.pumpAndSettle();
      expect(ids(), ['a', 'c', 'b']);
      expect(find.text('"Üç" taşındı'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(ids(), ['a', 'b', 'c']);
    });

    testWidgets('delete offers undo; the note says changes are sent with Kaydet', (tester) async {
      await pumpList(tester);
      expect(find.text("Değişiklikler formu Kaydet'te gönderilir."), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete_field_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_field_delete')));
      await tester.pumpAndSettle();
      expect(ids(), ['a', 'c']);
      expect(find.text('"İki" silindi'), findsOneWidget);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(ids(), ['a', 'b', 'c']);
    });

    testWidgets('required star is read as "zorunlu"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpList(tester);
      expect(find.semantics.byPredicate((n) => n.label.contains('Bir, zorunlu')), findsWidgets);
      handle.dispose();
    });

    testWidgets('new field: "Uygula" without typing anything validates instead of closing', (tester) async {
      await pumpList(tester);
      await tester.tap(find.byKey(const ValueKey('add_field_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field_apply_button')));
      await tester.pumpAndSettle();

      expect(find.byType(FieldEditScreen), findsOneWidget);
      expect(find.text('Alan ID zorunludur'), findsOneWidget);
      expect(find.text('2 alan hatalı: Alan ID'), findsOneWidget);
      expect(emitted, isEmpty);
    });

    testWidgets('error SnackBar sits above the Uygula bar; a successful apply clears it', (tester) async {
      await pumpList(tester);
      await tester.tap(find.byKey(const ValueKey('add_field_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field_apply_button')));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byKey(const ValueKey('field_apply_button')));
      final snack = tester.getRect(find.byType(SnackBar));
      expect(snack.bottom, lessThanOrEqualTo(bar.top), reason: 'SnackBar must not cover the button');
      expect(find.byKey(const ValueKey('field_apply_button')).hitTestable(), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field_id')), 'd');
      await tester.enterText(find.byKey(const ValueKey('field_label')), 'Dört');
      await tester.tap(find.byKey(const ValueKey('field_apply_button')));
      await tester.pumpAndSettle();
      expect(find.byType(FieldEditScreen), findsNothing);
      expect(find.byType(SnackBar), findsNothing, reason: 'stale error removed on success');
      expect(ids(), ['a', 'b', 'c', 'd']);
    });

    testWidgets('option rows: side by side normally, stacked on large text', (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<(Rect, Rect)> rects(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: const FieldEditScreen(
                  field: {
                    'id': 'x',
                    'type': 'select',
                    'label': 'X',
                    'options': [
                      {'label': 'A', 'value': 'a'},
                    ],
                  },
                  otherFields: [],
                ),
              ),
            ),
          ),
        );
        return (
          tester.getRect(find.byKey(const ValueKey('option_label_0'))),
          tester.getRect(find.byKey(const ValueKey('option_value_0'))),
        );
      }

      final (label1, value1) = await rects(1);
      expect(value1.left, greaterThan(label1.right - 1), reason: 'value beside label');
      final (label2, value2) = await rects(2);
      expect(value2.top, greaterThan(label2.bottom - 1), reason: 'value below label');
    });
  });

  group('form screen', () {
    late FakeBackend backend;
    late AuthProvider auth;

    setUp(() {
      backend = FakeBackend();
      auth = backend.newAuth();
      backend.ok('/mail-accounts/active', <Object>[]);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> pumpForm(WidgetTester tester, List<String> perms, {Map<String, dynamic>? form}) async {
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

    testWidgets('schema error clears as soon as a field is added', (tester) async {
      await pumpForm(tester, ['forms:create', 'mail:read']);
      await tester.tap(find.byKey(const ValueKey('crud_save_button')));
      await settle(tester);
      expect(find.text('En az bir alan eklemelisiniz'), findsOneWidget);
      expect(find.byKey(const ValueKey('crud_save_button')).hitTestable(), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open_fields_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add_field_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field_id')), 'q');
      await tester.enterText(find.byKey(const ValueKey('field_label')), 'Soru');
      await tester.tap(find.byKey(const ValueKey('field_apply_button')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('En az bir alan eklemelisiniz'), findsNothing);
    });

    testWidgets('no active mail account → the required sender explains why', (tester) async {
      await pumpForm(tester, ['forms:create', 'mail:read']);
      expect(
        find.text('Aktif mail hesabı yok. Önce bir mail hesabı oluşturun ya da bildirimi kapatın.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('field_notificationEnabled')));
      await tester.tap(find.byKey(const ValueKey('field_notificationEnabled')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aktif mail hesabı yok'), findsNothing, reason: 'not required any more');
    });

    testWidgets('steps: "Taşı" menu and screen-reader action reorder them', (tester) async {
      final handle = tester.ensureSemantics();
      final sent = <Map<String, dynamic>>[];
      backend.routes['/forms/7'] = (req) {
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return okData({'id': 7});
      };
      await pumpForm(tester, ['forms:update', 'mail:read'], form: _adminForm());

      await tester.tap(find.byKey(const ValueKey('move_step_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aşağı taşı'));
      await tester.pumpAndSettle();
      final row = find.semantics.byPredicate(
        (n) => n.label.contains('Kişisel Bilgiler') && n.getSemanticsData().customSemanticsActionIds!.isNotEmpty,
      );
      tester.semantics.customAction(row, moveUpAction);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move_step_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aşağı taşı'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crud_save_button')));
      await settle(tester);

      expect((sent.single['schema']['steps'] as List).map((s) => s['title']), ['Talep', 'Kişisel Bilgiler']);
      handle.dispose();
    });

    testWidgets('no mail:read → the required sender says the list is not visible', (tester) async {
      await pumpForm(tester, ['forms:update'], form: _adminForm());
      expect(find.text('Gönderici Mail Hesabı listesini görme yetkiniz yok (mail:read).'), findsOneWidget);
    });
  });

  testWidgets('submissions: pull-to-refresh reloads the count too', (tester) async {
    final backend = FakeBackend();
    var count = 1;
    backend.routes['/forms/7/submissions/paged'] = (_) => okData({'content': <Object>[], 'last': true});
    backend.routes['/forms/7/submissions/count'] = (_) => okData(count);
    await tester.pumpWidget(
      MaterialApp(
        home: FormSubmissionsScreen(form: _adminForm(), apiService: backend.api),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('Başvuru Formu · 1 yanıt'), findsOneWidget);

    count = 3;
    await tester.fling(find.text('Henüz yanıt yok.'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Başvuru Formu · 3 yanıt'), findsOneWidget);
  });
}
