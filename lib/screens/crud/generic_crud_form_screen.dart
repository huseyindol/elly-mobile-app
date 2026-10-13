import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/crud_module.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../services/rich_text_codec.dart' show isAllowedUrl;
import '../../services/text_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/asset_picker.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/relation_multi_select.dart';
import '../../widgets/rich_text_field.dart';
import '../../widgets/state_views.dart';

class GenericCrudFormScreen extends StatefulWidget {
  final CrudModule module;
  final Map<String, dynamic>? initialData;

  /// Test seam: lets tests inject an [ApiService] with a mock http client.
  final ApiService? apiService;

  const GenericCrudFormScreen({super.key, required this.module, this.initialData, this.apiService});

  @override
  State<GenericCrudFormScreen> createState() => _GenericCrudFormScreenState();
}

class _GenericCrudFormScreenState extends State<GenericCrudFormScreen> {
  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  final _formKey = GlobalKey<FormState>();
  late final ApiService _apiService = widget.apiService ?? ApiService();
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, GlobalKey<RichTextFieldState>> _richKeys = {};
  final Map<String, PlatformFile> _files = {};
  final Map<String, List<MapEntry<Object, String>>> _remoteOptions = {};
  final Set<String> _editedSlugs = {}; // slug fields the user typed into (no more auto-fill)
  Map<String, dynamic>? _original;
  bool _ready = false;
  String? _loadError;
  bool _isLoading = false;
  bool _dirty = false; // any user edit → leaving asks for confirmation

  /// Admin `ImageUploadBox` limit.
  static const _maxImageBytes = 5 * 1024 * 1024;

  bool get _isEditing => widget.initialData != null;
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  List<FieldConfig> get _fields => widget.module.fields;

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      if (field.optionsEndpoint != null) _loadOptions(field);
    }
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    var original = widget.initialData;
    final path = original == null ? null : detailPath(widget.module, original);
    if (path != null) {
      try {
        original = Map<String, dynamic>.from(await _apiService.get(path) as Map);
      } catch (e) {
        // Never edit from partial list data: it would wipe fields on save.
        if (mounted) setState(() => _loadError = e.toString());
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _original = original;
      _values
        ..clear()
        ..addAll(initialFormValues(widget.module, original));
      for (final field in _fields) {
        if (_usesController(field)) {
          // putIfAbsent: per-type fields may share a key (contents metadata.sortOrder).
          _controllers.putIfAbsent(field.key, () => TextEditingController(text: _toText(field, _values[field.key])));
        }
        if (field.type == FieldType.richText) _richKeys[field.key] = GlobalKey<RichTextFieldState>();
      }
      _ready = true;
      _loadError = null;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _usesController(FieldConfig f) => const {
    FieldType.text,
    FieldType.longText,
    FieldType.number,
    FieldType.json,
    FieldType.tags,
    FieldType.imageUrl,
  }.contains(f.type);

  String _toText(FieldConfig field, dynamic value) {
    if (value == null) return '';
    if (field.type == FieldType.json) return _jsonEncoder.convert(value);
    if (field.type == FieldType.tags && value is List) return value.join(', ');
    return value.toString();
  }

  Future<void> _loadOptions(FieldConfig field) async {
    try {
      final items = extractItems(await _apiService.get(field.optionsEndpoint!));
      if (!mounted) return;
      setState(() {
        _remoteOptions[field.key] = [
          for (final item in items)
            if (item[field.optionValueKey] != null)
              MapEntry(
                item[field.optionValueKey] as Object,
                item[field.optionLabelKey]?.toString() ?? item[field.optionValueKey].toString(),
              ),
        ];
      });
    } catch (e) {
      if (mounted) _showError('${field.label} yüklenemedi: $e');
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  void _onDropdownChanged(FieldConfig field, Object? value) {
    final previous = _values[field.key];
    _dirty = true;
    setState(() => _values[field.key] = value);
    // Swap templates bound to this dropdown (only if the user hasn't customised the field).
    for (final bound in _fields.where((f) => f.templateFromField == field.key)) {
      final controller = _controllers[bound.key]!;
      final previousTemplate = bound.templates?[previous];
      final untouched =
          controller.text.trim().isEmpty ||
          (previousTemplate != null && controller.text == _toText(bound, previousTemplate));
      final next = bound.templates?[value];
      if (untouched && next != null) controller.text = _toText(bound, next);
    }
  }

  void _onTextChanged(FieldConfig field, String text) {
    if (field.slugFrom != null) _editedSlugs.add(field.key);
    if (_isEditing) return; // admin keeps the slug of existing records unless typed
    for (final slug in _fields.where((f) => f.slugFrom == field.key && !_editedSlugs.contains(f.key))) {
      _controllers[slug.key]!.text = slugify(text);
    }
  }

  Future<void> _pickFile(FieldConfig field) async {
    final picked = await FilePicker.pickFiles(type: field.imageOnly ? FileType.image : FileType.any);
    if (picked.isEmpty || picked.first.path == null) return;
    final size = picked.first.lengthSync() ?? 0;
    if (field.imageOnly && size > _maxImageBytes) {
      _showError('${field.label}: dosya 5 MB sınırını aşıyor');
      return;
    }
    _dirty = true;
    setState(() => _files[field.key] = picked.first);
  }

  Future<void> _pickDate(FieldConfig field) async {
    final first = DateTime(2000);
    final last = DateTime(2100);
    final current = DateTime.tryParse(_values[field.key]?.toString() ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : (current.isAfter(last) ? last : current),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    final date =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    _dirty = true;
    setState(() => _values[field.key] = date);
  }

  void _collectControllerValues() {
    for (final field in _fields) {
      final rich = _richKeys[field.key]?.currentState;
      if (rich != null) _values[field.key] = rich.html;
      final controller = _controllers[field.key];
      if (controller == null) continue;
      final text = controller.text;
      switch (field.type) {
        case FieldType.number:
          _values[field.key] = text.trim().isEmpty ? null : int.tryParse(text.trim());
        case FieldType.json:
          _values[field.key] = text.trim().isEmpty ? null : jsonDecode(text);
        case FieldType.tags:
          _values[field.key] = [
            for (final tag in text.split(','))
              if (tag.trim().isNotEmpty) tag.trim(),
          ];
        default:
          _values[field.key] = text;
      }
    }
  }

  Future<void> _submit() async {
    final invalid = _formKey.currentState?.validateGranularly() ?? const {};
    if (invalid.isNotEmpty) {
      Scrollable.ensureVisible(invalid.first.context, alignment: 0.2, duration: const Duration(milliseconds: 250));
      _showError('${invalid.length} alan hatalı');
      return;
    }
    _collectControllerValues();
    setState(() => _isLoading = true);

    final module = widget.module;
    final payload = buildPayload(module, _original, _values);
    final id = _original?['id'];
    final endpoint = _isEditing ? '${module.crudEndpoint}/$id' : module.crudEndpoint;
    final method = _isEditing ? 'PUT' : 'POST';
    final files = [
      for (final field in _fields)
        if (_files[field.key] != null && isFieldVisible(field, _values))
          UploadFile(field.key, _files[field.key]!.path!),
    ];

    try {
      switch (module.requestMode) {
        case RequestMode.json:
          _isEditing ? await _apiService.put(endpoint, payload) : await _apiService.post(endpoint, payload);
        case RequestMode.multipartData:
          await _apiService.multipart(method, endpoint, fields: {'data': jsonEncode(payload)}, files: files);
        case RequestMode.multipartFields:
          await _apiService.multipart(method, endpoint, fields: toMultipartFields(payload), files: files);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditing ? 'Güncellendi' : 'Oluşturuldu')));
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.replaceFirst('Exception: ', '')),
        backgroundColor: _scheme.error,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  InputDecoration _decoration(FieldConfig field) => InputDecoration(
    labelText: field.isRequired ? '${field.label} *' : field.label,
    hintText: field.hint,
    hintStyle: TextStyle(color: _scheme.onSurface.withValues(alpha: 0.45)),
    labelStyle: TextStyle(color: _scheme.onSurface.withValues(alpha: 0.7)),
    filled: true,
    fillColor: _scheme.surface.withValues(alpha: 0.7),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: _scheme.onSurface.withValues(alpha: 0.1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: _scheme.onSurface.withValues(alpha: 0.1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: _scheme.primary),
    ),
  );

  String? _validateText(FieldConfig field, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return field.isRequired ? '${field.label} zorunlu' : null;
    if (field.type == FieldType.number) {
      final number = int.tryParse(value);
      if (number == null) return 'Sayı girin';
      if (number < 0) return '0 veya daha büyük olmalı';
    }
    if (field.type == FieldType.json) {
      try {
        jsonDecode(value);
      } catch (_) {
        return 'Geçersiz JSON';
      }
    }
    if (field.maxLength != null && value.length > field.maxLength!) {
      return '${field.label} ${field.maxLength} karakteri geçemez';
    }
    if (field.pattern != null && !RegExp(field.pattern!).hasMatch(value)) {
      return field.patternMessage ?? 'Geçersiz format';
    }
    return null;
  }

  Widget _buildDropdown(FieldConfig field) {
    final options = field.optionsEndpoint != null
        ? (_remoteOptions[field.key] ?? const <MapEntry<Object, String>>[])
        : [for (final o in field.options ?? const <String>[]) MapEntry<Object, String>(o, field.optionLabels?[o] ?? o)];
    final current = _values[field.key];
    // A stored value the form doesn't know (e.g. a legacy content type) stays visible and selected.
    final known = current == null || options.any((o) => o.key == current) || field.optionsEndpoint != null;
    final items = [...options, if (!known) MapEntry<Object, String>(current as Object, current.toString())];
    final hasCurrent = items.any((o) => o.key == current);
    final locked = _isEditing && field.readOnlyOnEdit;
    return DropdownButtonFormField<Object>(
      key: ValueKey('field_${field.key}_${items.length}'),
      initialValue: hasCurrent ? current as Object : null,
      decoration: _decoration(field),
      dropdownColor: _scheme.surface,
      style: TextStyle(color: _scheme.onSurface),
      isExpanded: true,
      items: [for (final o in items) DropdownMenuItem<Object>(value: o.key, child: Text(o.value))],
      onChanged: locked ? null : (val) => _onDropdownChanged(field, val),
      validator: (val) => field.isRequired && val == null ? '${field.label} zorunlu' : null,
    );
  }

  Widget _buildFile(FieldConfig field) {
    final picked = _files[field.key];
    final current = field.currentImageKey == null ? null : getPath(_original, field.currentImageKey!)?.toString();
    final hasCurrent = current != null && current.trim().isNotEmpty;
    final preview = picked != null && field.imageOnly
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(picked.path!),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              semanticLabel: '${field.label} yeni görsel',
              errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
            ),
          )
        : (hasCurrent ? AssetThumbnail(url: current, semanticLabel: '${field.label} mevcut görsel') : null);
    return FormField<PlatformFile>(
      key: ValueKey('field_${field.key}'),
      validator: (_) => field.isRequired && _files[field.key] == null ? '${field.label} seçin' : null,
      builder: (state) => InputDecorator(
        decoration: _decoration(field).copyWith(errorText: state.errorText),
        child: Row(
          children: [
            if (preview != null) ...[preview, const SizedBox(width: 8)],
            Expanded(
              child: Text(
                picked?.name ?? (hasCurrent ? 'Mevcut görsel' : 'Dosya seçilmedi'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _scheme.onSurface.withValues(alpha: picked == null ? 0.6 : 1)),
              ),
            ),
            if (picked != null)
              IconButton(
                tooltip: '${field.label} dosyasını kaldır',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _files.remove(field.key)),
              ),
            Tooltip(
              message: '${field.label} seç',
              excludeFromSemantics: true,
              child: Semantics(
                label: '${field.label} seç',
                button: true,
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: () async {
                    await _pickFile(field);
                    state.didChange(_files[field.key]);
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Seç'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDate(FieldConfig field) {
    final value = _values[field.key]?.toString() ?? '';
    final date = value.split('T').first;
    return InputDecorator(
      key: ValueKey('field_${field.key}'),
      decoration: _decoration(field),
      child: Row(
        children: [
          Expanded(
            child: Text(
              date.isEmpty ? 'Tarih seçilmedi' : date,
              style: TextStyle(color: _scheme.onSurface.withValues(alpha: date.isEmpty ? 0.6 : 1)),
            ),
          ),
          if (date.isNotEmpty)
            IconButton(
              tooltip: '${field.label} temizle',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                _dirty = true;
                setState(() => _values[field.key] = null);
              },
            ),
          Tooltip(
            message: '${field.label} seç',
            excludeFromSemantics: true,
            child: Semantics(
              label: '${field.label} seç',
              button: true,
              excludeSemantics: true,
              child: TextButton.icon(
                onPressed: () => _pickDate(field),
                icon: const Icon(Icons.event_rounded),
                label: const Text('Seç'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageUrl(FieldConfig field, bool canPickAssets) {
    final controller = _controllers[field.key]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: ValueKey('field_${field.key}'),
          controller: controller,
          keyboardType: TextInputType.url,
          style: TextStyle(color: _scheme.onSurface),
          decoration: _decoration(field).copyWith(
            suffixIcon: canPickAssets
                ? IconButton(
                    key: ValueKey('asset_pick_button_${field.key}'),
                    tooltip: '${field.label}: assetlerden seç',
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: () async {
                      final url = await showAssetPicker(context, _apiService);
                      if (url != null) controller.text = url;
                    },
                  )
                : null,
          ),
          validator: (val) => _validateText(field, val),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          // Preview only a usable URL/path (no request per keystroke of a half-typed "https://ex").
          builder: (_, value, _) => !_previewable(value.text)
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AssetThumbnail(url: value.text, size: 96, semanticLabel: '${field.label} önizleme'),
                ),
        ),
      ],
    );
  }

  static bool _previewable(String text) {
    final value = text.trim();
    if (!isAllowedUrl(value)) return false;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.hasScheme ? uri.host.contains('.') && uri.path.length > 1 : value.contains('/'));
  }

  Widget _buildField(FieldConfig field, {required bool canPickAssets}) {
    final Widget child;
    switch (field.type) {
      case FieldType.boolean:
        child = SwitchListTile(
          key: ValueKey('field_${field.key}'),
          title: Text(field.label),
          value: _values[field.key] == true,
          onChanged: (val) {
            _dirty = true;
            setState(() => _values[field.key] = val);
          },
          activeThumbColor: _scheme.primary,
        );
      case FieldType.dropdown:
        child = _buildDropdown(field);
      case FieldType.file:
        child = _buildFile(field);
      case FieldType.date:
        child = _buildDate(field);
      case FieldType.imageUrl:
        child = _buildImageUrl(field, canPickAssets);
      case FieldType.relation:
        child = RelationMultiSelect(
          key: ValueKey('field_${field.key}'),
          api: _apiService,
          label: field.label,
          endpoint: field.relationEndpoint!,
          valueKey: field.optionValueKey,
          labelKey: field.optionLabelKey,
          subtitleKey: field.optionSubtitleKey,
          isRequired: field.isRequired,
          initialValue: List<Object>.from(_values[field.key] as List? ?? const []),
          onChanged: (ids) {
            _values[field.key] = ids;
            _markDirty();
          },
        );
      case FieldType.richText:
        child = RichTextField(
          key: _richKeys[field.key],
          label: field.label,
          initialHtml: _values[field.key]?.toString() ?? '',
          api: _apiService,
          canPickAssets: canPickAssets,
          onChanged: _markDirty,
        );
      default:
        final isJson = field.type == FieldType.json;
        child = TextFormField(
          key: ValueKey('field_${field.key}'),
          controller: _controllers[field.key],
          minLines: isJson ? 6 : 1,
          maxLines: field.type == FieldType.longText ? 6 : (isJson ? 16 : 1),
          maxLength: field.maxLength,
          keyboardType: field.type == FieldType.number
              ? TextInputType.number
              : (field.type == FieldType.text || field.type == FieldType.tags
                    ? TextInputType.text
                    : TextInputType.multiline),
          style: TextStyle(
            color: _scheme.onSurface,
            fontFamily: isJson ? 'Courier' : null,
            fontSize: isJson ? 13 : null,
          ),
          decoration: _decoration(field).copyWith(helperText: field.type == FieldType.tags ? 'Virgülle ayırın' : null),
          onChanged: (text) => _onTextChanged(field, text),
          validator: (val) => _validateText(field, val),
        );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: child);
  }

  /// Visible fields with a header above each new [FieldConfig.section].
  List<Widget> _formFields(bool canPickAssets) {
    final widgets = <Widget>[];
    String? section;
    for (final field in _fields.where((f) => isFieldVisible(f, _values))) {
      if (field.section != null && field.section != section) {
        section = field.section;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Semantics(
              header: true,
              child: Text(
                section!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      }
      widgets.add(_buildField(field, canPickAssets: canPickAssets));
    }
    return widgets;
  }

  /// Back with unsaved edits (or while saving) asks first.
  Future<void> _confirmLeave() async {
    final leave = await showConfirmDialog(
      context,
      title: _isLoading ? 'Kayıt sürüyor' : 'Kaydedilmemiş değişiklikler',
      message: _isLoading
          ? 'Kayıt henüz tamamlanmadı. Çıkarsanız sonucu göremezsiniz.'
          : 'Değişiklikler kaydedilmedi ve kaybolacak. Çıkılsın mı?',
      confirmLabel: 'Çık',
      cancelLabel: 'Kal',
      destructive: true,
      confirmKey: const ValueKey('confirm_leave_button'),
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  Widget _saveBar() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          key: const ValueKey('crud_save_button'),
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _scheme.primary,
            foregroundColor: _scheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _isLoading
              ? CircularProgressIndicator(color: _scheme.onPrimary, semanticsLabel: 'Kaydediliyor')
              : const Text('Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final canPickAssets = context.watch<AuthProvider>().can('assets', 'read');
    return PopScope(
      canPop: !_dirty && !_isLoading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: AppScaffold(
        title: _isEditing ? '${widget.module.title} · Düzenle' : '${widget.module.title} · Yeni',
        body: !_ready
            ? (_loadError == null ? const LoadingView() : ErrorView(message: _loadError!, onRetry: _loadRecord))
            // Save stays reachable at the bottom while the long form scrolls.
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Form(
                        key: _formKey,
                        onChanged: _markDirty,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _formFields(canPickAssets),
                        ),
                      ),
                    ),
                  ),
                  _saveBar(),
                ],
              ),
      ),
    );
  }
}
