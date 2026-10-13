import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/form_schema.dart';
import '../../widgets/app_scaffold.dart';

/// Simple form preview: inputs by field type with live conditional visibility (tenant evaluator rules),
/// wizard steps as sections. "Gönder" shows the payload the site would send — nothing is submitted.
/// shortcut: no per-field validation and no step paging (the tenant site does both).
class FormPreviewScreen extends StatefulWidget {
  final String title;
  final Map<String, dynamic> schema;

  const FormPreviewScreen({super.key, required this.title, required this.schema});

  @override
  State<FormPreviewScreen> createState() => _FormPreviewScreenState();
}

class _FormPreviewScreenState extends State<FormPreviewScreen> {
  late final List<Map<String, dynamic>> _fields = schemaFields(widget.schema);

  /// Tenant defaults (`generateDefaultValues`): checkbox false, number undefined, others ''.
  late final Map<String, dynamic> _values = {
    for (final f in _fields)
      '${f['id']}': switch (f['type']) {
        'checkbox' => false,
        'number' => null,
        _ => '',
      },
  };

  void _set(Map<String, dynamic> field, Object? value) => setState(() => _values['${field['id']}'] = value);

  /// value → label; first entry per distinct non-empty value (a dropdown needs unique values).
  Map<String, String> _options(Map<String, dynamic> field) {
    final out = <String, String>{};
    for (final o in field['options'] as List? ?? const []) {
      final value = o is Map ? jsString(o['value'] ?? '') : '';
      if (value.isNotEmpty) out.putIfAbsent(value, () => '${(o as Map)['label'] ?? ''}');
    }
    return out;
  }

  Future<void> _pickDate(Map<String, dynamic> field) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse('${_values[field['id']]}') ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    String two(int n) => n.toString().padLeft(2, '0');
    _set(field, '${picked.year}-${two(picked.month)}-${two(picked.day)}');
  }

  Widget _input(Map<String, dynamic> field, ColorScheme scheme) {
    final id = '${field['id']}';
    final label = '${fieldLabel(field)}${field['required'] == true ? ' *' : ''}';
    final value = _values[id];
    final decoration = fieldDecoration(scheme, label: label);
    switch (field['type']) {
      case 'checkbox':
        return CheckboxListTile(
          key: ValueKey('preview_$id'),
          title: decoration.label ?? Text(label),
          value: value == true,
          onChanged: (v) => _set(field, v ?? false),
        );
      case 'select':
        return DropdownButtonFormField<String>(
          key: ValueKey('preview_$id'),
          initialValue: '$value',
          isExpanded: true,
          decoration: decoration,
          dropdownColor: scheme.surface,
          items: [
            const DropdownMenuItem(value: '', child: Text('Seçiniz...')),
            for (final o in _options(field).entries) DropdownMenuItem(value: o.key, child: Text(o.value)),
          ],
          onChanged: (v) => _set(field, v ?? ''),
        );
      case 'radio':
        return InputDecorator(
          key: ValueKey('preview_$id'),
          decoration: decoration,
          child: RadioGroup<String>(
            groupValue: '$value',
            onChanged: (v) => _set(field, v ?? ''),
            child: Column(
              children: [
                for (final o in _options(field).entries)
                  RadioListTile<String>(value: o.key, title: Text(o.value), dense: true),
              ],
            ),
          ),
        );
      case 'multi_checkbox':
        final selected = value is List ? value.cast<String>() : const <String>[];
        return InputDecorator(
          key: ValueKey('preview_$id'),
          decoration: decoration,
          child: Column(
            children: [
              for (final o in _options(field).entries)
                CheckboxListTile(
                  dense: true,
                  title: Text(o.value),
                  value: selected.contains(o.key),
                  onChanged: (v) => _set(field, [
                    for (final s in selected)
                      if (s != o.key) s,
                    if (v == true) o.key,
                  ]),
                ),
            ],
          ),
        );
      case 'date':
        return InputDecorator(
          key: ValueKey('preview_$id'),
          decoration: decoration,
          child: Row(
            children: [
              Expanded(child: Text('$value'.isEmpty ? 'Tarih seçilmedi' : '$value')),
              TextButton(onPressed: () => _pickDate(field), child: const Text('Seç')),
            ],
          ),
        );
      default:
        final type = field['type'];
        return TextFormField(
          key: ValueKey('preview_$id'),
          initialValue: value == null ? '' : jsString(value), // kept while hidden by a condition, like the site
          decoration: decoration,
          minLines: type == 'textarea' ? 4 : 1,
          maxLines: type == 'textarea' ? 6 : 1,
          keyboardType: switch (type) {
            'number' => const TextInputType.numberWithOptions(decimal: true, signed: true),
            'email' => TextInputType.emailAddress,
            'phone' => TextInputType.phone,
            'url' => TextInputType.url,
            _ => TextInputType.text,
          },
          // Number inputs hold numbers (react-hook-form `valueAsNumber`); empty → undefined.
          onChanged: (text) => _set(field, type == 'number' ? num.tryParse(text.trim()) : text),
        );
    }
  }

  void _submit() {
    final payload = visiblePayload(_fields, _values);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('Gönderilecek veri'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Önizleme: hiçbir şey gönderilmez. Gizli alanlar yanıtta yer almaz.'),
              const SizedBox(height: 12),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(payload),
                key: const ValueKey('preview_payload'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Kapat'))],
      ),
    );
  }

  Widget _header(String title, String? description, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: theme.textTheme.titleMedium)),
        if (description != null && description.isNotEmpty)
          Text(description, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.65))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = schemaLayout(widget.schema) == 'wizard' ? schemaSteps(widget.schema) : const <Map<String, dynamic>>[];
    Iterable<Widget> fieldsOf(Iterable<Map<String, dynamic>> fields) => [
      for (final f in fields)
        if (isFormFieldVisible(f, _values))
          Padding(padding: const EdgeInsets.only(bottom: 16), child: _input(f, scheme)),
    ];
    final stepIds = {for (final s in steps) s['id']};
    final unassigned = steps.isEmpty ? 0 : _fields.where((f) => !stepIds.contains(f['stepId'])).length;
    final submitLabel = '${(widget.schema['config'] as Map?)?['submitLabel'] ?? ''}';
    return AppScaffold(
      title: 'Önizleme',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        children: [
          if (widget.title.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(widget.title, style: theme.textTheme.titleLarge),
            ),
          if (steps.isEmpty)
            ...fieldsOf(_fields)
          else ...[
            for (final (i, step) in steps.indexed) ...[
              _header('${i + 1}. ${step['title'] ?? ''}', step['description']?.toString(), theme),
              ...fieldsOf(_fields.where((f) => f['stepId'] == step['id'])),
            ],
            if (unassigned > 0)
              Text(
                '$unassigned alan bir adıma atanmamış; sitede görünmez.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
          ],
          const SizedBox(height: 8),
          ElevatedButton(
            key: const ValueKey('preview_submit'),
            onPressed: _submit,
            child: Text(submitLabel.isEmpty ? 'Gönder' : submitLabel),
          ),
        ],
      ),
    );
  }
}
