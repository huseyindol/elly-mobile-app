import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../screens/forms/form_fields_screen.dart';
import '../screens/forms/form_preview_screen.dart';
import '../services/crud_payload.dart';
import '../services/form_schema.dart';
import 'confirm_dialog.dart';

/// Form builder for a form's `schema` (admin `forms/[id]`: layout, submit label, wizard steps, fields).
/// A [FormField]: the save-time checks of the admin (≥1 field; wizard: steps and every field on a step)
/// are its validator, so the screen's `validateGranularly` scrolls here.
///
/// Works on a copy of [initialValue]; [onChanged] gets the edited schema. Keys it doesn't know stay as
/// they are, and an untouched schema is never re-emitted (sent back byte for byte).
class FormSchemaEditor extends FormField<Map<String, dynamic>> {
  FormSchemaEditor({
    super.key,
    required Map<String, dynamic>? initialValue,
    required ValueChanged<Map<String, dynamic>> onChanged,

    /// Form title for the preview.
    String Function()? title,
  }) : super(
         initialValue: deepCopy(initialValue ?? newFormSchema()),
         validator: (schema) => schemaError(schema!),
         builder: (field) => _SchemaEditor(field: field, onChanged: onChanged, title: title),
       );
}

class _SchemaEditor extends StatefulWidget {
  final FormFieldState<Map<String, dynamic>> field;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String Function()? title;

  const _SchemaEditor({required this.field, required this.onChanged, required this.title});

  @override
  State<_SchemaEditor> createState() => _SchemaEditorState();
}

class _SchemaEditorState extends State<_SchemaEditor> {
  late final _submitLabel = TextEditingController(text: _config['submitLabel']?.toString() ?? '');

  /// Steps of a wizard switched to another layout: the admin keeps them in memory but doesn't send them.
  Object? _stashedSteps;

  Map<String, dynamic> get _schema => widget.field.value!;
  Map<String, dynamic> get _config => (_schema['config'] as Map?)?.cast<String, dynamic>() ?? {};
  String get _layout => schemaLayout(_schema);

  @override
  void dispose() {
    _submitLabel.dispose();
    super.dispose();
  }

  void _update(void Function(Map<String, dynamic> schema) change) {
    final next = deepCopy(_schema);
    change(next);
    widget.field.didChange(next);
    widget.onChanged(next);
  }

  void _setConfig(String key, Object? value) => _update((s) {
    final config = (s['config'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    s['config'] = {...config, key: value};
  });

  void _setLayout(String? layout) {
    if (layout == null || layout == _layout) return;
    _update((s) {
      s['config'] = {...(s['config'] as Map?)?.cast<String, dynamic>() ?? {}, 'layout': layout};
      if (layout != 'wizard' && s.containsKey('steps')) {
        _stashedSteps = s.remove('steps');
      } else if (layout == 'wizard' && _stashedSteps != null && !s.containsKey('steps')) {
        s['steps'] = _stashedSteps;
        _stashedSteps = null;
      }
    });
  }

  void _setSteps(List<Map<String, dynamic>> steps) => _update((s) => s['steps'] = steps);

  Future<void> _editStep([int? index]) async {
    final steps = schemaSteps(_schema);
    final step = index == null ? null : steps[index];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _StepDialog(step: step),
    );
    if (result == null) return;
    if (index == null) {
      _setSteps([...steps, result]);
    } else {
      _setSteps([...steps]..[index] = result);
    }
  }

  Future<void> _deleteStep(int index) async {
    final steps = schemaSteps(_schema);
    final step = steps[index];
    final count = schemaFields(_schema).where((f) => f['stepId'] == step['id']).length;
    final ok = await showConfirmDialog(
      context,
      title: 'Adım silinsin mi?',
      message:
          '"${step['title'] ?? ''}" adımı silinecek.'
          '${count == 0 ? '' : ' Bu adımdaki $count alan bir adıma yeniden atanmalı.'}',
      confirmLabel: 'Sil',
      destructive: true,
      confirmKey: const ValueKey('confirm_step_delete'),
    );
    if (ok) _setSteps([...steps]..removeAt(index));
  }

  void _openFields() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FormFieldsScreen(
          fields: schemaFields(_schema),
          steps: _layout == 'wizard' ? schemaSteps(_schema) : const [],
          onChanged: (fields) => _update((s) => s['fields'] = fields),
          onPreview: _openPreview,
        ),
      ),
    );
  }

  void _openPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FormPreviewScreen(title: widget.title?.call() ?? '', schema: _schema),
      ),
    );
  }

  Widget _layoutDropdown(ColorScheme scheme) {
    final layout = _layout;
    final items = {...formLayouts, if (!formLayouts.containsKey(layout)) layout: layout};
    return DropdownButtonFormField<String>(
      key: const ValueKey('schema_layout'),
      initialValue: layout,
      isExpanded: true,
      decoration: fieldDecoration(scheme, label: 'Düzen'),
      dropdownColor: scheme.surface,
      items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: _setLayout,
    );
  }

  Widget _steps(ThemeData theme) {
    final steps = schemaSteps(_schema);
    final muted = TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.65));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Adımlar (${steps.length})', style: theme.textTheme.titleSmall),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('add_step_button'),
              onPressed: _editStep,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adım Ekle'),
            ),
          ],
        ),
        if (steps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Henüz adım eklenmedi. Sihirbaz modu için en az bir adım ekleyin.', style: muted),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final next = [...steps];
              next.insert(to, next.removeAt(from)); // `to` is already the index after the removal
              _setSteps(next);
            },
            children: [
              for (final (i, step) in steps.indexed)
                ReorderableDelayedDragStartListener(
                  key: ObjectKey(step),
                  index: i,
                  child: ListTile(
                    key: ValueKey('step_$i'),
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                    title: Text('${step['title'] ?? ''}'),
                    subtitle: '${step['description'] ?? ''}'.isEmpty ? null : Text('${step['description']}'),
                    onTap: () => _editStep(i),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Adımı sil',
                          icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onErrorContainer),
                          onPressed: () => _deleteStep(i),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle_rounded, semanticLabel: 'Sürükleyerek sırala'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fields = schemaFields(_schema);
    final conditional = fields.where((f) => f['condition'] is Map).length;
    final error = widget.field.errorText;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: error == null ? scheme.onSurface.withValues(alpha: 0.1) : scheme.error),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _layoutDropdown(scheme),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('schema_submit_label'),
          controller: _submitLabel,
          decoration: fieldDecoration(scheme, label: 'Gönder Butonu Metni', hint: 'Gönder'),
          onChanged: (text) => _setConfig('submitLabel', text),
        ),
        if (_layout == 'wizard') ...[const SizedBox(height: 16), _steps(theme)],
        const SizedBox(height: 16),
        Material(
          color: scheme.surface.withValues(alpha: 0.7),
          shape: cardShape,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                key: const ValueKey('open_fields_button'),
                leading: const Icon(Icons.view_list_rounded),
                title: const Text('Form Alanları'),
                subtitle: Text(
                  fields.isEmpty
                      ? 'Henüz alan eklenmedi'
                      : '${fields.length} alan${conditional == 0 ? '' : ' · $conditional koşullu'}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openFields,
              ),
              if (fields.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    fields.map(fieldLabel).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('preview_button'),
                  onPressed: fields.isEmpty ? null : _openPreview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Önizle'),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12),
            child: Text(error, style: TextStyle(color: scheme.onErrorContainer, fontSize: 12)),
          ),
      ],
    );
  }
}

/// Admin `StepModal`: title (required) + description.
class _StepDialog extends StatefulWidget {
  final Map<String, dynamic>? step;
  const _StepDialog({this.step});

  @override
  State<_StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends State<_StepDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.step?['title']?.toString() ?? '');
  late final _description = TextEditingController(text: widget.step?['description']?.toString() ?? '');

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop({
      ...?widget.step,
      'id': widget.step?['id'] ?? newStepId(),
      'title': _title.text.trim(),
      'description': _description.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(widget.step == null ? 'Yeni Adım' : 'Adımı Düzenle'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('step_title'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Başlık *', hintText: 'Örn: Kişisel Bilgiler'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Adım başlığı zorunludur' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('step_description'),
              controller: _description,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        ElevatedButton(key: const ValueKey('step_save'), onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
