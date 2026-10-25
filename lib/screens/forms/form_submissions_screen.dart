import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/form_schema.dart';
import '../../services/text_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/searchable_paged_list.dart';

/// Admin `forms/[id]/submissions`: newest first, paged, values labelled by the form schema
/// (`forms:read`). The admin has no submission delete / export and the backend no endpoint for them.
class FormSubmissionsScreen extends StatefulWidget {
  /// Form record (list or detail DTO: `id`, `title`, `schema`).
  final Map<String, dynamic> form;
  final ApiService? apiService;

  const FormSubmissionsScreen({super.key, required this.form, this.apiService});

  @override
  State<FormSubmissionsScreen> createState() => _FormSubmissionsScreenState();
}

class _FormSubmissionsScreenState extends State<FormSubmissionsScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  late final List<Map<String, dynamic>> _fields = schemaFields(
    (widget.form['schema'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
  final _listKey = GlobalKey<SearchablePagedListState>();
  int? _count;

  String get _id => Uri.encodeComponent('${widget.form['id']}');

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  /// Admin header "N yanıt"; hidden when the count can't be loaded.
  Future<void> _loadCount() async {
    try {
      final count = await _api.get('/forms/$_id/submissions/count');
      if (mounted) setState(() => _count = (count as num?)?.toInt());
    } catch (_) {}
  }

  Future<void> _reload() async {
    await Future.wait([_loadCount(), if (_listKey.currentState != null) _listKey.currentState!.reload()]);
  }

  Future<void> _exportCsv() async {
    try {
      final res = await _api.get('/forms/$_id/submissions/export');
      final map = (res as Map?)?.cast<String, dynamic>() ?? const {};
      final csv = '${map['csvContent'] ?? ''}';
      final count = (map['count'] as num?)?.toInt() ?? 0;
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count yanıt CSV olarak panoya kopyalandı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV dışa aktarma başarısız: $e')),
      );
    }
  }

  Future<void> _cleanupOldSubmissions() async {
    try {
      final res = await _api.delete('/forms/$_id/submissions/cleanup?retentionDays=365');
      final map = (res as Map?)?.cast<String, dynamic>() ?? const {};
      final deleted = (map['deletedCount'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KVKK temizliği tamamlandı ($deleted eski kayıt silindi).')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KVKK temizliği başarısız: $e')),
      );
    }
  }

  Widget _item(BuildContext context, Map<String, dynamic> submission) {
    final scheme = Theme.of(context).colorScheme;
    final payload = submissionPayload(submission);
    final lines = [
      for (final f in _fields)
        if (payload.containsKey(f['id'])) '${fieldLabel(f)}: ${formatPayloadValue(payload[f['id']], f)}',
    ];
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65));
    return Padding(
      key: ValueKey('submission_${submission['id']}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.7),
        shape: _cardShape(scheme),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Text(formatDateTimeTr(submission['submittedAt']), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines.take(3)) Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              if (lines.length > 3) Text('+${lines.length - 3} alan', style: muted.copyWith(fontSize: 12)),
            ],
          ),
          trailing: Text('#${submission['id']}', style: muted.copyWith(fontFamily: 'monospace', fontSize: 12)),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FormSubmissionDetailScreen(submission: submission, fields: _fields),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.form['title'] ?? 'Yanıtlar'}';
    final canDelete = context.watch<AuthProvider?>()?.has('forms:delete') ?? false;
    return AppScaffold(
      title: 'Yanıtlar',
      actions: [
        IconButton(
          tooltip: 'CSV Dışa Aktar',
          icon: const Icon(Icons.download_rounded),
          onPressed: _exportCsv,
        ),
        if (canDelete)
          IconButton(
            tooltip: 'KVKK Eski Yanıtları Temizle',
            icon: const Icon(Icons.cleaning_services_rounded),
            onPressed: _cleanupOldSubmissions,
          ),
        IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reload),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Semantics(
              header: true,
              child: Text(
                _count == null ? title : '$title · $_count yanıt',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Expanded(
            child: SearchablePagedList(
              key: _listKey,
              api: _api,
              endpoint: '/forms/$_id/submissions/paged?sort=submittedAt,desc',
              paged: true,
              emptyMessage: 'Henüz yanıt yok.',
              onRefresh: _loadCount,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemBuilder: _item,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> submissionPayload(Map<String, dynamic> submission) =>
    (submission['payload'] as Map?)?.cast<String, dynamic>() ?? const {};

/// One submission: schema fields (form order, labels, option labels) and then payload keys the current
/// schema doesn't have (e.g. a field removed later) under their raw key.
class FormSubmissionDetailScreen extends StatelessWidget {
  final Map<String, dynamic> submission;
  final List<Map<String, dynamic>> fields;

  const FormSubmissionDetailScreen({super.key, required this.submission, required this.fields});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.65), fontSize: 12);
    final payload = submissionPayload(submission);
    final known = {for (final f in fields) '${f['id']}'};
    final rows = [
      for (final f in fields)
        if (payload.containsKey(f['id'])) (fieldLabel(f), formatPayloadValue(payload[f['id']], f)),
      for (final e in payload.entries)
        if (!known.contains(e.key)) (e.key, formatPayloadValue(e.value, null)),
    ];
    return AppScaffold(
      title: 'Yanıt #${submission['id']}',
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(formatDateTimeTr(submission['submittedAt']), style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          if (rows.isEmpty) Text('Bu yanıtta veri yok.', style: muted),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: muted),
                    const SizedBox(height: 2),
                    SelectableText(value),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

ShapeBorder _cardShape(ColorScheme scheme) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(16),
  side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.05)),
);
