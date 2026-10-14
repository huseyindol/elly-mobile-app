import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/chat_format.dart';
import '../services/realtime_service.dart';
import '../services/stomp_destinations.dart';

/// A message for the open chat screens: a rejected WebSocket frame (`/user/queue/chat-errors`), a membership
/// change or a deleted group. [leave]: the group is gone, its conversation should close.
class ChatNotice {
  final String? groupId;
  final String message;
  final bool leave;
  const ChatNotice(this.groupId, this.message, {this.leave = false});
}

/// Admin `chat-ws-store` + `ChatSidebar`/`ChatWindow` state (AC=TC: every group lives in the session tenant).
/// REST `GET/POST /chat/tenant/{tid}/…`; live: one message subscription per group (unread counts, last message),
/// typing/read/bans only for the open group, presence, new/deleted groups, own membership events, chat errors.
/// Typing and read receipts are sent over STOMP (`/app/tenant-chat/{tid}/{gid}/typing|read`); messages go over
/// REST (the response is inserted at once, the WebSocket echo is de-duplicated by id). After every reconnect the
/// group list and the open conversation are re-synced. Started by the chat screen, cleared on sign-out.
class ChatProvider extends ChangeNotifier {
  final ApiService api;
  final RealtimeService realtime;

  ChatProvider({required this.api, required this.realtime});

  static const maxMessageLength = 4000; // DtoChatMessageSend @Size(max = 4000)
  static const typingTimeout = Duration(seconds: 3);
  static const signalInterval = Duration(seconds: 2);

  bool _started = false;
  int _epoch = 0;
  int _seenSeq = 0;
  String? _tenantId;
  int? _myUserId;
  int _myLevel = 1;

  List<ChatGroup> _groups = const [];
  bool _groupsLoading = false;
  bool _groupsLoaded = false;
  String? _groupsError;

  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, int> _unread = {};
  final Map<String, ChatGroupAccess> _access = {};
  final Map<int, bool> _online = {};
  final Map<String, Map<String, String>> _typing = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, Map<int, String>> _seenBy = {};
  final Map<String, DateTime> _lastSignal = {};
  String? _activeGroupId;
  bool _atLatest = true; // the open conversation shows its newest message (read receipts only then)
  Set<String> _bannedKeys = {};

  final Map<String, RealtimeSubscription> _groupSubs = {};
  final List<RealtimeSubscription> _activeSubs = [];
  final List<RealtimeSubscription> _globalSubs = [];
  final _notices = StreamController<ChatNotice>.broadcast();

  // ── read ──
  bool get started => _started;
  bool get connected => realtime.connected;
  String? get tenantId => _tenantId;
  int? get myUserId => _myUserId;
  bool get groupsLoading => _groupsLoading;
  bool get groupsLoaded => _groupsLoaded;
  String? get groupsError => _groupsError;
  String? get activeGroupId => _activeGroupId;
  Set<String> get bannedKeys => _bannedKeys;
  Stream<ChatNotice> get notices => _notices.stream;

  /// Most recent activity first (backend order by updatedAt, live messages move a group up).
  List<ChatGroup> get groups {
    DateTime activity(ChatGroup g) {
      final last = lastMessageOf(g.id)?.createdAt;
      final updated = g.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return last != null && last.isAfter(updated) ? last : updated;
    }

    final indexed = _groups.indexed.toList()
      ..sort((a, b) {
        final c = activity(b.$2).compareTo(activity(a.$2));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  ChatGroup? groupById(String id) => _groups.where((g) => g.id == id).firstOrNull;
  List<ChatMessage> messagesOf(String groupId) => _messages[groupId] ?? const [];
  bool hasMore(String groupId) => _hasMore[groupId] ?? true;
  bool historyLoaded(String groupId) => _hasMore.containsKey(groupId);
  int unreadOf(String groupId) => _unread[groupId] ?? 0;
  ChatMessage? lastMessageOf(String groupId) => _messages[groupId]?.lastOrNull;
  ChatGroupAccess? accessOf(String groupId) => _access[groupId];

  /// true online · false offline · null unknown (no presence event since connecting; the backend has no snapshot).
  bool? isOnline(int userId) => _online[userId];

  /// Typing label without the signed-in user.
  String? typingText(String groupId) {
    final me = _myUserId == null ? null : 'u:$_myUserId';
    final names = [
      for (final e in (_typing[groupId] ?? const <String, String>{}).entries)
        if (e.key != me) e.value,
    ];
    return typingLabel(names);
  }

  /// Users whose read receipt arrived after the signed-in user's last message in [groupId].
  List<String> seenBy(String groupId) => (_seenBy[groupId] ?? const {}).values.toList();

  bool isOwn(ChatMessage m) => m.senderType == 'ADMIN' && _myUserId != null && m.senderId == _myUserId;

  /// Destination tenant of [group]: only the session tenant (fail closed on anything else).
  String? _wsTenant(ChatGroup group) =>
      isUuid(group.id) && group.tenantId == _tenantId && isSafeTenantId(_tenantId) ? _tenantId : null;

  String _base() {
    final tid = _tenantId;
    if (!isSafeTenantId(tid)) throw ApiException('Oturumda tenant bilgisi yok; sohbetler açılamıyor.');
    return chatBase(tid!);
  }

  // ── lifecycle ──

  Future<void>? _starting;
  Future<void>? _loadingGroups;

  /// Chat screen opened: first time subscribes the global topics, always refreshes the group list. Concurrent calls
  /// (list + a conversation opened from a notification) share the same start and list request.
  Future<void> open({required int? myUserId, required int myLevel}) async {
    _myLevel = myLevel;
    final epoch = _epoch;
    await (_starting ??= _start(myUserId));
    if (epoch != _epoch) return;
    if (_myUserId == null && myUserId != null) {
      _myUserId = myUserId;
      _globalSubs.add(realtime.subscribe(StompDest.membership(myUserId), _onMembership));
    }
    await loadGroups();
  }

  Future<void> _start(int? myUserId) async {
    final epoch = _epoch;
    _started = true;
    _myUserId = myUserId;
    final tenantId = await api.secureStorage.read(key: 'tenantId');
    if (epoch != _epoch) return;
    _tenantId = tenantId;
    _seenSeq = realtime.connectionSeq;
    _globalSubs
      ..add(realtime.subscribe(StompDest.presence, _onPresence))
      ..add(realtime.subscribe(StompDest.groupsNew, _onGroupCreated))
      ..add(realtime.subscribe(StompDest.groupsDeleted, _onGroupDeleted))
      ..add(realtime.subscribe(StompDest.chatErrors, _onChatError));
    if (myUserId != null) _globalSubs.add(realtime.subscribe(StompDest.membership(myUserId), _onMembership));
    realtime.addListener(_onRealtime);
  }

  /// Sign-out.
  void reset() {
    _epoch++;
    if (_started) realtime.removeListener(_onRealtime);
    _started = false;
    _starting = null;
    _loadingGroups = null;
    for (final s in [..._globalSubs, ..._activeSubs, ..._groupSubs.values]) {
      s.cancel();
    }
    _globalSubs.clear();
    _activeSubs.clear();
    _groupSubs.clear();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _groups = const [];
    _groupsLoading = _groupsLoaded = false;
    _groupsError = null;
    _messages.clear();
    _hasMore.clear();
    _unread.clear();
    _access.clear();
    _online.clear();
    _typing.clear();
    _seenBy.clear();
    _lastSignal.clear();
    _activeGroupId = null;
    _bannedKeys = {};
    _tenantId = null;
    _myUserId = null;
    notifyListeners();
  }

  void _onRealtime() {
    if (!realtime.connected || realtime.connectionSeq == _seenSeq) {
      notifyListeners(); // connection banner
      return;
    }
    _seenSeq = realtime.connectionSeq;
    notifyListeners();
    // Missed while offline: re-sync the list and the open conversation.
    loadGroups();
    final active = _activeGroupId == null ? null : groupById(_activeGroupId!);
    if (active != null) {
      loadLatest(active).catchError((_) {});
      loadAccess(active).catchError((_) => const ChatGroupAccess());
    }
  }

  // ── groups ──

  Future<void> loadGroups() => _loadingGroups ??= _loadGroups().whenComplete(() => _loadingGroups = null);

  Future<void> _loadGroups() async {
    final epoch = _epoch;
    _groupsLoading = true;
    _groupsError = null;
    notifyListeners();
    try {
      final data = await api.get('${_base()}/groups');
      if (epoch != _epoch) return;
      final seen = <String>{};
      _groups = [
        for (final g in (data is List ? data : const []).map(ChatGroup.fromJson).whereType<ChatGroup>())
          if (seen.add(g.id)) g,
      ];
      _groupsLoaded = true;
      _syncGroupSubs();
    } catch (e) {
      if (epoch != _epoch) return;
      _groupsError = chatErrorText(e);
    }
    _groupsLoading = false;
    notifyListeners();
  }

  /// Group from the list, else `GET /groups/{id}` (notification deep link); null when not accessible.
  Future<ChatGroup?> resolveGroup(String id) async {
    final known = groupById(id);
    if (known != null || !isUuid(id)) return known;
    try {
      final g = ChatGroup.fromJson(await api.get('${_base()}/groups/$id'));
      if (g != null) _upsertGroup(g);
      return g;
    } catch (_) {
      return null;
    }
  }

  void _upsertGroup(ChatGroup g) {
    final i = _groups.indexWhere((x) => x.id == g.id);
    _groups = i < 0 ? [g, ..._groups] : ([..._groups]..[i] = g);
    _syncGroupSubs();
    notifyListeners();
  }

  void _removeGroup(String id) {
    _groups = _groups.where((g) => g.id != id).toList();
    _groupSubs.remove(id)?.cancel();
    _messages.remove(id);
    _hasMore.remove(id);
    _unread.remove(id);
    _access.remove(id);
    _seenBy.remove(id);
    notifyListeners();
  }

  /// One message subscription per group (admin `allGroupSubs`): unread counts and last messages stay live.
  void _syncGroupSubs() {
    final wanted = {for (final g in _groups) g.id: g};
    for (final id in _groupSubs.keys.where((id) => !wanted.containsKey(id)).toList()) {
      _groupSubs.remove(id)!.cancel();
    }
    for (final g in wanted.values) {
      final tid = _wsTenant(g);
      if (tid == null || _groupSubs.containsKey(g.id)) continue;
      _groupSubs[g.id] = realtime.subscribe(StompDest.group(tid, g.id), (body) => _onGroupMessage(g.id, body));
    }
  }

  /// `POST /groups` — `chat:read` is enough on the backend; a tenant chat (visitor access possible) needs ADMIN+.
  Future<ChatGroup> createGroup({
    required String name,
    String? description,
    bool tenantChat = false,
    bool visitorAccess = false,
  }) async {
    final body = <String, dynamic>{
      'name': name.trim(),
      if ((description ?? '').trim().isNotEmpty) 'description': description!.trim(),
      if (tenantChat) ...{'tenantId': _tenantId, 'visitorAccess': visitorAccess},
    };
    final g = ChatGroup.fromJson(await api.post('${_base()}/groups', body));
    if (g == null) throw ApiException('Grup oluşturulamadı');
    _upsertGroup(g);
    return g;
  }

  /// `DELETE /groups/{id}` (chat:manage; owner or SUPER_ADMIN).
  Future<void> deleteGroup(ChatGroup g) async {
    await api.delete('${_base()}/groups/${g.id}');
    _removeGroup(g.id);
  }

  /// `POST /chat/dm/{userId}` (existing DM or a new one; no tenant alias on the backend).
  Future<ChatGroup> openDm(int userId) async {
    final g = ChatGroup.fromJson(await api.post('/chat/dm/$userId', const {}));
    if (g == null) throw ApiException('Direkt mesaj açılamadı');
    _upsertGroup(g);
    return g;
  }

  Future<List<ChatMember>> members(ChatGroup g) async {
    final data = await api.get('${_base()}/groups/${g.id}/members');
    return (data is List ? data : const []).map(ChatMember.fromJson).whereType<ChatMember>().toList();
  }

  /// Invite by e-mail (`/members/by-email`) or user id (`/members/{id}`); the backend applies the role hierarchy.
  Future<ChatMember?> invite(ChatGroup g, String input) async {
    final v = input.trim();
    final data = v.contains('@')
        ? await api.post('${_base()}/groups/${g.id}/members/by-email', {'email': v})
        : await api.post('${_base()}/groups/${g.id}/members/${int.parse(v)}', const {});
    _access.remove(g.id);
    return ChatMember.fromJson(data);
  }

  Future<void> removeMember(ChatGroup g, int userId) async {
    await api.delete('${_base()}/groups/${g.id}/members/$userId');
    _access.remove(g.id);
  }

  // ── conversation ──

  /// Conversation opened: typing/read/bans subscriptions for this group only, unread cleared.
  void enterGroup(ChatGroup g) {
    if (_activeGroupId != g.id) _leaveActive();
    _activeGroupId = g.id;
    _atLatest = true;
    _unread.remove(g.id);
    _bannedKeys = {};
    final tid = _wsTenant(g);
    if (tid != null && _activeSubs.isEmpty) {
      _activeSubs
        ..add(realtime.subscribe(StompDest.typing(tid, g.id), (b) => _onTyping(g.id, b)))
        ..add(realtime.subscribe(StompDest.read(tid, g.id), (b) => _onRead(g.id, b)))
        ..add(realtime.subscribe(StompDest.bans(tid, g.id), (b) => _onBan(g.id, b)));
    }
    notifyListeners();
  }

  /// The open conversation's list reached / left its newest message. Read receipts are sent only while the newest
  /// message is on screen (no false "Görüldü"); arriving back at it sends one.
  void setViewingLatest(ChatGroup g, bool atLatest) {
    if (_activeGroupId != g.id || _atLatest == atLatest) return;
    _atLatest = atLatest;
    if (atLatest) sendRead(g, force: true);
  }

  /// Called from the conversation's dispose (tree locked → no notify; nothing on screen depends on it).
  void leaveGroup(String groupId) {
    if (_activeGroupId == groupId) _leaveActive();
  }

  void _leaveActive() {
    for (final s in _activeSubs) {
      s.cancel();
    }
    _activeSubs.clear();
    _activeGroupId = null;
    _bannedKeys = {};
  }

  Future<ChatGroupAccess> loadAccess(ChatGroup g) async {
    final epoch = _epoch;
    final access = ChatGroupAccess.fromJson(await api.get('${_base()}/groups/${g.id}/access'));
    if (epoch == _epoch) {
      _access[g.id] = access;
      notifyListeners();
    }
    return access;
  }

  /// Newest page (open / re-sync). If none of it overlaps what is cached, the cache had a gap → replaced.
  Future<void> loadLatest(ChatGroup g) async {
    final epoch = _epoch;
    final page = _parseMessages(await api.get('${_base()}/groups/${g.id}/messages?limit=$chatPageSize'), g.id);
    if (epoch != _epoch) return;
    final cached = _messages[g.id] ?? const [];
    final ids = {for (final m in cached) m.id};
    if (cached.isNotEmpty && page.length >= chatPageSize && !page.any((m) => ids.contains(m.id))) {
      _messages[g.id] = page;
      _hasMore[g.id] = true;
    } else {
      _merge(g.id, page);
      _hasMore.putIfAbsent(g.id, () => page.length >= chatPageSize);
    }
    notifyListeners();
    if (_activeGroupId != g.id || _atLatest) sendRead(g, force: true);
  }

  /// Older page before the oldest loaded message (scrolling up).
  Future<void> loadOlder(ChatGroup g) async {
    final oldest = messagesOf(g.id).firstOrNull;
    if (oldest == null || !hasMore(g.id)) return;
    final epoch = _epoch;
    final page = _parseMessages(
      await api.get('${_base()}/groups/${g.id}/messages?before=${oldest.id}&limit=$chatPageSize'),
      g.id,
    );
    if (epoch != _epoch) return;
    _merge(g.id, page);
    _hasMore[g.id] = page.length >= chatPageSize;
    notifyListeners();
  }

  List<ChatMessage> _parseMessages(dynamic data, String groupId) => [
    for (final m in (data is List ? data : const []).map(ChatMessage.fromJson).whereType<ChatMessage>())
      if (m.groupId == groupId) m,
  ];

  /// By id (incoming wins), oldest first.
  void _merge(String groupId, List<ChatMessage> incoming) {
    final byId = {for (final m in _messages[groupId] ?? const <ChatMessage>[]) m.id: m};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    final epoch0 = DateTime.fromMillisecondsSinceEpoch(0);
    _messages[groupId] = byId.values.toList()..sort((a, b) => (a.createdAt ?? epoch0).compareTo(b.createdAt ?? epoch0));
  }

  /// `POST /groups/{id}/messages` (text). The response is shown at once (WS echo de-duplicated).
  Future<void> send(ChatGroup g, String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    await _postMessage(g, {'content': content, 'contentType': 'TEXT'});
  }

  /// Admin `ChatInput` file flow: `POST /files` (multipart `file`) → stored path sent as a FILE message.
  Future<void> sendFile(ChatGroup g, String filePath) async {
    final path = await api.multipart('POST', '${_base()}/files', files: [UploadFile('file', filePath)]);
    if (path is! String || path.isEmpty) throw ApiException('Dosya yüklenemedi');
    await _postMessage(g, {'content': path, 'contentType': 'FILE'});
  }

  Future<void> _postMessage(ChatGroup g, Map<String, dynamic> body) async {
    final epoch = _epoch;
    _lastSignal.remove('typing:${g.id}'); // next keystroke may signal again
    final m = ChatMessage.fromJson(await api.post('${_base()}/groups/${g.id}/messages', body));
    if (m == null || epoch != _epoch) return;
    _merge(g.id, [m]);
    _clearTyping(g.id, m);
    _seenBy[g.id] = {};
    notifyListeners();
  }

  Future<void> deleteMessage(ChatGroup g, ChatMessage m) async {
    await api.delete('${_base()}/messages/${m.id}');
    final list = _messages[g.id];
    if (list == null) return;
    _messages[g.id] = [for (final x in list) x.id == m.id ? x.markDeleted() : x];
    notifyListeners();
  }

  /// Keystroke in the composer: at most one typing signal per [signalInterval].
  void typing(ChatGroup g) {
    final tid = _wsTenant(g);
    if (tid != null && _throttle('typing:${g.id}')) realtime.send(StompDest.sendTyping(tid, g.id));
  }

  void sendRead(ChatGroup g, {bool force = false}) {
    final tid = _wsTenant(g);
    if (tid == null) return;
    if (force) _lastSignal.remove('read:${g.id}');
    if (_throttle('read:${g.id}')) realtime.send(StompDest.sendRead(tid, g.id));
  }

  bool _throttle(String key) {
    final now = DateTime.now();
    final last = _lastSignal[key];
    if (last != null && now.difference(last) < signalInterval) return false;
    _lastSignal[key] = now;
    return true;
  }

  // ── tenant-side moderation (chat:manage; GUEST/VISITOR senders) ──

  Future<void> loadBans(ChatGroup g) async {
    final epoch = _epoch;
    final data = await api.get('${_base()}/groups/${g.id}/bans');
    if (epoch != _epoch || _activeGroupId != g.id) return;
    _bannedKeys = {
      for (final b in data is List ? data : const [])
        if (b is Map)
          if (b['sessionId'] != null) 's:${b['sessionId']}' else if (b['visitorId'] != null) 'v:${b['visitorId']}',
    };
    notifyListeners();
  }

  Future<void> ban(ChatGroup g, ChatMessage m) async {
    final key = m.banKey;
    if (key == null) return;
    await api.post('${_base()}/groups/${g.id}/bans', {
      if (m.senderType == 'GUEST') 'sessionId': m.sessionId else 'visitorId': m.visitorId,
    });
    _bannedKeys = {..._bannedKeys, key};
    notifyListeners();
  }

  Future<void> unban(ChatGroup g, ChatMessage m) async {
    final key = m.banKey;
    if (key == null) return;
    final query = m.senderType == 'GUEST'
        ? 'sessionId=${Uri.encodeQueryComponent(m.sessionId!)}'
        : 'visitorId=${m.visitorId}';
    await api.delete('${_base()}/groups/${g.id}/bans?$query');
    _bannedKeys = {..._bannedKeys}..remove(key);
    notifyListeners();
  }

  // ── live events ──

  void _onGroupMessage(String groupId, String body) {
    final m = ChatMessage.fromJson(jsonDecode(body));
    if (m == null || m.groupId != groupId) return;
    final list = _messages[groupId];
    if (list != null && list.any((x) => x.id == m.id)) return; // REST response already in (admin dedup)
    _merge(groupId, [m]);
    _clearTyping(groupId, m);
    if (isOwn(m)) {
      _seenBy[groupId] = {};
    } else if (_activeGroupId == groupId) {
      final g = groupById(groupId);
      if (g != null && _atLatest) sendRead(g);
    } else {
      _unread[groupId] = unreadOf(groupId) + 1;
    }
    notifyListeners();
  }

  void _onTyping(String groupId, String body) {
    final data = jsonDecode(body);
    if (data is! Map || data['typing'] == false) return;
    final userId = data['userId'];
    final key = userId is num ? 'u:${userId.toInt()}' : (data['sessionId'] != null ? 's:${data['sessionId']}' : null);
    if (key == null) return;
    final name = safeChatText('${data['username'] ?? ''}').trim();
    (_typing[groupId] ??= {})[key] = name.isEmpty ? 'Misafir' : name;
    _typingTimers['$groupId|$key']?.cancel();
    _typingTimers['$groupId|$key'] = Timer(typingTimeout, () {
      _typingTimers.remove('$groupId|$key');
      if (_typing[groupId]?.remove(key) != null) notifyListeners();
    });
    notifyListeners();
  }

  void _clearTyping(String groupId, ChatMessage m) {
    final key = m.senderId != null
        ? 'u:${m.senderId}'
        : m.sessionId != null
        ? 's:${m.sessionId}'
        : null;
    if (key == null) return;
    _typingTimers.remove('$groupId|$key')?.cancel();
    _typing[groupId]?.remove(key);
  }

  void _onRead(String groupId, String body) {
    final data = jsonDecode(body);
    if (data is! Map) return;
    final userId = data['userId'];
    if (userId is! num || userId.toInt() == _myUserId) return;
    if (!messagesOf(groupId).any(isOwn)) return;
    final name = safeChatText('${data['username'] ?? ''}').trim();
    (_seenBy[groupId] ??= {})[userId.toInt()] = name.isEmpty ? '#${userId.toInt()}' : name;
    notifyListeners();
  }

  void _onBan(String groupId, String body) {
    final data = jsonDecode(body);
    if (data is! Map || groupId != _activeGroupId) return;
    final key = data['sessionId'] != null
        ? 's:${data['sessionId']}'
        : data['visitorId'] != null
        ? 'v:${data['visitorId']}'
        : null;
    if (key == null) return;
    _bannedKeys = data['action'] == 'BANNED' ? {..._bannedKeys, key} : ({..._bannedKeys}..remove(key));
    notifyListeners();
  }

  void _onPresence(String body) {
    final data = jsonDecode(body);
    if (data is! Map || data['userId'] is! num) return;
    _online[(data['userId'] as num).toInt()] = data['status'] == 'ONLINE';
    notifyListeners();
  }

  /// `/topic/groups/new` is broadcast to every connected user: only groups of the session tenant are taken;
  /// a group above the own level (visible only if invited) re-fetches the list instead (admin).
  void _onGroupCreated(String body) {
    final g = ChatGroup.fromJson(jsonDecode(body));
    if (g == null || !_groupsLoaded || g.tenantId != _tenantId) return;
    if (g.visibilityLevel > _myLevel) {
      loadGroups();
    } else {
      _upsertGroup(g);
    }
  }

  void _onGroupDeleted(String body) {
    final id = body.trim();
    if (!isUuid(id) || groupById(id) == null) return;
    final wasActive = _activeGroupId == id;
    if (wasActive) _leaveActive();
    _removeGroup(id);
    if (wasActive) _notices.add(ChatNotice(id, 'Bu grup silindi.', leave: true));
  }

  void _onMembership(String body) {
    final data = jsonDecode(body);
    if (data is! Map) return;
    final groupId = '${data['groupId'] ?? ''}';
    if (!isUuid(groupId)) return;
    final message = safeChatText('${data['message'] ?? ''}');
    final active = _activeGroupId == groupId;
    if (data['action'] == 'JOINED') {
      final g = ChatGroup.fromJson(data['group']);
      if (g != null && g.id == groupId && g.tenantId == _tenantId) {
        _upsertGroup(g);
      } else if (_groupsLoaded) {
        loadGroups();
      }
    } else if (data['action'] == 'REMOVED' && !active) {
      _removeGroup(groupId);
    }
    if (active) {
      if (message.isNotEmpty) _notices.add(ChatNotice(groupId, message));
      final g = groupById(groupId);
      if (g != null) loadAccess(g).catchError((_) => const ChatGroupAccess());
    }
  }

  void _onChatError(String body) {
    final data = jsonDecode(body);
    if (data is! Map) return;
    final groupId = data['groupId']?.toString();
    final message = safeChatText('${data['message'] ?? ''}').trim();
    _notices.add(ChatNotice(groupId, message.isEmpty ? 'Sohbet işlemi reddedildi.' : message));
  }

  @override
  void dispose() {
    reset();
    _notices.close();
    super.dispose();
  }
}
