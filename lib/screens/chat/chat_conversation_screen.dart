import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../models/chat_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../services/chat_format.dart';
import '../../services/text_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/chat_message_text.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/connection_banner.dart';
import '../../widgets/info_note.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import 'chat_members_screen.dart';

Future<bool> _launchExternal(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// A picked file: local path, display name, size in bytes (null = unknown).
typedef PickedChatFile = ({String path, String name, int? size});

Future<PickedChatFile?> _pickWithFilePicker() async {
  final file = (await FilePicker.pickFiles()).firstOrNull;
  final path = file?.path;
  if (file == null || path == null) return null;
  return (path: path, name: file.name, size: await file.length());
}

/// Backend multipart limit (`spring.servlet.multipart.max-file-size`).
const chatMaxFileBytes = 10 * 1024 * 1024;

/// Admin `ChatWindow` + `ChatInput` + `ChatTypingIndicator`: history newest at the bottom, older pages load while
/// scrolling up (`?before=<oldest id>`), send (REST), typing / read signals, "Görüldü" under the own last message,
/// file attachments, delete own message, ban/unban tenant-side senders (`chat:manage`). Write access from
/// `GET /access` (the only source of the composer banner). While the user reads older messages, new ones are not
/// inserted (the view would jump): an "N yeni mesaj ↓" chip appears and read receipts wait until the newest message
/// is on screen again. The backend has no live delete/edit events and the admin has no edit UI → no editing here.
class ChatConversationScreen extends StatefulWidget {
  final String groupId;

  /// Test seam: opens a confirmed http(s) link.
  final Future<bool> Function(Uri uri) launcher;

  /// Test seam: file picker.
  final Future<PickedChatFile?> Function() pickFile;

  const ChatConversationScreen({
    super.key,
    required this.groupId,
    this.launcher = _launchExternal,
    this.pickFile = _pickWithFilePicker,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  /// Within this many pixels of the newest message the list counts as "at the bottom".
  static const _bottomSlack = 48.0;

  late final ChatProvider _chat = context.read<ChatProvider>();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<ChatNotice>? _notices;

  ChatGroup? _group;
  String? _error;
  bool _sending = false;
  String? _uploadingName;
  bool _loadingOlder = false;
  bool _deletingGroup = false;

  /// Newest message shown while the user reads older ones (null = follow new messages).
  String? _frozenAt;
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _notices = _chat.notices.listen(_onNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _notices?.cancel();
    _chat.leaveGroup(widget.groupId);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    if (!_chat.groupsLoaded) {
      // Opened from a notification: the chat list may still be starting (shared request).
      final auth = context.read<AuthProvider>();
      await _chat.open(myUserId: auth.userId, myLevel: auth.roleLevel);
      if (!mounted) return;
    }
    final group = await _chat.resolveGroup(widget.groupId);
    if (!mounted) return;
    if (group == null) {
      setState(() => _error = 'Grup bulunamadı ya da erişiminiz yok.');
      return;
    }
    _chat.enterGroup(group);
    setState(() => _group = group);
    await _load(group);
  }

  Future<void> _load(ChatGroup group) async {
    try {
      final access = await _chat.loadAccess(group);
      if (!mounted) return;
      if (!access.canRead) {
        setState(() => _error = access.denialMessage ?? 'Bu gruba erişiminiz yok.');
        return;
      }
      await _chat.loadLatest(group);
      if (mounted && context.read<AuthProvider>().has('chat:manage')) {
        _chat.loadBans(group).catchError((_) {}); // badges only; the menu still works without
      }
    } catch (e) {
      if (mounted && _chat.messagesOf(group.id).isEmpty) setState(() => _error = chatErrorText(e));
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    }
  }

  /// Rejected frames / membership changes: a SnackBar (the composer banner comes only from `GET /access`, which the
  /// provider re-reads on membership events).
  void _onNotice(ChatNotice notice) {
    if (!mounted || (notice.groupId != null && notice.groupId != widget.groupId)) return;
    if (notice.leave) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).maybePop();
      if (messenger != null) showSnackBarOn(messenger, notice.message);
      return;
    }
    showAppSnackBar(context, notice.message, error: true);
  }

  void _onScroll() {
    final p = _scroll.position;
    // Reversed list: the oldest messages are at the max extent, the newest at 0.
    if (p.pixels >= p.maxScrollExtent - 300) _loadOlder();
    if (_jumping) return;
    final atBottom = p.pixels <= _bottomSlack;
    if (atBottom == (_frozenAt == null)) return;
    final group = _group;
    if (group == null) return;
    setState(() => _frozenAt = atBottom ? null : _chat.messagesOf(group.id).lastOrNull?.id);
    _chat.setViewingLatest(group, atBottom);
  }

  /// The "N yeni mesaj ↓" chip / own send: show everything and scroll to the newest; one read receipt at the end.
  Future<void> _toLatest({bool animate = true}) async {
    setState(() => _frozenAt = null);
    if (_scroll.hasClients) {
      if (animate) {
        _jumping = true; // positions passed on the way down must not re-freeze the list
        await _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        _jumping = false;
      } else {
        _scroll.jumpTo(0);
      }
    }
    final group = _group;
    if (group != null && mounted) _chat.setViewingLatest(group, true);
  }

  Future<void> _loadOlder() async {
    final group = _group;
    if (group == null || _loadingOlder || !_chat.hasMore(group.id) || _chat.messagesOf(group.id).isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      await _chat.loadOlder(group);
    } catch (e) {
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final group = _group;
    final text = _composer.text;
    if (group == null || text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _chat.send(group, text);
      if (!mounted) return;
      // Only the sent part goes; anything typed while sending stays.
      final now = _composer.text;
      final rest = now.startsWith(text) ? now.substring(text.length) : now;
      _composer.value = TextEditingValue(
        text: rest,
        selection: TextSelection.collapsed(offset: rest.length),
      );
      _toLatest(animate: false);
    } catch (e) {
      await _sendFailed(group, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendFailed(ChatGroup group, Object e) async {
    if (!mounted) return;
    showAppSnackBar(context, chatErrorText(e), error: true);
    if (e is ApiException && e.statusCode == 403) {
      await _chat.loadAccess(group).catchError((_) => const ChatGroupAccess());
    }
  }

  Future<void> _attach() async {
    final group = _group;
    if (group == null) return;
    final file = await widget.pickFile();
    if (file == null || !mounted) return;
    final size = file.size;
    if (size != null && size > chatMaxFileBytes) {
      showAppSnackBar(context, 'Dosya 10 MB\'tan büyük olamaz.', error: true);
      return;
    }
    final name = safeChatText(file.name);
    final ok = await showConfirmDialog(
      context,
      title: 'Dosya gönderilsin mi?',
      message: '$name${size == null ? '' : ' (${formatBytes(size)})'}\n\nGruptaki herkes görebilir ve indirebilir.',
      confirmLabel: 'Gönder',
    );
    if (!ok || !mounted) return;
    setState(() => _uploadingName = name);
    try {
      await _chat.sendFile(group, file.path);
      if (mounted) _toLatest(animate: false);
    } catch (e) {
      await _sendFailed(group, e);
    } finally {
      if (mounted) setState(() => _uploadingName = null);
    }
  }

  Future<void> _openLink(Uri uri) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Bağlantı açılsın mı?',
      message: 'Bu bağlantı sohbetteki bir mesajdan; tarayıcıda açılacak:\n\n$uri',
      confirmLabel: 'Aç',
    );
    if (!ok || !mounted) return;
    if (!await widget.launcher(uri) && mounted) showAppSnackBar(context, 'Bağlantı açılamadı.', error: true);
  }

  Future<void> _deleteGroup(ChatGroup group) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Grubu sil',
      message: '"${safeChatText(group.title)}" kalıcı olarak silinecek ve tüm mesajlar kaybolacak.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deletingGroup = true);
    try {
      await _chat.deleteGroup(group);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      showSnackBarOn(messenger, 'Grup silindi');
    } catch (e) {
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _deletingGroup = false);
    }
  }

  // ── message actions (long-press sheet and screen-reader custom actions share these) ──

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    }
  }

  Future<void> _copy(ChatMessage m) async {
    await Clipboard.setData(ClipboardData(text: safeChatText(m.content)));
    if (mounted) showAppSnackBar(context, 'Kopyalandı');
  }

  Future<void> _delete(ChatMessage m) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Mesajı sil',
      message: 'Mesaj herkes için "silindi" olarak görünecek.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (ok && mounted) await _chat.deleteMessage(_group!, m);
  }

  Future<void> _ban(ChatMessage m) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Yazmasını yasakla',
      message:
          '"${safeChatText(m.senderName)}" bu grupta artık yazamayacak (okuma serbest). Yasak sonradan kaldırılabilir.',
      confirmLabel: 'Yasakla',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _chat.ban(_group!, m);
    if (mounted) showAppSnackBar(context, 'Kullanıcı yasaklandı');
  }

  Future<void> _unban(ChatMessage m) async {
    await _chat.unban(_group!, m);
    if (mounted) showAppSnackBar(context, 'Yasak kaldırıldı');
  }

  Future<void> _messageActions(ChatMessage m, {required bool own, required bool canModerate}) async {
    final banned = m.banKey != null && _chat.bannedKeys.contains(m.banKey);
    final canCopy = !m.deleted && !m.isFile;
    final canDelete = own && !m.deleted;
    if (!canCopy && !canDelete && !canModerate) return;
    final action = await showModalBottomSheet<Future<void> Function()>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Metni kopyala'),
                onTap: () => Navigator.pop(sheet, () => _copy(m)),
              ),
            if (canModerate)
              ListTile(
                key: const ValueKey('chat_action_ban'),
                leading: Icon(banned ? Icons.verified_user_outlined : Icons.block_rounded),
                title: Text(banned ? 'Yasağı kaldır' : 'Yazmasını yasakla'),
                onTap: () => Navigator.pop(sheet, () => banned ? _unban(m) : _ban(m)),
              ),
            if (canDelete)
              ListTile(
                key: const ValueKey('chat_action_delete'),
                iconColor: Theme.of(sheet).colorScheme.onErrorContainer,
                textColor: Theme.of(sheet).colorScheme.onErrorContainer,
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Mesajı sil'),
                onTap: () => Navigator.pop(sheet, () => _delete(m)),
              ),
          ],
        ),
      ),
    );
    if (action != null && mounted) await _run(action);
  }

  /// The same actions for screen readers (one semantics node per message has no inner buttons).
  Map<CustomSemanticsAction, VoidCallback> _semanticActions(
    ChatMessage m, {
    required bool own,
    required bool canModerate,
    required bool banned,
  }) {
    final actions = <CustomSemanticsAction, VoidCallback>{};
    if (!m.deleted) {
      final path = chatFilePath(contentType: m.contentType, fileUrl: m.fileUrl, content: m.content);
      if (path != null) {
        actions[CustomSemanticsAction(label: 'Dosyayı aç: ${fileNameOf(path)}')] = () =>
            _openLink(Uri.parse(chatFileUrl(path)));
      } else {
        actions[const CustomSemanticsAction(label: 'Metni kopyala')] = () => _run(() => _copy(m));
        for (final (_, uri) in linkSegments(safeChatText(m.content)).where((s) => s.$2 != null).take(5)) {
          actions[CustomSemanticsAction(label: 'Bağlantıyı aç: $uri')] = () => _openLink(uri!);
        }
      }
    }
    if (canModerate) {
      actions[CustomSemanticsAction(label: banned ? 'Yasağı kaldır' : 'Yazmasını yasakla')] = () =>
          _run(() => banned ? _unban(m) : _ban(m));
    }
    if (own && !m.deleted) actions[const CustomSemanticsAction(label: 'Mesajı sil')] = () => _run(() => _delete(m));
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Only this conversation's data: other groups' traffic does not rebuild the screen.
    final view = context.select(
      (ChatProvider c) => (
        messages: c.messagesOf(widget.groupId),
        loaded: c.historyLoaded(widget.groupId),
        hasMore: c.hasMore(widget.groupId),
        access: c.accessOf(widget.groupId),
        typing: c.typingText(widget.groupId),
        seen: c.seenBy(widget.groupId).join('\u0000'),
        banned: c.bannedKeys,
      ),
    );
    final group = _group;
    final title = group == null ? 'Sohbet' : safeChatText(group.title);
    // Backend: chat:manage and (owner or SUPER_ADMIN); unknown own id → no delete (fail closed).
    final canDeleteGroup =
        group != null &&
        auth.has('chat:manage') &&
        auth.identityKnown &&
        (auth.roleLevel >= 4 || group.createdBy == auth.userId);
    return AppScaffold(
      title: title,
      actions: [
        if (group != null)
          IconButton(
            key: const ValueKey('chat_members_button'),
            tooltip: 'Üyeler',
            icon: const Icon(Icons.group_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'chat-members'),
                builder: (_) => ChatMembersScreen(group: group),
              ),
            ),
          ),
        if (canDeleteGroup)
          IconButton(
            key: const ValueKey('chat_delete_group'),
            tooltip: 'Grubu sil',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _deletingGroup ? null : () => _deleteGroup(group),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConnectionBanner(),
          Expanded(child: _body(view.messages, view.loaded, view.hasMore, view.banned, auth)),
        ],
      ),
      // As bottomNavigationBar: SnackBars show above it (never over the composer), keyboard handled by AppScaffold.
      bottomNavigationBar: group != null && _error == null ? _composerArea(view.access, view.typing) : null,
    );
  }

  Widget _body(List<ChatMessage> all, bool loaded, bool hasMore, Set<String> bannedKeys, AuthProvider auth) {
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _group == null ? _open : () => _reload(_group!));
    }
    final group = _group;
    if (group == null || !loaded) return const LoadingView(label: 'Mesajlar yükleniyor');
    if (all.isEmpty) {
      return const EmptyView(
        icon: Icons.chat_bubble_outline_rounded,
        message: 'Henüz mesaj yok. İlk mesajı siz gönderin.',
      );
    }
    final frozen = _frozenAt == null ? -1 : all.indexWhere((m) => m.id == _frozenAt);
    final messages = frozen < 0 ? all : all.sublist(0, frozen + 1);
    final unseen = frozen < 0 ? 0 : all.skip(frozen + 1).where((m) => !_chat.isOwn(m)).length;
    final canModerate = auth.has('chat:manage');
    final seen = _chat.seenBy(group.id);
    final now = DateTime.now();
    // index 0 = newest (reversed list); last index = older-page loader / start marker.
    final list = ListView.builder(
      key: const ValueKey('chat_messages'),
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == messages.length) return _historyEnd(hasMore);
        final i = messages.length - 1 - index;
        final m = messages[i];
        final prev = i > 0 ? messages[i - 1] : null;
        final own = _chat.isOwn(m);
        final continued =
            prev != null &&
            !prev.deleted &&
            _senderKey(prev) == _senderKey(m) &&
            m.createdAt != null &&
            prev.createdAt != null &&
            m.createdAt!.difference(prev.createdAt!).inMinutes < 5;
        final banned = m.banKey != null && bannedKeys.contains(m.banKey);
        final moderate = canModerate && !own && m.banKey != null;
        return _MessageBubble(
          key: ValueKey('chat_msg_${m.id}'),
          message: m,
          own: own,
          showSender: !own && !continued,
          banned: banned,
          time: formatMessageTime(m.createdAt, now),
          seenBy: index == 0 && own && frozen < 0 ? seen : const [],
          onOpenLink: _openLink,
          onActions: () => _messageActions(m, own: own, canModerate: moderate),
          semanticActions: _semanticActions(m, own: own, canModerate: moderate, banned: banned),
        );
      },
    );
    // Always the same Stack: swapping `list` ↔ `Stack(list)` would remount the list and lose the scroll position.
    return Stack(
      children: [
        list,
        if (unseen > 0)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: ActionChip(
                  key: const ValueKey('chat_new_messages'),
                  avatar: const Icon(Icons.arrow_downward_rounded, size: 18),
                  label: Text('$unseen yeni mesaj'),
                  onPressed: _toLatest,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _reload(ChatGroup group) async {
    setState(() => _error = null);
    await _load(group);
  }

  Widget _historyEnd(bool hasMore) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: _loadingOlder
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Eski mesajlar yükleniyor'),
              )
            : hasMore
            ? TextButton(onPressed: _loadOlder, child: const Text('Daha eski mesajları yükle'))
            : Text('Sohbetin başı', style: muted),
      ),
    );
  }

  static String _senderKey(ChatMessage m) => switch (m.senderType) {
    'ADMIN' when m.senderId != null => 'a:${m.senderId}',
    'VISITOR' when m.visitorId != null => 'v:${m.visitorId}',
    'GUEST' when m.sessionId != null => 'g:${m.sessionId}',
    _ => 'id:${m.id}',
  };

  Widget _composerArea(ChatGroupAccess? access, String? typing) {
    final scheme = Theme.of(context).colorScheme;
    final group = _group!;
    final canWrite = access?.canWrite ?? false;
    final banner = access != null && !canWrite ? access.denialMessage : null;
    final busy = _sending || _uploadingName != null;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Not a live region: typing changes every few seconds and would keep interrupting the screen reader.
        if (typing != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              typing,
              key: const ValueKey('chat_typing'),
              style: muted.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        if ((banner ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Semantics(liveRegion: true, child: InfoNote(safeChatText(banner!), warning: true)),
          ),
        if (_uploadingName != null)
          Padding(
            key: const ValueKey('chat_uploading'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Dosya yükleniyor'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Yükleniyor: $_uploadingName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('chat_attach'),
                  tooltip: 'Dosya ekle',
                  onPressed: canWrite && !busy ? _attach : null,
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat_composer'),
                    controller: _composer,
                    enabled: canWrite,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: ChatProvider.maxMessageLength,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                        currentLength >= maxLength!
                        ? Semantics(
                            liveRegion: true,
                            child: Text(
                              'Sınıra ulaşıldı: en fazla $maxLength karakter',
                              key: const ValueKey('chat_length_limit'),
                              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                            ),
                          )
                        : currentLength > 3500
                        ? Text('$currentLength/$maxLength', style: muted)
                        : null,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration:
                        fieldDecoration(
                          scheme,
                          hint: canWrite ? 'Mesaj yazın…' : 'Bu gruba mesaj gönderemezsiniz',
                        ).copyWith(
                          hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                    onChanged: (_) {
                      _chat.typing(group);
                      setState(() {}); // send button state
                    },
                  ),
                ),
                IconButton(
                  key: const ValueKey('chat_send'),
                  tooltip: 'Gönder',
                  onPressed: canWrite && !busy && _composer.text.trim().isNotEmpty ? _send : null,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Gönderiliyor'),
                        )
                      : Icon(Icons.send_rounded, color: canWrite ? AppColors.primaryLight : null),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool own;
  final bool showSender;
  final bool banned;
  final String time;
  final List<String> seenBy;
  final void Function(Uri uri) onOpenLink;
  final VoidCallback onActions;
  final Map<CustomSemanticsAction, VoidCallback> semanticActions;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.own,
    required this.showSender,
    required this.banned,
    required this.time,
    required this.seenBy,
    required this.onOpenLink,
    required this.onActions,
    required this.semanticActions,
  });

  (String, Color) _badge(ColorScheme scheme) => switch (message.senderType) {
    'VISITOR' => ('Ziyaretçi', AppColors.warning),
    'GUEST' => ('Misafir', scheme.secondary),
    _ => ('Admin', AppColors.primaryLight),
  };

  /// One node per message: "`gönderen | Siz`, `zaman`[, Görüldü: …][, rol][, Yasaklı]: `metin`".
  String _semanticLabel(ColorScheme scheme) {
    final m = message;
    final name = safeChatText(m.senderName).trim();
    final path = m.deleted ? null : chatFilePath(contentType: m.contentType, fileUrl: m.fileUrl, content: m.content);
    final body = m.deleted
        ? 'Bu mesaj silindi'
        : path != null
        ? '${m.contentType == 'IMAGE' || isImagePath(path) ? 'Görsel' : 'Dosya'}: ${fileNameOf(path)}'
        : safeChatText(m.content);
    final head = [
      own ? 'Siz' : (name.isEmpty ? 'Misafir' : name),
      time,
      if (m.edited && !m.deleted) 'düzenlendi',
      if (seenBy.isNotEmpty) 'Görüldü: ${seenBy.join(', ')}',
      if (!own) _badge(scheme).$1,
      if (banned) 'Yasaklı',
    ].where((s) => s.isNotEmpty).join(', ');
    return '$head: $body';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = message;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.65));
    final senderName = safeChatText(m.senderName).trim();
    final (badge, badgeColor) = _badge(scheme);
    final bubbleColor = own ? AppColors.primaryStrong : scheme.surface;
    final textColor = own ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      container: true,
      label: _semanticLabel(scheme),
      onLongPressHint: 'Mesaj seçenekleri',
      customSemanticsActions: semanticActions,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.only(top: showSender ? 10 : 3),
          child: Column(
            crossAxisAlignment: own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showSender)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        senderName.isEmpty ? 'Misafir' : senderName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      StatusBadge(label: badge, color: badgeColor),
                      if (banned) StatusBadge(label: 'Yasaklı', color: scheme.onErrorContainer),
                    ],
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                child: Material(
                  color: bubbleColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(own ? 16 : 4),
                      bottomRight: Radius.circular(own ? 4 : 16),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onLongPress: onActions,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: _content(context, textColor),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                child: Text(
                  [
                    time,
                    if (m.edited && !m.deleted) 'düzenlendi',
                    if (seenBy.isNotEmpty) 'Görüldü: ${seenBy.join(', ')}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  key: seenBy.isEmpty ? null : const ValueKey('chat_seen_by'),
                  style: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, Color textColor) {
    final m = message;
    if (m.deleted) {
      return Text(
        'Bu mesaj silindi',
        style: TextStyle(color: textColor.withValues(alpha: 0.75), fontStyle: FontStyle.italic),
      );
    }
    final path = chatFilePath(contentType: m.contentType, fileUrl: m.fileUrl, content: m.content);
    if (path == null) {
      return ChatMessageText(
        m.content,
        style: TextStyle(color: textColor, fontSize: 15),
        linkColor: own ? textColor : AppColors.primaryLight,
        onOpenLink: onOpenLink,
      );
    }
    final url = Uri.parse(chatFileUrl(path));
    final name = fileNameOf(path);
    final image = m.contentType == 'IMAGE' || isImagePath(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (image)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              key: ValueKey('chat_image_${m.id}'),
              onTap: () => onOpenLink(url),
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url.toString(),
                  height: 180,
                  fit: BoxFit.cover,
                  cacheWidth: 720,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : SizedBox(
                          height: 180,
                          width: 180,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: textColor,
                              value: progress.expectedTotalBytes == null
                                  ? null
                                  : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                            ),
                          ),
                        ),
                  errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: textColor),
                ),
              ),
            ),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: textColor, padding: EdgeInsets.zero),
          onPressed: () => onOpenLink(url),
          icon: Icon(image ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 18),
          label: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
