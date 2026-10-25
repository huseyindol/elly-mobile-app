import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../services/mail_payload.dart';
import '../../services/text_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/searchable_paged_list.dart';
import '../../widgets/status_badge.dart';

/// Admin `email-logs`: `GET /emails` newest first, paged, server-side status filter (`emails:read`); detail and
/// "Tekrar dene" (`POST /emails/{id}/retry`, `emails:retry`, not for SENT). The backend log DTO has no error
/// message / body, and there is no detail endpoint — the detail shows the list row.
class EmailLogsScreen extends StatefulWidget {
  final ApiService? apiService;
  const EmailLogsScreen({super.key, this.apiService});

  @override
  State<EmailLogsScreen> createState() => _EmailLogsScreenState();
}

class _EmailLogsScreenState extends State<EmailLogsScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  var _listKey = GlobalKey<SearchablePagedListState>();
  String? _status; // null = Tümü
  int? _total;
  Map<String, dynamic>? _stats;
  final Set<Object?> _retrying = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final data = await _api.get('/emails/stats');
      if (mounted && data is Map) {
        setState(() => _stats = Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // Best-effort stats bar: ignore if offline or mocked in existing tests.
    }
  }

  Future<void> _reload() async {
    await _loadStats();
    await _listKey.currentState?.reload();
  }

  void _selectStatus(String? status) => setState(() {
    _status = status;
    _total = null;
    _listKey = GlobalKey(); // new endpoint → fresh list
  });

  Future<void> _retry(Map<String, dynamic> log) async {
    if (!await confirmEmailRetry(context, log) || !mounted) return;
    setState(() => _retrying.add(log['id']));
    final ok = await retryEmail(context, _api, log);
    if (!mounted) return;
    setState(() => _retrying.remove(log['id']));
    if (ok) _reload();
  }

  Future<void> _openDetail(Map<String, dynamic> log) async {
    final retried = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmailLogDetailScreen(log: log, apiService: _api),
      ),
    );
    if (retried == true) _reload();
  }

  // Retry results use the screen's context (this.context via _retry): a list reload may dispose the row.
  Widget _item(BuildContext itemContext, Map<String, dynamic> log, bool canRetry) {
    final scheme = Theme.of(itemContext).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65));
    final id = log['id'];
    final retrying = _retrying.contains(id);
    return Padding(
      key: ValueKey('email_log_$id'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          title: Text('${log['recipient'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${log['subject'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              Text('#$id · ${log['templateName'] ?? ''}', style: muted.copyWith(fontFamily: 'monospace', fontSize: 12)),
              Text(
                'Deneme: ${log['retryCount'] ?? 0} · ${formatDateTimeTr(log['createdAt'])}',
                style: muted.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 4),
              EmailStatusBadge(status: log['status']),
            ],
          ),
          trailing: canRetry && canRetryEmail(log)
              ? IconButton(
                  key: ValueKey('retry_$id'),
                  tooltip: 'Yeniden kuyruğa al: #$id',
                  onPressed: retrying ? null : () => _retry(log),
                  icon: retrying
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Kuyruğa alınıyor'),
                        )
                      : const Icon(Icons.replay_rounded),
                )
              : null,
          onTap: () => _openDetail(log),
        ),
      ),
    );
  }

  Widget _statusChips() {
    Widget chip(String? value) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('status_${value ?? 'all'}'),
        label: Text(value == null ? 'Tümü' : emailStatusLabels[value]!),
        selected: _status == value,
        onSelected: (_) => _selectStatus(value),
      ),
    );
    return Semantics(
      label: 'Durum',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [chip(null), for (final s in emailStatusLabels.keys) chip(s)]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRetry = context.watch<AuthProvider>().has('emails:retry');
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12);
    return AppScaffold(
      title: 'Email Logları',
      navId: 'email-logs',
      actions: [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reload)],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((_stats?['failedLast24hCount'] as num? ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                key: const ValueKey('email_logs_24h_alert'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Son 24 saatte ${_stats!['failedLast24hCount']} başarısız / kota aşımı gönderim var.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _statusChips(),
          if (_total != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Toplam $_total kayıt', key: const ValueKey('email_logs_total'), style: muted),
            ),
          Expanded(
            child: SearchablePagedList(
              key: _listKey,
              api: _api,
              endpoint: emailLogsEndpoint(_status),
              paged: true,
              onLoad: (data) => setState(() => _total = totalCount(data)),
              emptyMessage: _status == null
                  ? 'Henüz email log kaydı yok.'
                  : '"${emailStatusLabels[_status]}" durumunda kayıt yok.',
              searchText: (log) =>
                  [log['recipient'], log['subject'], log['templateName']].map((v) => v ?? '').join(' '),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemBuilder: (itemContext, log) => _item(itemContext, log, canRetry),
            ),
          ),
        ],
      ),
    );
  }
}

/// `POST /emails/{id}/retry`: re-queues a FAILED / stuck PENDING e-mail (status → PENDING, retry count 0). The
/// backend refuses SENT logs, logs without a mail account and inactive accounts (400, message shown).
/// A PENDING mail may still be in the queue: re-queueing it can send it twice, so that asks first (true = go on).
Future<bool> confirmEmailRetry(BuildContext context, Map<String, dynamic> log) async =>
    log['status'] != 'PENDING' ||
    await showConfirmDialog(
      context,
      title: 'Yeniden kuyruğa alınsın mı?',
      message:
          'Bu mail hâlâ "Beklemede"; kuyrukta olabilir. Yeniden kuyruğa almak iki kez gönderilmesine yol açabilir.',
      confirmLabel: 'Kuyruğa al',
      confirmKey: const ValueKey('confirm_retry_button'),
    );

/// Pass the screen's context (not a list row's).
Future<bool> retryEmail(BuildContext context, ApiService api, Map<String, dynamic> log) async {
  try {
    await api.post('/emails/${log['id']}/retry', const {});
    if (context.mounted) showAppSnackBar(context, 'Mail yeniden kuyruğa alındı');
    return true;
  } catch (e) {
    if (context.mounted) showAppSnackBar(context, e.toString(), error: true);
    return false;
  }
}

/// PENDING amber · SENT green · FAILED red (admin `EmailLogStatusBadge`).
class EmailStatusBadge extends StatelessWidget {
  final Object? status;
  const EmailStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: emailStatusLabels[status] ?? '${status ?? ''}',
    color: switch (status) {
      'SENT' => AppColors.success,
      'PENDING' => AppColors.warning,
      'QUOTA_EXCEEDED' => AppColors.warning,
      'FAILED' => Theme.of(context).colorScheme.onErrorContainer,
      _ => null,
    },
  );
}

/// Admin `EmailLogDetailSheet`.
class EmailLogDetailScreen extends StatefulWidget {
  final Map<String, dynamic> log;
  final ApiService? apiService;
  const EmailLogDetailScreen({super.key, required this.log, this.apiService});

  @override
  State<EmailLogDetailScreen> createState() => _EmailLogDetailScreenState();
}

class _EmailLogDetailScreenState extends State<EmailLogDetailScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  bool _retrying = false;

  Future<void> _retry() async {
    if (!await confirmEmailRetry(context, widget.log) || !mounted) return;
    setState(() => _retrying = true);
    final ok = await retryEmail(context, _api, widget.log);
    if (!mounted) return;
    setState(() => _retrying = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.65), fontSize: 12);
    final log = widget.log;
    final canRetry = context.watch<AuthProvider>().has('emails:retry');
    final sent = !canRetryEmail(log);
    final sentAt = formatDateTimeTr(log['sentAt']);
    final errorMessage = '${log['errorMessage'] ?? ''}'.trim();
    final cc = '${log['cc'] ?? ''}'.trim();
    final bcc = '${log['bcc'] ?? ''}'.trim();
    final rows = [
      ('Alıcı (TO)', '${log['recipient'] ?? ''}', true),
      if (cc.isNotEmpty) ('CC', cc, true),
      if (bcc.isNotEmpty) ('BCC', bcc, true),
      ('Konu', '${log['subject'] ?? ''}', false),
      ('Template', '${log['templateName'] ?? ''}', true),
      ('Deneme sayısı', '${log['retryCount'] ?? 0}', false),
      ('Oluşturulma', formatDateTimeTr(log['createdAt']), false),
      ('Gönderim', sentAt.isEmpty ? 'Henüz gönderilmedi' : sentAt, false),
    ];
    return AppScaffold(
      title: 'Mail #${log['id']}',
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: EmailStatusBadge(status: log['status']),
          ),
          const SizedBox(height: 16),
          for (final (label, value, mono) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: muted),
                    const SizedBox(height: 2),
                    SelectableText(value, style: mono ? const TextStyle(fontFamily: 'monospace') : null),
                  ],
                ),
              ),
            ),
          if (errorMessage.isNotEmpty)
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hata Mesajı',
                    style: muted.copyWith(color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      errorMessage,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: canRetry
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sent) Text('Gönderilmiş mail yeniden kuyruğa alınamaz.', style: muted),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        key: const ValueKey('email_log_retry_button'),
                        onPressed: sent || _retrying ? null : _retry,
                        icon: _retrying
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Kuyruğa alınıyor'),
                              )
                            : const Icon(Icons.replay_rounded),
                        label: const Text('Yeniden kuyruğa al'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
