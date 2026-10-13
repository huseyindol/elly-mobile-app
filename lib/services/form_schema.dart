/// Pure form-builder helpers (no Flutter deps, unit-tested).
///
/// The form schema stays a raw JSON map (`{config, fields, steps}`, backend `FormSchema`): the builder
/// edits it in place, so keys and field types it doesn't know survive a save untouched. Rules mirror
/// elly-admin `forms/[id]/page.tsx` (field modal + save checks) and the tenant renderer.
library;

import 'dart:convert';
import 'dart:math';

/// Admin `FIELD_TYPES` (same order and labels).
const formFieldTypes = <String, String>{
  'text': 'Metin',
  'email': 'E-posta',
  'number': 'Sayı',
  'textarea': 'Uzun Metin',
  'select': 'Seçim Kutusu',
  'radio': 'Radyo Buton',
  'checkbox': 'Onay Kutusu',
  'date': 'Tarih',
  'phone': 'Telefon',
  'url': 'URL',
  'multi_checkbox': 'Çoklu Seçim (Checkbox Group)',
};

/// Field types that carry `options`.
const optionFieldTypes = {'select', 'radio', 'multi_checkbox'};

/// Types without the min/max/pattern block in the admin modal.
const noValidationFieldTypes = {'checkbox', 'select', 'radio'};

const formLayouts = <String, String>{
  'vertical': 'Dikey (Tek Sayfa)',
  'single': 'Tek Sayfa',
  'wizard': 'Sihirbaz (Çok Adımlı)',
};

const conditionOperators = <String, String>{'EQUALS': 'Eşit', 'NOT_EQUALS': 'Eşit Değil', 'GT': 'Büyük', 'LT': 'Küçük'};

/// Admin field id rule (also the submission payload key).
final fieldIdPattern = RegExp(r'^[a-zA-Z_]\w*$');

/// New-form schema (admin `NewFormPage` defaults).
Map<String, dynamic> newFormSchema() => {
  'config': {'layout': 'vertical', 'submitLabel': 'Gönder'},
  'fields': <Map<String, dynamic>>[],
};

/// `schema.fields` as editable maps (missing / malformed → empty).
List<Map<String, dynamic>> schemaFields(Map<String, dynamic> schema) => [
  for (final f in schema['fields'] as List? ?? const [])
    if (f is Map<String, dynamic>) f,
];

List<Map<String, dynamic>> schemaSteps(Map<String, dynamic> schema) => [
  for (final s in schema['steps'] as List? ?? const [])
    if (s is Map<String, dynamic>) s,
];

String schemaLayout(Map<String, dynamic> schema) => (schema['config'] as Map?)?['layout']?.toString() ?? 'vertical';

String fieldLabel(Map<String, dynamic> field) {
  final label = field['label']?.toString() ?? '';
  return label.trim().isEmpty ? 'Başlıksız Alan' : label;
}

// ---------------------------------------------------------------------------------------------------
// Condition evaluator — port of admin `_utils/condition-evaluator.ts` (identical to the tenant's).
// Both sides are compared as JavaScript `String(...)`, GT/LT as JavaScript `Number(...)`.
// ---------------------------------------------------------------------------------------------------

/// JavaScript `String(value)` for JSON-like values.
String jsString(Object? value) => switch (value) {
  null => 'null',
  String s => s,
  bool b => '$b',
  int i => '$i',
  double d when d.isNaN => 'NaN',
  double d when d.isInfinite => d > 0 ? 'Infinity' : '-Infinity',
  double d when d == d.truncateToDouble() && d.abs() < 1e21 => '${d.toInt()}',
  double d => '$d',
  List l => l.map((e) => e == null ? '' : jsString(e)).join(','),
  Map _ => '[object Object]',
  _ => value.toString(),
};

final _jsDecimal = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');
final _jsRadix = RegExp(r'^0([xXoObB])([0-9a-fA-F]+)$');

/// JavaScript `Number(string)`: trimmed, empty → 0, decimal / 0x / 0o / 0b / ±Infinity, else NaN.
double jsNumber(String text) {
  final s = text.trim();
  if (s.isEmpty) return 0;
  if (s == 'Infinity' || s == '+Infinity') return double.infinity;
  if (s == '-Infinity') return double.negativeInfinity;
  if (_jsDecimal.hasMatch(s)) return double.parse(s);
  final radix = _jsRadix.firstMatch(s);
  if (radix != null) {
    final base = switch (radix[1]!.toLowerCase()) {
      'x' => 16,
      'o' => 8,
      _ => 2,
    };
    final n = BigInt.tryParse(radix[2]!, radix: base);
    if (n != null) return n.toDouble();
  }
  return double.nan;
}

bool evaluateCondition(Object? operator, Object? currentValue, Object? expectedValue) {
  final current = currentValue == null ? '' : jsString(currentValue);
  final expected = expectedValue == null ? '' : jsString(expectedValue);
  switch (operator) {
    case 'EQUALS':
      return current == expected;
    case 'NOT_EQUALS':
      return current != expected;
    case 'GT':
    case 'LT':
      final a = jsNumber(current);
      final b = jsNumber(expected);
      if (a.isNaN || b.isNaN) return false;
      return operator == 'GT' ? a > b : a < b;
    default:
      return true;
  }
}

/// Admin/tenant `isFieldVisible`: no condition → visible.
bool isFormFieldVisible(Map<String, dynamic> field, Map<String, dynamic> values) {
  final condition = field['condition'];
  if (condition is! Map) return true;
  return evaluateCondition(condition['operator'], values['${condition['field']}'], condition['value']);
}

/// Tenant submit: only visible fields go into the payload (an empty number is `undefined` there → omitted).
Map<String, dynamic> visiblePayload(List<Map<String, dynamic>> fields, Map<String, dynamic> values) => {
  for (final field in fields)
    if (isFormFieldVisible(field, values) && values[field['id']] != null) '${field['id']}': values[field['id']],
};

// ---------------------------------------------------------------------------------------------------
// Builder rules (admin FieldEditModal.handleSave + onSubmit).
// ---------------------------------------------------------------------------------------------------

/// Field as the admin modal saves it: options only for option types (blank rows dropped, none → null),
/// an all-empty validation → null, a condition without a field → null, empty stepId → absent.
/// Every other key of [field] is kept.
Map<String, dynamic> normalizeField(Map<String, dynamic> field) {
  final out = Map<String, dynamic>.of(field);
  if (optionFieldTypes.contains(out['type'])) {
    final options = [
      for (final o in out['options'] as List? ?? const [])
        if (o is Map && '${o['label'] ?? ''}'.trim().isNotEmpty && '${o['value'] ?? ''}'.trim().isNotEmpty) o,
    ];
    out['options'] = options.isEmpty ? null : options;
  } else {
    out['options'] = null;
  }
  final validation = out['validation'];
  if (validation is Map &&
      validation['min'] == null &&
      validation['max'] == null &&
      '${validation['pattern'] ?? ''}'.isEmpty) {
    out['validation'] = null;
  }
  final condition = out['condition'];
  if (condition is Map && '${condition['field'] ?? ''}'.isEmpty) out['condition'] = null;
  if ('${out['stepId'] ?? ''}'.isEmpty) out.remove('stepId');
  return out;
}

/// After renaming a field, conditions of the other fields follow the new id (the admin leaves them
/// pointing at the old id, which silently hides the field forever).
void renameConditionTarget(List<Map<String, dynamic>> fields, String oldId, String newId) {
  if (oldId.isEmpty || oldId == newId) return;
  for (final field in fields) {
    final condition = field['condition'];
    if (condition is Map && condition['field'] == oldId) {
      field['condition'] = {...condition, 'field': newId};
    }
  }
}

/// Fields whose condition watches [fieldId].
List<Map<String, dynamic>> dependentFields(List<Map<String, dynamic>> fields, String fieldId) => [
  for (final f in fields)
    if (f['condition'] is Map && (f['condition'] as Map)['field'] == fieldId) f,
];

/// Save-time schema check (admin onSubmit). Wizard: every field needs a step that exists.
String? schemaError(Map<String, dynamic> schema) {
  final fields = schemaFields(schema);
  if (fields.isEmpty) return 'En az bir alan eklemelisiniz';
  if (schemaLayout(schema) != 'wizard') return null;
  final steps = schemaSteps(schema);
  if (steps.isEmpty) return 'Sihirbaz modunda en az bir adım eklemelisiniz';
  final stepIds = {for (final s in steps) s['id']};
  final unassigned = [
    for (final f in fields)
      if (!stepIds.contains(f['stepId'])) fieldLabel(f),
  ];
  if (unassigned.isNotEmpty) {
    return 'Sihirbaz modunda tüm alanlar bir adıma atanmalı. Atanmamış alanlar: ${unassigned.join(', ')}';
  }
  return null;
}

/// Step id like the admin (`uuid` v4).
String newStepId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

// ---------------------------------------------------------------------------------------------------
// Submissions — admin `formatPayloadValue`.
// ---------------------------------------------------------------------------------------------------

/// Payload value as text: empty → "—", option values → option labels, booleans → Evet/Hayır.
String formatPayloadValue(Object? value, Map<String, dynamic>? field) {
  if (value == null || value == '') return '—';
  final options = field?['options'] is List ? field!['options'] as List : null;
  String? labelOf(Object? v) {
    for (final o in options ?? const []) {
      if (o is Map && jsString(o['value']) == jsString(v)) return o['label']?.toString();
    }
    return null;
  }

  if (value is List) {
    if (value.isEmpty) return '—';
    return value.map((v) => labelOf(v) ?? jsString(v)).join(', ');
  }
  final label = labelOf(value);
  if (label != null) return label;
  if (value is bool) return value ? 'Evet' : 'Hayır';
  if (value is Map) return jsonEncode(value); // not produced by the renderer; readable instead of [object Object]
  return jsString(value);
}
