import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../services/text_format.dart';
import '../../widgets/ai_quota_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/searchable_paged_list.dart';

const aiLogActions = <(String?, String)>[
  (null, 'Tümü'),
  ('slug', 'slug'),
  ('seo', 'seo'),
  ('description', 'description'),
  ('alt-text', 'alt-text'),
  ('blog-info', 'blog-info'),
  ('article:outline', 'article:outline'),
  ('article:draft', 'article:draft'),
  ('article:sanitize', 'article:sanitize'),
];

String aiLogsEndpoint({String? action, String? status}) {
  final params = <String>[
    if (action != null && action.isNotEmpty) 'action=${Uri.encodeQueryComponent(action)}',
    if (status != null && status.isNotEmpty) 'status=${Uri.encodeQueryComponent(status)}',
  ];
  return params.isEmpty ? '/ai/logs' : '/ai/logs?${params.join('&')}';
}

class AiLogsScreen extends StatefulWidget {
  final ApiService? apiService;
  const AiLogsScreen({super.key, this.apiService});

  @override
  State<AiLogsScreen> createState() => _AiLogsScreenState();
}

class _AiLogsScreenState extends State<AiLogsScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  var _listKey = GlobalKey<SearchablePagedListState>();
  final _quotaKey = GlobalKey<AiQuotaCardState>();
  String? _action;
  String? _status;
  int? _total;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final res = await _api.get('/ai/stats');
      if (mounted && res is Map) {
        setState(() => _stats = Map<String, dynamic>.from(res));
      }
    } catch (_) {}
  }

  Future<void> _reload() async {
    await Future.wait([
      _loadStats(),
      _quotaKey.currentState?.reload() ?? Future.value(),
      _listKey.currentState?.reload() ?? Future.value(),
    ]);
  }

  void _selectFilter({String? action, bool updateAction = false, String? status, bool updateStatus = false}) {
    setState(() {
      if (updateAction) _action = action;
      if (updateStatus) _status = status;
      _total = null;
      _listKey = GlobalKey<SearchablePagedListState>();
    });
  }

  Widget _statsHeader(ColorScheme scheme) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        key: const ValueKey('ai_stats_card'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _metric(scheme, 'Toplam Çağrı', '${stats['totalCalls'] ?? 0}', muted),
            _metric(
              scheme,
              'Başarılı / Hata',
              '${stats['successCalls'] ?? 0} / ${stats['errorCalls'] ?? 0}',
              muted,
            ),
            _metric(scheme, 'Toplam Token', '${stats['totalTokens'] ?? 0}', muted, primary: true),
            _metric(
              scheme,
              'G / Ç / D Token',
              '${stats['totalInputTokens'] ?? 0} / ${stats['totalOutputTokens'] ?? 0} / ${stats['totalThoughtTokens'] ?? 0}',
              muted,
            ),
            _metric(scheme, 'Ort. Süre', '${stats['avgDurationMs'] ?? 0} ms', muted),
          ],
        ),
      ),
    );
  }

  Widget _metric(ColorScheme scheme, String label, String value, TextStyle muted, {bool primary = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: muted),
      Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          color: primary ? scheme.primary : scheme.onSurface,
        ),
      ),
    ],
  );

  Widget _filterChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              for (final (val, label) in const <(String?, String)>[
                (null, 'Tüm Durumlar'),
                ('SUCCESS', 'Başarılı'),
                ('ERROR', 'Hatalı'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('ai_status_${val ?? 'all'}'),
                    label: Text(label),
                    selected: _status == val,
                    onSelected: (_) => _selectFilter(status: val, updateStatus: true),
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              for (final (val, label) in aiLogActions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('ai_action_${val ?? 'all'}'),
                    label: Text(label),
                    selected: _action == val,
                    onSelected: (_) => _selectFilter(action: val, updateAction: true),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(BuildContext itemContext, Map<String, dynamic> log) {
    final scheme = Theme.of(itemContext).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 12);
    final id = log['id'];
    final ok = log['status'] == 'SUCCESS';
    final errorCode = (log['errorCode'] ?? '').toString();
    final preview = (ok
            ? (log['parsedOutput'] ?? log['responseText'] ?? '')
            : (log['errorMessage'] ?? log['responseText'] ?? ''))
        .toString();
    return Padding(
      key: ValueKey('ai_log_$id'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '${log['action'] ?? ''} · #${log['id'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (ok ? Colors.teal : scheme.error).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  ok ? 'BAŞARILI' : (errorCode.isNotEmpty ? 'HATA · $errorCode' : 'HATA'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ok ? Colors.tealAccent : scheme.error,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              if ((log['userInput']?.toString() ?? '').isNotEmpty)
                Text('İstek: ${log['userInput']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              if (preview.isNotEmpty)
                Text(
                  ok ? 'Sonuç: $preview' : 'Hata: $preview',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ok ? muted : muted.copyWith(color: scheme.error),
                ),
              const SizedBox(height: 4),
              Text(
                'Token: ${log['totalTokens'] ?? 0} (G:${log['inputTokens'] ?? 0} / Ç:${log['outputTokens'] ?? 0} / D:${log['thoughtTokens'] ?? 0}) · '
                '${log['durationMs'] ?? 0} ms · ${formatDateTimeTr(log['createdAt'])}',
                style: muted.copyWith(fontFamily: 'monospace', fontSize: 11),
              ),
            ],
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => AiLogDetailScreen(log: log)),
          ),
        ),
      ),
    );
  }

  void _openQuotaSheet(bool canEditLimit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: AiQuotaCard(
            key: _quotaKey,
            api: _api,
            showManagement: true,
            canEditLimit: canEditLimit,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 12);
    final canEditLimit = (context.watch<AuthProvider?>()?.roleLevel ?? 1) >= 4;
    return AppScaffold(
      title: 'AI Logları',
      navId: 'ai-logs',
      actions: [
        IconButton(
          key: const ValueKey('ai_quota_sheet_button'),
          tooltip: 'AI Kota & Limit',
          icon: const Icon(Icons.auto_awesome_rounded),
          onPressed: () => _openQuotaSheet(canEditLimit),
        ),
        IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reload),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statsHeader(scheme),
          _filterChips(),
          if (_total != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Toplam $_total kayıt', key: const ValueKey('ai_logs_total'), style: muted),
            ),
          Expanded(
            child: SearchablePagedList(
              key: _listKey,
              api: _api,
              endpoint: aiLogsEndpoint(action: _action, status: _status),
              paged: true,
              onLoad: (data) => setState(() => _total = totalCount(data)),
              emptyMessage: 'Henüz AI kullanım log kaydı yok.',
              searchText: (log) => [
                log['action'],
                log['endpoint'],
                log['userInput'],
                log['responseText'],
                log['parsedOutput'],
                log['username'],
              ].map((v) => v ?? '').join(' '),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemBuilder: _item,
            ),
          ),
        ],
      ),
    );
  }
}

class AiLogDetailScreen extends StatelessWidget {
  final Map<String, dynamic> log;
  const AiLogDetailScreen({super.key, required this.log});

  Widget _kv(ColorScheme scheme, String label, Object? value, {bool mono = false}) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            text,
            style: TextStyle(fontFamily: mono ? 'monospace' : null, fontSize: mono ? 12 : 14),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(ColorScheme scheme, String title, Object? content, {bool isError = false}) {
    final text = content?.toString() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isError ? scheme.error : scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isError ? scheme.error.withValues(alpha: 0.12) : scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isError ? scheme.error.withValues(alpha: 0.35) : scheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isError ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppScaffold(
      title: 'AI Çağrısı #${log['id'] ?? ''}',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(scheme, 'Endpoint', log['endpoint'], mono: true),
            _kv(scheme, 'İşlem / Adım', '${log['action'] ?? ''} (Adım #${log['stepOrder'] ?? 1})', mono: true),
            _kv(scheme, 'Model', log['model'], mono: true),
            _kv(scheme, 'Durum', '${log['status'] ?? ''}${log['httpStatus'] != null ? ' (HTTP ${log['httpStatus']})' : ''}'),
            _kv(
              scheme,
              'Token Kırılımı',
              'Toplam: ${log['totalTokens'] ?? 0} · Input: ${log['inputTokens'] ?? 0} · '
              'Output: ${log['outputTokens'] ?? 0} · Thought: ${log['thoughtTokens'] ?? 0} · '
              'Cached: ${log['cachedTokens'] ?? 0}',
              mono: true,
            ),
            _kv(scheme, 'Süre', '${log['durationMs'] ?? 0} ms', mono: true),
            _kv(scheme, 'Kullanıcı', log['username'] ?? 'Sistem'),
            _kv(scheme, 'Tenant', log['tenantId'], mono: true),
            _kv(scheme, 'Request ID', log['requestId'], mono: true),
            _kv(scheme, 'Tarih', formatDateTimeTr(log['createdAt'])),
            _codeBlock(scheme, 'Hata (${log['errorCode'] ?? 'ERROR'})', log['errorMessage'], isError: true),
            _codeBlock(scheme, 'Kullanıcı İsteği (User Input)', log['userInput']),
            _codeBlock(scheme, 'Gönderilen Prompt (${log['promptChars'] ?? 0} karakter)', log['promptText']),
            _codeBlock(scheme, 'AI Ham Yanıtı (${log['responseChars'] ?? 0} karakter)', log['responseText']),
            if (log['parsedOutput'] != null && log['parsedOutput'] != log['responseText'])
              _codeBlock(scheme, 'Ayrıştırılmış Çıktı (Parsed Output)', log['parsedOutput']),
          ],
        ),
      ),
    );
  }
}
