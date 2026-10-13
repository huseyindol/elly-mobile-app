import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:elly_mobile_app/services/form_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures are produced by the admin / tenant TypeScript sources (`test/fixtures/gen_form_fixtures.ts`).
dynamic _fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  group('evaluateCondition = admin/tenant condition-evaluator.ts', () {
    final cases = _fixture('condition_cases.json') as List;

    test('fixture covers every operator', () {
      expect(cases.length, greaterThan(1000));
      expect({for (final c in cases) c[0]}, {'EQUALS', 'NOT_EQUALS', 'GT', 'LT', 'UNKNOWN'});
    });

    test('same result for all ${cases.length} admin cases', () {
      final failures = [
        for (final c in cases)
          if (evaluateCondition(c[0], c[1] == '__undefined__' ? null : c[1], c[2]) != c[3]) '$c',
      ];
      expect(failures, isEmpty);
    });

    test('readable examples', () {
      expect(evaluateCondition('GT', 25, '18'), isTrue);
      expect(evaluateCondition('GT', '', -1), isTrue, reason: 'JS Number("") is 0');
      expect(evaluateCondition('LT', 'abc', 5), isFalse, reason: 'NaN never compares');
      expect(evaluateCondition('EQUALS', true, 'true'), isTrue);
      expect(evaluateCondition('EQUALS', 18.0, '18'), isTrue, reason: 'JS prints 18.0 as "18"');
      expect(evaluateCondition('EQUALS', ['a', 'b'], 'a,b'), isTrue);
      expect(evaluateCondition('NOT_EQUALS', null, ''), isFalse);
    });
  });

  group('jsString / jsNumber', () {
    test('JavaScript String()', () {
      expect(jsString(null), 'null');
      expect(jsString(1.5), '1.5');
      expect(jsString(-0.0), '0');
      expect(jsString(double.nan), 'NaN');
      expect(jsString([1, null, 'x']), '1,,x');
      expect(jsString({'a': 1}), '[object Object]');
    });

    test('JavaScript Number()', () {
      expect(jsNumber('  12 '), 12);
      expect(jsNumber(''), 0);
      expect(jsNumber('0x10'), 16);
      expect(jsNumber('0b11'), 3);
      expect(jsNumber('1e2'), 100);
      expect(jsNumber('.5'), 0.5);
      expect(jsNumber('-Infinity'), double.negativeInfinity);
      expect(jsNumber('12px').isNaN, isTrue);
      expect(jsNumber('-0x10').isNaN, isTrue);
      expect(jsNumber('NaN').isNaN, isTrue);
    });
  });

  group('visibility & preview payload (tenant DynamicFormRenderer)', () {
    final fields = [
      {'id': 'age', 'type': 'number', 'condition': null},
      {
        'id': 'company',
        'type': 'text',
        'condition': {'field': 'age', 'operator': 'GT', 'value': 18},
      },
      {
        'id': 'other',
        'type': 'text',
        'condition': {'field': 'missing', 'operator': 'EQUALS', 'value': 'x'},
      },
    ];

    test('field without condition is visible; hidden fields drop out of the payload', () {
      expect(isFormFieldVisible(fields[0], {}), isTrue);
      expect(isFormFieldVisible(fields[1], {'age': 17}), isFalse);
      expect(isFormFieldVisible(fields[1], {'age': 30}), isTrue);
      expect(visiblePayload(fields, {'age': 17, 'company': 'Acme', 'other': ''}), {'age': 17});
      expect(visiblePayload(fields, {'age': 30, 'company': 'Acme'}), {'age': 30, 'company': 'Acme'});
    });

    test('an empty number is left out (react-hook-form valueAsNumber → undefined)', () {
      expect(visiblePayload(fields, {'age': null, 'company': ''}), isEmpty);
    });
  });

  group('normalizeField (admin FieldEditModal.handleSave)', () {
    test('options only for option types, blank rows dropped, none → null', () {
      final select = normalizeField({
        'id': 'topic',
        'type': 'select',
        'options': [
          {'label': 'A', 'value': 'a'},
          {'label': ' ', 'value': 'b'},
          {'label': 'C', 'value': ''},
        ],
      });
      expect(select['options'], [
        {'label': 'A', 'value': 'a'},
      ]);
      expect(normalizeField({'type': 'radio', 'options': <Object>[]})['options'], isNull);
      expect(
        normalizeField({
          'type': 'text',
          'options': [
            {'label': 'A', 'value': 'a'},
          ],
        })['options'],
        isNull,
      );
    });

    test('empty validation / condition → null, empty stepId removed, unknown keys kept', () {
      final out = normalizeField({
        'id': 'x',
        'type': 'star_rating',
        'validation': {'min': null, 'max': null, 'pattern': ''},
        'condition': {'field': '', 'operator': 'EQUALS', 'value': ''},
        'stepId': '',
        'placeholder': '1-5',
      });
      expect(out['validation'], isNull);
      expect(out['condition'], isNull);
      expect(out.containsKey('stepId'), isFalse);
      expect(out['placeholder'], '1-5');
      expect(out['type'], 'star_rating');
    });

    test('a filled validation and condition stay', () {
      final out = normalizeField({
        'type': 'number',
        'validation': {'min': 1, 'max': null, 'pattern': null},
        'condition': {'field': 'age', 'operator': 'GT', 'value': 18},
        'stepId': 's1',
      });
      expect(out['validation'], {'min': 1, 'max': null, 'pattern': null});
      expect(out['condition'], {'field': 'age', 'operator': 'GT', 'value': 18});
      expect(out['stepId'], 's1');
    });
  });

  group('builder helpers', () {
    test('renaming a field id moves the conditions that watch it', () {
      final fields = [
        {'id': 'age'},
        {
          'id': 'company',
          'condition': {'field': 'age', 'operator': 'GT', 'value': 18},
        },
        {
          'id': 'x',
          'condition': {'field': 'other', 'operator': 'EQUALS', 'value': 1},
        },
      ];
      renameConditionTarget(fields, 'age', 'years');
      expect((fields[1]['condition'] as Map)['field'], 'years');
      expect((fields[1]['condition'] as Map)['value'], 18);
      expect((fields[2]['condition'] as Map)['field'], 'other');
      expect(dependentFields(fields, 'years').map((f) => f['id']), ['company']);
    });

    test('field id rule', () {
      for (final ok in ['name', '_x', 'a1_b']) {
        expect(fieldIdPattern.hasMatch(ok), isTrue, reason: ok);
      }
      for (final bad in ['', '1a', 'a-b', 'a b', 'ç']) {
        expect(fieldIdPattern.hasMatch(bad), isFalse, reason: bad);
      }
    });

    test('schemaError: at least one field; wizard needs steps and every field on an existing step', () {
      expect(schemaError({'config': {}, 'fields': []}), 'En az bir alan eklemelisiniz');
      expect(
        schemaError({
          'config': {'layout': 'vertical'},
          'fields': [
            {'id': 'a'},
          ],
        }),
        isNull,
      );
      final wizard = {
        'config': {'layout': 'wizard'},
        'fields': [
          {'id': 'a', 'label': 'A', 'stepId': 's1'},
          {'id': 'b', 'label': 'B', 'stepId': 'gone'},
          {'id': 'c', 'label': 'C'},
        ],
        'steps': null,
      };
      expect(schemaError(wizard), 'Sihirbaz modunda en az bir adım eklemelisiniz');
      wizard['steps'] = [
        {'id': 's1', 'title': 'Bir'},
      ];
      expect(schemaError(wizard), contains('Atanmamış alanlar: B, C'));
    });

    test('newStepId is a uuid v4', () {
      final id = newStepId(Random(1));
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(newStepId(), isNot(newStepId()));
    });
  });

  group('formatPayloadValue = admin formatPayloadValue.ts', () {
    final fixture = _fixture('payload_format_cases.json') as Map<String, dynamic>;
    final fields = fixture['fields'] as Map<String, dynamic>;

    test('same text for every admin case', () {
      for (final c in fixture['cases'] as List) {
        final field = fields[c[1]] as Map<String, dynamic>?;
        expect(formatPayloadValue(c[0], field), c[2], reason: '$c');
      }
    });

    test('nested objects show as JSON (admin would print [object Object])', () {
      expect(formatPayloadValue({'a': 1}, null), '{"a":1}');
    });
  });
}
