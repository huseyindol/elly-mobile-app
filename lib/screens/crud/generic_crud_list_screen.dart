import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crud_module.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/searchable_paged_list.dart';
import 'generic_crud_form_screen.dart';

class GenericCrudListScreen extends StatefulWidget {
  final CrudModule module;

  /// Test seam: lets tests inject an [ApiService] with a mock http client.
  final ApiService? apiService;

  const GenericCrudListScreen({super.key, required this.module, this.apiService});

  @override
  State<GenericCrudListScreen> createState() => _GenericCrudListScreenState();
}

class _GenericCrudListScreenState extends State<GenericCrudListScreen> {
  late final ApiService _apiService = widget.apiService ?? ApiService();
  final _listKey = GlobalKey<SearchablePagedListState>();

  Future<void> _fetchItems() async => _listKey.currentState?.reload();

  Future<bool> _confirm(String title, String message, String action) => showConfirmDialog(
        context,
        title: title,
        message: message,
        confirmLabel: action,
        destructive: true,
        confirmKey: const ValueKey('confirm_delete_button'),
      );

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: Duration(seconds: error ? 6 : 2),
    ));
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = item['id'];
    final name = resolveListText(item, widget.module.listTitleKey) ?? '#$id';
    if (!await _confirm('Silinsin mi?', '"$name" kalıcı olarak silinecek.', 'Sil')) return;

    final endpoint = '${widget.module.crudEndpoint}/$id';
    try {
      await _apiService.delete(endpoint);
      _snack('Silindi');
    } catch (e) {
      final force = widget.module.forceDeleteSuffix;
      if (force == null || !mounted) {
        _snack(e.toString(), error: true);
        return;
      }
      // e.g. form has submissions → FK conflict; offer cascade delete like elly-admin.
      final ok = await _confirm(
        'Silinemedi',
        '$e\n\nBağlı kayıtlarla (örn. form gönderimleri) birlikte zorla silinsin mi?',
        'Zorla Sil',
      );
      if (!ok) return;
      try {
        await _apiService.delete('$endpoint$force');
        _snack('Silindi');
      } catch (e2) {
        _snack(e2.toString(), error: true);
        return;
      }
    }
    _fetchItems();
  }

  void _navigateToForm([Map<String, dynamic>? item]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => GenericCrudFormScreen(
          module: widget.module,
          initialData: item,
        ),
      ),
    );

    if (result == true) {
      _fetchItems();
    }
  }

  Widget _buildItem(Map<String, dynamic> item, {required bool canEdit, required bool canDelete}) {
    final title = resolveListText(item, widget.module.listTitleKey) ?? '#${item['id']}';
    final subtitle = resolveListText(item, widget.module.listSubtitleKey) ?? '';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('crud_item_${item['id']}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit)
              IconButton(
                key: ValueKey('edit_${item['id']}'),
                tooltip: 'Düzenle',
                icon: Icon(Icons.edit_rounded, color: scheme.onSurface.withValues(alpha: 0.75)),
                onPressed: () => _navigateToForm(item),
              ),
            if (canDelete)
              IconButton(
                key: ValueKey('delete_${item['id']}'),
                tooltip: 'Sil',
                icon: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
                onPressed: () => _deleteItem(item),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final module = widget.module;
    final canCreate = module.canCreate && auth.can(module.permissionKey, 'create');
    final canEdit = module.canEdit && auth.can(module.permissionKey, 'update');
    final canDelete = module.canDelete && auth.can(module.permissionKey, 'delete');
    return AppScaffold(
      title: module.title,
      navId: module.permissionKey,
      actions: [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _fetchItems)],
      body: SearchablePagedList(
        key: _listKey,
        api: _apiService,
        endpoint: module.listEndpoint,
        paged: module.paged,
        searchText: (item) =>
            [module.listTitleKey, module.listSubtitleKey].map((key) => resolveListText(item, key) ?? '').join(' '),
        itemBuilder: (context, item) => _buildItem(item, canEdit: canEdit, canDelete: canDelete),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              tooltip: 'Yeni kayıt',
              onPressed: () => _navigateToForm(),
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}
