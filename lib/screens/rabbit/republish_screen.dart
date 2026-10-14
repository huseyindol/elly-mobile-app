import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/rabbit_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/info_note.dart';
import '../../widgets/save_bar.dart';

/// Admin `RepublishDialog`: `POST /admin/rabbit/queues/{source}/republish {targetQueue, payload, contentType}`
/// (`rabbit:manage`, 202). Prefilled from a peeked message (pretty JSON, its `content_type`) or empty (manual).
/// Consumers process the message again (e.g. an e-mail is sent again) → confirmation before publishing.
class RepublishScreen extends StatefulWidget {
  final String sourceQueue;

  /// Peeked message; null = manual publish.
  final Map<String, dynamic>? message;
  final ApiService? apiService;

  const RepublishScreen({super.key, required this.sourceQueue, this.message, this.apiService});

  @override
  State<RepublishScreen> createState() => _RepublishScreenState();
}

class _RepublishScreenState extends State<RepublishScreen> {
  static const _labels = {'target': 'Hedef Queue', 'contentType': 'Content Type', 'payload': 'Payload'};

  late final ApiService _api = widget.apiService ?? ApiService();
  final _formKey = GlobalKey<FormState>();
  // DLQ source → its main queue; otherwise empty: the target is chosen on purpose (no silent email-queue).
  late final _target = TextEditingController(text: republishTargetFor(widget.sourceQueue));
  final _contentType = TextEditingController(text: 'application/json');
  final _payload = TextEditingController();
  bool _sending = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final m = widget.message;
    if (m != null) {
      // Raw text: re-indenting would re-encode numbers / whitespace and publish a different message.
      _payload.text = '${m['payload'] ?? ''}';
      final ct = (m['properties'] is Map) ? (m['properties'] as Map)['content_type'] : null;
      if (ct is String && ct.isNotEmpty) _contentType.text = ct;
    }
  }

  @override
  void dispose() {
    for (final c in [_target, _contentType, _payload]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reportInvalidFields(context, invalid, labelOf: _labelOf);
      return;
    }
    final target = _target.text.trim();
    final ok = await showConfirmDialog(
      context,
      title: 'Mesajı Publish Et',
      message:
          'Mesaj "$target" kuyruğuna publish edilecek ve tüketiciler tarafından yeniden işlenecek (ör. e-posta '
          'tekrar gönderilebilir). Kaynak kuyruktaki mesaj silinmez (kopyalanır).',
      confirmLabel: 'Publish Et',
      confirmKey: const ValueKey('confirm_republish_button'),
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      await _api.post(
        queuePath(widget.sourceQueue, '/republish'),
        republishPayload(targetQueue: target, payload: _payload.text, contentType: _contentType.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      showAppSnackBar(context, 'Mesaj yeniden publish edildi');
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAppSnackBar(context, rabbitErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _labelOf(FormFieldState<Object?> state) {
    final key = state.widget.key;
    return key is ValueKey<String> ? _labels[key.value.replaceFirst('republish_', '')] : null;
  }

  void _markDirty(String _) {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height;
    return PopScope(
      canPop: !_dirty && !_sending,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeaveForm(context, saving: _sending) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: AppScaffold(
        title: 'Mesajı Yeniden Publish Et',
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              InputDecorator(
                decoration: fieldDecoration(scheme, label: 'Kaynak Queue'),
                child: Text(widget.sourceQueue, style: const TextStyle(fontFamily: 'monospace')),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('republish_target'),
                controller: _target,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: fieldDecoration(
                  scheme,
                  label: '${_labels['target']} *',
                  hint: 'email-queue',
                  helper: republishTargetFor(widget.sourceQueue).isEmpty
                      ? 'Kaynak bir DLQ değil: mesajın gideceği kuyruğu bilinçli seçin.'
                      : null,
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Hedef queue zorunludur' : null,
                onChanged: _markDirty,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('republish_contentType'),
                controller: _contentType,
                autocorrect: false,
                enableSuggestions: false,
                decoration: fieldDecoration(scheme, label: _labels['contentType']),
                onChanged: (v) {
                  _markDirty(v);
                  setState(() {}); // payload JSON check depends on it
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: height * 0.45,
                child: TextFormField(
                  key: const ValueKey('republish_payload'),
                  controller: _payload,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartQuotesType: SmartQuotesType.disabled,
                  smartDashesType: SmartDashesType.disabled,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: fieldDecoration(
                    scheme,
                    label: '${_labels['payload']} *',
                    hint: '{ "to": "test@example.com", "subject": "..." }',
                  ),
                  validator: (v) => republishPayloadError(v ?? '', _contentType.text),
                  onChanged: _markDirty,
                ),
              ),
              const SizedBox(height: 16),
              const InfoNote('Mesaj default exchange üzerinden hedef queue adıyla (routing key) publish edilir.'),
            ],
          ),
        ),
        bottomNavigationBar: SaveBar(
          onPressed: _send,
          loading: _sending,
          label: 'Publish Et',
          buttonKey: const ValueKey('republish_send'),
        ),
      ),
    );
  }
}
