import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/mail_payload.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/save_bar.dart';
import '../../widgets/state_views.dart';
import 'email_template_preview_screen.dart';
import 'email_templates_screen.dart' show confirmDeleteTemplate;

/// Admin `email-templates/new` and `email-templates/[key]` (`TemplateForm`). The HTML body is a monospace code
/// field (admin: Monaco). Saving an existing template stays on the screen like the admin (edit → save →
/// preview loop); a new one opens its edit screen. Without `email_templates:manage` the form is read-only.
class EmailTemplateFormScreen extends StatefulWidget {
  /// null = new template.
  final String? templateKey;
  final ApiService? apiService;

  /// Test seam for the preview's WebView.
  final Widget Function(String html)? previewViewBuilder;

  const EmailTemplateFormScreen({super.key, this.templateKey, this.apiService, this.previewViewBuilder});

  @override
  State<EmailTemplateFormScreen> createState() => _EmailTemplateFormScreenState();
}

class _EmailTemplateFormScreenState extends State<EmailTemplateFormScreen> {
  static const _labels = {
    'templateKey': 'Template Key',
    'subject': 'Konu',
    'description': 'Açıklama',
    'htmlBody': 'HTML Body',
  };

  late final ApiService _api = widget.apiService ?? ApiService();
  final _formKey = GlobalKey<FormState>();
  final _controllers = {for (final k in _labels.keys) k: TextEditingController()};
  bool _active = true;
  Map<String, dynamic>? _record;
  bool _ready = false;
  String? _loadError;
  bool _saving = false;
  bool _deleting = false;
  bool _dirty = false;

  /// Key of the record being edited; set after a create so the same screen continues as its edit screen (admin
  /// goes to `/email-templates/{key}`) — the list awaiting this route then reloads once the user leaves.
  late String? _key = widget.templateKey;

  bool get _isEditing => _key != null;
  bool get _busy => _saving || _deleting;
  String get _path => '/email-templates/${Uri.encodeComponent(_key!)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    Map<String, dynamic>? record;
    if (_isEditing) {
      try {
        record = Map<String, dynamic>.from(await _api.get(_path) as Map);
      } catch (e) {
        if (mounted) setState(() => _loadError = e.toString());
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _apply(record);
      _ready = true;
      _loadError = null;
    });
  }

  void _apply(Map<String, dynamic>? record) {
    _record = record;
    for (final k in _labels.keys) {
      _controllers[k]!.text = '${record?[k] ?? ''}';
    }
    _active = record == null || record['active'] != false;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reportInvalidFields(context, invalid, labelOf: _labelOf);
      return;
    }
    final payload = emailTemplatePayload(
      templateKey: _key ?? _controllers['templateKey']!.text,
      subject: _controllers['subject']!.text,
      htmlBody: _controllers['htmlBody']!.text,
      description: _controllers['description']!.text,
      active: _active,
      optimisticLockVersion: _record?['optimisticLockVersion'],
    );
    setState(() => _saving = true);
    try {
      final saved = _isEditing ? await _api.put(_path, payload) : await _api.post('/email-templates', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      if (_isEditing) {
        showAppSnackBar(context, 'Template güncellendi');
        setState(() {
          if (saved is Map) _apply(Map<String, dynamic>.from(saved)); // new optimisticLockVersion
          _dirty = false;
        });
      } else {
        showAppSnackBar(context, 'Template oluşturuldu');
        setState(() {
          _key = payload['templateKey'] as String;
          _dirty = false;
          _ready = false;
        });
        await _load(); // the stored record (lock version, timestamps) like the admin's detail page
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        showAppSnackBar(
          context,
          'Başka biri bu template\'i güncellemiş. Yenilerseniz buradaki düzenlemeleriniz kaybolur.',
          error: true,
          action: SnackBarAction(
            label: 'Yenile',
            onPressed: () {
              _dirty = false;
              _load();
            },
          ),
        );
      } else {
        showAppSnackBar(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final key = _key!;
    if (!await confirmDeleteTemplate(context, key) || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _api.delete(_path);
      if (!mounted) return;
      showAppSnackBar(context, 'Template silindi');
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        showAppSnackBar(context, e.toString(), error: true);
      }
    }
  }

  void _preview() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EmailTemplatePreviewScreen(
        templateKey: _key!,
        apiService: _api,
        unsavedChanges: _dirty,
        htmlViewBuilder: widget.previewViewBuilder,
      ),
    ),
  );

  String? _labelOf(FormFieldState<Object?> state) {
    final key = state.widget.key;
    return key is ValueKey<String> ? _labels[key.value.replaceFirst('template_field_', '')] : null;
  }

  Widget _field(
    String key, {
    required bool readOnly,
    bool required = true,
    int? max,
    String? hint,
    String? helper,
    bool code = false,
    bool literal = false,
    int minLines = 1,
    double? height,
    String? Function(String value)? validator,
  }) {
    // code: monospace; code or literal: typed text is kept exactly — iOS smart punctuation would turn " into “
    // and -- into — inside HTML / Thymeleaf expressions, autocorrect would rewrite variable names.
    final exact = code || literal;
    final multiline = minLines > 1 || height != null;
    final field = TextFormField(
      key: ValueKey('template_field_$key'),
      controller: _controllers[key],
      readOnly: readOnly,
      expands: height != null,
      minLines: height != null ? null : minLines,
      maxLines: height != null || multiline ? null : 1,
      textAlignVertical: height != null ? TextAlignVertical.top : null,
      keyboardType: multiline ? TextInputType.multiline : null,
      autocorrect: !exact,
      enableSuggestions: !exact,
      smartQuotesType: exact ? SmartQuotesType.disabled : null,
      smartDashesType: exact ? SmartDashesType.disabled : null,
      style: code ? const TextStyle(fontFamily: 'monospace', fontSize: 13) : null,
      decoration: fieldDecoration(
        Theme.of(context).colorScheme,
        label: required ? '${_labels[key]} *' : _labels[key],
        hint: hint,
        helper: helper,
      ).copyWith(alignLabelWithHint: multiline),
      validator: (raw) {
        final v = key == 'htmlBody' ? raw ?? '' : raw?.trim() ?? '';
        if (v.trim().isEmpty) return required ? '${_labels[key]} zorunlu' : null;
        if (max != null && v.length > max) return 'En fazla $max karakter';
        return validator?.call(v);
      },
      onChanged: (_) => _markDirty(),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: height == null ? field : SizedBox(height: height, child: field),
    );
  }

  Widget _form(bool readOnly) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7));
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText(
                _key!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600),
              ),
            )
          else
            _field(
              'templateKey',
              readOnly: readOnly,
              max: 100,
              code: true,
              hint: 'ornek-template-key',
              helper: 'Sadece küçük harf, rakam ve tire. Oluşturulduktan sonra değiştirilemez.',
              validator: (v) => v.length < 2
                  ? 'Minimum 2 karakter'
                  : (templateKeyPattern.hasMatch(v) ? null : 'Sadece küçük harf, rakam ve tire (-) kullanılabilir'),
            ),
          _field(
            'subject',
            readOnly: readOnly,
            literal: true,
            max: 255,
            hint: r'Thymeleaf değişkenleri: [[${userName}]]',
          ),
          _field(
            'description',
            readOnly: readOnly,
            required: false,
            max: 500,
            minLines: 2,
            hint: 'Bu template ne için kullanılıyor?',
          ),
          SwitchListTile(
            key: const ValueKey('template_field_active'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktif'),
            value: _active,
            onChanged: readOnly
                ? null
                : (v) {
                    _markDirty();
                    setState(() => _active = v);
                  },
          ),
          const SizedBox(height: 8),
          // Fixed height, scrolls inside (long templates; the rest of the form stays reachable, also in landscape).
          _field(
            'htmlBody',
            readOnly: readOnly,
            code: true,
            height: MediaQuery.sizeOf(context).height * 0.6,
            hint: '<html>…</html>',
          ),
          if (readOnly) Text('Düzenleme yetkiniz yok (email_templates:manage).', style: muted),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().has('email_templates:manage');
    final Widget body;
    if (_loadError != null) {
      body = ErrorView(message: _loadError!, onRetry: _load);
    } else if (!_ready) {
      body = const LoadingView();
    } else {
      body = _form(!canManage);
    }
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeaveForm(context, saving: _busy) && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        title: _isEditing ? 'Template Düzenle' : 'Yeni Email Template',
        actions: [
          if (_isEditing && _ready) ...[
            IconButton(
              key: const ValueKey('template_preview_button'),
              tooltip: 'Önizle',
              icon: const Icon(Icons.visibility_rounded),
              onPressed: _preview,
            ),
            if (canManage)
              IconButton(
                key: const ValueKey('template_delete_button'),
                tooltip: 'Sil',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _busy ? null : _delete,
              ),
          ],
        ],
        body: body,
        bottomNavigationBar: _ready && canManage
            ? SaveBar(onPressed: _deleting ? null : _save, loading: _saving)
            : null,
      ),
    );
  }
}
