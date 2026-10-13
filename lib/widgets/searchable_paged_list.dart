import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/crud_payload.dart';
import '../services/text_format.dart';
import 'app_snack_bar.dart';
import 'state_views.dart';

/// List screen body for a backend list endpoint: loading / error / empty states,
/// pull-to-refresh, optional search box and, for `/list/paged` endpoints, infinite scroll.
///
/// Reload from outside (after create/delete) with a `GlobalKey<SearchablePagedListState>`.
class SearchablePagedList extends StatefulWidget {
  final ApiService api;

  /// Relative to `/api/v1`, e.g. `/posts/list` or `/assets/list/paged?sort=id,desc`.
  final String endpoint;

  /// [endpoint] returns a backend `PagedResponse`: `page`/`size` are appended and the
  /// next page is fetched when the end of the list is reached (while searching: on demand,
  /// via the "Daha fazla ara" button, so a no-match query does not page through everything).
  final bool paged;
  final int pageSize;

  /// Text the search box matches against (compared with [foldTr]); null hides the search box.
  /// shortcut: client-side filter over loaded items (backend list endpoints have no search param);
  /// move to a query param if the backend adds one.
  final String Function(Map<String, dynamic> item)? searchText;

  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;

  /// Client-side filter (e.g. a filter chip) and order (admin tables sort on the client too).
  final bool Function(Map<String, dynamic> item)? itemFilter;
  final int Function(Map<String, dynamic> a, Map<String, dynamic> b)? compare;
  final String emptyMessage;

  /// Extra work for pull-to-refresh besides reloading the list (e.g. a count shown above it).
  final Future<void> Function()? onRefresh;

  /// Default bottom inset keeps the last row clear of a FloatingActionButton.
  final EdgeInsetsGeometry padding;

  const SearchablePagedList({
    super.key,
    required this.api,
    required this.endpoint,
    required this.itemBuilder,
    this.paged = false,
    this.pageSize = 20,
    this.searchText,
    this.itemFilter,
    this.compare,
    this.emptyMessage = 'Kayıt bulunamadı.',
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 88),
  });

  @override
  State<SearchablePagedList> createState() => SearchablePagedListState();
}

class SearchablePagedListState extends State<SearchablePagedList> {
  final List<Map<String, dynamic>> _items = [];
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  String? _error;
  String? _moreError;
  String _query = ''; // foldTr'd

  // Drops responses of a load that a newer reload() superseded.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Items loaded so far (all pages), e.g. for "select all".
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  String _url(int page) => widget.paged ? pagedEndpoint(widget.endpoint, page, widget.pageSize) : widget.endpoint;

  /// Reloads from the first page. Loaded items stay visible meanwhile (thin progress bar); if the
  /// reload fails they stay too and the error is shown in a SnackBar.
  Future<void> reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _moreError = null;
    });
    try {
      final data = await widget.api.get(_url(0));
      if (!mounted || generation != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(extractItems(data));
        _page = 0;
        _hasMore = widget.paged && !isLastPage(data, widget.pageSize);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      final keepItems = _items.isNotEmpty;
      setState(() {
        if (!keepItems) _error = e.toString();
        _loading = false;
      });
      if (keepItems) {
        showAppSnackBar(context, 'Yenilenemedi: $e', error: true);
      }
    }
  }

  Future<void> _loadMore() async {
    if (!mounted || _loading || _loadingMore || !_hasMore || _moreError != null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final data = await widget.api.get(_url(_page + 1));
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(extractItems(data));
        _page++;
        _hasMore = !isLastPage(data, widget.pageSize);
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _moreError = e.toString();
        _loadingMore = false;
      });
    }
  }

  void _setQuery(String value) => setState(() => _query = foldTr(value.trim()));

  Widget _footer(bool noVisibleMatch) {
    final scheme = Theme.of(context).colorScheme;
    if (_moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              _moreError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            TextButton(
              onPressed: () {
                setState(() => _moreError = null);
                _loadMore();
              },
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: LoadingView(label: 'Daha fazla yükleniyor'),
      );
    }
    if (_query.isNotEmpty) {
      // Searching: fetch further pages only on request.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            if (noVisibleMatch)
              Text('Yüklenen kayıtlarda yok', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.75))),
            TextButton.icon(
              key: const ValueKey('list_search_more_button'),
              onPressed: _loadMore,
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('Daha fazla ara'),
            ),
          ],
        ),
      );
    }
    // Built lazily = the end of the list is (nearly) on screen → fetch the next page.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: LoadingView(label: 'Daha fazla yükleniyor'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: reload);

    final scheme = Theme.of(context).colorScheme;
    final search = widget.searchText;
    final filter = widget.itemFilter;
    final visible = _items
        .where((item) => filter == null || filter(item))
        .where((item) => search == null || _query.isEmpty || foldTr(search(item)).contains(_query))
        .toList();
    if (widget.compare != null) visible.sort(widget.compare);
    final showFooter = _hasMore;

    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2, semanticsLabel: 'Yenileniyor'),
        if (search != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const ValueKey('list_search_field'),
              controller: _searchController,
              onChanged: _setQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Ara',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('list_search_clear'),
                        tooltip: 'Aramayı temizle',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _setQuery('');
                        },
                      ),
                filled: true,
                fillColor: scheme.surface.withValues(alpha: 0.7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => Future.wait([reload(), if (widget.onRefresh != null) widget.onRefresh!()]),
            child: visible.isEmpty && !showFooter
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      EmptyView(message: _query.isEmpty ? widget.emptyMessage : 'Aramayla eşleşen kayıt yok.'),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: widget.padding,
                    itemCount: visible.length + (showFooter ? 1 : 0),
                    itemBuilder: (context, index) =>
                        index < visible.length ? widget.itemBuilder(context, visible[index]) : _footer(visible.isEmpty),
                  ),
          ),
        ),
      ],
    );
  }
}
