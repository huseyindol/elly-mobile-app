import 'package:flutter/material.dart';
import '../models/crud_module.dart';

/// Each module mirrors its backend `Dto*IU` (elly-backend/src/main/java/com/cms/dto).
/// `payloadKeys` = IU DTO keys sent on create/update. Relation id lists
/// (componentIds, pageIds, bannerIds, ...) are intentionally NOT sent: backend
/// treats null as "leave relations untouched".
class ModulesConfig {
  static const _slugPattern = r'^[a-z0-9]+(?:-[a-z0-9]+)*$';
  static const _slugMessage = 'Sadece küçük harf, rakam ve tire (örn: hakkimda-sayfasi)';
  static const _emailListPattern =
      r'^\s*[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}(\s*,\s*[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})*\s*$';

  static const List<CrudModule> allModules = [
    // DtoPageIU
    CrudModule(
      title: 'Pages',
      crudEndpoint: '/pages',
      listEndpoint: '/pages/list',
      detailEndpoint: '/pages/{slug}',
      icon: Icons.pages_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'slug',
      payloadKeys: ['title', 'description', 'slug', 'template', 'status', 'seoInfo'],
      fields: [
        FieldConfig(key: 'title', label: 'Başlık', isRequired: true),
        FieldConfig(
            key: 'slug', label: 'Slug', isRequired: true, pattern: _slugPattern, patternMessage: _slugMessage),
        FieldConfig(key: 'description', label: 'Açıklama', type: FieldType.longText),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: APage'),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        FieldConfig(key: 'seoInfo.title', label: 'SEO Başlık'),
        FieldConfig(key: 'seoInfo.description', label: 'SEO Açıklama', type: FieldType.longText),
        FieldConfig(key: 'seoInfo.keywords', label: 'SEO Anahtar Kelimeler'),
        FieldConfig(key: 'seoInfo.canonicalUrl', label: 'Canonical URL'),
        FieldConfig(key: 'seoInfo.noIndex', label: 'noindex', type: FieldType.boolean, defaultValue: false),
        FieldConfig(key: 'seoInfo.noFollow', label: 'nofollow', type: FieldType.boolean, defaultValue: false),
      ],
    ),
    // DtoComponentIU
    CrudModule(
      title: 'Components',
      crudEndpoint: '/components',
      listEndpoint: '/components/list',
      detailEndpoint: '/components/{id}',
      icon: Icons.extension_rounded,
      listTitleKey: 'name',
      listSubtitleKey: 'type',
      payloadKeys: ['name', 'description', 'type', 'content', 'template', 'orderIndex', 'status'],
      fields: [
        FieldConfig(key: 'name', label: 'Bileşen Adı', isRequired: true),
        FieldConfig(
          key: 'type',
          label: 'Tip',
          type: FieldType.dropdown,
          isRequired: true,
          options: ['BANNER', 'WIDGET', 'FORM'],
          defaultValue: 'BANNER',
        ),
        FieldConfig(key: 'description', label: 'Açıklama', type: FieldType.longText),
        FieldConfig(key: 'content', label: 'İçerik (HTML)', type: FieldType.longText),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: BComponent'),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
      ],
    ),
    // DtoPostIU
    CrudModule(
      title: 'Posts',
      crudEndpoint: '/posts',
      listEndpoint: '/posts/list',
      detailEndpoint: '/posts/{id}',
      icon: Icons.article_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'slug',
      payloadKeys: [
        'title', 'content', 'slug', 'template', 'status', 'orderIndex', 'description',
        'category', 'coverImage', 'publishedAt', 'author', 'readingTime', 'seoInfo',
      ],
      fields: [
        FieldConfig(key: 'title', label: 'Başlık', isRequired: true),
        FieldConfig(
            key: 'slug', label: 'Slug', isRequired: true, pattern: _slugPattern, patternMessage: _slugMessage),
        FieldConfig(key: 'description', label: 'Kısa Açıklama', type: FieldType.longText),
        FieldConfig(key: 'content', label: 'İçerik (HTML/Markdown)', type: FieldType.longText),
        FieldConfig(key: 'category', label: 'Kategori'),
        FieldConfig(key: 'author', label: 'Yazar'),
        FieldConfig(key: 'readingTime', label: 'Okuma Süresi', hint: 'örn: 5 dk'),
        FieldConfig(key: 'coverImage', label: 'Kapak Görseli URL'),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: APost'),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        FieldConfig(key: 'seoInfo.title', label: 'SEO Başlık'),
        FieldConfig(key: 'seoInfo.description', label: 'SEO Açıklama', type: FieldType.longText),
        FieldConfig(key: 'seoInfo.keywords', label: 'SEO Anahtar Kelimeler'),
        FieldConfig(key: 'seoInfo.canonicalUrl', label: 'Canonical URL'),
        FieldConfig(key: 'seoInfo.noIndex', label: 'noindex', type: FieldType.boolean, defaultValue: false),
        FieldConfig(key: 'seoInfo.noFollow', label: 'nofollow', type: FieldType.boolean, defaultValue: false),
      ],
    ),
    // DtoCmsContentIU { basicInfo: DtoCmsBasicInfoIU, contentType, metadata }
    CrudModule(
      title: 'Contents',
      crudEndpoint: '/contents',
      listEndpoint: '/contents/list',
      icon: Icons.text_snippet_rounded,
      listTitleKey: 'metadata.name|metadata.company|metadata.title|basicInfo.title',
      listSubtitleKey: 'basicInfo.sectionKey',
      payloadKeys: ['basicInfo', 'contentType', 'metadata'],
      fields: [
        FieldConfig(
          key: 'contentType',
          label: 'İçerik Tipi',
          type: FieldType.dropdown,
          isRequired: true,
          options: ['skills', 'experience'],
          defaultValue: 'skills',
        ),
        FieldConfig(key: 'basicInfo.title', label: 'Bölüm Başlığı', isRequired: true),
        FieldConfig(
            key: 'basicInfo.sectionKey',
            label: 'Section Key',
            isRequired: true,
            defaultValue: 'portfolio_skills',
            hint: 'portfolio_skills / portfolio_experience'),
        FieldConfig(key: 'basicInfo.description', label: 'Bölüm Açıklaması', type: FieldType.longText),
        FieldConfig(key: 'basicInfo.sortOrder', label: 'Sıra', type: FieldType.number, isRequired: true, defaultValue: 0),
        FieldConfig(key: 'basicInfo.isActive', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        FieldConfig(
          key: 'metadata',
          label: 'Metadata (JSON)',
          type: FieldType.json,
          isRequired: true,
          templateFromField: 'contentType',
          templates: {
            'skills': {
              'name': '',
              'level': 'Expert',
              'years': '',
              'imageUrl': 'https://',
              'url': 'https://',
              'sortOrder': 0,
            },
            'experience': {
              'company': '',
              'position': '',
              'period': '',
              'location': '',
              'industry': '',
              'description': '',
              'technologies': <String>[],
              'achievements': <String>[],
              'sortOrder': 0,
            },
          },
        ),
      ],
    ),
    // DtoWidgetIU
    CrudModule(
      title: 'Widgets',
      crudEndpoint: '/widgets',
      listEndpoint: '/widgets/list',
      detailEndpoint: '/widgets/{id}',
      icon: Icons.widgets_rounded,
      listTitleKey: 'name',
      listSubtitleKey: 'type',
      payloadKeys: ['name', 'description', 'type', 'content', 'template', 'orderIndex', 'status'],
      fields: [
        FieldConfig(key: 'name', label: 'Widget Adı', isRequired: true),
        FieldConfig(
          key: 'type',
          label: 'Widget Tipi',
          type: FieldType.dropdown,
          isRequired: true,
          options: ['BANNER', 'POST'],
          defaultValue: 'BANNER',
        ),
        FieldConfig(key: 'description', label: 'Açıklama', type: FieldType.longText),
        FieldConfig(key: 'content', label: 'İçerik (HTML)', type: FieldType.longText),
        FieldConfig(key: 'template', label: 'Şablon', hint: 'örn: BWidget'),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
      ],
    ),
    // DtoBannerIU — multipart: `data` (JSON) + optional desktop/tablet/mobile files
    CrudModule(
      title: 'Banners',
      crudEndpoint: '/banners',
      listEndpoint: '/banners/list',
      icon: Icons.view_carousel_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'subFolder|type',
      requestMode: RequestMode.multipartData,
      payloadKeys: ['title', 'altText', 'link', 'target', 'type', 'orderIndex', 'status', 'images', 'subFolder'],
      fields: [
        FieldConfig(key: 'title', label: 'Başlık', isRequired: true),
        FieldConfig(key: 'altText', label: 'Alt Metin'),
        FieldConfig(key: 'link', label: 'Link (URL)'),
        FieldConfig(
          key: 'target',
          label: 'Hedef',
          type: FieldType.dropdown,
          options: ['_blank', '_self'],
          defaultValue: '_blank',
        ),
        FieldConfig(key: 'type', label: 'Tip'),
        FieldConfig(key: 'subFolder', label: 'Alt Klasör'),
        FieldConfig(key: 'orderIndex', label: 'Sıra', type: FieldType.number, defaultValue: 0),
        FieldConfig(key: 'status', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        FieldConfig(key: 'images.desktop', label: 'Desktop Görsel URL'),
        FieldConfig(key: 'images.tablet', label: 'Tablet Görsel URL'),
        FieldConfig(key: 'images.mobile', label: 'Mobile Görsel URL'),
        FieldConfig(key: 'desktop', label: 'Desktop Görsel Yükle', type: FieldType.file),
        FieldConfig(key: 'tablet', label: 'Tablet Görsel Yükle', type: FieldType.file),
        FieldConfig(key: 'mobile', label: 'Mobile Görsel Yükle', type: FieldType.file),
      ],
    ),
    // DtoFormDefinitionIU
    CrudModule(
      title: 'Forms',
      crudEndpoint: '/forms',
      listEndpoint: '/forms/list',
      icon: Icons.dynamic_form_rounded,
      listTitleKey: 'title',
      listSubtitleKey: 'recipientEmail|senderMailAccountName',
      forceDeleteSuffix: '/force',
      payloadKeys: [
        'title', 'version', 'schema', 'active', 'senderMailAccountId',
        'recipientEmail', 'notificationSubject', 'notificationEnabled',
      ],
      fields: [
        FieldConfig(key: 'title', label: 'Form Başlığı', isRequired: true),
        FieldConfig(key: 'active', label: 'Aktif', type: FieldType.boolean, defaultValue: true),
        FieldConfig(
            key: 'notificationEnabled', label: 'Mail Bildirimi', type: FieldType.boolean, defaultValue: true),
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
    // Assets — multipart: `file` (+ `subFolder`); PUT replaces the file
    CrudModule(
      title: 'Assets',
      crudEndpoint: '/assets',
      listEndpoint: '/assets/list/paged?page=0&size=100&sort=id,desc',
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
}
