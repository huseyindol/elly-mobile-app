import 'dart:io';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed snapshot of the backend IU DTOs (`elly-backend/src/main/java/com/cms/dto/Dto*IU.java`).
/// Update both sides together; the last group re-checks the snapshot against the sources when the
/// backend repo sits next to this one.
const _dtoFields = <String, Set<String>>{
  // DtoPageIU
  'pages': {'title', 'description', 'slug', 'template', 'status', 'seoInfo', 'componentIds'},
  // DtoComponentIU
  'components': {
    'name',
    'description',
    'type',
    'content',
    'template',
    'orderIndex',
    'status',
    'pageIds',
    'bannerIds',
    'widgetIds',
    'formIds',
  },
  // DtoPostIU
  'posts': {
    'title',
    'content',
    'slug',
    'template',
    'status',
    'orderIndex',
    'description',
    'category',
    'coverImage',
    'publishedAt',
    'author',
    'readingTime',
    'seoInfo',
  },
  // DtoCmsContentIU
  'contents': {'basicInfoId', 'basicInfo', 'contentType', 'metadata'},
  // DtoWidgetIU
  'widgets': {'name', 'description', 'type', 'content', 'template', 'orderIndex', 'status', 'bannerIds', 'postIds'},
  // DtoBannerIU
  'banners': {'title', 'altText', 'link', 'target', 'type', 'orderIndex', 'status', 'images', 'subFolder'},
  // DtoFormDefinitionIU
  'forms': {
    'title',
    'version',
    'schema',
    'active',
    'senderMailAccountId',
    'recipientEmail',
    'ccEmails',
    'bccEmails',
    'notificationTemplateKey',
    'notificationSubject',
    'notificationEnabled',
  },
  // DtoAssetsIU
  'assets': {'subFolder'},
};

/// Nested DTOs addressed with dot paths: seoInfo = DtoSeoInfoIU, basicInfo = DtoCmsBasicInfoIU,
/// images = entity BannerImage. `metadata` is a free-form map (no table).
const _nested = <String, Set<String>>{
  'seoInfo': {'title', 'description', 'keywords', 'canonicalUrl', 'noIndex', 'noFollow'},
  'basicInfo': {'sectionKey', 'title', 'description', 'isActive', 'sortOrder'},
  'images': {'desktop', 'tablet', 'mobile'},
};

/// IU fields the mobile form deliberately never sends.
const _notSent = <String, Set<String>>{
  'contents': {'basicInfoId'}, // the backend resolves the basic info from the nested basicInfo object
};

const _dtoFiles = <String, String>{
  'pages': 'DtoPageIU',
  'components': 'DtoComponentIU',
  'posts': 'DtoPostIU',
  'contents': 'DtoCmsContentIU',
  'widgets': 'DtoWidgetIU',
  'banners': 'DtoBannerIU',
  'forms': 'DtoFormDefinitionIU',
  'assets': 'DtoAssetsIU',
};

String _root(String key) => key.split('.').first;

void main() {
  final modules = ModulesConfig.allModules;

  test('every module has a row in the backend snapshot and vice versa', () {
    expect(modules.map((m) => m.permissionKey).toSet(), _dtoFields.keys.toSet());
  });

  group('payloadKeys vs backend Dto*IU', () {
    for (final module in modules) {
      final key = module.permissionKey;

      test('$key: payloadKeys ⊆ DTO fields (an unknown key would be ignored or rejected by the backend)', () {
        expect(module.payloadKeys.toSet().difference(_dtoFields[key]!), isEmpty);
      });

      test('$key: no DTO field is left out unless deliberately (the backend mapper nulls missing fields)', () {
        final missing = _dtoFields[key]!.difference(module.payloadKeys.toSet());
        expect(missing, _notSent[key] ?? <String>{});
      });

      test('$key: payloadKeys has no duplicates', () {
        expect(module.payloadKeys.toSet().length, module.payloadKeys.length);
      });
    }
  });

  group('form fields vs payloadKeys / nested DTOs', () {
    for (final module in modules) {
      test('${module.permissionKey}: every sent field key belongs to payloadKeys', () {
        for (final field in module.fields) {
          if (field.key.startsWith('_') || field.type == FieldType.file) continue; // local state / multipart part
          expect(module.payloadKeys, contains(_root(field.key)), reason: field.key);
        }
      });

      test('${module.permissionKey}: nested keys exist in the nested DTO', () {
        for (final field in module.fields) {
          final parts = field.key.split('.');
          final table = _nested[parts.first];
          if (parts.length == 1 || table == null) continue; // metadata.* is free-form
          expect(parts, hasLength(2), reason: field.key);
          expect(table, contains(parts[1]), reason: field.key);
        }
      });
    }

    test('local keys (`_…`) and file parts are never payload keys', () {
      for (final module in modules) {
        for (final field in module.fields) {
          if (field.key.startsWith('_') || field.type == FieldType.file) {
            expect(module.payloadKeys, isNot(contains(field.key)), reason: '${module.permissionKey}.${field.key}');
          }
        }
      }
    });

    test('required fields are sent (isRequired on a non-payload key could never be satisfied)', () {
      for (final module in modules) {
        for (final field in module.fields.where((f) => f.isRequired && f.type != FieldType.file)) {
          expect(module.payloadKeys, contains(_root(field.key)), reason: '${module.permissionKey}.${field.key}');
        }
      }
    });
  });

  group('structure', () {
    test('permission keys and titles are unique; byKey resolves every module', () {
      expect(modules.map((m) => m.permissionKey).toSet(), hasLength(modules.length));
      expect(modules.map((m) => m.title).toSet(), hasLength(modules.length));
      for (final m in modules) {
        expect(ModulesConfig.byKey(m.permissionKey), same(m));
      }
    });

    test('endpoints start with / and the crud endpoint has no trailing slash', () {
      for (final m in modules) {
        expect(m.crudEndpoint, startsWith('/'), reason: m.permissionKey);
        expect(m.crudEndpoint, isNot(endsWith('/')), reason: m.permissionKey);
        expect(m.listEndpoint, startsWith('/'), reason: m.permissionKey);
        for (final e in [m.detailEndpoint, m.filter?.optionsEndpoint, m.filter?.endpointTemplate]) {
          if (e != null) expect(e, startsWith('/'), reason: '${m.permissionKey} $e');
        }
        for (final f in m.fields) {
          for (final e in [f.relationEndpoint, f.optionsEndpoint]) {
            if (e != null) expect(e, startsWith('/'), reason: '${m.permissionKey}.${f.key} $e');
          }
        }
      }
    });

    test('list/detail endpoints live under the module endpoint', () {
      for (final m in modules) {
        expect(m.listEndpoint, startsWith(m.crudEndpoint), reason: m.permissionKey);
        if (m.detailEndpoint != null) {
          expect(m.detailEndpoint, startsWith('${m.crudEndpoint}/'), reason: m.permissionKey);
        }
      }
    });

    test('request modes: banners = multipart data, assets = multipart fields, the rest JSON', () {
      for (final m in modules) {
        final expected = switch (m.permissionKey) {
          'banners' => RequestMode.multipartData,
          'assets' => RequestMode.multipartFields,
          _ => RequestMode.json,
        };
        expect(m.requestMode, expected, reason: m.permissionKey);
      }
    });

    test('paged modules point at a /paged endpoint', () {
      for (final m in modules.where((m) => m.paged)) {
        expect(m.listEndpoint, contains('/paged'), reason: m.permissionKey);
      }
    });

    test('relation fields name their option endpoint; ids use the DTO *Ids naming', () {
      for (final m in modules) {
        for (final f in m.fields.where((f) => f.type == FieldType.relation)) {
          expect(f.relationEndpoint, isNotNull, reason: '${m.permissionKey}.${f.key}');
          expect(f.key, endsWith('Ids'), reason: '${m.permissionKey}.${f.key}');
        }
      }
    });

    test('dropdowns have options or an options endpoint; defaults and visibleWhen values are valid', () {
      for (final m in modules) {
        final byKey = {for (final f in m.fields) f.key: f};
        for (final f in m.fields.where((f) => f.type == FieldType.dropdown)) {
          final where = '${m.permissionKey}.${f.key}';
          expect(f.options != null || f.optionsEndpoint != null, isTrue, reason: where);
          if (f.options != null && f.defaultValue != null) expect(f.options, contains(f.defaultValue), reason: where);
        }
        for (final f in m.fields) {
          for (final cond in (f.visibleWhen ?? const <String, Object>{}).entries) {
            final selector = byKey[cond.key];
            expect(selector, isNotNull, reason: '${m.permissionKey}.${f.key} visibleWhen ${cond.key}');
            final options = selector!.options;
            if (options != null) expect(options, contains(cond.value), reason: '${m.permissionKey}.${f.key}');
          }
        }
      }
    });

    test('type dropdowns match the backend enums (ComponentTypeEnum / WidgetTypeEnum)', () {
      List<String> options(String module) =>
          ModulesConfig.byKey(module).fields.firstWhere((f) => f.key == 'type').options!;
      expect(options('components'), ['BANNER', 'WIDGET', 'FORM']);
      expect(options('widgets'), ['BANNER', 'POST']);
    });

    test('each relation of components/widgets is visible for exactly the matching type', () {
      Map<String, Object>? when(String module, String key) =>
          ModulesConfig.byKey(module).fields.firstWhere((f) => f.key == key).visibleWhen;
      expect(when('components', 'bannerIds'), {'type': 'BANNER'});
      expect(when('components', 'widgetIds'), {'type': 'WIDGET'});
      expect(when('components', 'formIds'), {'type': 'FORM'});
      expect(when('widgets', 'bannerIds'), {'type': 'BANNER'});
      expect(when('widgets', 'postIds'), {'type': 'POST'});
    });

    test('templateFromField / slugFrom point at existing fields', () {
      for (final m in modules) {
        final keys = m.fields.map((f) => f.key).toSet();
        for (final f in m.fields) {
          if (f.templateFromField != null) expect(keys, contains(f.templateFromField), reason: f.key);
          if (f.slugFrom != null) expect(keys, contains(f.slugFrom), reason: f.key);
        }
      }
    });

    test('permissionKey is the backend module name (PermissionConstants)', () {
      const known = {'pages', 'components', 'posts', 'contents', 'widgets', 'banners', 'forms', 'assets'};
      expect(modules.map((m) => m.permissionKey).toSet(), known);
    });
  });

  group(
    'snapshot vs backend sources (runs only when ../elly-backend is present)',
    () {
      final dir = Directory('../elly-backend/src/main/java/com/cms/dto');

      for (final entry in _dtoFiles.entries) {
        test('${entry.key}: ${entry.value}.java fields == snapshot', () {
          final source = File('${dir.path}/${entry.value}.java').readAsStringSync();
          final fields = {
            for (final m in RegExp(
              r'^\s*private\s+(?!static)[\w<>?,. ]+?\s+(\w+)\s*(?:=[^;]*)?;',
              multiLine: true,
            ).allMatches(source))
              m.group(1)!,
          };
          expect(fields, _dtoFields[entry.key]);
        });
      }

      test('DtoSeoInfoIU / DtoCmsBasicInfoIU fields == nested snapshot', () {
        Set<String> fieldsOf(String name) => {
          for (final m in RegExp(
            r'^\s*private\s+(?!static)[\w<>?,. ]+?\s+(\w+)\s*(?:=[^;]*)?;',
            multiLine: true,
          ).allMatches(File('${dir.path}/$name.java').readAsStringSync()))
            m.group(1)!,
        };
        expect(fieldsOf('DtoSeoInfoIU'), _nested['seoInfo']);
        expect(fieldsOf('DtoCmsBasicInfoIU'), _nested['basicInfo']);
      });
    },
    skip: !Directory('../elly-backend/src/main/java/com/cms/dto').existsSync()
        ? 'backend repo not next to this one'
        : false,
  );
}
