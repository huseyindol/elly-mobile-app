import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crud_module.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
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
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = extractItems(await _apiService.get(widget.module.listEndpoint));
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C22),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_delete_button'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.redAccent : Colors.green,
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final module = widget.module;
    final canCreate = module.canCreate && auth.can(module.permissionKey, 'create');
    final canEdit = module.canEdit && auth.can(module.permissionKey, 'update');
    final canDelete = module.canDelete && auth.can(module.permissionKey, 'delete');
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: const Color(0xFF0A0A0C).withOpacity(0.5),
              title: Text(widget.module.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  tooltip: 'Yenile',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _fetchItems,
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withOpacity(0.15),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(_errorMessage!,
                                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchItems,
                              child: const Text('Tekrar Dene'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchItems,
                        child: _items.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 200),
                            Center(child: Text('Kayıt bulunamadı.')),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final title = resolveListText(item, widget.module.listTitleKey) ?? '#${item['id']}';
                              final subtitle = resolveListText(item, widget.module.listSubtitleKey) ?? '';

                              return Container(
                                key: ValueKey('crud_item_${item['id']}'),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1C1C22).withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5))),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (canEdit)
                                        IconButton(
                                          key: ValueKey('edit_${item['id']}'),
                                          tooltip: 'Düzenle',
                                          icon: const Icon(Icons.edit_rounded, color: Colors.white70),
                                          onPressed: () => _navigateToForm(item),
                                        ),
                                      if (canDelete)
                                        IconButton(
                                          key: ValueKey('delete_${item['id']}'),
                                          tooltip: 'Sil',
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                          onPressed: () => _deleteItem(item),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF6366F1),
              onPressed: () => _navigateToForm(),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
    );
  }
}
