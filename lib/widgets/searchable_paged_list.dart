import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/crud_payload.dart';
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
  /// next page is fetched when the end of the list is reached.
  final bool paged;
  final int pageSize;

  /// Text the search box matches against; null hides the search box.
  /// shortcut: client-side filter over loaded items (backend list endpoints have no search param);
  /// move to a query param if the backend adds one.
  final String Function(Map<String, dynamic> item)? searchText;

  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;
  final String emptyMessage;
  final EdgeInsetsGeometry padding;

  const SearchablePagedList({
    super.key,
    required this.api,
    required this.endpoint,
    required this.itemBuilder,
    this.paged = false,
    this.pageSize = 20,
    this.searchText,
    this.emptyMessage = 'Kayıt bulunamadı.',
    this.padding = const EdgeInsets.all(16),
  });

  @override
  State<SearchablePagedList> createState() => SearchablePagedListState();
}

class SearchablePagedListState extends State<SearchablePagedList> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  String? _error;
  String? _moreError;
  String _query = '';

  // Drops responses of a load that a newer reload() superseded.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  String _url(int page) => widget.paged ? pagedEndpoint(widget.endpoint, page, widget.pageSize) : widget.endpoint;

  /// Reloads from the first page. Loaded items stay visible meanwhile (pull-to-refresh).
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
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _moreError != null) return;
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

  Widget _footer() {
    if (_moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              _moreError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
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

    final search = widget.searchText;
    final visible = search == null || _query.isEmpty
        ? _items
        : _items.where((item) => search(item).toLowerCase().contains(_query)).toList();
    final showFooter = _hasMore;

    return Column(
      children: [
        if (search != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const ValueKey('list_search_field'),
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Ara',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: const Color(0xFF1C1C22).withValues(alpha: 0.7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: reload,
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
                        index < visible.length ? widget.itemBuilder(context, visible[index]) : _footer(),
                  ),
          ),
        ),
      ],
    );
  }
}
