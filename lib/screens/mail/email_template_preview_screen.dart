import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/safe_html_view.dart';
import '../../widgets/state_views.dart';

/// Admin `PreviewPanel`: `POST /email-templates/{key}/preview {data}` renders the **saved** template with test
/// variables (Thymeleaf on the backend); the HTML is untrusted and shown in [SafeHtmlView]. Renders once on open
/// with the admin's default data; "Test verisi" edits the JSON.
class EmailTemplatePreviewScreen extends StatefulWidget {
  final String templateKey;
  final ApiService? apiService;

  /// The edit form has unsaved changes (they are not in the preview).
  final bool unsavedChanges;

  /// Test seam: widget showing the rendered HTML (default [SafeHtmlView]).
  final Widget Function(String html)? htmlViewBuilder;

  const EmailTemplatePreviewScreen({
    super.key,
    required this.templateKey,
    this.apiService,
    this.unsavedChanges = false,
    this.htmlViewBuilder,
  });

  static const defaultData = {'userName': 'Ahmet', 'link': 'https://example.com'};

  @override
  State<EmailTemplatePreviewScreen> createState() => _EmailTemplatePreviewScreenState();
}

class _EmailTemplatePreviewScreenState extends State<EmailTemplatePreviewScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  Map<String, dynamic> _data = Map.of(EmailTemplatePreviewScreen.defaultData);
  String? _html;
  String? _subject;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.post('/email-templates/${Uri.encodeComponent(widget.templateKey)}/preview', {
        'data': _data,
      });
      if (!mounted) return;
      setState(() {
        _html = '${(result as Map?)?['html'] ?? ''}';
        _subject = '${result?['subject'] ?? ''}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editData() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TestDataDialog(initial: _data),
    );
    if (data == null || !mounted) return;
    _data = data;
    _render();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 12);
    final html = _html;
    final Widget content;
    if (_error != null) {
      content = ErrorView(message: _error!, onRetry: _render);
    } else if (html == null) {
      content = const LoadingView(label: 'Render ediliyor');
    } else {
      content = (widget.htmlViewBuilder ?? (h) => SafeHtmlView(key: ValueKey(h), html: h))(html);
    }
    return AppScaffold(
      title: 'Önizleme',
      actions: [
        IconButton(
          key: const ValueKey('preview_data_button'),
          tooltip: 'Test verisi',
          icon: const Icon(Icons.data_object_rounded),
          onPressed: _loading ? null : _editData,
        ),
        IconButton(
          tooltip: 'Yeniden render et',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _render,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2, semanticsLabel: 'Render ediliyor'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.templateKey,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
                if (_subject != null && _error == null) ...[
                  const SizedBox(height: 4),
                  Text('Konu: $_subject', key: const ValueKey('preview_subject')),
                ],
                if (widget.unsavedChanges) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Önizleme kayıtlı sürümü gösterir; kaydedilmemiş değişiklikler görünmez.',
                    key: const ValueKey('preview_unsaved_note'),
                    style: muted.copyWith(color: AppColors.warning),
                  ),
                ],
                const SizedBox(height: 4),
                Text('Güvenlik için betikler, bağlantılar ve uzak görseller kapalı.', style: muted),
              ],
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _TestDataDialog extends StatefulWidget {
  final Map<String, dynamic> initial;
  const _TestDataDialog({required this.initial});

  @override
  State<_TestDataDialog> createState() => _TestDataDialogState();
}

class _TestDataDialogState extends State<_TestDataDialog> {
  late final _controller = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(widget.initial));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    try {
      final value = jsonDecode(_controller.text);
      if (value is! Map) {
        setState(() => _error = 'Test verisi bir JSON nesnesi olmalı ({ … })');
        return;
      }
      Navigator.of(context).pop(Map<String, dynamic>.from(value));
    } on FormatException {
      setState(() => _error = 'Geçersiz JSON formatı');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surface,
      title: const Text('Test Verisi (JSON)'),
      content: SingleChildScrollView(
        child: TextField(
          key: const ValueKey('preview_data_field'),
          controller: _controller,
          minLines: 6,
          maxLines: 14,
          autocorrect: false,
          enableSuggestions: false,
          smartQuotesType: SmartQuotesType.disabled,
          smartDashesType: SmartDashesType.disabled,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: fieldDecoration(scheme).copyWith(errorText: _error, errorMaxLines: 3),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        ElevatedButton(key: const ValueKey('preview_data_apply'), onPressed: _apply, child: const Text('Render Et')),
      ],
    );
  }
}
