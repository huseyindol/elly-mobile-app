import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/crud_payload.dart';
import '../services/realtime_service.dart';
import '../services/stomp_destinations.dart';

/// Admin `useNotifications` + `NotificationBell`: unread count (app-bar bell badge), newest-first list
/// (`GET /notifications?page&size`, createdAt DESC), mark read / all read, delete; live updates over
/// `/user/queue/notifications` (+ `/unread-count`). New ones are also emitted on [incoming] (in-app banner).
/// Counts and the loaded list are re-fetched after every (re)connect — pushes missed while offline are not replayed.
/// No push notifications (FCM/APNs): out of plan.
class NotificationsProvider extends ChangeNotifier {
  final ApiService api;
  final RealtimeService realtime;

  NotificationsProvider({required this.api, required this.realtime});

  static const pageSize = 20;

  bool _active = false;
  int _epoch = 0; // bumps on reset: late responses of the previous session are dropped
  int _seenSeq = 0;
  final List<RealtimeSubscription> _subs = [];
  final _incoming = StreamController<AppNotification>.broadcast();

  int? _unreadCount;

  /// Bumps on every count change (server push, new notification, local action): an older REST count answer
  /// must not overwrite a newer value.
  int _countVersion = 0;

  /// Bumps on every server count push (`/unread-count`): a local -1 after a request is skipped when the server
  /// already sent the new number meanwhile (no double effect).
  int _serverCountSeq = 0;

  /// Ids seen in a list page or a push (de-duplication works without a loaded list) / marked read this session.
  final Set<int> _seenIds = {};
  final Set<int> _readIds = {};
  final Map<int, Future<void>> _inFlight = {};
  List<AppNotification> _items = const [];
  bool _loaded = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  String? _error;
  String? _loadMoreError;

  /// Set by the notifications screen while visible (no banner then: the list itself updates).
  bool listVisible = false;

  int get unreadCount => _unreadCount ?? 0;
  List<AppNotification> get items => _items;
  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;

  /// Next page failed: automatic loading stops until [loadMore] is retried by the user.
  String? get loadMoreError => _loadMoreError;
  Stream<AppNotification> get incoming => _incoming.stream;

  /// After sign-in.
  void start() {
    if (_active) return;
    _active = true;
    _seenSeq = realtime.connectionSeq;
    _subs
      ..add(realtime.subscribe(StompDest.notifications, _onPush))
      ..add(realtime.subscribe(StompDest.notificationsUnreadCount, _onCount));
    realtime.addListener(_onRealtime);
    refreshCount();
  }

  /// Sign-out: forget everything.
  void reset() {
    _epoch++;
    if (_active) realtime.removeListener(_onRealtime);
    _active = false;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _unreadCount = null;
    _countVersion++;
    _seenIds.clear();
    _readIds.clear();
    _inFlight.clear();
    _items = const [];
    _loaded = _loading = _loadingMore = _hasMore = false;
    _page = 0;
    _error = null;
    _loadMoreError = null;
    listVisible = false;
    notifyListeners();
  }

  void _onRealtime() {
    if (!realtime.connected || realtime.connectionSeq == _seenSeq) return;
    _seenSeq = realtime.connectionSeq;
    refreshCount();
    if (_loaded) load();
  }

  void _setCount(int? count) {
    _unreadCount = count == null ? null : max(0, count);
    _countVersion++;
  }

  /// Local -1 after an action, unless a server count push already arrived since [serverSeq].
  void _decrement(int serverSeq) {
    if (serverSeq == _serverCountSeq && _unreadCount != null) _setCount(_unreadCount! - 1);
  }

  Future<void> refreshCount() async {
    final epoch = _epoch;
    final version = _countVersion;
    try {
      final data = await api.get('/notifications/unread-count');
      if (epoch != _epoch || version != _countVersion) return; // a newer push / action wins
      final count = data is Map ? data['count'] : null;
      if (count is num) {
        _setCount(count.toInt());
        notifyListeners();
      }
    } catch (_) {
      // badge keeps its last value; the next reconnect / screen refresh retries
    }
  }

  /// First page (also pull-to-refresh).
  Future<void> load() async {
    final epoch = _epoch;
    _loading = true;
    _error = null;
    _loadMoreError = null;
    notifyListeners();
    try {
      final data = await api.get('/notifications?page=0&size=$pageSize');
      if (epoch != _epoch) return;
      _items = _parse(data);
      _seenIds.addAll(_items.map((n) => n.id));
      _page = 0;
      _hasMore = !isLastPage(data, pageSize);
      _loaded = true;
    } catch (e) {
      if (epoch != _epoch) return;
      _error = '$e';
    }
    _loading = false;
    notifyListeners();
    refreshCount();
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    final epoch = _epoch;
    _loadingMore = true;
    _loadMoreError = null;
    notifyListeners();
    try {
      final data = await api.get('/notifications?page=${_page + 1}&size=$pageSize');
      if (epoch != _epoch) return;
      final known = {for (final n in _items) n.id};
      _items = [..._items, ..._parse(data).where((n) => !known.contains(n.id))];
      _seenIds.addAll(_items.map((n) => n.id));
      _page++;
      _hasMore = !isLastPage(data, pageSize);
    } catch (e) {
      if (epoch != _epoch) return;
      _loadingMore = false;
      _loadMoreError = '$e';
      notifyListeners();
      rethrow;
    }
    _loadingMore = false;
    notifyListeners();
  }

  static List<AppNotification> _parse(dynamic data) =>
      extractItems(data).map(AppNotification.fromJson).whereType<AppNotification>().toList();

  /// Read state from the current list / this session, not from a (possibly stale) captured object.
  bool _isRead(AppNotification n) =>
      _readIds.contains(n.id) || (_items.where((x) => x.id == n.id).firstOrNull?.read ?? n.read);

  /// One request per notification at a time: a second tap / the banner's "Aç" joins the one in flight.
  Future<void> _once(int id, Future<void> Function() action) => _inFlight[id] ??= action().whenComplete(() {
    _inFlight.remove(id); // block body: returning the removed future would make it wait for itself
  });

  /// Marks [n] read (no-op when already read). Throws on failure.
  Future<void> markRead(AppNotification n) {
    if (_isRead(n)) return Future.value();
    return _once(n.id, () async {
      final epoch = _epoch;
      final serverSeq = _serverCountSeq;
      await api.post('/notifications/${n.id}/read', const {});
      if (epoch != _epoch) return; // the previous session's late answer
      _readIds.add(n.id);
      _replace(n.id, (x) => x.asRead());
      _decrement(serverSeq);
      notifyListeners();
    });
  }

  Future<void> markAllRead() async {
    final epoch = _epoch;
    final serverSeq = _serverCountSeq;
    await api.post('/notifications/read-all', const {});
    if (epoch != _epoch) return;
    _readIds.addAll(_items.map((n) => n.id));
    _items = [for (final n in _items) n.asRead()];
    if (serverSeq == _serverCountSeq) _setCount(0);
    notifyListeners();
  }

  Future<void> remove(AppNotification n) => _once(-n.id - 1, () async {
    final epoch = _epoch;
    final serverSeq = _serverCountSeq;
    final wasUnread = !_isRead(n);
    await api.delete('/notifications/${n.id}');
    if (epoch != _epoch) return;
    final before = _items.length;
    _items = _items.where((x) => x.id != n.id).toList();
    if (wasUnread && (before != _items.length || !_loaded)) _decrement(serverSeq);
    notifyListeners();
  });

  void _replace(int id, AppNotification Function(AppNotification) update) {
    _items = [for (final n in _items) n.id == id ? update(n) : n];
  }

  void _onPush(String body) {
    final n = AppNotification.fromJson(jsonDecode(body));
    if (n == null || !_seenIds.add(n.id)) return;
    if (_loaded) _items = [n, ..._items];
    if (!n.read) _setCount((_unreadCount ?? 0) + 1);
    notifyListeners();
    _incoming.add(n);
  }

  /// Server's own count (source of truth; also follows reads made in the web panel).
  void _onCount(String body) {
    final data = jsonDecode(body);
    final count = data is Map ? data['count'] : null;
    if (count is! num) return;
    _serverCountSeq++;
    _setCount(count.toInt());
    notifyListeners();
  }

  @override
  void dispose() {
    reset();
    _incoming.close();
    super.dispose();
  }
}
