import 'package:flutter/material.dart';

import '../models/crud_module.dart';
import '../services/crud_payload.dart';

/// Each module mirrors its backend `Dto*IU` (elly-backend/src/main/java/com/cms/dto) and its elly-admin
/// form/list (`src/app/(baseLayout)/<module>`, Zod schemas in `src/schemas`).
/// `payloadKeys` = IU DTO keys sent on create/update. Relation id lists follow the backend semantics
/// documented on [buildPayload] / [FieldConfig.relationKeepsOnNull].
/// Titles match the elly-admin sidebar labels.
class ModulesConfig {
  static const _slugPattern = r'^[a-z0-9]+(?:-[a-z0-9]+)*$';
  static const _slugMessage = 'Sadece küçük harf, rakam ve tire (örn: hakkimda-sayfasi)';
  static const _urlPattern = r'^[a-zA-Z][a-zA-Z0-9+.-]*:\S+$';
  static const _urlMessage = 'Geçerli bir URL girin (https://...)';
  static const _emailListPattern =
      r'^\s*[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}(\s*,\s*[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})*\s*$';

  static const _seo = 'SEO Ayarları';
  static const _seoFields = [
    FieldConfig(key: 'seoInfo.title', label: 'SEO Başlık', maxLength: 60, section: _seo),
    FieldConfig(
      key: 'seoInfo.description',
      label: 'Meta Açıklama',
      type: FieldType.longText,
      maxLength: 160,
      section: _seo,
    ),
    FieldConfig(key: 'seoInfo.keywords', label: 'Anahtar Kelimeler', hint: 'kelime1, kelime2', section: _seo),
    FieldConfig(key: 'seoInfo.canonicalUrl', label: 'Canonical URL', section: _seo),
    FieldConfig(key: 'seoInfo.noIndex', label: 'noindex', type: FieldType.boolean, defaultValue: false, section: _seo),
    FieldConfig(
      key: 'seoInfo.noFollow',
      label: 'nofollow',
      type: FieldType.boolean,
      defaultValue: false,
      section: _seo,
    ),
  ];

  static const _banners = FieldConfig(
    key: 'bannerIds',
    label: 'Bannerlar',
    type: FieldType.relation,
    relationEndpoint: '/banners/list/summary',
    optionLabelKey: 'title',
    optionSubtitleKey: 'subFolder',
    relationSource: 'banners',
    visibleWhen: {'type': 'BANNER'},
  );

  static const List<CrudModule> allModules = [
    // DtoPageIU — admin pages/[id]/edit
    CrudModule(
      title: 'Sayfalar',
      crudEndpoint: '/pages',
      permissionKey: 'pages',
      listEndpoint: '/pages/list',
      detailEndpoint: '/pages/{slug}',
      icon: Icons.pages_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'slug',
      sortKey: 'title',
      statusKey: 'status',
      listMeta: _seoFlags,
      payloadKeys: ['title', 'description', 'slug', 'template', 'status', 'seoInfo', 'componentIds'],
      fields: [
        FieldConfig(key: 'title', label: 'Başlık', isRequired: true, maxLength: 100),
        FieldConfig(
          key: 'slug',
          label: 'Slug',
          isRequired: true,
          maxLength: 100,
          pattern: _slugPattern,
          patternMessage: _slugMessage,
          slugFrom: 'title',
        ),
        FieldConfig(key: 'description', label: 'Açıklama', type: FieldType.longText),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: APage', maxLength: 50),
        FieldConfig(key: 'status', label: 'Aktif (Yayında)', type: FieldType.boolean, defaultValue: true),
        ..._seoFields,
        FieldConfig(
          key: 'componentIds',
          label: 'Bileşenler',
          type: FieldType.relation,
          relationEndpoint: '/components/list/summary',
          optionSubtitleKey: 'type',
          relationSource: 'components',
          relationKeepsOnNull: true,
          section: 'Bileşen (Component) Atama',
        ),
      ],
    ),
    // DtoComponentIU — pageIds has no field: sent back from the record unchanged.
    CrudModule(
      title: 'Componentler',
      crudEndpoint: '/components',
      permissionKey: 'components',
      listEndpoint: '/components/list',
      detailEndpoint: '/components/{id}',
      icon: Icons.extension_rounded,
      listTitleKey: 'name',
      listSubtitleKey: 'type',
      sortKey: 'orderIndex',
      statusKey: 'status',
      listMeta: _componentMeta,
      payloadKeys: [
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
      ],
      fields: [
        FieldConfig(key: 'name', label: 'Bileşen Adı', isRequired: true, maxLength: 100),
        FieldConfig(key: 'description', label: 'Açıklama', type: FieldType.longText),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: BComponent', maxLength: 50),
        FieldConfig(
          key: 'type',
          label: 'Tip',
          type: FieldType.dropdown,
          isRequired: true,
          options: ['BANNER', 'WIDGET', 'FORM'],
          defaultValue: 'BANNER',
        ),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        _banners,
        FieldConfig(
          key: 'widgetIds',
          label: 'Widgetlar',
          type: FieldType.relation,
          relationEndpoint: '/widgets/list/summary',
          optionSubtitleKey: 'type',
          relationSource: 'widgets',
          visibleWhen: {'type': 'WIDGET'},
        ),
        FieldConfig(
          key: 'formIds',
          label: 'Formlar',
          type: FieldType.relation,
          relationEndpoint: '/forms/list',
          optionLabelKey: 'title',
          relationSource: 'forms',
          visibleWhen: {'type': 'FORM'},
        ),
        FieldConfig(key: 'content', label: 'İçerik (HTML)', type: FieldType.longText, section: 'Gelişmiş'),
      ],
    ),
    // DtoPostIU
    CrudModule(
      title: 'Yazılar',
      crudEndpoint: '/posts',
      permissionKey: 'posts',
      listEndpoint: '/posts/list',
      detailEndpoint: '/posts/{id}',
      icon: Icons.article_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'slug',
      sortKey: 'orderIndex',
      statusKey: 'status',
      thumbnailKey: 'coverImage',
      listMeta: _postMeta,
      payloadKeys: [
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
      ],
      fields: [
        FieldConfig(key: 'title', label: 'Başlık', isRequired: true, maxLength: 200),
        FieldConfig(
          key: 'slug',
          label: 'Slug',
          isRequired: true,
          maxLength: 200,
          pattern: _slugPattern,
          patternMessage: _slugMessage,
          slugFrom: 'title',
        ),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: APost', maxLength: 50),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif (Yayında)', type: FieldType.boolean, defaultValue: true),
        FieldConfig(key: 'content', label: 'İçerik', type: FieldType.richText, section: 'İçerik'),
        FieldConfig(key: 'description', label: 'Kısa Açıklama', type: FieldType.longText, section: 'Blog Bilgileri'),
        FieldConfig(key: 'category', label: 'Kategori', section: 'Blog Bilgileri'),
        FieldConfig(key: 'author', label: 'Yazar', section: 'Blog Bilgileri'),
        FieldConfig(key: 'readingTime', label: 'Okuma Süresi', hint: 'örn: 5 dk', section: 'Blog Bilgileri'),
        FieldConfig(key: 'publishedAt', label: 'Yayın Tarihi', type: FieldType.date, section: 'Blog Bilgileri'),
        FieldConfig(
          key: 'coverImage',
          label: 'Kapak Görseli',
          type: FieldType.imageUrl,
          hint: 'https://... veya /assets/...',
          section: 'Blog Bilgileri',
        ),
        ..._seoFields,
      ],
    ),
    // DtoCmsContentIU { basicInfo: DtoCmsBasicInfoIU, contentType, metadata } — metadata fields per
    // content type like admin `schemas/dynamic` (skills / experience).
    CrudModule(
      title: 'İçerikler',
      crudEndpoint: '/contents',
      permissionKey: 'contents',
      listEndpoint: '/contents/list',
      icon: Icons.text_snippet_rounded,
      listTitleKey: 'metadata.name|metadata.company|metadata.title|basicInfo.title',
      listSubtitleKey: 'basicInfo.sectionKey',
      sortKey: 'metadata.sortOrder|basicInfo.sortOrder',
      statusKey: 'basicInfo.isActive',
      listMeta: _contentMeta,
      filter: ListFilter(label: 'İçerik Tipi', options: _contentTypes, key: 'contentType'),
      payloadKeys: ['basicInfo', 'contentType', 'metadata'],
      fields: [
        FieldConfig(
          key: 'contentType',
          label: 'İçerik Tipi',
          type: FieldType.dropdown,
          isRequired: true,
          options: ['skills', 'experience'],
          optionLabels: _contentTypes,
          defaultValue: 'skills',
          readOnlyOnEdit: true,
        ),
        FieldConfig(key: 'basicInfo.title', label: 'Bölüm Başlığı', isRequired: true),
        FieldConfig(
          key: 'basicInfo.sectionKey',
          label: 'Section Key',
          isRequired: true,
          defaultValue: 'portfolio_skills',
          templateFromField: 'contentType',
          templates: {'skills': 'portfolio_skills', 'experience': 'portfolio_experience'},
        ),
        FieldConfig(key: 'basicInfo.description', label: 'Bölüm Açıklaması', type: FieldType.longText),
        FieldConfig(key: 'basicInfo.sortOrder', label: 'Bölüm Sırası', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'basicInfo.isActive', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        // skills
        FieldConfig(
          key: 'metadata.name',
          label: 'Yetenek Adı',
          isRequired: true,
          hint: 'örnek: React',
          section: 'Yetenek',
          visibleWhen: _skills,
        ),
        FieldConfig(
          key: 'metadata.level',
          label: 'Seviye',
          type: FieldType.dropdown,
          options: ['Expert', 'Advanced', 'Intermediate'],
          defaultValue: 'Expert',
          section: 'Yetenek',
          visibleWhen: _skills,
        ),
        FieldConfig(
          key: 'metadata.years',
          label: 'Deneyim',
          hint: 'örnek: 5+',
          section: 'Yetenek',
          visibleWhen: _skills,
        ),
        FieldConfig(
          key: 'metadata.imageUrl',
          label: 'Görsel URL',
          type: FieldType.imageUrl,
          isRequired: true,
          pattern: _urlPattern,
          patternMessage: _urlMessage,
          section: 'Yetenek',
          visibleWhen: _skills,
        ),
        FieldConfig(
          key: 'metadata.url',
          label: 'Referans Link',
          isRequired: true,
          pattern: _urlPattern,
          patternMessage: _urlMessage,
          section: 'Yetenek',
          visibleWhen: _skills,
        ),
        FieldConfig(
          key: 'metadata.sortOrder',
          label: 'Sıralama',
          type: FieldType.number,
          defaultValue: 0,
          section: 'Yetenek',
          visibleWhen: _skills,
        ),
        // experience
        FieldConfig(
          key: 'metadata.company',
          label: 'Şirket Adı',
          isRequired: true,
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
        FieldConfig(
          key: 'metadata.position',
          label: 'Pozisyon',
          isRequired: true,
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
        FieldConfig(
          key: 'metadata.period',
          label: 'Çalışma Dönemi',
          hint: 'örnek: Ekim 2023 - Günümüz',
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
        FieldConfig(key: 'metadata.location', label: 'Konum', section: 'Deneyim', visibleWhen: _experience),
        FieldConfig(
          key: 'metadata.industry',
          label: 'Sektör',
          type: FieldType.dropdown,
          options: ['Fintech', 'E-commerce', 'Agency', 'Media', 'Freelancer'],
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
        FieldConfig(
          key: 'metadata.description',
          label: 'Açıklama',
          type: FieldType.longText,
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
        FieldConfig(
          key: 'metadata.technologies',
          label: 'Teknolojiler',
          type: FieldType.tags,
          hint: 'React, Next.js, TypeScript',
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
        FieldConfig(
          key: 'metadata.achievements',
          label: 'Başarılar',
          type: FieldType.tags,
          hint: 'Virgülle ayırın',
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
        FieldConfig(
          key: 'metadata.sortOrder',
          label: 'Sıralama',
          type: FieldType.number,
          defaultValue: 0,
          section: 'Deneyim',
          visibleWhen: _experience,
        ),
      ],
    ),
    // DtoWidgetIU
    CrudModule(
      title: 'Widgetlar',
      crudEndpoint: '/widgets',
      permissionKey: 'widgets',
      listEndpoint: '/widgets/list',
      detailEndpoint: '/widgets/{id}',
      icon: Icons.widgets_rounded,
      listTitleKey: 'name',
      listSubtitleKey: 'type',
      sortKey: 'orderIndex',
      statusKey: 'status',
      listMeta: _widgetMeta,
      payloadKeys: [
        'name',
        'description',
        'type',
        'content',
        'template',
        'orderIndex',
        'status',
        'bannerIds',
        'postIds',
      ],
      fields: [
        FieldConfig(key: 'name', label: 'Widget Adı', isRequired: true, maxLength: 100),
        FieldConfig(key: 'description', label: 'Açıklama', type: FieldType.longText),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: BWidget', maxLength: 50),
        FieldConfig(
          key: 'type',
          label: 'Widget Tipi',
          type: FieldType.dropdown,
          isRequired: true,
          options: ['BANNER', 'POST'],
          defaultValue: 'BANNER',
        ),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        _banners,
        FieldConfig(
          key: 'postIds',
          label: 'Yazılar',
          type: FieldType.relation,
          relationEndpoint: '/posts/list/summary',
          optionLabelKey: 'title',
          optionSubtitleKey: 'slug',
          relationSource: 'posts',
          visibleWhen: {'type': 'POST'},
        ),
        FieldConfig(key: 'content', label: 'İçerik (HTML)', type: FieldType.longText, section: 'Gelişmiş'),
      ],
    ),
    // DtoBannerIU — multipart: `data` (JSON) + optional desktop/tablet/mobile files. Backend: when any
    // file is sent the URL images are ignored, so (like admin) it is either upload or URL mode.
    CrudModule(
      title: 'Bannerlar',
      crudEndpoint: '/banners',
      permissionKey: 'banners',
      listEndpoint: '/banners/list',
      icon: Icons.view_carousel_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'altText',
      sortKey: 'orderIndex',
      statusKey: 'status',
      thumbnailKey: 'images.desktop|images.tablet|images.mobile',
      listMeta: _bannerMeta,
      filter: ListFilter(
        label: 'Klasör',
        optionsEndpoint: '/banners/sub-folders',
        endpointTemplate: '/banners/list/{value}',
      ),
      requestMode: RequestMode.multipartData,
      payloadKeys: ['title', 'altText', 'link', 'target', 'type', 'orderIndex', 'status', 'images', 'subFolder'],
      fields: [
        FieldConfig(key: 'title', label: 'Başlık', isRequired: true, maxLength: 200),
        FieldConfig(key: 'altText', label: 'Alt Metin'),
        FieldConfig(key: 'link', label: 'Link (URL)', pattern: _urlPattern, patternMessage: _urlMessage),
        FieldConfig(
          key: 'target',
          label: 'Hedef',
          type: FieldType.dropdown,
          options: ['_blank', '_self'],
          optionLabels: {'_blank': 'Yeni sekme (_blank)', '_self': 'Aynı sekme (_self)'},
          defaultValue: '_blank',
        ),
        FieldConfig(key: 'type', label: 'Tip'),
        FieldConfig(key: 'subFolder', label: 'Alt Klasör', hint: 'örn: promo'),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        // Local (not in payloadKeys): picks which image inputs are shown and sent.
        FieldConfig(
          key: '_imageMode',
          label: 'Görsel Kaynağı',
          type: FieldType.dropdown,
          options: ['upload', 'url'],
          optionLabels: {'upload': 'Dosya yükle', 'url': 'URL gir'},
          defaultValue: 'upload',
          section: 'Görseller',
        ),
        FieldConfig(key: 'desktop', label: 'Desktop Görsel', type: FieldType.file, visibleWhen: _upload),
        FieldConfig(key: 'tablet', label: 'Tablet Görsel', type: FieldType.file, visibleWhen: _upload),
        FieldConfig(key: 'mobile', label: 'Mobile Görsel', type: FieldType.file, visibleWhen: _upload),
        FieldConfig(key: 'images.desktop', label: 'Desktop Görsel URL', type: FieldType.imageUrl, visibleWhen: _url),
        FieldConfig(key: 'images.tablet', label: 'Tablet Görsel URL', type: FieldType.imageUrl, visibleWhen: _url),
        FieldConfig(key: 'images.mobile', label: 'Mobile Görsel URL', type: FieldType.imageUrl, visibleWhen: _url),
      ],
    ),
    // DtoFormDefinitionIU
    CrudModule(
      title: 'Formlar',
      crudEndpoint: '/forms',
      permissionKey: 'forms',
      listEndpoint: '/forms/list',
      icon: Icons.dynamic_form_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'recipientEmail|senderMailAccountName',
      forceDeleteSuffix: '/force',
      payloadKeys: [
        'title',
        'version',
        'schema',
        'active',
        'senderMailAccountId',
        'recipientEmail',
        'notificationSubject',
        'notificationEnabled',
      ],
      fields: [
        FieldConfig(key: 'title', label: 'Form Başlığı', isRequired: true),
        FieldConfig(key: 'active', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        FieldConfig(key: 'notificationEnabled', label: 'Mail Bildirimi', type: FieldType.boolean, defaultValue: true),
        FieldConfig(
          key: 'senderMailAccountId',
          label: 'Gönderici Mail Hesabı',
          type: FieldType.dropdown,
          optionsEndpoint: '/mail-accounts',
          optionValueKey: 'id',
          optionLabelKey: 'name',
          hint: 'Bildirim açıksa zorunlu',
        ),
        FieldConfig(
          key: 'recipientEmail',
          label: 'Alıcı E-posta',
          pattern: _emailListPattern,
          patternMessage: 'Geçerli e-posta girin (birden fazlası için virgül)',
          hint: 'Bildirim açıksa zorunlu',
        ),
        FieldConfig(key: 'notificationSubject', label: 'Bildirim Konusu'),
        FieldConfig(
          key: 'schema',
          label: 'Form Şeması (JSON)',
          type: FieldType.json,
          isRequired: true,
          defaultValue: {
            'config': {'layout': 'vertical', 'submitLabel': 'Gönder'},
            'fields': [
              {'id': 'name', 'type': 'text', 'label': 'Ad Soyad', 'required': true},
              {'id': 'email', 'type': 'email', 'label': 'E-posta', 'required': true},
              {'id': 'message', 'type': 'textarea', 'label': 'Mesaj', 'required': false},
            ],
          },
        ),
      ],
    ),
    // Assets — own screen (AssetsScreen); this entry carries endpoints/permission for it and the drawer.
    CrudModule(
      title: 'Assetler',
      crudEndpoint: '/assets',
      permissionKey: 'assets',
      listEndpoint: '/assets/list/paged?sort=id,desc',
      paged: true,
      icon: Icons.folder_special_rounded,
      listTitleKey: 'name',
      listSubtitleKey: 'path|subFolder|extension',
      requestMode: RequestMode.multipartFields,
      payloadKeys: ['subFolder'],
      fields: [
        FieldConfig(key: 'file', label: 'Dosya', type: FieldType.file, isRequired: true),
        FieldConfig(key: 'subFolder', label: 'Alt Klasör', hint: 'örn: images'),
      ],
    ),
  ];

  static const _skills = {'contentType': 'skills'};
  static const _experience = {'contentType': 'experience'};
  static const _upload = {'_imageMode': 'upload'};
  static const _url = {'_imageMode': 'url'};
  static const _contentTypes = {'skills': 'Yetenekler', 'experience': 'Deneyimler'};

  /// Module by its backend permission key (`posts`, `pages`, ...).
  static CrudModule byKey(String permissionKey) => allModules.firstWhere((m) => m.permissionKey == permissionKey);
}

String _order(Map<String, dynamic> item) => 'Sıra: ${item['orderIndex'] ?? 0}';

int _count(Map<String, dynamic> item, String key) => (item[key] as List?)?.length ?? 0;

List<String> _seoFlags(Map<String, dynamic> item) => [
  if (getPath(item, 'seoInfo.noIndex') == true) 'noindex',
  if (getPath(item, 'seoInfo.noFollow') == true) 'nofollow',
];

List<String> _componentMeta(Map<String, dynamic> item) => [
  _order(item),
  '${_count(item, 'banners')} banner · ${_count(item, 'widgets')} widget · ${_count(item, 'forms')} form · '
      '${_count(item, 'pageIds')} sayfa',
];

List<String> _widgetMeta(Map<String, dynamic> item) => [
  _order(item),
  '${_count(item, 'banners')} banner · ${_count(item, 'posts')} post',
];

List<String> _bannerMeta(Map<String, dynamic> item) => [
  _order(item),
  'Klasör: ${item['subFolder']?.toString().isNotEmpty == true ? item['subFolder'] : '-'}',
  if (item['link']?.toString().isNotEmpty == true) '${item['link']} (${item['target'] ?? '_blank'})',
];

List<String> _postMeta(Map<String, dynamic> item) => [
  _order(item),
  [
    item['category'],
    item['author'],
    item['publishedAt']?.toString().split('T').first,
  ].where((v) => v != null && v.toString().isNotEmpty).join(' · '),
  ..._seoFlags(item),
].where((v) => v.isNotEmpty).toList();

List<String> _contentMeta(Map<String, dynamic> item) => [
  ModulesConfig._contentTypes[item['contentType']] ?? item['contentType']?.toString() ?? '',
  'Sıra: ${resolveListText(item, 'metadata.sortOrder|basicInfo.sortOrder') ?? 0}',
];
