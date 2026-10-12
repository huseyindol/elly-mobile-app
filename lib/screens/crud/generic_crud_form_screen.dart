import 'dart:convert';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/crud_module.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../widgets/state_views.dart';

class GenericCrudFormScreen extends StatefulWidget {
  final CrudModule module;
  final Map<String, dynamic>? initialData;

  const GenericCrudFormScreen({super.key, required this.module, this.initialData});

  @override
  State<GenericCrudFormScreen> createState() => _GenericCrudFormScreenState();
}

class _GenericCrudFormScreenState extends State<GenericCrudFormScreen> {
  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, PlatformFile> _files = {};
  final Map<String, List<MapEntry<Object, String>>> _remoteOptions = {};
  Map<String, dynamic>? _original;
  bool _ready = false;
  String? _loadError;
  bool _isLoading = false;

  bool get _isEditing => widget.initialData != null;
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
          _controllers[field.key] = TextEditingController(text: _toText(field, _values[field.key]));
        }
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

  bool _usesController(FieldConfig f) =>
      f.type == FieldType.text || f.type == FieldType.longText || f.type == FieldType.number || f.type == FieldType.json;

  String _toText(FieldConfig field, dynamic value) {
    if (value == null) return '';
    if (field.type == FieldType.json) return _jsonEncoder.convert(value);
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
              MapEntry(item[field.optionValueKey] as Object,
                  item[field.optionLabelKey]?.toString() ?? item[field.optionValueKey].toString()),
        ];
      });
    } catch (e) {
      if (mounted) _showError('${field.label} yüklenemedi: $e');
    }
  }

  void _onDropdownChanged(FieldConfig field, Object? value) {
    final previous = _values[field.key];
    setState(() => _values[field.key] = value);
    // Swap JSON templates bound to this dropdown (only if user hasn't customised them).
    for (final jsonField in _fields.where((f) => f.templateFromField == field.key)) {
      final controller = _controllers[jsonField.key]!;
      final previousTemplate = jsonField.templates?[previous];
      final untouched = controller.text.trim().isEmpty ||
          (previousTemplate != null && controller.text == _jsonEncoder.convert(previousTemplate));
      final next = jsonField.templates?[value];
      if (untouched && next != null) controller.text = _jsonEncoder.convert(next);
    }
  }

  Future<void> _pickFile(FieldConfig field) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || picked.first.path == null) return;
    setState(() => _files[field.key] = picked.first);
  }

  void _collectControllerValues() {
    for (final field in _fields) {
      final controller = _controllers[field.key];
      if (controller == null) continue;
      final text = controller.text;
      switch (field.type) {
        case FieldType.number:
          _values[field.key] = text.trim().isEmpty ? null : int.tryParse(text.trim());
        case FieldType.json:
          _values[field.key] = text.trim().isEmpty ? null : jsonDecode(text);
        default:
          _values[field.key] = text;
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _collectControllerValues();
    setState(() => _isLoading = true);

    final module = widget.module;
    final payload = buildPayload(module, _original, _values);
    final id = _original?['id'];
    final endpoint = _isEditing ? '${module.crudEndpoint}/$id' : module.crudEndpoint;
    final method = _isEditing ? 'PUT' : 'POST';
    final files = [for (final e in _files.entries) UploadFile(e.key, e.value.path!)];

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditing ? 'Güncellendi' : 'Oluşturuldu'),
        backgroundColor: Colors.green,
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message.replaceFirst('Exception: ', '')),
      backgroundColor: Colors.redAccent,
      duration: const Duration(seconds: 6),
    ));
  }

  InputDecoration _decoration(FieldConfig field) => InputDecoration(
        labelText: field.isRequired ? '${field.label} *' : field.label,
        hintText: field.hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        filled: true,
        fillColor: const Color(0xFF1C1C22).withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF6366F1)),
        ),
      );

  String? _validateText(FieldConfig field, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return field.isRequired ? '${field.label} zorunlu' : null;
    if (field.type == FieldType.number && int.tryParse(value) == null) return 'Sayı girin';
    if (field.type == FieldType.json) {
      try {
        jsonDecode(value);
      } catch (_) {
        return 'Geçersiz JSON';
      }
    }
    if (field.pattern != null && !RegExp(field.pattern!).hasMatch(value)) {
      return field.patternMessage ?? 'Geçersiz format';
    }
    return null;
  }

  Widget _buildField(FieldConfig field) {
    final Widget child;
    switch (field.type) {
      case FieldType.boolean:
        child = SwitchListTile(
          key: ValueKey('field_${field.key}'),
          title: Text(field.label, style: const TextStyle(color: Colors.white)),
          value: _values[field.key] == true,
          onChanged: (val) => setState(() => _values[field.key] = val),
          activeThumbColor: const Color(0xFF6366F1),
        );
      case FieldType.dropdown:
        final options = field.optionsEndpoint != null
            ? (_remoteOptions[field.key] ?? const <MapEntry<Object, String>>[])
            : [for (final o in field.options ?? const <String>[]) MapEntry<Object, String>(o, o)];
        final current = _values[field.key];
        final hasCurrent = options.any((o) => o.key == current);
        child = DropdownButtonFormField<Object>(
          key: ValueKey('field_${field.key}_${options.length}'),
          initialValue: hasCurrent ? current as Object : null,
          decoration: _decoration(field),
          dropdownColor: const Color(0xFF1C1C22),
          style: const TextStyle(color: Colors.white),
          isExpanded: true,
          items: [for (final o in options) DropdownMenuItem<Object>(value: o.key, child: Text(o.value))],
          onChanged: (val) => _onDropdownChanged(field, val),
          validator: (val) => field.isRequired && val == null ? '${field.label} zorunlu' : null,
        );
      case FieldType.file:
        final picked = _files[field.key];
        child = FormField<PlatformFile>(
          key: ValueKey('field_${field.key}'),
          validator: (_) => field.isRequired && _files[field.key] == null ? '${field.label} seçin' : null,
          builder: (state) => InputDecorator(
            decoration: _decoration(field).copyWith(errorText: state.errorText),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    picked?.name ?? 'Dosya seçilmedi',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: picked == null ? 0.4 : 1)),
                  ),
                ),
                if (picked != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _files.remove(field.key)),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    await _pickFile(field);
                    state.didChange(_files[field.key]);
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Seç'),
                ),
              ],
            ),
          ),
        );
      default:
        child = TextFormField(
          key: ValueKey('field_${field.key}'),
          controller: _controllers[field.key],
          minLines: field.type == FieldType.json ? 6 : 1,
          maxLines: field.type == FieldType.longText ? 6 : (field.type == FieldType.json ? 16 : 1),
          keyboardType: field.type == FieldType.number
              ? TextInputType.number
              : (field.type == FieldType.text ? TextInputType.text : TextInputType.multiline),
          style: TextStyle(
            color: Colors.white,
            fontFamily: field.type == FieldType.json ? 'Courier' : null,
            fontSize: field.type == FieldType.json ? 13 : null,
          ),
          decoration: _decoration(field),
          validator: (val) => _validateText(field, val),
        );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: const Color(0xFF0A0A0C).withValues(alpha: 0.5),
              title: Text(_isEditing ? '${widget.module.title} · Düzenle' : '${widget.module.title} · Yeni'),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEC4899).withValues(alpha: 0.15),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          SafeArea(
            child: !_ready
                ? (_loadError == null ? const LoadingView() : ErrorView(message: _loadError!, onRetry: _loadRecord))
                : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    ..._fields.map(_buildField),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        key: const ValueKey('crud_save_button'),
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white, semanticsLabel: 'Kaydediliyor')
                            : const Text('Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
