import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../models/chat_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../services/chat_format.dart';
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

/// Backend multipart limit (`spring.servlet.multipart.max-file-size`).
const chatMaxFileBytes = 10 * 1024 * 1024;

/// Admin `ChatWindow` + `ChatInput` + `ChatTypingIndicator`: history newest at the bottom, older pages load while
/// scrolling up (`?before=<oldest id>`), send (REST), typing / read signals, "Görüldü" under the own last message,
/// file attachments, delete own message, ban/unban tenant-side senders (`chat:manage`). Write access from
/// `GET /access` (banner with the denial reason). The backend has no live delete/edit events and the admin has no
/// edit UI → no message editing here either.
class ChatConversationScreen extends StatefulWidget {
  final String groupId;

  /// Test seam: opens a confirmed http(s) link.
  final Future<bool> Function(Uri uri) launcher;

  const ChatConversationScreen({super.key, required this.groupId, this.launcher = _launchExternal});

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  late final ChatProvider _chat = context.read<ChatProvider>();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<ChatNotice>? _notices;

  ChatGroup? _group;
  String? _error;
  String? _banner;
  bool _sending = false;
  bool _uploading = false;
  bool _loadingOlder = false;
  bool _deletingGroup = false;

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

  void _onNotice(ChatNotice notice) {
    if (!mounted || (notice.groupId != null && notice.groupId != widget.groupId)) return;
    if (notice.leave) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).maybePop();
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(notice.message)));
      return;
    }
    setState(() => _banner = notice.message);
    showAppSnackBar(context, notice.message, error: true);
  }

  void _onScroll() {
    // Reversed list: the oldest messages are at the max extent.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) _loadOlder();
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
      _composer.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
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
      setState(() => _banner = chatErrorText(e));
      await _chat.loadAccess(group).catchError((_) => const ChatGroupAccess());
    }
  }

  Future<void> _attach() async {
    final group = _group;
    if (group == null) return;
    final picked = await FilePicker.pickFiles();
    final file = picked.firstOrNull;
    if (file?.path == null || !mounted) return;
    final size = await file!.length();
    if (!mounted) return;
    if (size != null && size > chatMaxFileBytes) {
      showAppSnackBar(context, 'Dosya 10 MB\'tan büyük olamaz.', error: true);
      return;
    }
    setState(() => _uploading = true);
    try {
      await _chat.sendFile(group, file.path!);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      await _sendFailed(group, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
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
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Grup silindi')));
    } catch (e) {
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _deletingGroup = false);
    }
  }

  Future<void> _messageActions(ChatMessage m, {required bool own, required bool canModerate}) async {
    final group = _group!;
    final banned = m.banKey != null && _chat.bannedKeys.contains(m.banKey);
    final canCopy = !m.deleted && !m.isFile;
    final canDelete = own && !m.deleted;
    if (!canCopy && !canDelete && !canModerate) return;
    final action = await showModalBottomSheet<String>(
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
                onTap: () => Navigator.pop(sheet, 'copy'),
              ),
            if (canModerate)
              ListTile(
                key: const ValueKey('chat_action_ban'),
                leading: Icon(banned ? Icons.verified_user_outlined : Icons.block_rounded),
                title: Text(banned ? 'Yasağı kaldır' : 'Yazmasını yasakla'),
                onTap: () => Navigator.pop(sheet, banned ? 'unban' : 'ban'),
              ),
            if (canDelete)
              ListTile(
                key: const ValueKey('chat_action_delete'),
                iconColor: Theme.of(sheet).colorScheme.onErrorContainer,
                textColor: Theme.of(sheet).colorScheme.onErrorContainer,
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Mesajı sil'),
                onTap: () => Navigator.pop(sheet, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'copy':
          await Clipboard.setData(ClipboardData(text: safeChatText(m.content)));
          if (mounted) showAppSnackBar(context, 'Kopyalandı');
        case 'delete':
          if (await showConfirmDialog(
                context,
                title: 'Mesajı sil',
                message: 'Mesaj herkes için "silindi" olarak görünecek.',
                confirmLabel: 'Sil',
                destructive: true,
              ) &&
              mounted) {
            await _chat.deleteMessage(group, m);
          }
        case 'ban':
          if (await showConfirmDialog(
                context,
                title: 'Yazmasını yasakla',
                message:
                    '"${safeChatText(m.senderName)}" bu grupta artık yazamayacak (okuma serbest). Yasak sonradan kaldırılabilir.',
                confirmLabel: 'Yasakla',
                destructive: true,
              ) &&
              mounted) {
            await _chat.ban(group, m);
            if (mounted) showAppSnackBar(context, 'Kullanıcı yasaklandı');
          }
        case 'unban':
          await _chat.unban(group, m);
          if (mounted) showAppSnackBar(context, 'Yasak kaldırıldı');
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final auth = context.watch<AuthProvider>();
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
          Expanded(child: _body(chat, auth)),
          if (group != null && _error == null) _composerArea(chat, group),
        ],
      ),
    );
  }

  Widget _body(ChatProvider chat, AuthProvider auth) {
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _group == null ? _open : () => _reload(_group!));
    }
    final group = _group;
    if (group == null || !chat.historyLoaded(group.id)) return const LoadingView(label: 'Mesajlar yükleniyor');
    final messages = chat.messagesOf(group.id);
    if (messages.isEmpty) {
      return const EmptyView(
        icon: Icons.chat_bubble_outline_rounded,
        message: 'Henüz mesaj yok. İlk mesajı siz gönderin.',
      );
    }
    final canModerate = auth.has('chat:manage');
    final seen = chat.seenBy(group.id);
    final now = DateTime.now();
    // index 0 = newest (reversed list); last index = older-page loader / start marker.
    return ListView.builder(
      key: const ValueKey('chat_messages'),
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == messages.length) return _historyEnd(chat.hasMore(group.id));
        final i = messages.length - 1 - index;
        final m = messages[i];
        final prev = i > 0 ? messages[i - 1] : null;
        final own = chat.isOwn(m);
        final continued =
            prev != null &&
            !prev.deleted &&
            _senderKey(prev) == _senderKey(m) &&
            m.createdAt != null &&
            prev.createdAt != null &&
            m.createdAt!.difference(prev.createdAt!).inMinutes < 5;
        return _MessageBubble(
          key: ValueKey('chat_msg_${m.id}'),
          message: m,
          own: own,
          showSender: !own && !continued,
          banned: m.banKey != null && chat.bannedKeys.contains(m.banKey),
          time: formatMessageTime(m.createdAt, now),
          seenBy: index == 0 && own ? seen : const [],
          onOpenLink: _openLink,
          onActions: () => _messageActions(m, own: own, canModerate: canModerate && !own && m.banKey != null),
        );
      },
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

  Widget _composerArea(ChatProvider chat, ChatGroup group) {
    final scheme = Theme.of(context).colorScheme;
    final access = chat.accessOf(group.id);
    final canWrite = access?.canWrite ?? false;
    final banner = _banner ?? (access != null && !canWrite ? access.denialMessage : null);
    final typing = chat.typingText(group.id);
    final busy = _sending || _uploading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Semantics(
            liveRegion: true,
            child: Text(
              typing ?? '',
              key: const ValueKey('chat_typing'),
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        if ((banner ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Semantics(liveRegion: true, child: InfoNote(safeChatText(banner!), warning: true)),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('chat_attach'),
                  tooltip: 'Dosya ekle',
                  onPressed: canWrite && !busy ? _attach : null,
                  icon: _uploading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Dosya yükleniyor'),
                        )
                      : const Icon(Icons.attach_file_rounded),
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
                        currentLength > 3500 ? Text('$currentLength/$maxLength') : null,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: fieldDecoration(
                      scheme,
                      hint: canWrite ? 'Mesaj yazın…' : 'Bu gruba mesaj gönderemezsiniz',
                    ).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    onChanged: (_) {
                      chat.typing(group);
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
                      : Icon(Icons.send_rounded, color: canWrite ? scheme.primary : null),
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
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = message;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.65));
    final senderName = safeChatText(m.senderName).trim();
    final (badge, badgeColor) = switch (m.senderType) {
      'VISITOR' => ('Ziyaretçi', AppColors.warning),
      'GUEST' => ('Misafir', scheme.secondary),
      _ => ('Admin', AppColors.primaryLight),
    };
    final bubbleColor = own ? AppColors.primaryStrong : scheme.surface;
    final textColor = own ? scheme.onPrimary : scheme.onSurface;
    return Padding(
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryLight),
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
                child: Semantics(
                  onLongPressHint: 'Mesaj seçenekleri',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: _content(context, textColor),
                  ),
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url.toString(),
                height: 180,
                fit: BoxFit.cover,
                cacheWidth: 720,
                semanticLabel: 'Görsel: $name',
                errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: textColor),
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
