import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/services/crud_payload.dart';
import 'package:elly_mobile_app/services/text_format.dart';
import 'package:flutter_test/flutter_test.dart';

final _pages = ModulesConfig.byKey('pages');
final _components = ModulesConfig.byKey('components');
final _widgets = ModulesConfig.byKey('widgets');
final _banners = ModulesConfig.byKey('banners');
final _contents = ModulesConfig.byKey('contents');
final _posts = ModulesConfig.byKey('posts');

/// GET /pages/{slug} (DtoPageDetail): components are objects.
final _page = {
  'id': 7,
  'title': 'Hakkımda',
  'slug': 'hakkimda',
  'status': true,
  'seoInfo': {'title': 'SEO', 'description': 'd'},
  'components': [
    {'id': 1, 'name': 'Hero'},
    {'id': 2, 'name': 'Footer'},
  ],
};

/// GET /components/{id} (DtoComponent): pageIds ids, banners/widgets/forms objects (omitted when empty).
final _component = {
  'id': 3,
  'name': 'Slider',
  'type': 'BANNER',
  'orderIndex': 2,
  'status': true,
  'pageIds': [7, 8],
  'pages': [
    {'id': 7},
    {'id': 8},
  ],
  'banners': [
    {'id': 11, 'title': 'A'},
    {'id': 12, 'title': 'B'},
  ],
};

void main() {
  group('relationIds', () {
    test('objects, ids, junk', () {
      expect(
        relationIds([
          {'id': 1},
          2,
          {'name': 'no id'},
          null,
        ]),
        [1, 2],
      );
      expect(relationIds(null), isEmpty);
      expect(relationIds('x'), isEmpty);
    });
  });

  group('relations: pages.componentIds (backend null = untouched)', () {
    test('initial value = ids of the page components', () {
      expect(initialFormValues(_pages, _page)['componentIds'], [1, 2]);
    });

    test('untouched → not sent (no risk of wiping)', () {
      final payload = buildPayload(_pages, _page, initialFormValues(_pages, _page)..['title'] = 'Yeni');
      expect(payload.containsKey('componentIds'), isFalse);
      expect(payload['title'], 'Yeni');
    });

    test('same ids in another order count as untouched', () {
      final payload = buildPayload(_pages, _page, initialFormValues(_pages, _page)..['componentIds'] = [2, 1]);
      expect(payload.containsKey('componentIds'), isFalse);
    });

    test('changed → full new list sent; cleared → []', () {
      expect(buildPayload(_pages, _page, initialFormValues(_pages, _page)..['componentIds'] = [2, 5])['componentIds'], [
        2,
        5,
      ]);
      expect(
        buildPayload(_pages, _page, initialFormValues(_pages, _page)..['componentIds'] = <Object>[])['componentIds'],
        isEmpty,
      );
    });

    test('create sends the selection', () {
      final values = initialFormValues(_pages, null)
        ..['title'] = 'T'
        ..['slug'] = 't'
        ..['componentIds'] = [4];
      expect(buildPayload(_pages, null, values)['componentIds'], [4]);
    });
  });

  group('relations: components (backend null = CLEAR)', () {
    test('untouched relations are sent back unchanged (ids from the detail record)', () {
      final payload = buildPayload(_components, _component, initialFormValues(_components, _component)..['name'] = 'X');
      expect(payload['bannerIds'], [11, 12]);
      expect(payload['pageIds'], [7, 8], reason: 'no field, kept from the record');
      expect(payload['widgetIds'], isEmpty, reason: 'hidden for BANNER type → []');
      expect(payload['formIds'], isEmpty);
      expect(payload.containsKey('banners'), isFalse, reason: 'response-only key');
    });

    test('changed selection is sent', () {
      final values = initialFormValues(_components, _component)..['bannerIds'] = [12, 13];
      expect(buildPayload(_components, _component, values)['bannerIds'], [12, 13]);
    });

    test('type change: relations of the old type are cleared (backend rejects mismatches)', () {
      final values = initialFormValues(_components, _component)
        ..['type'] = 'WIDGET'
        ..['widgetIds'] = [21];
      final payload = buildPayload(_components, _component, values);
      expect(payload['bannerIds'], isEmpty);
      expect(payload['widgetIds'], [21]);
      expect(payload['pageIds'], [7, 8]);
    });

    test('missing relation key in the record (empty, JsonInclude NON_NULL) → []', () {
      final record = {..._component}..remove('banners');
      expect(buildPayload(_components, record, initialFormValues(_components, record))['bannerIds'], isEmpty);
    });
  });

  group('relations: widgets', () {
    final widget = {
      'id': 5,
      'name': 'Son yazılar',
      'type': 'POST',
      'banners': <Object>[],
      'posts': [
        {'id': 31},
        {'id': 32},
      ],
    };

    test('untouched posts sent back, hidden banners []', () {
      final payload = buildPayload(_widgets, widget, initialFormValues(_widgets, widget));
      expect(payload['postIds'], [31, 32]);
      expect(payload['bannerIds'], isEmpty);
    });
  });

  group('visibleWhen', () {
    test('isFieldVisible', () {
      final bannerIds = _components.fields.firstWhere((f) => f.key == 'bannerIds');
      expect(isFieldVisible(bannerIds, {'type': 'BANNER'}), isTrue);
      expect(isFieldVisible(bannerIds, {'type': 'FORM'}), isFalse);
      expect(isFieldVisible(_components.fields.first, const {}), isTrue);
    });

    test('contents: only the metadata fields of the content type are written', () {
      final values = initialFormValues(_contents, null)
        ..['basicInfo.title'] = 'Yetenekler'
        ..['metadata.name'] = 'React'
        ..['metadata.company'] = 'should not be sent';
      final payload = buildPayload(_contents, null, values);
      expect(payload['contentType'], 'skills');
      expect(payload['basicInfo']['sectionKey'], 'portfolio_skills');
      expect(payload['metadata']['name'], 'React');
      expect(payload['metadata']['level'], 'Expert');
      expect((payload['metadata'] as Map).containsKey('company'), isFalse);
    });

    test('contents experience: tags are lists, unknown stored metadata keys survive', () {
      final record = {
        'id': 9,
        'contentType': 'experience',
        'basicInfo': {'title': 'Deneyim', 'sectionKey': 'portfolio_experience', 'sortOrder': 0, 'isActive': true},
        'metadata': {
          'company': 'Elly',
          'position': 'Dev',
          'technologies': ['Dart'],
          'legacy': 'keep',
        },
      };
      final values = initialFormValues(_contents, record)..['metadata.technologies'] = ['Dart', 'Flutter'];
      final metadata = buildPayload(_contents, record, values)['metadata'] as Map;
      expect(metadata['technologies'], ['Dart', 'Flutter']);
      expect(metadata['legacy'], 'keep');
      expect(metadata.containsKey('name'), isFalse);
    });
  });

  group('banners', () {
    final banner = {
      'id': 4,
      'title': 'Kampanya',
      'subFolder': 'promo',
      'images': {'desktop': 'assets/t/t1/images/d.png', 'tablet': 'https://cdn/t.png', 'mobile': null},
    };

    test('upload mode: image URLs kept from the record, the local mode field is never sent', () {
      final payload = buildPayload(_banners, banner, initialFormValues(_banners, banner)..['title'] = 'Yeni');
      expect(payload['images'], banner['images']);
      expect(payload.containsKey('_imageMode'), isFalse);
      expect(payload.keys, isNot(contains('desktop')));
    });

    test('URL mode: edited URLs are sent', () {
      final values = initialFormValues(_banners, banner)
        ..['_imageMode'] = 'url'
        ..['images.mobile'] = ' https://cdn/m.png ';
      final images = buildPayload(_banners, banner, values)['images'] as Map;
      expect(images['mobile'], 'https://cdn/m.png');
      expect(images['desktop'], 'assets/t/t1/images/d.png');
    });
  });

  group('posts', () {
    test('date: picked value sent, cleared → null, untouched original kept', () {
      final post = {'id': 1, 'title': 'T', 'slug': 't', 'publishedAt': '2026-01-02T03:04:05.000+00:00'};
      expect(buildPayload(_posts, post, initialFormValues(_posts, post))['publishedAt'], post['publishedAt']);
      expect(
        buildPayload(_posts, post, initialFormValues(_posts, post)..['publishedAt'] = '2026-10-12')['publishedAt'],
        '2026-10-12',
      );
      expect(buildPayload(_posts, post, initialFormValues(_posts, post)..['publishedAt'] = '')['publishedAt'], isNull);
    });

    test('rich text body is not trimmed', () {
      const html = '<p>a</p>\n';
      expect(buildPayload(_posts, null, initialFormValues(_posts, null)..['content'] = html)['content'], html);
    });
  });

  group('compareByKey', () {
    test('numbers numerically, missing = 0, ties by id', () {
      final items = [
        {'id': 3, 'orderIndex': 10},
        {'id': 2, 'orderIndex': 2},
        {'id': 1},
        {'id': 4, 'orderIndex': 2},
      ]..sort((a, b) => compareByKey(a, b, 'orderIndex'));
      expect(items.map((e) => e['id']), [1, 2, 4, 3]);
    });

    test('text with Turkish folding; a|b fallback', () {
      final items = [
        {'id': 1, 'title': 'Zeytin'},
        {'id': 2, 'title': 'çiçek'},
        {'id': 3, 'title': 'Can'},
      ]..sort((a, b) => compareByKey(a, b, 'title'));
      expect(items.map((e) => e['id']), [3, 2, 1]);
      expect(
        compareByKey(
          {
            'metadata': {'sortOrder': 1},
          },
          {
            'basicInfo': {'sortOrder': 0},
          },
          'metadata.sortOrder|basicInfo.sortOrder',
        ),
        greaterThan(0),
      );
    });
  });

  group('slugify (admin generateSlug)', () {
    test('Turkish letters, symbols, spaces', () {
      expect(slugify('Merhaba Dünya!'), 'merhaba-dunya');
      expect(slugify('Türkçe Başlık  İçin  Şık Ödev'), 'turkce-baslik-icin-sik-odev');
      expect(slugify('  -Ilık su- '), 'ilik-su');
      expect(slugify('a -- b'), 'a-b');
    });
  });

  group('seoInfo', () {
    test('all-empty SEO block is not sent for a record without one', () {
      final values = initialFormValues(_pages, null)
        ..['title'] = 'T'
        ..['slug'] = 't'
        ..['seoInfo.title'] = ''
        ..['seoInfo.keywords'] = '  ';
      expect(buildPayload(_pages, null, values).containsKey('seoInfo'), isFalse);
    });

    test('a filled field or a set flag sends it', () {
      final values = initialFormValues(_pages, null)..['seoInfo.noIndex'] = true;
      expect(buildPayload(_pages, null, values)['seoInfo'], containsPair('noIndex', true));
    });

    test('an existing seoInfo is kept even when emptied (explicit edit)', () {
      final values = initialFormValues(_pages, _page)
        ..['seoInfo.title'] = ''
        ..['seoInfo.description'] = '';
      expect(buildPayload(_pages, _page, values)['seoInfo'], isA<Map>());
    });
  });

  group('banner _imageMode', () {
    test('edit: url when the record has images, upload otherwise; never read from the record', () {
      expect(
        initialFormValues(_banners, {
          'images': {'desktop': 'a.png'},
        })['_imageMode'],
        'url',
      );
      expect(
        initialFormValues(_banners, {
          'images': {'desktop': null, 'mobile': ''},
        })['_imageMode'],
        'upload',
      );
      expect(initialFormValues(_banners, {'_imageMode': 'url'})['_imageMode'], 'upload');
      expect(initialFormValues(_banners, null)['_imageMode'], 'upload');
    });
  });
}
