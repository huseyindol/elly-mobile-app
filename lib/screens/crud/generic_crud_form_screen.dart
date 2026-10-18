import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/crud_module.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../services/rich_text_codec.dart' show isAllowedUrl;
import '../../services/text_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/asset_picker.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/form_schema_editor.dart';
import '../../widgets/post_preview_sheet.dart';
import '../../widgets/relation_multi_select.dart';
import '../../widgets/rich_text_field.dart';
import '../../widgets/save_bar.dart';
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
  final Set<String> _optionsDenied = {}; // remote dropdowns not loaded: missing optionsPermission
  final Set<String> _editedSlugs = {}; // slug fields the user typed into (no more auto-fill)
  final Set<String> _aiBusy = {}; // active AI generation keys ('field_<key>' or 'section_<name>')
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
    final auth = context.read<AuthProvider>();
    for (final field in _fields) {
      if (field.optionsEndpoint == null) continue;
      if (field.optionsPermission == null || auth.has(field.optionsPermission!)) {
        _loadOptions(field);
      } else {
        _optionsDenied.add(field.key);
      }
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
                field.optionLabelOf?.call(item) ??
                    item[field.optionLabelKey]?.toString() ??
                    item[field.optionValueKey].toString(),
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
      reportInvalidFields(context, invalid, labelOf: _labelOf);
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
      ScaffoldMessenger.of(context).clearSnackBars(); // stale errors must not follow onto the list
      showAppSnackBar(context, _isEditing ? 'Güncellendi' : 'Oluşturuldu');
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) => showAppSnackBar(context, message, error: true);

  /// Field widgets are keyed `field_<key>` (dropdowns `field_<key>_<n>`).
  String? _labelOf(FormFieldState<Object?> state) {
    final key = state.widget.key;
    if (key is! ValueKey<String>) return null;
    return _fields
        .where((f) => key.value == 'field_${f.key}' || key.value.startsWith('field_${f.key}_'))
        .firstOrNull
        ?.label;
  }

  bool _isRequired(FieldConfig field) =>
      field.isRequired || (field.requiredWhen?.entries.every((e) => _values[e.key] == e.value) ?? false);

  InputDecoration _decoration(FieldConfig field) =>
      fieldDecoration(_scheme, label: _isRequired(field) ? '${field.label} *' : field.label, hint: field.hint);

  String? _validateText(FieldConfig field, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return _isRequired(field) ? '${field.label} zorunlu' : null;
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
    // A stored value the form doesn't know (e.g. a legacy content type) stays visible and selected;
    // a remote one only with a [FieldConfig.currentOptionLabel] (no bare id while options load).
    final unknownLabel = current == null || options.any((o) => o.key == current)
        ? null
        : (field.optionsEndpoint == null ? current.toString() : field.currentOptionLabel?.call(_original));
    final items = [...options, if (unknownLabel != null) MapEntry<Object, String>(current as Object, unknownLabel)];
    final hasCurrent = items.any((o) => o.key == current);
    final locked = _isEditing && field.readOnlyOnEdit;
    // A required remote dropdown with nothing to pick says why.
    String? helper;
    if (field.optionsEndpoint != null && options.isEmpty && _isRequired(field)) {
      if (_optionsDenied.contains(field.key)) {
        helper = '${field.label} listesini görme yetkiniz yok (${field.optionsPermission}).';
      } else if (_remoteOptions.containsKey(field.key)) {
        helper = field.emptyOptionsHint ?? 'Seçilebilecek kayıt yok.';
      }
    }
    return DropdownButtonFormField<Object>(
      key: ValueKey('field_${field.key}_${items.length}'),
      initialValue: hasCurrent ? current as Object : null,
      decoration: _decoration(field).copyWith(helperText: helper),
      dropdownColor: _scheme.surface,
      style: TextStyle(color: _scheme.onSurface),
      isExpanded: true,
      items: [for (final o in items) DropdownMenuItem<Object>(value: o.key, child: Text(o.value))],
      onChanged: locked ? null : (val) => _onDropdownChanged(field, val),
      validator: (val) => _isRequired(field) && val == null ? '${field.label} zorunlu' : null,
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
          subtitle: field.hint == null ? null : Text(field.hint!),
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
      case FieldType.formSchema:
        child = FormSchemaEditor(
          key: ValueKey('field_${field.key}'),
          initialValue: _values[field.key] as Map<String, dynamic>?,
          title: () => _controllers['title']?.text ?? '',
          onChanged: (schema) {
            _values[field.key] = schema;
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
            fontFamily: isJson ? 'monospace' : null,
            fontSize: isJson ? 13 : null,
          ),
          decoration: _decoration(field).copyWith(
            helperText: field.type == FieldType.tags ? 'Virgülle ayırın' : null,
            suffixIcon: _buildAiFieldButton(field),
          ),
          onChanged: (text) => _onTextChanged(field, text),
          validator: (val) => _validateText(field, val),
        );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: child);
  }

  Widget? _buildAiFieldButton(FieldConfig field) {
    if (field.aiAction == null) return null;
    final busy = _aiBusy.contains('field_${field.key}');
    return IconButton(
      key: ValueKey('ai_button_${field.key}'),
      tooltip: '${field.label}: AI ile oluştur',
      onPressed: busy || _isLoading ? null : () => _generateFieldAi(field),
      icon: busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.auto_awesome_rounded, size: 20, color: _scheme.primary),
    );
  }

  Widget? _buildSectionAiAction(String section) {
    final (String key, String label, VoidCallback onPressed)? config = switch (section) {
      'SEO Ayarları' when _controllers.containsKey('seoInfo.title') => (
        'section_seo',
        'AI ile Oluştur',
        _generateSeoAi,
      ),
      'Blog Bilgileri' when widget.module.permissionKey == 'posts' => (
        'section_blog_info',
        'AI ile Oluştur',
        _generateBlogInfoAi,
      ),
      'İçerik' when widget.module.permissionKey == 'posts' => ('section_article', 'AI Makale', _generateArticleAi),
      _ => null,
    };
    if (config == null) return null;
    final (busyKey, label, handler) = config;
    final busy = _aiBusy.contains(busyKey);
    return TextButton.icon(
      key: ValueKey('ai_$busyKey'),
      onPressed: busy || _isLoading ? null : handler,
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_awesome_rounded, size: 18),
      label: Text(label),
    );
  }

  Future<void> _generateFieldAi(FieldConfig field) async {
    final sourceKey = field.aiSourceKey ?? 'title';
    final source = _controllers[sourceKey]?.text.trim() ?? '';
    if (source.isEmpty) {
      final sourceLabel = _fields.where((f) => f.key == sourceKey).firstOrNull?.label ?? sourceKey;
      _showError('Önce $sourceLabel alanını doldurun');
      return;
    }
    final busyKey = 'field_${field.key}';
    setState(() => _aiBusy.add(busyKey));
    try {
      switch (field.aiAction) {
        case 'slug':
          final data = Map<String, dynamic>.from(await _apiService.post('/ai/slug', {'title': source}) as Map);
          final slug = data['slug']?.toString() ?? '';
          if (slug.isNotEmpty) {
            _controllers[field.key]?.text = slug;
            _editedSlugs.add(field.key);
            _markDirty();
            if (mounted) showAppSnackBar(context, 'Slug oluşturuldu');
          }
        case 'description':
          final data = Map<String, dynamic>.from(
            await _apiService.post('/ai/description', {'name': source, 'context': field.aiContext ?? 'sayfa'}) as Map,
          );
          final desc = data['description']?.toString() ?? '';
          if (desc.isNotEmpty) {
            _controllers[field.key]?.text = desc;
            _markDirty();
            if (mounted) showAppSnackBar(context, 'Açıklama oluşturuldu');
          }
        case 'altText':
          final data = Map<String, dynamic>.from(await _apiService.post('/ai/alt-text', {'title': source}) as Map);
          final altText = data['altText']?.toString() ?? '';
          if (altText.isNotEmpty) {
            _controllers[field.key]?.text = altText;
            _markDirty();
            if (mounted) showAppSnackBar(context, 'Alt metin oluşturuldu');
          }
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy.remove(busyKey));
    }
  }

  Future<void> _generateSeoAi() async {
    final title = _controllers['title']?.text.trim() ?? '';
    if (title.isEmpty) {
      _showError('Önce Başlık alanını doldurun');
      return;
    }
    const busyKey = 'section_seo';
    setState(() => _aiBusy.add(busyKey));
    try {
      final data = Map<String, dynamic>.from(await _apiService.post('/ai/seo', {'title': title}) as Map);
      _controllers['seoInfo.title']?.text = data['seoTitle']?.toString() ?? '';
      _controllers['seoInfo.description']?.text = data['seoDescription']?.toString() ?? '';
      final rawKeywords = data['seoKeywords'];
      _controllers['seoInfo.keywords']?.text = rawKeywords is List
          ? rawKeywords.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(', ')
          : (rawKeywords?.toString() ?? '');
      final slug = _controllers['slug']?.text.trim() ?? '';
      if (slug.isNotEmpty) _controllers['seoInfo.canonicalUrl']?.text = '/$slug';
      _markDirty();
      if (mounted) showAppSnackBar(context, 'SEO alanları oluşturuldu');
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy.remove(busyKey));
    }
  }

  Future<void> _generateBlogInfoAi() async {
    final title = _controllers['title']?.text.trim() ?? '';
    final content = (_richKeys['content']?.currentState?.html ?? _values['content']?.toString() ?? '').trim();
    final plainContent = content.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (title.isEmpty || plainContent.isEmpty) {
      _showError('Önce Başlık ve İçerik alanlarını doldurun');
      return;
    }
    const busyKey = 'section_blog_info';
    setState(() => _aiBusy.add(busyKey));
    try {
      final data = Map<String, dynamic>.from(
        await _apiService.post('/ai/blog-info', {'title': title, 'content': content}) as Map,
      );
      _controllers['description']?.text = data['description']?.toString() ?? '';
      _controllers['category']?.text = data['category']?.toString() ?? '';
      _controllers['readingTime']?.text = data['readingTime']?.toString() ?? '';
      final imagePrompt = data['imagePrompt']?.toString().trim() ?? '';
      if (imagePrompt.isNotEmpty) {
        _controllers['coverImage']?.text =
            'https://image.pollinations.ai/prompt/${Uri.encodeComponent(imagePrompt)}?width=1600&height=900&nologo=true';
      }
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final author = auth.currentUser?.username ?? auth.profile?['email']?.toString() ?? '';
      if (author.isNotEmpty) _controllers['author']?.text = author;
      _dirty = true;
      setState(() => _values['publishedAt'] = today);
      showAppSnackBar(context, 'Blog bilgileri oluşturuldu');
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy.remove(busyKey));
    }
  }

  Future<void> _generateArticleAi() async {
    final params = await showDialog<({String topic, String keywords})>(
      context: context,
      builder: (_) => _AiArticleDialog(initialTopic: _controllers['title']?.text.trim() ?? ''),
    );
    if (params == null || !mounted) return;
    const busyKey = 'section_article';
    setState(() => _aiBusy.add(busyKey));
    try {
      final data = Map<String, dynamic>.from(
        await _apiService.post('/ai/article', {
              'topic': params.topic,
              if (params.keywords.isNotEmpty) 'keywords': params.keywords,
            })
            as Map,
      );
      final html = data['html']?.toString() ?? '';
      if (html.isNotEmpty) {
        _values['content'] = html;
        _richKeys['content']?.currentState?.replaceHtml(html);
        _markDirty();
        if (mounted) showAppSnackBar(context, 'Makale oluşturuldu');
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy.remove(busyKey));
    }
  }

  void _openPostPreview() {
    _collectControllerValues();
    final auth = context.read<AuthProvider>();
    final fallbackAuthor = auth.currentUser?.username ?? auth.profile?['email']?.toString() ?? '';
    final authorText = _values['author']?.toString().trim() ?? '';
    showPostPreviewSheet(
      context,
      post: PostPreviewData(
        title: _values['title']?.toString() ?? '',
        slug: _values['slug']?.toString() ?? '',
        content: _values['content']?.toString() ?? '',
        description: _values['description']?.toString() ?? '',
        category: _values['category']?.toString() ?? '',
        coverImage: _values['coverImage']?.toString() ?? '',
        publishedAt: _values['publishedAt']?.toString() ?? '',
        author: authorText.isNotEmpty ? authorText : fallbackAuthor,
        readingTime: _values['readingTime']?.toString() ?? '',
      ),
    );
  }

  /// Visible fields with a header above each new [FieldConfig.section].
  List<Widget> _formFields(bool canPickAssets) {
    final widgets = <Widget>[];
    String? section;
    for (final field in _fields.where((f) => isFieldVisible(f, _values))) {
      if (field.section != null && field.section != section) {
        section = field.section;
        final sectionAction = _buildSectionAiAction(section!);
        final showSectionPreview = section == 'İçerik' && widget.module.permissionKey == 'posts';
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      section,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (showSectionPreview)
                  TextButton.icon(
                    key: const ValueKey('post_section_preview_button'),
                    onPressed: _isLoading ? null : _openPostPreview,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Önizleme'),
                  ),
                ?sectionAction,
              ],
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
    if (await confirmLeaveForm(context, saving: _isLoading) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canPickAssets = auth.can('assets', 'read');
    final link = widget.module.recordLink;
    return PopScope(
      canPop: !_dirty && !_isLoading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: AppScaffold(
        title: _isEditing ? '${widget.module.title} · Düzenle' : '${widget.module.title} · Yeni',
        actions: [
          if (widget.module.permissionKey == 'posts' && _ready)
            IconButton(
              key: const ValueKey('post_preview_button'),
              tooltip: 'Canlı Önizleme (Mobil / Web)',
              icon: const Icon(Icons.visibility_outlined),
              onPressed: _openPostPreview,
            ),
          if (link != null && _original != null && auth.can(widget.module.permissionKey, link.action))
            IconButton(
              key: const ValueKey('record_link_button'),
              tooltip: link.label,
              icon: Icon(link.icon),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => link.builder(_original!, _apiService))),
            ),
        ],
        body: !_ready
            ? (_loadError == null ? const LoadingView() : ErrorView(message: _loadError!, onRetry: _loadRecord))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Form(
                  key: _formKey,
                  onChanged: _markDirty,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _formFields(canPickAssets)),
                ),
              ),
        // Save stays reachable at the bottom while the long form scrolls; SnackBars show above it.
        bottomNavigationBar: _ready ? SaveBar(onPressed: _submit, loading: _isLoading) : null,
      ),
    );
  }
}

class _AiArticleDialog extends StatefulWidget {
  final String initialTopic;
  const _AiArticleDialog({required this.initialTopic});

  @override
  State<_AiArticleDialog> createState() => _AiArticleDialogState();
}

class _AiArticleDialogState extends State<_AiArticleDialog> {
  late final _topic = TextEditingController(text: widget.initialTopic);
  final _keywords = TextEditingController();

  @override
  void dispose() {
    _topic.dispose();
    _keywords.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = _topic.text.trim();
    return AlertDialog(
      scrollable: true,
      title: const Text('AI Makale Oluşturucu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('ai_article_topic'),
            controller: _topic,
            decoration: const InputDecoration(
              labelText: 'Makale Konusu *',
              hintText: 'Örn: React Server Components nasıl çalışır?',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('ai_article_keywords'),
            controller: _keywords,
            decoration: const InputDecoration(
              labelText: 'Yardımcı Anahtar Kelimeler',
              hintText: 'Örn: performans, SSR, hydration',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('İptal')),
        FilledButton.icon(
          key: const ValueKey('ai_article_submit'),
          onPressed: topic.isEmpty
              ? null
              : () => Navigator.of(context).pop((topic: topic, keywords: _keywords.text.trim())),
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('Makale Oluştur'),
        ),
      ],
    );
  }
}
