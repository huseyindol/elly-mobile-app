import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// json: JSON editor (Map/List). file: picked file, sent as multipart part named [FieldConfig.key].
/// relation: id list picker ([FieldConfig.relationEndpoint]). richText: HTML body (Quill editor, raw HTML
/// fallback). date: `YYYY-MM-DD`. tags: `List<String>` typed comma separated. imageUrl: URL + preview +
/// pick from assets. formSchema: form builder for a backend `FormSchema` map (forms `schema`).
enum FieldType {
  text,
  longText,
  number,
  boolean,
  dropdown,
  json,
  file,
  relation,
  richText,
  date,
  tags,
  imageUrl,
  formSchema,
}

/// How create/update requests are sent.
/// - json: application/json body
/// - multipartData: multipart with JSON payload in a `data` part (+ file parts) — banners
/// - multipartFields: multipart with payload keys as plain text fields (+ file parts) — assets
enum RequestMode { json, multipartData, multipartFields }

class FieldConfig {
  /// Dot-path into the backend object (e.g. `basicInfo.title`, `images.desktop`).
  final String key;
  final String label;
  final FieldType type;
  final bool isRequired;
  final List<String>? options;

  /// Value used when creating a new record.
  final Object? defaultValue;

  /// Regex applied to non-empty text values.
  final String? pattern;
  final String? patternMessage;

  /// Dropdown options loaded from an endpoint (e.g. `/mail-accounts`).
  final String? optionsEndpoint;
  final String optionValueKey;
  final String optionLabelKey;

  /// Remote dropdown option label built from the whole item (wins over [optionLabelKey]).
  final String Function(Map<String, dynamic> item)? optionLabelOf;

  /// Remote dropdown: label for the record's current value when it is not among the loaded options
  /// (e.g. an inactive mail account); null → such a value is not shown.
  final String? Function(Map<String, dynamic>? record)? currentOptionLabel;

  /// `<module>:<action>` needed to load [optionsEndpoint]; without it the options are not requested.
  final String? optionsPermission;

  /// JSON field: template chosen by the current value of another field
  /// (e.g. metadata template by `contentType`). Applied when the editor is empty
  /// or still shows the previous template.
  final String? templateFromField;
  final Map<String, Object>? templates;

  final String? hint;

  /// Max characters (admin Zod `.max`).
  final int? maxLength;

  /// Dropdown option → label (options are the raw values otherwise).
  final Map<String, String>? optionLabels;

  /// Shown (and sent) only while every `fieldKey: value` matches the form values, e.g.
  /// `{'type': 'BANNER'}`. A hidden relation is sent as `[]` (admin does the same; the backend
  /// rejects relations that don't match the type); other hidden fields are not written.
  final Map<String, Object>? visibleWhen;

  /// Required while every `fieldKey: value` matches the form values (e.g. `{'notificationEnabled': true}`).
  final Map<String, Object>? requiredWhen;

  /// Locked when editing (e.g. content type: admin does not let it change).
  final bool readOnlyOnEdit;

  /// Slug field filled from this field while creating, until the user edits the slug.
  final String? slugFrom;

  /// Header shown above the first field of a new section.
  final String? section;

  /// Relation: options endpoint (e.g. `/components/list/summary`), shown as [optionLabelKey] /
  /// [optionSubtitleKey].
  final String? relationEndpoint;
  final String? optionSubtitleKey;

  /// Relation: dot-path in the record holding the related objects or ids (default: [key]).
  final String? relationSource;

  /// Relation: backend treats a missing (null) list as "leave untouched" (pages.componentIds), so the list
  /// is sent only when the selection changed. Otherwise null CLEARS the relation (components, widgets) and
  /// the current ids are always sent.
  final bool relationKeepsOnNull;

  /// File field: images only (picker filter + 5 MB limit like the admin `ImageUploadBox`).
  final bool imageOnly;

  /// File field: dot-path of the record's current image, previewed next to the picker.
  final String? currentImageKey;

  /// Initial value computed from the record (null when creating). Local `_` fields use it instead of
  /// reading the record (banner `_imageMode`).
  final Object? Function(Map<String, dynamic>? record)? initialValueOf;

  const FieldConfig({
    required this.key,
    required this.label,
    this.type = FieldType.text,
    this.isRequired = false,
    this.options,
    this.defaultValue,
    this.pattern,
    this.patternMessage,
    this.optionsEndpoint,
    this.optionValueKey = 'id',
    this.optionLabelKey = 'name',
    this.optionLabelOf,
    this.currentOptionLabel,
    this.optionsPermission,
    this.templateFromField,
    this.templates,
    this.hint,
    this.maxLength,
    this.optionLabels,
    this.visibleWhen,
    this.requiredWhen,
    this.readOnlyOnEdit = false,
    this.slugFrom,
    this.section,
    this.relationEndpoint,
    this.optionSubtitleKey,
    this.relationSource,
    this.relationKeepsOnNull = false,
    this.imageOnly = false,
    this.currentImageKey,
    this.initialValueOf,
  });
}

/// List filter chips. [optionsEndpoint] returns a list of strings (e.g. `/banners/sub-folders`);
/// with [endpointTemplate] the list is re-fetched from it (`{value}` URL-encoded), otherwise loaded
/// items are filtered by [key].
class ListFilter {
  final String label;
  final String? optionsEndpoint;
  final Map<String, String>? options;
  final String? endpointTemplate;
  final String? key;

  const ListFilter({required this.label, this.optionsEndpoint, this.options, this.endpointTemplate, this.key});
}

/// Screen opened for one record from its list row and its edit screen (forms → submissions).
class RecordLink {
  final String label;
  final IconData icon;

  /// `<permissionKey>:<action>` needed to show the link.
  final String action;
  final Widget Function(Map<String, dynamic> record, ApiService api) builder;

  const RecordLink({required this.label, required this.icon, this.action = 'read', required this.builder});
}

class CrudModule {
  final String title;
  final String crudEndpoint;
  final String listEndpoint;

  /// [listEndpoint] is a backend `/list/paged` endpoint (`PagedResponse`): the list
  /// appends `page`/`size` and loads more on scroll.
  final bool paged;
  final IconData icon;
  final List<FieldConfig> fields;

  /// Backend permission module (PermissionConstants): `<key>:read|create|update|delete`.
  final String permissionKey;

  /// Top-level keys of the backend IU DTO. Update payload = original record merged
  /// with form values, filtered to these keys — so fields not on the form are
  /// preserved (backend mappers overwrite missing fields with null).
  final List<String> payloadKeys;

  /// Dot-path; `a|b|c` = first non-empty wins.
  final String listTitleKey;
  final String listSubtitleKey;

  final RequestMode requestMode;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  /// Appended to `DELETE {crudEndpoint}/{id}` for a force delete fallback (forms → `/force`).
  final String? forceDeleteSuffix;

  /// Full record for editing; `{id}` / `{slug}` are filled from the list item.
  /// Needed where list endpoints return "simple" DTOs (e.g. posts list has seoInfo=null) —
  /// editing from list data would send those nulls back and wipe the fields.
  final String? detailEndpoint;

  /// Client-side list order like the admin tables: `a|b` dot-path, numbers numerically, text with foldTr.
  final String? sortKey;

  /// Boolean dot-path shown as an Aktif/Pasif badge.
  final String? statusKey;

  /// Image dot-path (`a|b`) shown as the list thumbnail.
  final String? thumbnailKey;

  /// Extra list line(s) (admin table columns: order, relation counts, SEO flags, …).
  final List<String> Function(Map<String, dynamic> item)? listMeta;

  final ListFilter? filter;

  final RecordLink? recordLink;

  const CrudModule({
    required this.title,
    required this.crudEndpoint,
    required this.listEndpoint,
    this.paged = false,
    required this.icon,
    required this.fields,
    required this.permissionKey,
    required this.payloadKeys,
    this.listTitleKey = 'title',
    this.listSubtitleKey = 'status',
    this.requestMode = RequestMode.json,
    this.canCreate = true,
    this.canEdit = true,
    this.canDelete = true,
    this.forceDeleteSuffix,
    this.detailEndpoint,
    this.sortKey,
    this.statusKey,
    this.thumbnailKey,
    this.listMeta,
    this.filter,
    this.recordLink,
  });
}
