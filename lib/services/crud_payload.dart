import 'dart:convert';

import '../models/crud_module.dart';
import 'text_format.dart';

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

/// Admin table order for [CrudModule.sortKey]: numbers numerically (missing = 0), otherwise
/// Turkish-folded text; ties by id so the order is stable.
int compareByKey(Map<String, dynamic> a, Map<String, dynamic> b, String keySpec) {
  final x = resolveListText(a, keySpec) ?? '';
  final y = resolveListText(b, keySpec) ?? '';
  final nx = num.tryParse(x);
  final ny = num.tryParse(y);
  final byKey = nx != null || ny != null ? (nx ?? 0).compareTo(ny ?? 0) : foldTr(x).compareTo(foldTr(y));
  if (byKey != 0) return byKey;
  return (num.tryParse('${a['id']}') ?? 0).compareTo(num.tryParse('${b['id']}') ?? 0);
}

/// Initial form values: from the record when editing, from field defaults when creating.
Map<String, dynamic> initialFormValues(CrudModule module, Map<String, dynamic>? original) {
  final values = <String, dynamic>{};
  for (final field in module.fields) {
    if (field.type == FieldType.file) continue;
    if (field.type == FieldType.relation) {
      values[field.key] = original == null
          ? <Object>[]
          : relationIds(getPath(original, field.relationSource ?? field.key));
    } else if (original != null) {
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

/// Ids of a relation value: related objects (`{id: …}`) or plain ids; anything else → empty.
List<Object> relationIds(dynamic value) => [
  if (value is List)
    for (final e in value)
      if ((e is Map ? e['id'] : e) case final Object id) id,
];

/// [FieldConfig.visibleWhen] against the current form values.
bool isFieldVisible(FieldConfig field, Map<String, dynamic> values) =>
    field.visibleWhen?.entries.every((e) => values[e.key] == e.value) ?? true;

/// Request body = original record ⊕ form values, filtered to [CrudModule.payloadKeys].
/// Keeping the original values matters: backend `update*FromDto` mappers set every
/// missing property to null (e.g. post.seoInfo, content.metadata, form.schema).
///
/// Relations (backend semantics, verified in the services): pages `componentIds` null = untouched
/// → sent only when changed; components/widgets `*Ids` null = CLEAR → always sent (current ids, from
/// the detail record when the user did not touch them; `[]` when hidden by the type). Relation keys
/// without a form field (components `pageIds`) go back from the record unchanged.
Map<String, dynamic> buildPayload(CrudModule module, Map<String, dynamic>? original, Map<String, dynamic> formValues) {
  final merged = deepCopy(original);
  final initial = initialFormValues(module, original);
  for (final field in module.fields) {
    if (field.type == FieldType.file) continue;
    if (!formValues.containsKey(field.key)) continue;
    if (!isFieldVisible(field, formValues)) {
      if (field.type == FieldType.relation) setPath(merged, field.key, <Object>[]);
      continue;
    }
    var value = formValues[field.key];
    if (field.type == FieldType.relation) {
      value = relationIds(value);
      final unchanged = _sameIds(value as List<Object>, initial[field.key] as List<Object>);
      if (original != null && field.relationKeepsOnNull && unchanged) continue;
    } else if (value is String &&
        !const {FieldType.longText, FieldType.json, FieldType.richText}.contains(field.type)) {
      value = value.trim();
      if (field.type == FieldType.date && value == '') value = null;
    }
    setPath(merged, field.key, value);
  }
  return {
    for (final key in module.payloadKeys)
      if (merged.containsKey(key)) key: merged[key],
  };
}

bool _sameIds(List<Object> a, List<Object> b) => a.length == b.length && a.toSet().containsAll(b);

/// Multipart text fields (assets): drop nulls, stringify the rest.
Map<String, String> toMultipartFields(Map<String, dynamic> payload) => {
  for (final e in payload.entries)
    if (e.value != null && e.value.toString().isNotEmpty)
      e.key: e.value is String ? e.value as String : jsonEncode(e.value),
};

/// Extracts the list from `data` (plain list or Spring page `{content: [...]}`).
List<Map<String, dynamic>> extractItems(dynamic data) {
  final list = data is List ? data : (data is Map ? (data['content'] ?? const []) : const []);
  return [
    for (final e in list as List)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

/// `/posts/{id}` → `/posts/42`; null when the module has no detail endpoint.
String? detailPath(CrudModule module, Map<String, dynamic> item) => module.detailEndpoint?.replaceAllMapped(
  RegExp(r'\{(\w+)\}'),
  (m) => Uri.encodeComponent(item[m.group(1)]?.toString() ?? ''),
);

/// `/assets/list/paged?sort=id,desc` + page/size → backend `PagedResponse` query.
String pagedEndpoint(String endpoint, int page, int size) {
  final uri = Uri.parse(endpoint);
  // queryParametersAll: Spring accepts repeated `sort` params; queryParameters would keep only the last.
  return uri.replace(queryParameters: {...uri.queryParametersAll, 'page': '$page', 'size': '$size'}).toString();
}

/// Backend `PagedResponse.last`; falls back to "fewer items than requested" when absent.
bool isLastPage(dynamic data, int size) => data is! Map || (data['last'] as bool? ?? extractItems(data).length < size);

/// Record count of a list (`length`) or page (`totalElements`) response; null when unknown.
int? totalCount(dynamic data) {
  if (data is List) return data.length;
  if (data is Map) return (data['totalElements'] as num?)?.toInt() ?? extractItems(data).length;
  return null;
}
