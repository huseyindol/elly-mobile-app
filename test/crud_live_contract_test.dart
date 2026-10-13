// Live contract test: drives the real CRUD engine code (ModulesConfig + buildPayload +
// ApiService) against the backend. Opt-in, because it writes (then deletes) data:
//
//   LIVE_API=1 flutter test test/crud_live_contract_test.dart
//
// Credentials (required with LIVE_API=1): ELLY_USER / ELLY_PASS, optional ELLY_TENANT (default tenant1).
import 'dart:convert';
import 'dart:io';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/crud_payload.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final _env = Platform.environment;
final _live = _env['LIVE_API'] == '1';
final _ts = DateTime.now().millisecondsSinceEpoch;

// 1x1 transparent PNG
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

CrudModule _module(String permissionKey) => ModulesConfig.byKey(permissionKey);

final api = ApiService();

Future<List<Map<String, dynamic>>> _list(CrudModule m) async => extractItems(await api.get(m.listEndpoint));

Future<Map<String, dynamic>> _find(CrudModule m, dynamic id) async =>
    (await _list(m)).firstWhere((e) => e['id'] == id, orElse: () => throw StateError('$id not in ${m.title} list'));

/// Mirrors GenericCrudFormScreen._loadRecord: edit from the detail record when available.
Future<Map<String, dynamic>> _editable(CrudModule m, Map<String, dynamic> listed) async {
  final path = detailPath(m, listed);
  return path == null ? listed : Map<String, dynamic>.from(await api.get(path) as Map);
}

/// Mirrors GenericCrudFormScreen._submit.
Future<Map<String, dynamic>> _save(CrudModule m, Map<String, dynamic>? original, Map<String, dynamic> values,
    {List<UploadFile> files = const []}) async {
  final payload = buildPayload(m, original, values);
  final editing = original != null;
  final endpoint = editing ? '${m.crudEndpoint}/${original['id']}' : m.crudEndpoint;
  final method = editing ? 'PUT' : 'POST';
  final dynamic res = switch (m.requestMode) {
    RequestMode.json => editing ? await api.put(endpoint, payload) : await api.post(endpoint, payload),
    RequestMode.multipartData =>
      await api.multipart(method, endpoint, fields: {'data': jsonEncode(payload)}, files: files),
    RequestMode.multipartFields =>
      await api.multipart(method, endpoint, fields: toMultipartFields(payload), files: files),
  };
  return Map<String, dynamic>.from(res as Map);
}

/// create → listed → edit one field → change persisted + `preserved` paths untouched → delete → gone.
Future<void> _crudCycle(
  String permissionKey, {
  required Map<String, dynamic> createValues,
  required String editKey,
  required Object editValue,
  List<String> preserved = const [],
  List<UploadFile> files = const [],
  List<UploadFile> editFiles = const [],
}) async {
  final m = _module(permissionKey);
  final title = m.title;
  final values = {...initialFormValues(m, null), ...createValues};
  final created = await _save(m, null, values, files: files);
  final id = created['id'];
  expect(id, isNotNull, reason: '$title create returned no id');
  try {
    final listed = await _find(m, id);
    for (final e in createValues.entries) {
      // `_`-keys are local form state (banner `_imageMode`), never sent.
      if (!e.key.startsWith('_') && m.fields.any((f) => f.key == e.key && f.type != FieldType.file)) {
        expect(getPath(listed, e.key), e.value, reason: '$title create: ${e.key}');
      }
    }

    final original = await _editable(m, listed);
    final editValues = initialFormValues(m, original)..[editKey] = editValue;
    await _save(m, original, editValues, files: editFiles);
    final updated = await _editable(m, await _find(m, id));
    expect(getPath(updated, editKey), editValue, reason: '$title update: $editKey');
    for (final path in preserved) {
      expect(jsonEncode(getPath(updated, path)), jsonEncode(getPath(original, path)),
          reason: '$title update must preserve $path');
    }
  } finally {
    await api.delete('${m.crudEndpoint}/$id');
  }
  expect((await _list(m)).any((e) => e['id'] == id), isFalse, reason: '$title delete');
}

void main() {
  setUpAll(() async {
    if (!_live) return;
    FlutterSecureStorage.setMockInitialValues({});
    final tenant = _env['ELLY_TENANT'] ?? 'tenant1';
    final login = await api.post('/auth/login', {
      'usernameOrEmail': _env['ELLY_USER']!,
      'password': _env['ELLY_PASS']!,
      'tenantId': tenant,
      'loginType': 'admin',
    }, tenantId: tenant);
    const storage = FlutterSecureStorage();
    await storage.write(key: 'accessToken', value: login['token']);
    await storage.write(key: 'refreshToken', value: login['refreshToken']);
    await storage.write(key: 'tenantId', value: tenant);
  });

  group('live CRUD contract', skip: !_live ? 'set LIVE_API=1' : null, () {
    test('every module list loads', () async {
      for (final m in ModulesConfig.allModules) {
        await expectLater(_list(m), completes, reason: m.title);
      }
    });

    test('expired access token is refreshed transparently', () async {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'accessToken', value: 'expired.token.value');
      expect(await _list(_module('pages')), isA<List>());
      expect(await storage.read(key: 'accessToken'), isNot('expired.token.value'));
    });

    test('Pages', () => _crudCycle('pages',
        createValues: {
          'title': 'Mobile Test $_ts',
          'slug': 'mobile-test-$_ts',
          'template': 'APage',
          'seoInfo.title': 'SEO $_ts',
        },
        editKey: 'title',
        editValue: 'Mobile Test Edited $_ts',
        preserved: ['slug', 'seoInfo.title', 'template', 'status']));

    test('Components', () => _crudCycle('components',
        createValues: {'name': 'Mobile Comp $_ts', 'type': 'WIDGET', 'template': 'BComponent'},
        editKey: 'name',
        editValue: 'Mobile Comp Edited $_ts',
        preserved: ['type', 'template', 'orderIndex', 'status']));

    test('Relations survive unrelated edits (components/widgets: backend null = clear)', () async {
      final pages = _module('pages');
      final comps = _module('components');
      final widgets = _module('widgets');
      final posts = _module('posts');
      final post = await _save(posts, null, {
        ...initialFormValues(posts, null),
        'title': 'Mobile Rel Post $_ts',
        'slug': 'mobile-rel-post-$_ts',
      });
      final widget = await _save(widgets, null, {
        ...initialFormValues(widgets, null),
        'name': 'Mobile Rel Widget $_ts',
        'type': 'POST',
        'postIds': [post['id']],
      });
      final comp = await _save(comps, null, {
        ...initialFormValues(comps, null),
        'name': 'Mobile Rel Comp $_ts',
        'type': 'WIDGET',
        'widgetIds': [widget['id']],
      });
      final page = await _save(pages, null, {
        ...initialFormValues(pages, null),
        'title': 'Mobile Rel Page $_ts',
        'slug': 'mobile-rel-page-$_ts',
        'componentIds': [comp['id']],
      });
      try {
        // Edit each record without touching its relations.
        for (final (m, listed, key) in [
          (comps, comp, 'name'),
          (widgets, widget, 'name'),
          (pages, page, 'title'),
        ]) {
          final original = await _editable(m, await _find(m, listed['id']));
          await _save(m, original, initialFormValues(m, original)..[key] = '${original[key]} Edited');
        }
        final comp2 = await _editable(comps, await _find(comps, comp['id']));
        expect(relationIds(comp2['widgets']), [widget['id']], reason: 'component widgets wiped');
        expect(comp2['pageIds'], [page['id']], reason: 'component pages wiped');
        final widget2 = await _editable(widgets, await _find(widgets, widget['id']));
        expect(relationIds(widget2['posts']), [post['id']], reason: 'widget posts wiped');
        final page2 = await _editable(pages, await _find(pages, page['id']));
        expect(relationIds(page2['components']), [comp['id']], reason: 'page components wiped');
      } finally {
        await api.delete('/pages/${page['id']}');
        await api.delete('/components/${comp['id']}');
        await api.delete('/widgets/${widget['id']}');
        await api.delete('/posts/${post['id']}');
      }
    });

    test('Posts (rich text body, date, cover image)', () => _crudCycle('posts',
        createValues: {
          'title': 'Mobile Rich Post $_ts',
          'slug': 'mobile-rich-post-$_ts',
          'content': '<h2>Başlık</h2><p>Merhaba <strong>dünya</strong></p>',
          'coverImage': 'https://example.com/cover.png',
          'category': 'Mobile',
        },
        editKey: 'title',
        editValue: 'Mobile Rich Post Edited $_ts',
        preserved: ['content', 'coverImage', 'category', 'slug']));

    test('Posts (publishedAt not on form must survive update)', () async {
      final m = _module('posts');
      final created = await api.post(m.crudEndpoint, {
        ...buildPayload(m, null, {
          ...initialFormValues(m, null),
          'title': 'Mobile Post $_ts',
          'slug': 'mobile-post-$_ts',
        }),
        'publishedAt': '2026-01-02T03:04:05.000+00:00',
        'seoInfo': {'title': 'Post SEO $_ts'},
      });
      final id = created['id'];
      try {
        final original = await _editable(m, await _find(m, id));
        expect(getPath(original, 'seoInfo.title'), 'Post SEO $_ts', reason: 'seoInfo not saved on create');
        await _save(m, original, initialFormValues(m, original)..['title'] = 'Mobile Post Edited $_ts');
        final updated = await _editable(m, await _find(m, id));
        expect(updated['title'], 'Mobile Post Edited $_ts');
        expect(updated['publishedAt'], isNotNull, reason: 'publishedAt wiped');
        expect(getPath(updated, 'seoInfo.title'), 'Post SEO $_ts', reason: 'seoInfo wiped');
      } finally {
        await api.delete('${m.crudEndpoint}/$id');
      }
    });

    test('Contents', () => _crudCycle('contents',
        createValues: {
          'basicInfo.title': 'Mobile Section $_ts',
          'basicInfo.sectionKey': 'mobile_contract_test',
          'metadata.name': 'Mobile Skill $_ts',
          'metadata.level': 'Expert',
          'metadata.years': '1',
          'metadata.imageUrl': 'https://example.com/skill.png',
          'metadata.url': 'https://example.com',
        },
        editKey: 'basicInfo.title',
        editValue: 'Mobile Section Edited $_ts',
        preserved: ['metadata', 'contentType', 'basicInfo.sectionKey']));

    test('Widgets', () => _crudCycle('widgets',
        createValues: {'name': 'Mobile Widget $_ts', 'type': 'POST', 'template': 'BWidget'},
        editKey: 'name',
        editValue: 'Mobile Widget Edited $_ts',
        preserved: ['type', 'template', 'orderIndex']));

    test('Banners (multipart, URL mode)', () => _crudCycle('banners',
        createValues: {
          'title': 'Mobile Banner URL $_ts',
          'subFolder': 'mobile-test',
          '_imageMode': 'url',
          'images.tablet': 'https://example.com/t.png',
          'images.mobile': 'https://example.com/m.png',
        },
        editKey: 'title',
        editValue: 'Mobile Banner URL Edited $_ts',
        preserved: ['images', 'link', 'target', 'subFolder']));

    test('Banners (multipart, upload mode)', () async {
      final file = File('${Directory.systemTemp.path}/elly_banner_$_ts.png')..writeAsBytesSync(_png);
      await _crudCycle('banners',
          createValues: {'title': 'Mobile Banner $_ts', 'subFolder': 'mobile-test'},
          files: [UploadFile('desktop', file.path)],
          editKey: 'title',
          editValue: 'Mobile Banner Edited $_ts',
          preserved: ['images', 'link', 'target', 'subFolder']);
    });

    test('Forms', () async {
      final m = _module('forms');
      final accounts = extractItems(await api.get('/mail-accounts'));
      await _crudCycle('forms',
          createValues: {
            'title': 'Mobile Form $_ts',
            'senderMailAccountId': accounts.first['id'],
            'recipientEmail': 'mobile-test@example.com',
          },
          editKey: 'title',
          editValue: 'Mobile Form Edited $_ts',
          preserved: ['schema', 'senderMailAccountId', 'recipientEmail', 'notificationEnabled']);
      expect(m.forceDeleteSuffix, '/force');
    });

    test('Assets (multipart upload, replace, delete)', () async {
      final f1 = File('${Directory.systemTemp.path}/elly_asset_$_ts.png')..writeAsBytesSync(_png);
      final f2 = File('${Directory.systemTemp.path}/elly_asset_${_ts}_v2.png')..writeAsBytesSync(_png);
      await _crudCycle('assets',
          createValues: {'subFolder': 'mobile-test'},
          files: [UploadFile('file', f1.path)],
          editKey: 'subFolder',
          editValue: 'mobile-test',
          editFiles: [UploadFile('file', f2.path)]);
    });
  });
}
