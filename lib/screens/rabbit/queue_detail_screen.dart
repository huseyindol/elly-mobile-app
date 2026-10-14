import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/rabbit_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/info_note.dart';
import '../../widgets/status_badge.dart';
import 'rabbit_screen.dart' show QueueStateBadge, purgeQueue;
import 'republish_screen.dart';

/// Admin `QueueDetailSheet` + `MessageList`: `GET /admin/rabbit/queues/{name}`, peek on request
/// (`GET …/messages?count=1..100`), republish / purge with `rabbit:manage`. Payloads and properties are untrusted
/// text: shown as plain (selectable) monospace text, never rendered.
class QueueDetailScreen extends StatefulWidget {
  /// List row (shown until the fresh detail arrives).
  final Map<String, dynamic> queue;
  final ApiService? apiService;

  const QueueDetailScreen({super.key, required this.queue, this.apiService});

  @override
  State<QueueDetailScreen> createState() => _QueueDetailScreenState();
}

class _QueueDetailScreenState extends State<QueueDetailScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  late Map<String, dynamic> _queue = widget.queue;
  final _count = TextEditingController(text: '$peekDefault');
  String? _detailError;
  List<Map<String, dynamic>>? _messages;
  String? _messagesError;
  bool _peeking = false;

  String get _name => '${widget.queue['name']}';

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final data = await _api.get(queuePath(_name));
      if (mounted && data is Map) {
        setState(() {
          _queue = Map<String, dynamic>.from(data);
          _detailError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _detailError = rabbitErrorText(e));
    }
  }

  /// Peek is not automatic (admin: it should not feel destructive); messages are requeued by the backend.
  Future<void> _peek() async {
    final count = clampPeekCount(int.tryParse(_count.text));
    _count.text = '$count';
    setState(() {
      _peeking = true;
      _messagesError = null;
    });
    try {
      final data = await _api.get('${queuePath(_name, '/messages')}?count=$count');
      if (!mounted) return;
      setState(() => _messages = [for (final m in (data as List? ?? const [])) Map<String, dynamic>.from(m as Map)]);
    } catch (e) {
      if (mounted) setState(() => _messagesError = rabbitErrorText(e));
    } finally {
      if (mounted) setState(() => _peeking = false);
    }
  }

  Future<void> _republish([Map<String, dynamic>? message]) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RepublishScreen(sourceQueue: _name, message: message, apiService: _api),
      ),
    );
    if (sent == true && mounted) _loadDetail();
  }

  Future<void> _purge() async {
    if (await purgeQueue(context, _api, _queue) && mounted) {
      setState(() => _messages = null);
      _loadDetail();
    }
  }

  Widget _kv(String key, Object? value) {
    final scheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(key, style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.65))),
            Text('${value ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  static String _yesNo(Object? v) => v == null ? '—' : (v == true ? 'evet' : 'hayır');

  Widget _code(String text, {Key? key}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
      child: SelectableText(
        text,
        key: key,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _message(int index, Map<String, dynamic> m, bool canManage) {
    final payload = '${m['payload'] ?? ''}';
    final base64 = m['payloadEncoding'] == 'base64';
    return Card(
      key: ValueKey('message_$index'),
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
      child: ExpansionTile(
        shape: const Border(),
        title: Text(
          '#${index + 1} · ${'${m['routingKey'] ?? ''}'.isEmpty ? '—' : m['routingKey']}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        subtitle: Wrap(
          spacing: 6,
          children: [
            if (m['redelivered'] == true) const StatusBadge(label: 'redelivered', color: AppColors.warning),
            if (base64) const StatusBadge(label: 'base64'),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payload', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          _code(clipText(prettyPayload(payload)), key: ValueKey('message_payload_$index')),
          const SizedBox(height: 8),
          Text('Properties', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          _code(const JsonEncoder.withIndent('  ').convert(m['properties'] ?? const {})),
          if (canManage)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: ValueKey('republish_message_$index'),
                // base64 bodies are binary: republishing the text would publish different bytes.
                onPressed: base64 ? null : () => _republish(m),
                icon: const Icon(Icons.replay_rounded),
                label: Text(base64 ? 'Republish (base64 desteklenmiyor)' : 'Republish'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _messagesSection(bool canManage) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Semantics(header: true, child: Text('Son Mesajlar (peek)', style: Theme.of(context).textTheme.titleSmall)),
      const SizedBox(height: 8),
      const InfoNote(
        'Peek mesajları kuyruktan silmez; okunan mesajlar yeniden kuyruğa alınır ve "redelivered" '
        'işaretlenebilir.',
      ),
      Row(
        children: [
          SizedBox(
            width: 96,
            child: TextField(
              key: const ValueKey('peek_count'),
              controller: _count,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: fieldDecoration(scheme, label: 'Adet'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('peek_button'),
              onPressed: _peeking ? null : _peek,
              icon: _peeking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Mesajlar yükleniyor'),
                    )
                  : const Icon(Icons.visibility_rounded),
              label: Text(_messages == null ? 'Mesajları Göster' : 'Yenile'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_messagesError != null)
        Text(_messagesError!, style: TextStyle(color: scheme.onErrorContainer))
      else if (_messages != null && _messages!.isEmpty)
        Text('Kuyrukta mesaj yok.', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)))
      else if (_messages != null)
        for (var i = 0; i < _messages!.length; i++) _message(i, _messages![i], canManage),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canManage = context.watch<AuthProvider>().has('rabbit:manage');
    final q = _queue;
    final total = countOf(q['messages']);
    final args = q['arguments'];
    return AppScaffold(
      title: _name,
      actions: [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _loadDetail)],
      body: RefreshIndicator(
        onRefresh: _loadDetail,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_detailError != null) ...[
              _ErrorBanner(message: _detailError!, onRetry: _loadDetail),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    q['vhost'] == null ? '' : 'vhost: ${q['vhost']}',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                  ),
                ),
                QueueStateBadge(state: q['state']?.toString()),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kv('Mesaj', total),
                _kv('Ready', countOf(q['messagesReady'])),
                _kv('Unacked', countOf(q['messagesUnacknowledged'])),
                _kv('Consumer', countOf(q['consumers'])),
                _kv('Durable', _yesNo(q['durable'])),
                _kv('Auto-delete', _yesNo(q['autoDelete'])),
                _kv('Policy', q['policy'] ?? '—'),
              ],
            ),
            if (args is Map && args.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Arguments', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              _code(const JsonEncoder.withIndent('  ').convert(args)),
            ],
            if (canManage) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('manual_republish'),
                    onPressed: () => _republish(),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Manuel Republish'),
                  ),
                  ElevatedButton.icon(
                    key: const ValueKey('detail_purge'),
                    style: ElevatedButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                    onPressed: total == 0 ? null : _purge,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(total == 0 ? 'Kuyruk boş' : 'Purge ($total)'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            ..._messagesSection(canManage),
          ],
        ),
      ),
    );
  }
}

/// Inline error with a retry (a stale list row stays visible under it).
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
      ],
    );
  }
}
