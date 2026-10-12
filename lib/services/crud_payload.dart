import 'dart:convert';

import '../models/crud_module.dart';

/// Pure helpers for the generic CRUD engine (unit-testable, no Flutter deps).

dynamic getPath(Map<String, dynamic>? item, String path) {
  dynamic current = item;
  for (final part in path.split('.')) {
    if (current is! Map) return null;
    current = current[part];
  }
  return current;
}

void setPath(Map<String, dynamic> target, String path, dynamic value) {
  final parts = path.split('.');
  var current = target;
  for (final part in parts.take(parts.length - 1)) {
    final next = current[part];
    if (next is Map<String, dynamic>) {
      current = next;
    } else {
      final created = <String, dynamic>{};
      current[part] = created;
      current = created;
    }
  }
  current[parts.last] = value;
}

Map<String, dynamic> deepCopy(Map<String, dynamic>? source) =>
    source == null ? <String, dynamic>{} : (jsonDecode(jsonEncode(source)) as Map<String, dynamic>);

/// `a|b|c` → first non-empty value as text.
String? resolveListText(Map<String, dynamic> item, String keySpec) {
  for (final key in keySpec.split('|')) {
    final value = getPath(item, key.trim());
    if (value != null && value.toString().trim().isNotEmpty) return value.toString();
  }
  return null;
}

/// Initial form values: from the record when editing, from field defaults when creating.
Map<String, dynamic> initialFormValues(CrudModule module, Map<String, dynamic>? original) {
  final values = <String, dynamic>{};
  for (final field in module.fields) {
    if (field.type == FieldType.file) continue;
    if (original != null) {
      values[field.key] = getPath(original, field.key);
    } else if (field.defaultValue != null) {
      values[field.key] = field.defaultValue;
    } else if (field.type == FieldType.json && field.templateFromField != null) {
      final selector = module.fields.where((f) => f.key == field.templateFromField).firstOrNull;
      final selected = selector?.defaultValue ?? selector?.options?.first;
      values[field.key] = field.templates?[selected];
    }
  }
  return values;
}

/// Request body = original record ⊕ form values, filtered to [CrudModule.payloadKeys].
/// Keeping the original values matters: backend `update*FromDto` mappers set every
/// missing property to null (e.g. post.seoInfo, content.metadata, form.schema).
Map<String, dynamic> buildPayload(
  CrudModule module,
  Map<String, dynamic>? original,
  Map<String, dynamic> formValues,
) {
  final merged = deepCopy(original);
  for (final field in module.fields) {
    if (field.type == FieldType.file) continue;
    if (!formValues.containsKey(field.key)) continue;
    var value = formValues[field.key];
    if (value is String && field.type != FieldType.longText && field.type != FieldType.json) {
      value = value.trim();
    }
    setPath(merged, field.key, value);
  }
  return {for (final key in module.payloadKeys) if (merged.containsKey(key)) key: merged[key]};
}

/// Multipart text fields (assets): drop nulls, stringify the rest.
Map<String, String> toMultipartFields(Map<String, dynamic> payload) => {
      for (final e in payload.entries)
        if (e.value != null && e.value.toString().isNotEmpty)
          e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };

/// Extracts the list from `data` (plain list or Spring page `{content: [...]}`).
List<Map<String, dynamic>> extractItems(dynamic data) {
  final list = data is List ? data : (data is Map ? (data['content'] ?? const []) : const []);
  return [for (final e in list as List) if (e is Map) Map<String, dynamic>.from(e)];
}

/// `/posts/{id}` → `/posts/42`; null when the module has no detail endpoint.
String? detailPath(CrudModule module, Map<String, dynamic> item) => module.detailEndpoint?.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => Uri.encodeComponent(item[m.group(1)]?.toString() ?? ''),
    );

/// `/assets/list/paged?sort=id,desc` + page/size → backend `PagedResponse` query.
String pagedEndpoint(String endpoint, int page, int size) {
  final uri = Uri.parse(endpoint);
  return uri.replace(queryParameters: {...uri.queryParameters, 'page': '$page', 'size': '$size'}).toString();
}

/// Backend `PagedResponse.last`; falls back to "fewer items than requested" when absent.
bool isLastPage(dynamic data, int size) =>
    data is! Map || (data['last'] as bool? ?? extractItems(data).length < size);

/// Record count of a list (`length`) or page (`totalElements`) response; null when unknown.
int? totalCount(dynamic data) {
  if (data is List) return data.length;
  if (data is Map) return (data['totalElements'] as num?)?.toInt() ?? extractItems(data).length;
  return null;
}
