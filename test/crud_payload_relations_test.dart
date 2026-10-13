import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:elly_mobile_app/services/crud_payload.dart';
import 'package:flutter_test/flutter_test.dart';

/// Relation semantics of the backend (verified in ComponentService / WidgetService / PageController):
/// - components, widgets: a missing (null) id list CLEARS the relation → every save must send them.
/// - pages `componentIds`: null = untouched, [] = clear → sent only when the selection changed.
/// Complements crud_payload_test.dart (basic cases) with the wipe-risk edge cases.

final _pages = ModulesConfig.byKey('pages');
final _components = ModulesConfig.byKey('components');
final _widgets = ModulesConfig.byKey('widgets');

Map<String, dynamic> _component(String type, {Map<String, dynamic> extra = const {}}) => {
  'id': 3,
  'name': 'C',
  'type': type,
  'orderIndex': 1,
  'status': true,
  'pageIds': [7, 8],
  ...extra,
};

/// DtoComponent from GET /components/{id}: related objects are omitted when empty (NON_NULL mapper).
final _bannerComponent = _component(
  'BANNER',
  extra: {
    'banners': [
      {'id': 11},
      {'id': 12},
    ],
  },
);
final _widgetComponent = _component(
  'WIDGET',
  extra: {
    'widgets': [
      {'id': 21},
    ],
  },
);
final _formComponent = _component(
  'FORM',
  extra: {
    'forms': [
      {'id': 41},
      {'id': 42},
    ],
  },
);

/// Edit with an untouched relation selection, only the name changed (what the form does on save).
Map<String, dynamic> _saveUntouched(CrudModule module, Map<String, dynamic> record) =>
    buildPayload(module, record, initialFormValues(module, record)..['name'] = 'Yeni ad');

void main() {
  group('components: every save carries the current relations (backend null = CLEAR)', () {
    test('BANNER: banners back as ids, other types [], pageIds from the record', () {
      final p = _saveUntouched(_components, _bannerComponent);
      expect(p['bannerIds'], [11, 12]);
      expect(p['widgetIds'], <Object>[]);
      expect(p['formIds'], <Object>[]);
      expect(p['pageIds'], [7, 8]);
    });

    test('WIDGET: widgets back as ids', () {
      final p = _saveUntouched(_components, _widgetComponent);
      expect(p['widgetIds'], [21]);
      expect(p['bannerIds'], <Object>[]);
      expect(p['formIds'], <Object>[]);
      expect(p['pageIds'], [7, 8]);
    });

    test('FORM: forms back as ids', () {
      final p = _saveUntouched(_components, _formComponent);
      expect(p['formIds'], [41, 42]);
      expect(p['bannerIds'], <Object>[]);
      expect(p['widgetIds'], <Object>[]);
      expect(p['pageIds'], [7, 8]);
    });

    for (final record in [_bannerComponent, _widgetComponent, _formComponent]) {
      test('${record['type']}: all four relation keys are present (a missing key would clear on the backend)', () {
        final p = _saveUntouched(_components, record);
        expect(p.keys, containsAll(['pageIds', 'bannerIds', 'widgetIds', 'formIds']));
      });
    }

    test('component without any page/relation (empty lists omitted) still sends [] lists', () {
      final record = {'id': 3, 'name': 'C', 'type': 'BANNER', 'pageIds': <Object>[]};
      final p = _saveUntouched(_components, record);
      expect(p['bannerIds'], <Object>[]);
      expect(p['widgetIds'], <Object>[]);
      expect(p['formIds'], <Object>[]);
      expect(p['pageIds'], <Object>[]);
    });

    test('the user explicitly emptying the selection sends []', () {
      final values = initialFormValues(_components, _bannerComponent)..['bannerIds'] = <Object>[];
      expect(buildPayload(_components, _bannerComponent, values)['bannerIds'], <Object>[]);
    });

    test('type switch BANNER→FORM: old relation [] even if the user had touched it first', () {
      final values = initialFormValues(_components, _bannerComponent)
        ..['bannerIds'] = [99]
        ..['type'] = 'FORM'
        ..['formIds'] = [5];
      final p = buildPayload(_components, _bannerComponent, values);
      expect(p['bannerIds'], <Object>[], reason: 'backend rejects banners on a FORM component');
      expect(p['formIds'], [5]);
      expect(p['widgetIds'], <Object>[]);
      expect(p['pageIds'], [7, 8]);
    });

    test('type switch without picking new relations → new type gets [] (not the old ids)', () {
      final values = initialFormValues(_components, _bannerComponent)..['type'] = 'WIDGET';
      final p = buildPayload(_components, _bannerComponent, values);
      expect(p['widgetIds'], <Object>[]);
      expect(p['bannerIds'], <Object>[]);
    });

    test('relation fields are matched to the payload by key, record objects never leak', () {
      final p = _saveUntouched(_components, _bannerComponent);
      expect(p.keys, isNot(containsAll(['banners'])));
      expect(p.keys, isNot(contains('pages')));
      expect(p.keys, isNot(contains('id')));
    });

    test('ids come from a copy: mutating the payload does not touch the record', () {
      final record = _component(
        'BANNER',
        extra: {
          'banners': [
            {'id': 11},
          ],
        },
      );
      final p = _saveUntouched(_components, record);
      (p['pageIds'] as List).add(999);
      expect(record['pageIds'], [7, 8]);
    });

    test('create sends the selection and [] for the hidden types; pageIds has no source', () {
      final values = initialFormValues(_components, null)
        ..['name'] = 'Yeni'
        ..['bannerIds'] = [1];
      final p = buildPayload(_components, null, values);
      expect(p['bannerIds'], [1]);
      expect(p['widgetIds'], <Object>[]);
      expect(p['formIds'], <Object>[]);
      expect(p.containsKey('pageIds'), isFalse);
    });
  });

  group('widgets: every save carries the current relations', () {
    final postWidget = {
      'id': 5,
      'name': 'W',
      'type': 'POST',
      'posts': [
        {'id': 31},
        {'id': 32},
      ],
    };
    final bannerWidget = {
      'id': 6,
      'name': 'W2',
      'type': 'BANNER',
      'banners': [
        {'id': 11},
      ],
    };

    test('POST widget: posts back, banners []', () {
      final p = _saveUntouched(_widgets, postWidget);
      expect(p['postIds'], [31, 32]);
      expect(p['bannerIds'], <Object>[]);
    });

    test('BANNER widget: banners back, posts []', () {
      final p = _saveUntouched(_widgets, bannerWidget);
      expect(p['bannerIds'], [11]);
      expect(p['postIds'], <Object>[]);
    });

    test('both relation keys are always present', () {
      for (final record in [
        postWidget,
        bannerWidget,
        {'id': 7, 'name': 'x', 'type': 'BANNER'},
      ]) {
        expect(_saveUntouched(_widgets, record).keys, containsAll(['bannerIds', 'postIds']));
      }
    });

    test('type switch POST→BANNER clears posts, sends the new banners', () {
      final values = initialFormValues(_widgets, postWidget)
        ..['type'] = 'BANNER'
        ..['bannerIds'] = [11, 12];
      final p = buildPayload(_widgets, postWidget, values);
      expect(p['postIds'], <Object>[]);
      expect(p['bannerIds'], [11, 12]);
    });

    test('type switch BANNER→POST clears banners', () {
      final values = initialFormValues(_widgets, bannerWidget)
        ..['type'] = 'POST'
        ..['postIds'] = [31];
      final p = buildPayload(_widgets, bannerWidget, values);
      expect(p['bannerIds'], <Object>[]);
      expect(p['postIds'], [31]);
    });
  });

  group('pages: componentIds only when the selection changed (backend null = untouched)', () {
    final page = {
      'id': 7,
      'title': 'P',
      'slug': 'p',
      'components': [
        {'id': 1},
        {'id': 2},
      ],
    };

    test('editing every other field never sends componentIds', () {
      final values = initialFormValues(_pages, page)
        ..['title'] = 'Yeni'
        ..['description'] = 'd'
        ..['status'] = false
        ..['seoInfo.title'] = 's';
      expect(buildPayload(_pages, page, values).containsKey('componentIds'), isFalse);
    });

    test('adding one component sends the full new list; removing the last sends []', () {
      expect(
        buildPayload(_pages, page, initialFormValues(_pages, page)..['componentIds'] = [1, 2, 3])['componentIds'],
        [1, 2, 3],
      );
      final single = {
        ...page,
        'components': [
          {'id': 1},
        ],
      };
      expect(
        buildPayload(_pages, single, initialFormValues(_pages, single)..['componentIds'] = <Object>[])['componentIds'],
        <Object>[],
      );
    });

    test('page without components (key omitted): untouched not sent, first pick sent', () {
      final empty = {'id': 8, 'title': 'E', 'slug': 'e'};
      expect(buildPayload(_pages, empty, initialFormValues(_pages, empty)).containsKey('componentIds'), isFalse);
      expect(buildPayload(_pages, empty, initialFormValues(_pages, empty)..['componentIds'] = [4])['componentIds'], [
        4,
      ]);
    });

    test('a different set of the same size counts as changed', () {
      expect(buildPayload(_pages, page, initialFormValues(_pages, page)..['componentIds'] = [1, 3])['componentIds'], [
        1,
        3,
      ]);
    });

    test('componentIds is the only relation on pages and is the only one with relationKeepsOnNull', () {
      final keeps = [
        for (final m in ModulesConfig.allModules)
          for (final f in m.fields)
            if (f.relationKeepsOnNull) '${m.permissionKey}.${f.key}',
      ];
      expect(keeps, ['pages.componentIds']);
    });
  });

  group('payload invariants', () {
    test('every module: payload only has payloadKeys, never local `_` keys or response-only keys', () {
      for (final module in ModulesConfig.allModules) {
        final p = buildPayload(module, null, initialFormValues(module, null));
        expect(p.keys.toSet().difference(module.payloadKeys.toSet()), isEmpty, reason: module.permissionKey);
        expect(p.keys.where((k) => k.startsWith('_')), isEmpty, reason: module.permissionKey);
      }
    });

    test('a module with relation fields always has a detail endpoint (never edit from list data)', () {
      for (final module in ModulesConfig.allModules) {
        if (module.fields.any((f) => f.type == FieldType.relation)) {
          expect(module.detailEndpoint, isNotNull, reason: module.permissionKey);
        }
      }
    });

    test('relation modules: the detail path resolves to a concrete record (no empty placeholder)', () {
      expect(detailPath(_components, {'id': 3}), '/components/3');
      expect(detailPath(_widgets, {'id': 5}), '/widgets/5');
      expect(detailPath(_pages, {'id': 7, 'slug': 'a b'}), '/pages/a%20b');
    });

    test('a list item without the path key yields an unresolved path (id missing → trailing slash)', () {
      // The form then GETs "/components/" which is not a record; the load must fail, not fall back to list data.
      expect(detailPath(_components, {'name': 'x'}), '/components/');
    });

    test('modules without detailEndpoint return null (banners, forms, contents)', () {
      for (final key in ['banners', 'forms', 'contents']) {
        expect(detailPath(ModulesConfig.byKey(key), {'id': 1}), isNull, reason: key);
      }
    });
  });
}
