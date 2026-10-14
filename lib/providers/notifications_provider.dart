import 'dart:async';
import 'dart:convert';

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
  List<AppNotification> _items = const [];
  bool _loaded = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  String? _error;

  /// Set by the notifications screen while visible (no banner then: the list itself updates).
  bool listVisible = false;

  int get unreadCount => _unreadCount ?? 0;
  List<AppNotification> get items => _items;
  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
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
    _items = const [];
    _loaded = _loading = _loadingMore = _hasMore = false;
    _page = 0;
    _error = null;
    listVisible = false;
    notifyListeners();
  }

  void _onRealtime() {
    if (!realtime.connected || realtime.connectionSeq == _seenSeq) return;
    _seenSeq = realtime.connectionSeq;
    refreshCount();
    if (_loaded) load();
  }

  Future<void> refreshCount() async {
    final epoch = _epoch;
    try {
      final data = await api.get('/notifications/unread-count');
      if (epoch != _epoch) return;
      final count = data is Map ? data['count'] : null;
      if (count is num) {
        _unreadCount = count.toInt();
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
    notifyListeners();
    try {
      final data = await api.get('/notifications?page=0&size=$pageSize');
      if (epoch != _epoch) return;
      _items = _parse(data);
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
    notifyListeners();
    try {
      final data = await api.get('/notifications?page=${_page + 1}&size=$pageSize');
      if (epoch != _epoch) return;
      final known = {for (final n in _items) n.id};
      _items = [..._items, ..._parse(data).where((n) => !known.contains(n.id))];
      _page++;
      _hasMore = !isLastPage(data, pageSize);
    } catch (e) {
      if (epoch != _epoch) return;
      _loadingMore = false;
      notifyListeners();
      rethrow;
    }
    _loadingMore = false;
    notifyListeners();
  }

  static List<AppNotification> _parse(dynamic data) =>
      extractItems(data).map(AppNotification.fromJson).whereType<AppNotification>().toList();

  /// Marks [n] read (no-op when already read). Throws on failure.
  Future<void> markRead(AppNotification n) async {
    if (n.read) return;
    await api.post('/notifications/${n.id}/read', const {});
    _replace(n.id, (x) => x.asRead());
    if (_unreadCount != null && _unreadCount! > 0) _unreadCount = _unreadCount! - 1;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    await api.post('/notifications/read-all', const {});
    _items = [for (final n in _items) n.asRead()];
    _unreadCount = 0;
    notifyListeners();
  }

  Future<void> remove(AppNotification n) async {
    await api.delete('/notifications/${n.id}');
    _items = _items.where((x) => x.id != n.id).toList();
    if (!n.read && _unreadCount != null && _unreadCount! > 0) _unreadCount = _unreadCount! - 1;
    notifyListeners();
  }

  void _replace(int id, AppNotification Function(AppNotification) update) {
    _items = [for (final n in _items) n.id == id ? update(n) : n];
  }

  void _onPush(String body) {
    final n = AppNotification.fromJson(jsonDecode(body));
    if (n == null) return;
    if (_items.any((x) => x.id == n.id)) return;
    if (_loaded) _items = [n, ..._items];
    if (!n.read) _unreadCount = (_unreadCount ?? 0) + 1;
    notifyListeners();
    _incoming.add(n);
  }

  /// Server's own count (source of truth; also follows reads made in the web panel).
  void _onCount(String body) {
    final data = jsonDecode(body);
    final count = data is Map ? data['count'] : null;
    if (count is! num) return;
    _unreadCount = count.toInt();
    notifyListeners();
  }

  @override
  void dispose() {
    reset();
    _incoming.close();
    super.dispose();
  }
}
