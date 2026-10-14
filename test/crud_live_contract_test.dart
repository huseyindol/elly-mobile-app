// Live contract test: drives the real CRUD engine code (ModulesConfig + buildPayload +
// ApiService) against the backend. Opt-in, because it writes (then deletes) data:
//
//   LIVE_API=1 flutter test test/crud_live_contract_test.dart
//
// Credentials (required with LIVE_API=1): ELLY_USER / ELLY_PASS, optional ELLY_TENANT (default tenant1).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/chat_models.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/chat_format.dart';
import 'package:elly_mobile_app/screens/forms/form_submissions_screen.dart' show submissionPayload;
import 'package:elly_mobile_app/services/crud_payload.dart';
import 'package:elly_mobile_app/services/form_schema.dart';
import 'package:elly_mobile_app/services/mail_payload.dart';
import 'package:elly_mobile_app/services/rabbit_admin.dart';
import 'package:elly_mobile_app/services/realtime_service.dart';
import 'package:elly_mobile_app/services/stomp_destinations.dart';
import 'package:elly_mobile_app/services/user_admin.dart';
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

    test('Forms (builder schema round trip, submit, submissions, 409 → force delete)', () async {
      final m = _module('forms');
      final accounts = extractItems(await api.get('/mail-accounts/active'));
      const step1 = '11111111-1111-4111-8111-111111111111';
      const step2 = '22222222-2222-4222-8222-222222222222';
      // What the builder sends (normalizeField shape, admin modal semantics).
      final schema = {
        'config': {'layout': 'wizard', 'submitLabel': 'Gönder'},
        'fields': [
          for (final f in [
            {'id': 'name', 'type': 'text', 'label': 'Ad', 'required': true, 'validation': {'min': 2, 'max': 50, 'pattern': null}},
            {'id': 'age', 'type': 'number', 'label': 'Yaş', 'required': false},
            {
              'id': 'company',
              'type': 'text',
              'label': 'Şirket',
              'required': false,
              'condition': {'field': 'age', 'operator': 'GT', 'value': '18'},
            },
            {
              'id': 'topic',
              'type': 'select',
              'label': 'Konu',
              'required': false,
              'options': [
                {'label': 'Destek', 'value': 'support'},
                {'label': 'Satış', 'value': 'sales'},
              ],
            },
          ])
            normalizeField({...f, 'stepId': f['id'] == 'topic' ? step2 : step1}),
        ],
        'steps': [
          {'id': step1, 'title': 'Kişisel', 'description': ''},
          {'id': step2, 'title': 'Talep', 'description': ''},
        ],
      };
      final created = await _save(m, null, {
        ...initialFormValues(m, null),
        'title': 'Mobile Form $_ts',
        'schema': schema,
        'senderMailAccountId': accounts.isEmpty ? null : accounts.first['id'],
        'recipientEmail': 'mobile-test@example.com',
        'notificationEnabled': accounts.isNotEmpty,
      });
      final id = created['id'];
      try {
        final stored = Map<String, dynamic>.from(await api.get('/forms/$id') as Map);
        final fields = schemaFields(stored['schema'] as Map<String, dynamic>);
        expect(fields.map((f) => f['id']), ['name', 'age', 'company', 'topic']);
        expect(fields[2]['condition'], {'field': 'age', 'operator': 'GT', 'value': '18'});
        expect(fields[3]['options'], ((schema['fields'] as List)[3] as Map)['options']);
        expect(fields[3]['stepId'], step2);
        expect(schemaSteps(stored['schema'] as Map<String, dynamic>).map((s) => s['id']), [step1, step2]);

        // Untouched schema back → identical, and the backend does not bump the version (it does on change).
        await _save(m, stored, initialFormValues(m, stored)..['title'] = 'Mobile Form Edited $_ts');
        final updated = Map<String, dynamic>.from(await api.get('/forms/$id') as Map);
        expect(updated['title'], 'Mobile Form Edited $_ts');
        expect(jsonEncode(updated['schema']), jsonEncode(stored['schema']));
        expect(updated['version'], stored['version']);

        // Submission: hidden `company` (age ≤ 18) is dropped by the backend, like the site.
        await api.post('/forms/$id/submit', {
          'payload': {'name': 'Mobil', 'age': 17, 'company': 'Gizli', 'topic': 'sales'},
        });
        final page = await api.get('/forms/$id/submissions/paged?page=0&size=20&sort=submittedAt,desc');
        final sub = extractItems(page).single;
        expect(submissionPayload(sub).containsKey('company'), isFalse);
        expect(formatPayloadValue(submissionPayload(sub)['topic'], fields[3]), 'Satış');
        expect(await api.get('/forms/$id/submissions/count'), 1);
        expect((await api.get('/forms/submissions/${sub['id']}') as Map)['id'], sub['id']);

        // A form with submissions: plain delete → 409, force delete (ADMIN) removes both.
        await expectLater(
          api.delete('${m.crudEndpoint}/$id'),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
        );
      } finally {
        await api.delete('${m.crudEndpoint}/$id${m.forceDeleteSuffix}');
      }
      expect((await _list(m)).any((e) => e['id'] == id), isFalse, reason: 'forms force delete');
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

  // Communication screens. No scenario here sends an e-mail or opens an SMTP connection: /test is never called,
  // /verify only on an inactive account (rejected before connecting), /retry only on a SENT log (rejected).
  group('live communication contract', skip: !_live ? 'set LIVE_API=1' : null, () {
    test('Mail accounts: create (inactive), password never returned, blank password on update, delete', () async {
      final values = {
        'name': 'mobile-live-$_ts',
        'fromAddress': 'mobile-live-$_ts@example.com',
        'smtpHost': 'smtp.invalid',
        'smtpPort': '587',
        'smtpUsername': 'mobile-live',
        'tenantId': '',
        'isPrimary': false,
        'active': false,
      };
      final created = Map<String, dynamic>.from(
          await api.post('/mail-accounts', mailAccountPayload(values, password: 'live-secret')) as Map);
      final id = created['id'];
      try {
        final detail = Map<String, dynamic>.from(await api.get('/mail-accounts/$id') as Map);
        expect(detail.containsKey('smtpPassword'), isFalse, reason: 'write-only');
        expect(detail['tenantId'], isNull, reason: 'empty tenant is sent as null');
        expect(extractItems(await api.get('/mail-accounts')).any((a) => a['id'] == id), isTrue);

        final update = mailAccountPayload({...values, 'name': 'mobile-live-$_ts-2'}, password: '');
        expect(update.containsKey('smtpPassword'), isFalse);
        await api.put('/mail-accounts/$id', update);
        expect((await api.get('/mail-accounts/$id') as Map)['name'], 'mobile-live-$_ts-2');

        await expectLater(
          api.post('/mail-accounts/$id/verify', const {}),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
          reason: 'inactive account: rejected before any SMTP connection',
        );
      } finally {
        await api.delete('/mail-accounts/$id');
      }
      expect(extractItems(await api.get('/mail-accounts')).any((a) => a['id'] == id), isFalse);
    });

    test('E-mail templates: create, PUT with key + lock, preview, delete (204)', () async {
      final key = 'mobile-live-$_ts';
      final path = '/email-templates/$key';
      await api.post(
          '/email-templates',
          emailTemplatePayload(
              templateKey: key,
              subject: 'Canlı [[\${userName}]]',
              htmlBody: '<p th:text="\${userName}">x</p>',
              description: 'mobil canlı test',
              active: false));
      try {
        final record = Map<String, dynamic>.from(await api.get(path) as Map);
        expect(extractItems(await api.get(pagedEndpoint('/email-templates', 0, 100))).any((t) => t['templateKey'] == key),
            isTrue);
        await api.put(
            path,
            emailTemplatePayload(
                templateKey: key,
                subject: 'Güncel [[\${userName}]]',
                htmlBody: record['htmlBody'] as String,
                description: '',
                active: false,
                optimisticLockVersion: record['optimisticLockVersion']));
        final updated = Map<String, dynamic>.from(await api.get(path) as Map);
        expect(updated['subject'], 'Güncel [[\${userName}]]');
        expect(updated['description'], isNull);

        final preview = Map<String, dynamic>.from(await api.post('$path/preview', {
          'data': {'userName': 'Zeynep'},
        }) as Map);
        expect(preview['html'], contains('Zeynep'));
        expect(preview['subject'], 'Güncel Zeynep');
      } finally {
        expect(await api.delete(path), isNull);
      }
      await expectLater(api.get(path), throwsA(isA<ApiException>()));
    });

    test('E-mail logs: paged list, status filter; classpath templates', () async {
      final all = await api.get(pagedEndpoint(emailLogsEndpoint(null), 0, 5));
      expect(totalCount(all), isNotNull);
      final failed = extractItems(await api.get(pagedEndpoint(emailLogsEndpoint('FAILED'), 0, 20)));
      expect(failed.every((l) => l['status'] == 'FAILED'), isTrue);
      expect(await api.get('/emails/templates'), isA<List>());
    });

    test('E-mail logs: retry of a SENT log is rejected (no side effect)', () async {
      final sent = extractItems(await api.get(pagedEndpoint(emailLogsEndpoint('SENT'), 0, 1)));
      if (sent.isEmpty) return markTestSkipped('no SENT log');
      expect(canRetryEmail(sent.first), isFalse);
      await expectLater(api.post('/emails/${sent.first['id']}/retry', const {}),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)));
    });
  });

  // Read-only on purpose: no user create/delete, no 2FA setup (GET /auth/mfa/setup resets the secret and
  // disables 2FA), no peek (requeues messages), no purge/republish.
  group('live system & account contract (read-only)', skip: !_live ? 'set LIVE_API=1' : null, () {
    late Set<String> perms;
    setUpAll(() async {
      final data = await api.get('/users/me/permissions') as Map;
      perms = {for (final p in data['permissions'] as List) '$p'};
    });

    test('profile: /users/me has the fields the screens read', () async {
      final me = Map<String, dynamic>.from(await api.get('/users/me') as Map);
      for (final k in ['id', 'username', 'email', 'firstName', 'lastName', 'provider', 'isActive', 'roles', 'createdAt']) {
        expect(me.containsKey(k), isTrue, reason: k);
      }
    });

    test('wrong current password → 400 "Current password is incorrect" (mapped), nothing changes', () async {
      await expectLater(
        api.put('/users/me/password', {'currentPassword': 'yanlis-$_ts', 'newPassword': 'Yeni${_ts}Aa1'}),
        throwsA(isA<ApiException>().having((e) => userErrorText(e), 'text', 'Mevcut şifre hatalı.')),
      );
    });

    test('2FA status with the session; a refused disable keeps the session', () async {
      final status = await api.get('/auth/mfa/status') as Map;
      expect(status['mfaEnabled'], isA<bool>());
      // 400 (2FA off) or 401 (wrong password) — either way no state change and still signed in.
      await expectLater(api.post('/auth/mfa/disable', {'password': 'yanlis-$_ts'}), throwsA(isA<ApiException>()));
      expect(await api.get('/auth/mfa/status'), isA<Map>());
    });

    test('users (users:manage): panel/tenant lists, roles list for the hierarchy', () async {
      if (!perms.contains('users:manage')) return markTestSkipped('no users:manage');
      final panel = extractItems(await api.get('/users?audience=panel'));
      expect(panel.every((u) => rolesOf(u).any(roleLevels.containsKey)), isTrue);
      final tenant = extractItems(await api.get('/users?audience=tenant'));
      expect(tenant.every((u) => rolesOf(u).contains('TENANT')), isTrue);
      final roles = extractItems(await api.get('/roles'));
      expect(roles.map((r) => r['name']), containsAll(['SUPER_ADMIN', 'ADMIN', 'EDITOR', 'VIEWER']));
      if (panel.isNotEmpty) expect(await api.get('/users/${panel.first['id']}'), isA<Map>());
    });

    test('RabbitMQ (rabbit:read): overview + queues + queue detail', () async {
      if (!perms.contains('rabbit:read')) return markTestSkipped('no rabbit:read');
      final overview = await api.get('$rabbitBase/overview') as Map;
      expect(overview.containsKey('queueCount'), isTrue);
      final queues = extractItems(await api.get('$rabbitBase/queues'));
      if (queues.isEmpty) return;
      final detail = await api.get(queuePath('${queues.first['name']}')) as Map;
      expect(detail['name'], queues.first['name']);
    });

    test('storage quota of the session tenant', () async {
      final tenant = _env['ELLY_TENANT'] ?? 'tenant1';
      final quota = await api.get('/storage/tenant/$tenant/quota') as Map;
      expect(quota['limitBytes'], isA<num>());
    });
  });

  // Read-only on purpose: never sends a chat message, creates/deletes a group, invites, bans or marks anything read.
  group('live realtime contract (read-only)', skip: !_live ? 'set LIVE_API=1' : null, () {
    test('notifications: unread count + newest page parse', () async {
      expect((await api.get('/notifications/unread-count') as Map)['count'], isA<num>());
      final page = await api.get('/notifications?page=0&size=5');
      final items = extractItems(page);
      expect(items.map(AppNotification.fromJson).every((n) => n != null), isTrue);
    });

    test('chat (chat:read): groups of the session tenant, then access / members / history / bans of one', () async {
      final perms = {for (final p in (await api.get('/users/me/permissions') as Map)['permissions'] as List) '$p'};
      if (!perms.contains('chat:read')) return markTestSkipped('no chat:read');
      final tenant = _env['ELLY_TENANT'] ?? 'tenant1';
      final groups = [for (final g in await api.get('${chatBase(tenant)}/groups') as List) ChatGroup.fromJson(g)!];
      expect(groups.every((g) => g.tenantId == tenant && isUuid(g.id)), isTrue, reason: 'AC=TC: session tenant');
      if (groups.isEmpty) return;
      final g = groups.first;
      final access = ChatGroupAccess.fromJson(await api.get('${chatBase(tenant)}/groups/${g.id}/access'));
      if (!access.canRead) return;
      final members = await api.get('${chatBase(tenant)}/groups/${g.id}/members') as List;
      expect(members.map(ChatMember.fromJson).every((m) => m != null), isTrue);
      final history = await api.get('${chatBase(tenant)}/groups/${g.id}/messages?limit=5') as List;
      final messages = history.map(ChatMessage.fromJson).toList();
      expect(messages.every((m) => m != null && m.groupId == g.id), isTrue);
      expect(await api.get('${chatBase(tenant)}/groups/${g.id}/bans'), isA<List>());
    });

    test('STOMP over SockJS: CONNECT with the Bearer token is accepted, user queue subscribable', () async {
      final token = await const FlutterSecureStorage().read(key: 'accessToken');
      final connected = Completer<void>();
      final link = stompClientConnector(
        url: RealtimeService.url,
        headers: {'Authorization': 'Bearer $token'},
        onConnected: () => connected.complete(),
        onError: (m) => connected.completeError(StateError('STOMP ERROR: $m')),
        onClosed: () {
          if (!connected.isCompleted) connected.completeError(StateError('closed before CONNECTED'));
        },
      );
      try {
        await connected.future.timeout(const Duration(seconds: 20));
        link.subscribe(StompDest.notificationsUnreadCount, (_) {})();
      } finally {
        link.close();
      }
    });
  });
}
