import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/modules_config.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/asset_picker.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/searchable_paged_list.dart';
import '../widgets/state_views.dart';

/// Backend paged asset list for a folder and/or name search (admin `assets/page.tsx` + folder browsing
/// via `/assets/list/{subFolder}/paged`). Newest first like the previous mobile list.
String assetsEndpoint({String? folder, String? name}) {
  String seg(String v) => Uri.encodeComponent(v);
  final hasFolder = folder != null && folder.isNotEmpty;
  final hasName = name != null && name.trim().isNotEmpty;
  final path = switch ((hasFolder, hasName)) {
    (true, true) => '/assets/${seg(folder!)}/${seg(name!.trim())}/paged',
    (false, true) => '/assets/${seg(name!.trim())}/paged',
    (true, false) => '/assets/list/${seg(folder!)}/paged',
    (false, false) => '/assets/list/paged',
  };
  return '$path?sort=id,desc';
}

/// Assets (Medya): folder chips, server-side search by name or id, preview, copy URL, replace file,
/// delete, multi-select bulk delete and single/multi upload into a folder.
/// Own screen instead of the generic CRUD list: server search, multi upload and bulk delete don't fit it.
class AssetsScreen extends StatefulWidget {
  /// Test seam: lets tests inject an [ApiService] with a mock http client.
  final ApiService? apiService;

  const AssetsScreen({super.key, this.apiService});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  static final _module = ModulesConfig.byKey('assets');

  late final ApiService _api = widget.apiService ?? ApiService();
  final _search = TextEditingController();
  var _listKey = GlobalKey<SearchablePagedListState>();
  List<String> _folders = const [];
  String? _folder;
  String? _name; // submitted name search
  String? _id; // submitted id search
  bool _searchById = false;

  /// Selected asset id → name (names for the bulk delete confirmation).
  final Map<Object, String> _selected = {};

  /// A delete / bulk delete / replace is running: actions are locked.
  bool _busy = false;

  /// Admin `ImageUploadBox` limit, also applied when replacing an image asset.
  static const _maxImageBytes = 5 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    try {
      final data = await _api.get('/assets/sub-folders');
      if (!mounted || data is! List) return;
      setState(
        () => _folders = [
          for (final f in data)
            if (f != null && '$f'.isNotEmpty) '$f',
        ],
      );
    } catch (_) {} // like the admin: no folder chips when they can't be loaded
  }

  void _reload() {
    setState(() => _listKey = GlobalKey());
    _loadFolders();
  }

  void _submitSearch() {
    final value = _search.text.trim();
    if (_searchById && value.isNotEmpty && int.tryParse(value) == null) {
      _snack('ID bir sayı olmalı', error: true);
      return;
    }
    setState(() {
      _id = _searchById && value.isNotEmpty ? value : null;
      _name = !_searchById && value.isNotEmpty ? value : null;
      _selected.clear(); // ids of another result set must not be deleted unseen
      _listKey = GlobalKey();
    });
  }

  void _clearSearch() {
    _search.clear();
    setState(() {
      _id = null;
      _name = null;
      _selected.clear();
      _listKey = GlobalKey();
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        duration: Duration(seconds: error ? 6 : 2),
      ),
    );
  }

  String _urlOf(Map<String, dynamic> asset) => ApiService.fileUrl(asset['path']?.toString() ?? '');

  Future<void> _copy(Map<String, dynamic> asset) async {
    await Clipboard.setData(ClipboardData(text: _urlOf(asset)));
    _snack('URL kopyalandı');
  }

  /// Runs [action] with the actions locked.
  Future<void> _locked(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> asset) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Asset Sil',
      message: '"${asset['name']}" adlı asset silinecek.',
      confirmLabel: 'Sil',
      destructive: true,
      confirmKey: const ValueKey('confirm_delete_button'),
    );
    if (!ok) return;
    await _locked(() async {
      try {
        await _api.delete('/assets/${asset['id']}');
        _snack('Asset silindi');
        _reload();
      } catch (e) {
        _snack(e.toString(), error: true);
      }
    });
  }

  Future<void> _bulkDelete() async {
    final ids = _selected.keys.toList();
    final names = _selected.values.take(5).join('\n• ');
    final more = ids.length > 5 ? '\n+${ids.length - 5} asset daha' : '';
    final ok = await showConfirmDialog(
      context,
      title: 'Toplu Asset Silme',
      message:
          'Seçili ${ids.length} asset kalıcı olarak silinecek (dosyalar dahil). Bu işlem geri alınamaz.\n\n• $names$more',
      confirmLabel: '${ids.length} Asseti Sil',
      destructive: true,
      confirmKey: const ValueKey('confirm_bulk_delete_button'),
    );
    if (!ok) return;
    await _locked(() => _sendBulkDelete(ids));
  }

  Future<void> _sendBulkDelete(List<Object> ids) async {
    try {
      final result = await _api.post('/assets/bulk-delete', {'ids': ids}) as Map?;
      final failed = (result?['failedIds'] as List?) ?? const [];
      final deleted = result?['deletedCount'] ?? ids.length - failed.length;
      _snack(
        failed.isEmpty
            ? '$deleted asset silindi.'
            : '$deleted asset silindi, ${failed.length} silinemedi (ID: ${failed.join(', ')})',
        error: failed.isNotEmpty,
      );
      setState(_selected.clear);
      _reload();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  /// PUT /assets/{id} with a new file (backend keeps the record, replaces the file).
  /// Image assets are replaced only by images (≤ 5 MB, like the admin); other files by any file.
  Future<void> _replace(Map<String, dynamic> asset) async {
    final image = isImageAsset(asset);
    final picked = await FilePicker.pickFiles(type: image ? FileType.image : FileType.any);
    final file = picked.isEmpty ? null : picked.first;
    final path = file?.path;
    if (file == null || path == null) return;
    if (image && (file.lengthSync() ?? 0) > _maxImageBytes) {
      _snack('Dosya 5 MB sınırını aşıyor', error: true);
      return;
    }
    await _locked(() async {
      try {
        await _api.multipart('PUT', '/assets/${asset['id']}', files: [UploadFile('file', path)]);
        _snack('Dosya değiştirildi');
        _reload();
      } catch (e) {
        _snack(e.toString(), error: true);
      }
    });
  }

  Future<void> _upload() async {
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: false, // no swipe-away mid-upload; back/barrier go through the sheet's PopScope
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _UploadSheet(api: _api, folders: _folders, initialFolder: _folder ?? ''),
    );
    if (uploaded == true) {
      _snack('Yüklendi');
      _reload();
    }
  }

  void _preview(Map<String, dynamic> asset) {
    final image = isImageAsset(asset);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(asset['name']?.toString() ?? '#${asset['id']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _urlOf(asset),
                    semanticLabel: asset['name']?.toString(),
                    errorBuilder: (_, _, _) =>
                        const ListTile(leading: Icon(Icons.broken_image_outlined), title: Text('Görsel yüklenemedi')),
                  ),
                ),
              const SizedBox(height: 12),
              SelectableText(
                'ID: ${asset['id']}\nYol: ${asset['path']}\nTür: ${asset['type'] ?? '-'}\n'
                'Alt Klasör: ${asset['subFolder'] ?? '-'}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _copy(asset),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('URL kopyala'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> asset, {required bool canUpdate, required bool canDelete}) {
    final scheme = Theme.of(context).colorScheme;
    final id = asset['id'] as Object;
    final selecting = _selected.isNotEmpty;
    final selected = _selected.containsKey(id);
    void toggle() =>
        setState(() => selected ? _selected.remove(id) : _selected[id] = asset['name']?.toString() ?? '#$id');
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 12);
    return Padding(
      key: ValueKey('asset_$id'),
      padding: const EdgeInsets.only(bottom: 12),
      // Material (not a decorated Container) so the tappable ListTile's ink and selection show.
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.18) : scheme.surface.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          selected: selected,
          leading: selecting
              ? Checkbox(value: selected, onChanged: (_) => toggle())
              : (isImageAsset(asset)
                    ? AssetThumbnail(url: asset['path']?.toString(), semanticLabel: asset['name']?.toString())
                    : const SizedBox.square(dimension: 48, child: Icon(Icons.insert_drive_file_outlined))),
          title: Text(asset['name']?.toString() ?? '#$id', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(asset['path']?.toString() ?? '', style: muted, overflow: TextOverflow.ellipsis),
              Text('#$id · ${asset['type'] ?? asset['extension'] ?? '-'} · ${asset['subFolder'] ?? '-'}', style: muted),
            ],
          ),
          onTap: selecting ? toggle : () => _preview(asset),
          onLongPress: canDelete && !_busy ? toggle : null,
          trailing: selecting
              ? null
              : PopupMenuButton<String>(
                  key: ValueKey('asset_menu_$id'),
                  tooltip: 'İşlemler',
                  enabled: !_busy,
                  onSelected: (action) => switch (action) {
                    'copy' => _copy(asset),
                    'replace' => _replace(asset),
                    'delete' => _delete(asset),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('URL kopyala')),
                    if (canUpdate) const PopupMenuItem(value: 'replace', child: Text('Dosyayı değiştir')),
                    if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Sil')),
                    if (canDelete) PopupMenuItem(value: 'select', onTap: toggle, child: const Text('Seç')),
                  ],
                ),
        ),
      ),
    );
  }

  // Horizontal scroll without a fixed height so large text scales the chips.
  Widget _folderChips() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        for (final folder in [null, ..._folders])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('folder_${folder ?? 'all'}'),
              avatar: const Icon(Icons.folder_outlined, size: 18),
              label: Text(folder ?? 'Tümü'),
              selected: _folder == folder,
              onSelected: (_) => setState(() {
                _folder = folder;
                _selected.clear();
                _listKey = GlobalKey();
              }),
            ),
          ),
      ],
    ),
  );

  Widget _searchBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Ad')),
              ButtonSegment(value: true, label: Text('ID')),
            ],
            selected: {_searchById},
            onSelectionChanged: (v) => setState(() => _searchById = v.first),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('asset_search_field'),
              controller: _search,
              textInputAction: TextInputAction.search,
              keyboardType: _searchById ? TextInputType.number : TextInputType.text,
              onSubmitted: (_) => _submitSearch(),
              decoration: InputDecoration(
                labelText: _searchById ? 'Asset ID' : 'Dosya adı',
                filled: true,
                fillColor: scheme.surface.withValues(alpha: 0.7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                suffixIcon: _name == null && _id == null
                    ? IconButton(tooltip: 'Ara', icon: const Icon(Icons.search_rounded), onPressed: _submitSearch)
                    : IconButton(
                        key: const ValueKey('asset_search_clear'),
                        tooltip: 'Aramayı temizle',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(bool canUpdate, bool canDelete) {
    Widget tile(BuildContext context, Map<String, dynamic> a) => _tile(a, canUpdate: canUpdate, canDelete: canDelete);
    final id = _id;
    if (id != null) return _AssetById(key: _listKey, api: _api, id: id, itemBuilder: tile);
    return SearchablePagedList(
      key: _listKey,
      api: _api,
      endpoint: assetsEndpoint(folder: _folder, name: _name),
      paged: true,
      emptyMessage: 'Asset bulunamadı.',
      itemBuilder: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.can(_module.permissionKey, 'create');
    final canUpdate = auth.can(_module.permissionKey, 'update');
    final canDelete = auth.can(_module.permissionKey, 'delete');
    final selecting = _selected.isNotEmpty;
    final list = _listKey.currentState;
    return PopScope(
      canPop: !selecting, // back first leaves the selection mode
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: AppScaffold(
        title: selecting ? '${_selected.length} seçili' : _module.title,
        navId: _module.permissionKey,
        actions: selecting
            ? [
                if (list is SearchablePagedListState)
                  IconButton(
                    key: const ValueKey('select_all_button'),
                    tooltip: 'Yüklenenlerin tümünü seç',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            for (final a in list.items) {
                              _selected[a['id'] as Object] = a['name']?.toString() ?? '#${a['id']}';
                            }
                          }),
                  ),
                IconButton(
                  tooltip: 'Seçimi temizle',
                  icon: const Icon(Icons.deselect_rounded),
                  onPressed: _busy ? null : () => setState(_selected.clear),
                ),
                IconButton(
                  key: const ValueKey('bulk_delete_button'),
                  tooltip: 'Seçilenleri sil (${_selected.length})',
                  icon: Icon(Icons.delete_sweep_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                  onPressed: _busy ? null : _bulkDelete,
                ),
              ]
            : [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reload)],
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2, semanticsLabel: 'İşlem sürüyor'),
            // Selection mode: no folder/search change (the selection belongs to this result set).
            IgnorePointer(
              ignoring: selecting,
              child: Opacity(
                opacity: selecting ? 0.4 : 1,
                child: Column(children: [if (_folders.isNotEmpty) _folderChips(), _searchBar()]),
              ),
            ),
            Expanded(child: _list(canUpdate, canDelete)),
          ],
        ),
        floatingActionButton: canCreate && !selecting
            ? FloatingActionButton(
                key: const ValueKey('asset_upload_fab'),
                tooltip: 'Yeni Asset Yükle',
                onPressed: _upload,
                child: const Icon(Icons.upload_rounded),
              )
            : null,
      ),
    );
  }
}

/// ID search result (`GET /assets/id/{id}` returns a single asset).
class _AssetById extends StatefulWidget {
  final ApiService api;
  final String id;
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;
  const _AssetById({super.key, required this.api, required this.id, required this.itemBuilder});

  @override
  State<_AssetById> createState() => _AssetByIdState();
}

class _AssetByIdState extends State<_AssetById> {
  late Future<dynamic> _future = widget.api.get('/assets/id/${widget.id}');

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const LoadingView();
      if (snap.hasError) {
        return ErrorView(
          message: snap.error.toString(),
          onRetry: () => setState(() => _future = widget.api.get('/assets/id/${widget.id}')),
        );
      }
      final data = snap.data;
      if (data is! Map) return const EmptyView(message: 'Asset bulunamadı.');
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [widget.itemBuilder(context, Map<String, dynamic>.from(data))],
      );
    },
  );
}

/// Upload into a folder: one file → `POST /assets` (`file`), several → `POST /assets/multi` (`files`).
class _UploadSheet extends StatefulWidget {
  final ApiService api;
  final List<String> folders;
  final String initialFolder;
  const _UploadSheet({required this.api, required this.folders, required this.initialFolder});

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  late final _folder = TextEditingController(text: widget.initialFolder);
  List<PlatformFile> _files = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    setState(
      () => _files = [
        for (final f in picked)
          if (f.path != null) f,
      ],
    );
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final folder = _folder.text.trim();
    final fields = {if (folder.isNotEmpty) 'subFolder': folder};
    try {
      if (_files.length == 1) {
        await widget.api.multipart('POST', '/assets', fields: fields, files: [UploadFile('file', _files.single.path!)]);
      } else {
        await widget.api.multipart(
          'POST',
          '/assets/multi',
          fields: fields,
          files: [for (final f in _files) UploadFile('files', f.path!)],
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString()); // e.g. 413 STORAGE_QUOTA_EXCEEDED message
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy, // no closing while uploading
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Yeni Asset Yükle', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('upload_folder_field'),
                controller: _folder,
                decoration: const InputDecoration(labelText: 'Alt Klasör (opsiyonel)', hintText: 'Örn: images/banners'),
              ),
              if (widget.folders.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final f in widget.folders)
                      ActionChip(label: Text(f), onPressed: () => setState(() => _folder.text = f)),
                  ],
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('upload_pick_button'),
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(_files.isEmpty ? 'Dosya seç (bir veya birden fazla)' : '${_files.length} dosya seçildi'),
              ),
              for (final f in _files.take(5)) Text(f.name, overflow: TextOverflow.ellipsis),
              if (_files.length > 5) Text('+${_files.length - 5} dosya daha'),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('upload_send_button'),
                onPressed: _busy || _files.isEmpty ? null : _send,
                child: _busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Yükleniyor',
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Text('Yükle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
