import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/crud_payload.dart';
import '../../services/form_schema.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/reorder_controls.dart';
import '../../widgets/save_bar.dart';
import '../../widgets/state_views.dart';

/// Form builder field list (admin "Form Alanları" card): add, edit, delete, drag to reorder.
/// Changes go straight to [onChanged] (the form screen saves them); back just returns.
/// Own screen so the ReorderableListView is the scroll view (drag auto-scrolls on long forms).
class FormFieldsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> fields;

  /// Wizard steps (empty for other layouts → no step picker).
  final List<Map<String, dynamic>> steps;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final VoidCallback? onPreview;

  const FormFieldsScreen({
    super.key,
    required this.fields,
    required this.steps,
    required this.onChanged,
    this.onPreview,
  });

  @override
  State<FormFieldsScreen> createState() => _FormFieldsScreenState();
}

class _FormFieldsScreenState extends State<FormFieldsScreen> {
  late final List<Map<String, dynamic>> _fields = [for (final f in widget.fields) deepCopy(f)];

  void _emit() {
    setState(() {});
    widget.onChanged([for (final f in _fields) deepCopy(f)]);
  }

  Future<void> _edit([int? index]) async {
    final field = index == null
        ? <String, dynamic>{
            'id': '',
            'type': 'text',
            'label': '',
            'required': false,
            'options': null,
            'validation': null,
            'condition': null,
          }
        : _fields[index];
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FieldEditScreen(
          field: field,
          otherFields: [
            for (final (i, f) in _fields.indexed)
              if (i != index) f,
          ],
          steps: widget.steps,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (index == null) {
      _fields.add(result);
    } else {
      renameConditionTarget(_fields, '${field['id'] ?? ''}', '${result['id']}');
      _fields[index] = result;
    }
    _emit();
  }

  Future<void> _delete(int index) async {
    final field = _fields[index];
    final dependents = dependentFields(_fields, '${field['id']}');
    final ok = await showConfirmDialog(
      context,
      title: 'Alan silinsin mi?',
      message:
          '"${fieldLabel(field)}" alanı formdan kaldırılacak.'
          '${dependents.isEmpty ? '' : ' Koşulu bu alana bağlı alanlar: ${dependents.map(fieldLabel).join(', ')}.'}',
      confirmLabel: 'Sil',
      destructive: true,
      confirmKey: const ValueKey('confirm_field_delete'),
    );
    if (!ok || !mounted) return;
    final before = [..._fields];
    _fields.removeAt(index);
    _commit(before, '"${fieldLabel(field)}" silindi');
  }

  /// [to] is the index after removing [from] (ReorderableListView.onReorderItem).
  void _reorder(int from, int to) {
    if (from == to) return;
    final before = [..._fields];
    _fields.insert(to, _fields.removeAt(from));
    _commit(before, '"${fieldLabel(_fields[to])}" taşındı');
  }

  /// Applies a delete / move and offers to take it back.
  void _commit(List<Map<String, dynamic>> before, String message) {
    _emit();
    showAppSnackBar(
      context,
      message,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Geri al',
        onPressed: () {
          if (!mounted) return;
          _fields
            ..clear()
            ..addAll(before);
          _emit();
        },
      ),
    );
  }

  String _subtitle(Map<String, dynamic> field) {
    final type = '${field['type'] ?? ''}';
    final options = field['options'];
    final step = widget.steps.where((s) => s['id'] == field['stepId']).firstOrNull;
    return [
      formFieldTypes[type] ?? type,
      '${field['id'] ?? ''}',
      if (step != null) '${step['title']}' else if (widget.steps.isNotEmpty) 'Adım atanmadı',
      if (options is List && options.isNotEmpty) '${options.length} seçenek',
      if (field['condition'] is Map) 'koşullu',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      title: 'Form Alanları',
      actions: [
        if (widget.onPreview != null)
          IconButton(
            tooltip: 'Önizle',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: _fields.isEmpty ? null : widget.onPreview,
          ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add_field_button'),
        onPressed: _edit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Alan Ekle'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Değişiklikler formu Kaydet\'te gönderilir.',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          Expanded(child: _list(scheme)),
        ],
      ),
    );
  }

  Widget _list(ColorScheme scheme) => _fields.isEmpty
      ? EmptyView(message: 'Henüz alan eklenmedi', actionLabel: 'İlk alanı ekle', onAction: _edit)
      : ReorderableListView(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          onReorderItem: _reorder,
          children: [
            for (final (i, field) in _fields.indexed)
              ReorderableDelayedDragStartListener(
                key: ObjectKey(field),
                index: i,
                child: ReorderableRow(
                  index: i,
                  count: _fields.length,
                  onMove: (delta) => _reorder(i, i + delta),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: scheme.surface.withValues(alpha: 0.7),
                      shape: _cardShape(scheme),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: ValueKey('field_row_$i'),
                        title: Text.rich(
                          TextSpan(
                            text: fieldLabel(field),
                            children: [
                              if (field['required'] == true)
                                TextSpan(
                                  text: ' *',
                                  semanticsLabel: ', zorunlu',
                                  style: TextStyle(color: scheme.onErrorContainer),
                                ),
                            ],
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _subtitle(field),
                          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                        ),
                        onTap: () => _edit(i),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('delete_field_$i'),
                              tooltip: 'Alanı sil',
                              icon: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
                              onPressed: () => _delete(i),
                            ),
                            ReorderControls(
                              index: i,
                              count: _fields.length,
                              onMove: (delta) => _reorder(i, i + delta),
                              menuKey: ValueKey('move_field_$i'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
}

/// Admin `FieldEditModal`: id, step (wizard), type, label, required, options, validation, condition.
/// Pops the field normalized like the admin (keys it doesn't know kept), or null when nothing changed.
class FieldEditScreen extends StatefulWidget {
  final Map<String, dynamic> field;
  final List<Map<String, dynamic>> otherFields;
  final List<Map<String, dynamic>> steps;

  const FieldEditScreen({super.key, required this.field, required this.otherFields, this.steps = const []});

  @override
  State<FieldEditScreen> createState() => _FieldEditScreenState();
}

class _OptionRow {
  final Map original;
  final TextEditingController label;
  final TextEditingController value;
  _OptionRow(this.original)
    : label = TextEditingController(text: '${original['label'] ?? ''}'),
      value = TextEditingController(text: original['value'] == null ? '' : jsString(original['value']));
}

class _FieldEditScreenState extends State<FieldEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, dynamic> _f = widget.field;
  late final _id = TextEditingController(text: '${_f['id'] ?? ''}');
  late final _label = TextEditingController(text: '${_f['label'] ?? ''}');
  late String _type = '${_f['type'] ?? 'text'}';
  late bool _required = _f['required'] == true;
  late String? _stepId = _f['stepId']?.toString();
  late final List<_OptionRow> _options = [
    for (final o in _f['options'] as List? ?? const [])
      if (o is Map) _OptionRow(o),
  ];
  late final Map? _validation = _f['validation'] is Map ? _f['validation'] as Map : null;
  late final _min = TextEditingController(text: _validation?['min'] == null ? '' : jsString(_validation!['min']));
  late final _max = TextEditingController(text: _validation?['max'] == null ? '' : jsString(_validation!['max']));
  late final _pattern = TextEditingController(text: '${_validation?['pattern'] ?? ''}');
  late final Map? _condition = _f['condition'] is Map ? _f['condition'] as Map : null;
  late String? _condField = _condition?['field']?.toString();
  late String _condOp = '${_condition?['operator'] ?? 'EQUALS'}';
  late final _condValue = TextEditingController(
    text: _condition?['value'] == null ? '' : jsString(_condition!['value']),
  );
  bool _dirty = false;

  bool get _isNew => '${_f['id'] ?? ''}'.isEmpty;
  bool get _hasOptions => optionFieldTypes.contains(_type);

  @override
  void dispose() {
    for (final c in [_id, _label, _min, _max, _pattern, _condValue]) {
      c.dispose();
    }
    for (final o in _options) {
      o.label.dispose();
      o.value.dispose();
    }
    super.dispose();
  }

  void _change(VoidCallback fn) => setState(() {
    fn();
    _dirty = true;
  });

  /// Admin type switch: entering an option type starts an option list, leaving one drops it.
  void _setType(String? type) {
    if (type == null) return;
    _change(() {
      if (optionFieldTypes.contains(_type) && !optionFieldTypes.contains(type)) {
        for (final o in _options) {
          o.label.dispose();
          o.value.dispose();
        }
        _options.clear();
      }
      _type = type;
    });
  }

  /// Text that still shows the original value keeps the original (typed) value, e.g. `value: 18`.
  static Object? _keep(Object? original, String text) =>
      original != null && jsString(original) == text ? original : text;

  Map<String, dynamic> _result() {
    final out = Map<String, dynamic>.of(_f)
      ..['id'] = _id.text
      ..['type'] = _type
      ..['label'] = _label.text.trim()
      ..['required'] = _required
      ..['stepId'] = _stepId;
    if (_hasOptions) {
      out['options'] = [
        for (final o in _options)
          {
            ...o.original.cast<String, dynamic>(),
            'label': o.label.text.trim(),
            'value': _keep(o.original['value'], o.value.text.trim()),
          },
      ];
    }
    if (!noValidationFieldTypes.contains(_type)) {
      out['validation'] = {
        ...?_validation?.cast<String, dynamic>(),
        'min': int.tryParse(_min.text.trim()),
        'max': int.tryParse(_max.text.trim()),
        'pattern': _pattern.text.isEmpty ? null : _pattern.text,
      };
    }
    out['condition'] = _condField == null
        ? null
        : {
            ...?_condition?.cast<String, dynamic>(),
            'field': _condField,
            'operator': _condOp,
            'value': _keep(_condition?['value'], _condValue.text),
          };
    return normalizeField(out);
  }

  void _save() {
    // An untouched existing field stays as it is; a new one is always checked (an empty id/label must not pass).
    if (!_dirty && !_isNew) {
      Navigator.of(context).pop();
      return;
    }
    final invalid = _formKey.currentState?.validateGranularly() ?? const {};
    if (invalid.isNotEmpty) {
      reportInvalidFields(context, invalid, labelOf: _labelOf);
      return;
    }
    _dirty = false;
    ScaffoldMessenger.of(context).clearSnackBars();
    Navigator.of(context).pop(_result());
  }

  static String? _labelOf(FormFieldState<Object?> state) {
    final key = state.widget.key;
    final name = key is ValueKey<String> ? key.value : '';
    return switch (name) {
      'field_id' => 'Alan ID',
      'field_label' => 'Etiket',
      'options_section' => 'Seçenekler',
      'validation_min' => 'Min',
      'validation_max' => 'Max',
      'validation_pattern' => 'Pattern',
      _ when name.startsWith('option_label_') => 'Seçenek etiketi',
      _ when name.startsWith('option_value_') => 'Seçenek değeri',
      _ => null,
    };
  }

  Future<void> _confirmLeave() async {
    if (await confirmLeaveForm(context) && mounted) Navigator.of(context).pop();
  }

  String? _validateId(String? raw) {
    final id = raw ?? '';
    if (id.trim().isEmpty) return 'Alan ID zorunludur';
    if (!fieldIdPattern.hasMatch(id)) return 'ID sadece harf, rakam ve alt çizgi içerebilir';
    if (widget.otherFields.any((f) => f['id'] == id)) return 'Bu ID zaten kullanılıyor';
    return null;
  }

  String? _validateInt(String? raw) {
    final text = raw?.trim() ?? '';
    return text.isEmpty || int.tryParse(text) != null ? null : 'Tam sayı girin';
  }

  /// min > max can never be satisfied on the site.
  String? _validateMin(String? raw) {
    final min = int.tryParse(raw?.trim() ?? '');
    final max = int.tryParse(_max.text.trim());
    return _validateInt(raw) ?? (min != null && max != null && min > max ? "Min, Max'ten büyük olamaz" : null);
  }

  String? _validatePattern(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      RegExp(raw);
      return null;
    } on FormatException {
      return 'Geçersiz RegEx';
    }
  }

  Widget _gap(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 16), child: child);

  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T? value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
    String? helper,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      isExpanded: true,
      decoration: fieldDecoration(scheme, label: label, helper: helper),
      dropdownColor: scheme.surface,
      items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
      onChanged: onChanged,
    );
  }

  Widget _optionsSection(ColorScheme scheme) {
    return FormField<void>(
      key: const ValueKey('options_section'),
      validator: (_) => _options.any((o) => o.label.text.trim().isNotEmpty && o.value.text.trim().isNotEmpty)
          ? null
          : 'Seçim kutusu ve radyo buton için en az bir seçenek gereklidir',
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: const Text.rich(
                    TextSpan(
                      text: 'Seçenekler',
                      children: [TextSpan(text: ' *', semanticsLabel: ', zorunlu')],
                    ),
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('add_option_button'),
                onPressed: () => _change(() => _options.add(_OptionRow({'label': '', 'value': ''}))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Seçenek Ekle'),
              ),
            ],
          ),
          for (final (i, o) in _options.indexed)
            Padding(key: ObjectKey(o), padding: const EdgeInsets.only(bottom: 8), child: _optionRow(i, o, scheme)),
          Text(
            state.errorText ?? 'Etiket: kullanıcıya gösterilir. Değer: API\'ye gönderilir.',
            style: TextStyle(
              fontSize: 12,
              color: state.hasError ? scheme.onErrorContainer : scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// Label + value side by side; stacked on narrow screens / large text so neither gets squeezed.
  Widget _optionRow(int i, _OptionRow o, ColorScheme scheme) {
    final label = TextFormField(
      key: ValueKey('option_label_$i'),
      controller: o.label,
      decoration: fieldDecoration(scheme, label: 'Etiket'),
      validator: (v) => (v ?? '').trim().isEmpty && o.value.text.trim().isNotEmpty ? 'Etiket girin' : null,
    );
    final value = TextFormField(
      key: ValueKey('option_value_$i'),
      controller: o.value,
      style: const TextStyle(fontFamily: 'monospace'),
      decoration: fieldDecoration(scheme, label: 'Değer'),
      validator: (v) => (v ?? '').trim().isEmpty && o.label.text.trim().isNotEmpty ? 'Değer girin' : null,
    );
    final remove = IconButton(
      tooltip: 'Seçeneği sil',
      icon: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      onPressed: () => _change(() {
        _options.removeAt(i);
        o.label.dispose();
        o.value.dispose();
      }),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 360;
        if (!narrow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: label),
              const SizedBox(width: 8),
              Expanded(child: value),
              remove,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: [label, const SizedBox(height: 8), value])),
            remove,
          ],
        );
      },
    );
  }

  /// Hint for the condition value: the watched field's option values (what the renderer compares).
  String? _conditionHint() {
    final target = widget.otherFields.where((f) => f['id'] == _condField).firstOrNull;
    if (target == null) return null;
    if (target['type'] == 'checkbox') return 'Onay kutusu değeri: true / false';
    final options = target['options'];
    if (options is List && options.isNotEmpty) {
      return 'Seçenek değerleri: ${options.map((o) => o is Map ? jsString(o['value']) : '').join(', ')}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final types = {...formFieldTypes, if (!formFieldTypes.containsKey(_type)) _type: _type};
    final hasStep = widget.steps.isNotEmpty;
    final stepItems = <String?, String>{
      null: '-- Adım Seçin --',
      for (final s in widget.steps) s['id']?.toString(): '${s['title'] ?? ''}',
      if (_stepId != null && !widget.steps.any((s) => s['id']?.toString() == _stepId)) _stepId: 'Bilinmeyen adım',
    };
    final condItems = <String?, String>{
      null: 'Koşul Yok',
      for (final f in widget.otherFields)
        if ('${f['id'] ?? ''}'.isNotEmpty)
          '${f['id']}': '${f['label']}'.trim().isEmpty ? '${f['id']}' : '${f['label']}',
      if (_condField != null && !widget.otherFields.any((f) => f['id'] == _condField))
        _condField: 'Bulunamayan alan ($_condField)',
    };
    final operators = {...conditionOperators, if (!conditionOperators.containsKey(_condOp)) _condOp: _condOp};
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: AppScaffold(
        title: _isNew ? 'Yeni Alan' : 'Alan Düzenle',
        bottomNavigationBar: SaveBar(
          onPressed: _save,
          label: 'Uygula',
          buttonKey: const ValueKey('field_apply_button'),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Form(
                  key: _formKey,
                  onChanged: () {
                    if (!_dirty) setState(() => _dirty = true);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _gap(
                        TextFormField(
                          key: const ValueKey('field_id'),
                          controller: _id,
                          style: const TextStyle(fontFamily: 'monospace'),
                          autocorrect: false,
                          decoration: fieldDecoration(
                            scheme,
                            label: 'Alan ID *',
                            hint: 'ornek: name, email, rating',
                            helper: 'Form gönderiminde payload key olarak kullanılır',
                          ),
                          validator: _validateId,
                        ),
                      ),
                      if (hasStep)
                        _gap(
                          _dropdown<String?>(
                            key: const ValueKey('field_step'),
                            label: 'Adım',
                            value: _stepId,
                            items: stepItems,
                            onChanged: (v) => _change(() => _stepId = v),
                          ),
                        ),
                      _gap(
                        _dropdown<String>(
                          key: const ValueKey('field_type'),
                          label: 'Alan Tipi *',
                          value: _type,
                          items: types,
                          onChanged: _setType,
                        ),
                      ),
                      _gap(
                        TextFormField(
                          key: const ValueKey('field_label'),
                          controller: _label,
                          decoration: fieldDecoration(scheme, label: 'Etiket *', hint: 'Beğeni Derecesi'),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Etiket zorunludur' : null,
                        ),
                      ),
                      _gap(
                        SwitchListTile(
                          key: const ValueKey('field_required'),
                          title: const Text('Zorunlu Alan'),
                          value: _required,
                          onChanged: (v) => _change(() => _required = v),
                          activeThumbColor: scheme.primary,
                        ),
                      ),
                      if (_hasOptions) _gap(_optionsSection(scheme)),
                      if (!noValidationFieldTypes.contains(_type)) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Semantics(header: true, child: const Text('Validasyon')),
                        ),
                        _gap(
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  key: const ValueKey('validation_min'),
                                  controller: _min,
                                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                                  decoration: fieldDecoration(scheme, label: 'Min'),
                                  validator: _validateMin,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  key: const ValueKey('validation_max'),
                                  controller: _max,
                                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                                  decoration: fieldDecoration(scheme, label: 'Max'),
                                  validator: _validateInt,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _gap(
                          TextFormField(
                            key: const ValueKey('validation_pattern'),
                            controller: _pattern,
                            autocorrect: false,
                            style: const TextStyle(fontFamily: 'monospace'),
                            decoration: fieldDecoration(scheme, label: 'Pattern (RegEx)', hint: r'^[a-zA-Z]+$'),
                            validator: _validatePattern,
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(header: true, child: const Text('Koşullu Görünürlük')),
                      ),
                      _gap(
                        _dropdown<String?>(
                          key: const ValueKey('condition_field'),
                          label: 'Bu alan görünsün, eğer',
                          value: _condField,
                          items: condItems,
                          onChanged: (v) => _change(() => _condField = v),
                        ),
                      ),
                      if (_condField != null) ...[
                        _gap(
                          _dropdown<String>(
                            key: const ValueKey('condition_operator'),
                            label: 'Operatör',
                            value: _condOp,
                            items: operators,
                            onChanged: (v) => _change(() => _condOp = v ?? 'EQUALS'),
                          ),
                        ),
                        _gap(
                          TextFormField(
                            key: const ValueKey('condition_value'),
                            controller: _condValue,
                            decoration: fieldDecoration(scheme, label: 'Değer', helper: _conditionHint()),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ShapeBorder _cardShape(ColorScheme scheme) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(16),
  side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.05)),
);
