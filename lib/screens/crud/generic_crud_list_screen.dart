import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/crud_module.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/asset_picker.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/searchable_paged_list.dart';
import 'generic_crud_form_screen.dart';
import '../../widgets/app_snack_bar.dart';

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
  var _listKey = GlobalKey<SearchablePagedListState>();

  /// Filter chip options (value → label) and the selected value (null = Tümü).
  Map<String, String> _filterOptions = const {};
  String? _filterValue;

  Future<void> _fetchItems() async => _listKey.currentState?.reload();

  @override
  void initState() {
    super.initState();
    final filter = widget.module.filter;
    if (filter?.options != null) _filterOptions = filter!.options!;
    if (filter?.optionsEndpoint != null) _loadFilterOptions(filter!.optionsEndpoint!);
  }

  /// Like the admin: no chips when the options can't be loaded or there are none.
  Future<void> _loadFilterOptions(String endpoint) async {
    try {
      final data = await _apiService.get(endpoint);
      if (!mounted || data is! List) return;
      setState(
        () => _filterOptions = {
          for (final v in data)
            if (v != null && '$v'.isNotEmpty) '$v': '$v',
        },
      );
    } catch (_) {}
  }

  void _selectFilter(String? value) {
    setState(() {
      _filterValue = value;
      if (widget.module.filter?.endpointTemplate != null) _listKey = GlobalKey(); // new endpoint → fresh list
    });
  }

  String get _endpoint {
    final template = widget.module.filter?.endpointTemplate;
    final value = _filterValue;
    if (template == null || value == null) return widget.module.listEndpoint;
    return template.replaceAll('{value}', Uri.encodeComponent(value));
  }

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
    showAppSnackBar(context, message, error: error);
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
      // 409 = related records (form submissions: FK conflict) → offer the cascade delete like elly-admin.
      if (force == null || e is! ApiException || e.statusCode != 409 || !mounted) {
        _snack(e.toString(), error: true);
        return;
      }
      final ok = await _confirm(
        'İlişkili kayıtlar mevcut',
        '"$name" ile ilişkili kayıtlar (örn. form gönderimleri) bulunuyor. Tümünü sil seçeneği kaydı ve '
            'bağlı tüm kayıtları kalıcı olarak siler. Bu işlem geri alınamaz.',
        'Evet, Tümünü Sil',
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
        builder: (ctx) => GenericCrudFormScreen(module: widget.module, initialData: item, apiService: _apiService),
      ),
    );

    if (result == true) {
      _fetchItems();
    }
  }

  Widget _buildItem(
    Map<String, dynamic> item, {
    required bool canEdit,
    required bool canDelete,
    required bool canOpenLink,
  }) {
    final module = widget.module;
    final title = resolveListText(item, module.listTitleKey) ?? '#${item['id']}';
    final subtitle = resolveListText(item, module.listSubtitleKey) ?? '';
    final meta = module.listMeta?.call(item) ?? const <String>[];
    final status = module.statusKey == null ? null : getPath(item, module.statusKey!);
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65));
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
        leading: module.thumbnailKey == null
            ? null
            : AssetThumbnail(url: resolveListText(item, module.thumbnailKey!), semanticLabel: title),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle.isNotEmpty) Text(subtitle, style: muted),
            for (final line in meta) Text(line, style: muted.copyWith(fontSize: 12)),
            if (status is bool) ...[const SizedBox(height: 4), _StatusBadge(active: status)],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canOpenLink)
              IconButton(
                key: ValueKey('record_link_${item['id']}'),
                tooltip: module.recordLink!.label,
                icon: Icon(module.recordLink!.icon, color: scheme.onSurface.withValues(alpha: 0.75)),
                onPressed: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => module.recordLink!.builder(item, _apiService))),
              ),
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

  Widget _filterChips(ListFilter filter) {
    Widget chip(String? value, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('filter_${value ?? 'all'}'),
        label: Text(label),
        selected: _filterValue == value,
        onSelected: (_) => _selectFilter(value),
      ),
    );
    return Semantics(
      label: filter.label,
      // No fixed height: large text scales the chips.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [chip(null, 'Tümü'), for (final o in _filterOptions.entries) chip(o.key, o.value)]),
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
    final link = module.recordLink;
    final canOpenLink = link != null && auth.can(module.permissionKey, link.action);
    return AppScaffold(
      title: module.title,
      navId: module.permissionKey,
      actions: [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _fetchItems)],
      body: Column(
        children: [
          if (_filterOptions.isNotEmpty) _filterChips(module.filter!),
          Expanded(
            child: SearchablePagedList(
              key: _listKey,
              api: _apiService,
              endpoint: _endpoint,
              paged: module.paged,
              searchText: (item) => [
                module.listTitleKey,
                module.listSubtitleKey,
              ].map((key) => resolveListText(item, key) ?? '').join(' '),
              itemFilter: module.filter?.key == null || _filterValue == null
                  ? null
                  : (item) => getPath(item, module.filter!.key!)?.toString() == _filterValue,
              compare: module.sortKey == null ? null : (a, b) => compareByKey(a, b, module.sortKey!),
              itemBuilder: (context, item) =>
                  _buildItem(item, canEdit: canEdit, canDelete: canDelete, canOpenLink: canOpenLink),
            ),
          ),
        ],
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

class _StatusBadge extends StatelessWidget {
  final bool active;
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(
        active ? 'Aktif' : 'Pasif',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
