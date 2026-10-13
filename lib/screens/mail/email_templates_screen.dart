import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/text_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/searchable_paged_list.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import 'email_template_form_screen.dart';

/// Admin `email-templates`: DB Thymeleaf templates (`GET /email-templates`, paged, `email_templates:read`) +
/// the read-only classpath template names (`GET /emails/templates`, `emails:read`). Custom screen: templates are
/// addressed by `templateKey`, not id, and have a preview.
class EmailTemplatesScreen extends StatefulWidget {
  final ApiService? apiService;
  const EmailTemplatesScreen({super.key, this.apiService});

  @override
  State<EmailTemplatesScreen> createState() => _EmailTemplatesScreenState();
}

class _EmailTemplatesScreenState extends State<EmailTemplatesScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  final _listKey = GlobalKey<SearchablePagedListState>();

  Future<void> _reload() async => _listKey.currentState?.reload();

  Future<void> _open([String? key]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailTemplateFormScreen(templateKey: key, apiService: _api),
      ),
    );
    _reload(); // the edit screen saves in place (admin stays on the page), so always refresh
  }

  Future<void> _delete(String key) async {
    if (await confirmDeleteTemplate(context, key) && mounted) {
      try {
        await _api.delete('/email-templates/${Uri.encodeComponent(key)}');
        if (mounted) showAppSnackBar(context, 'Template silindi');
        _reload();
      } catch (e) {
        if (mounted) showAppSnackBar(context, e.toString(), error: true);
      }
    }
  }

  void _showClasspath() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ClasspathTemplates(api: _api),
  );

  Widget _item(BuildContext context, Map<String, dynamic> t, bool canManage) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65));
    final key = '${t['templateKey'] ?? ''}';
    final updated = formatDateTimeTr(t['updatedAt'] ?? t['createdAt']);
    return Padding(
      key: ValueKey('template_$key'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Text(
            key,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t['subject'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
              if (updated.isNotEmpty) Text('Güncelleme: $updated', style: muted.copyWith(fontSize: 12)),
              // Backend falls back to the global (tenantId null) template; editing it changes every tenant's copy.
              if (t['tenantId'] == null) Text('Genel şablon', style: muted.copyWith(fontSize: 12)),
              const SizedBox(height: 4),
              StatusBadge.active(t['active'] == true),
            ],
          ),
          trailing: canManage
              ? IconButton(
                  key: ValueKey('delete_$key'),
                  tooltip: 'Sil',
                  icon: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
                  onPressed: () => _delete(key),
                )
              : null,
          onTap: () => _open(key),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManage = auth.has('email_templates:manage');
    return AppScaffold(
      title: 'Email Templates',
      navId: 'email-templates',
      actions: [
        if (auth.has('emails:read'))
          IconButton(
            key: const ValueKey('classpath_templates_button'),
            tooltip: 'Classpath şablonları',
            icon: const Icon(Icons.folder_zip_outlined),
            onPressed: _showClasspath,
          ),
        IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reload),
      ],
      body: SearchablePagedList(
        key: _listKey,
        api: _api,
        endpoint: '/email-templates',
        paged: true,
        emptyMessage: 'Henüz email template yok.',
        searchText: (t) => [t['templateKey'], t['subject'], t['description']].map((v) => v ?? '').join(' '),
        itemBuilder: (context, t) => _item(context, t, canManage),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              tooltip: 'Yeni Template',
              onPressed: () => _open(),
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}

/// Admin `DestructiveConfirmDialog`: the key must be typed to delete.
Future<bool> confirmDeleteTemplate(BuildContext context, String key) => showConfirmDialog(
  context,
  title: 'Template Sil',
  message: '"$key" template\'i kalıcı olarak silinecek. Bu işlem geri alınamaz.',
  confirmLabel: 'Template\'i Sil',
  destructive: true,
  requiredText: key,
  confirmKey: const ValueKey('confirm_delete_button'),
);

/// Admin `ClasspathTemplateSection`: static Thymeleaf files in the backend JAR (read-only names).
class _ClasspathTemplates extends StatefulWidget {
  final ApiService api;
  const _ClasspathTemplates({required this.api});

  @override
  State<_ClasspathTemplates> createState() => _ClasspathTemplatesState();
}

class _ClasspathTemplatesState extends State<_ClasspathTemplates> {
  late Future<dynamic> _future = widget.api.get('/emails/templates');

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: FutureBuilder<dynamic>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
            if (snapshot.hasError) {
              return ErrorView(
                message: '${snapshot.error}',
                onRetry: () => setState(() => _future = widget.api.get('/emails/templates')),
              );
            }
            final names = [for (final n in snapshot.data is List ? snapshot.data as List : const []) '$n'];
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Classpath Template\'leri (${names.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('JAR içindeki statik Thymeleaf dosyaları (salt okunur)', style: muted),
                const SizedBox(height: 8),
                if (names.isEmpty) Text('Classpath template\'i yok.', style: muted),
                for (final name in names)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.mail_outline_rounded),
                    title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
