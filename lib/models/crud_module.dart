import 'package:flutter/material.dart';

/// json: JSON editor (Map/List). file: picked file, sent as multipart part named [FieldConfig.key].
enum FieldType { text, longText, number, boolean, dropdown, json, file }

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

  /// JSON field: template chosen by the current value of another field
  /// (e.g. metadata template by `contentType`). Applied when the editor is empty
  /// or still shows the previous template.
  final String? templateFromField;
  final Map<String, Object>? templates;

  final String? hint;

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
    this.templateFromField,
    this.templates,
    this.hint,
  });
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
  });
}
