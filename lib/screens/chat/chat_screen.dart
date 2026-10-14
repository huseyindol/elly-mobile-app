import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/chat_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/chat_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/connection_banner.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import 'chat_conversation_screen.dart';
import 'chat_group_form_screen.dart';

/// Opens the conversation of [groupId] above the current route.
Future<void> openChatConversation(NavigatorState navigator, String groupId) => navigator.push(
  MaterialPageRoute(
    settings: const RouteSettings(name: 'chat-conversation'),
    builder: (_) => ChatConversationScreen(groupId: groupId),
  ),
);

/// Admin `chat` page sidebar: conversations of the session tenant (unread count and last message are live),
/// new group (backend: `chat:read`), direct message by user id. Tenant chat groups (visitor access) are in the
/// same list (AC=TC), marked with the tenant and a globe.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() {
    final auth = context.read<AuthProvider>();
    return context.read<ChatProvider>().open(myUserId: auth.userId, myLevel: auth.roleLevel);
  }

  Future<void> _create() async {
    final navigator = Navigator.of(context);
    final group = await navigator.push<ChatGroup>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'chat-group-new'),
        builder: (_) => const ChatGroupFormScreen(),
      ),
    );
    if (group != null && mounted) await openChatConversation(navigator, group.id);
  }

  Future<void> _startDm() async {
    final navigator = Navigator.of(context);
    final group = await showDialog<ChatGroup>(context: context, builder: (_) => const _DmDialog());
    if (group != null && mounted) await openChatConversation(navigator, group.id);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    return AppScaffold(
      title: 'Chat',
      navId: 'chat',
      actions: [
        IconButton(
          key: const ValueKey('chat_dm_button'),
          tooltip: 'Direkt mesaj başlat',
          icon: const Icon(Icons.person_add_alt_rounded),
          onPressed: chat.tenantId == null ? null : _startDm,
        ),
      ],
      floatingActionButton: chat.groupsLoaded
          ? FloatingActionButton.extended(
              key: const ValueKey('chat_new_group'),
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yeni grup'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConnectionBanner(),
          Expanded(child: _list(chat)),
        ],
      ),
    );
  }

  Widget _list(ChatProvider chat) {
    if (!chat.groupsLoaded) {
      return chat.groupsError == null
          ? const LoadingView(label: 'Sohbetler yükleniyor')
          : ErrorView(message: chat.groupsError!, onRetry: _open);
    }
    final groups = chat.groups;
    return RefreshIndicator(
      onRefresh: chat.loadGroups,
      child: groups.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                EmptyView(icon: Icons.forum_outlined, message: 'Henüz konuşma yok. Yeni bir grup oluşturun.'),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _tile(chat, groups[i]),
            ),
    );
  }

  Widget _tile(ChatProvider chat, ChatGroup g) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 13);
    final unread = chat.unreadOf(g.id);
    final last = chat.lastMessageOf(g.id);
    final preview = last == null
        ? safeChatText(g.description ?? '')
        : last.deleted
        ? 'Mesaj silindi'
        : '${chat.isOwn(last) ? 'Siz' : safeChatText(last.senderName)}: '
              '${last.isFile ? 'Dosya' : safeChatText(last.content).replaceAll('\n', ' ')}';
    return Material(
      key: ValueKey('chat_group_${g.id}'),
      color: scheme.surface.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.2),
          foregroundColor: AppColors.primaryLight,
          child: Icon(g.isDm ? Icons.person_rounded : (g.visitorAccess ? Icons.public_rounded : Icons.forum_rounded)),
        ),
        title: Text(
          safeChatText(g.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview.isNotEmpty) Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (g.isDm)
                  const StatusBadge(label: 'Direkt mesaj')
                else
                  StatusBadge(label: chatVisibilityLabel(g.visibilityLevel)),
                if (g.visitorAccess) const StatusBadge(label: 'Ziyaretçilere açık', color: AppColors.warning),
              ],
            ),
          ],
        ),
        trailing: last == null && unread == 0
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (last != null)
                    Text(formatMessageTime(last.createdAt, DateTime.now()), style: muted.copyWith(fontSize: 12)),
                  if (unread > 0) ...[
                    const SizedBox(height: 4),
                    Semantics(
                      label: '$unread okunmamış mesaj',
                      excludeSemantics: true,
                      child: Badge(
                        key: ValueKey('chat_unread_${g.id}'),
                        label: Text(unread > 99 ? '99+' : '$unread'),
                        backgroundColor: AppColors.primaryStrong,
                        textColor: Colors.white,
                        largeSize: 22,
                      ),
                    ),
                  ],
                ],
              ),
        onTap: () => openChatConversation(Navigator.of(context), g.id),
      ),
    );
  }
}

/// Admin `DmDialog`: user id → `POST /chat/dm/{id}` (existing DM or a new one).
class _DmDialog extends StatefulWidget {
  const _DmDialog();

  @override
  State<_DmDialog> createState() => _DmDialogState();
}

class _DmDialogState extends State<_DmDialog> {
  final _id = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = int.tryParse(_id.text.trim());
    if (id == null || id <= 0) {
      setState(() => _error = 'Geçerli bir kullanıcı ID girin');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final group = await context.read<ChatProvider>().openDm(id);
      if (mounted) Navigator.of(context).pop(group);
    } catch (e) {
      if (mounted) setState(() => _error = chatErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Direkt mesaj başlat'),
        content: TextField(
          key: const ValueKey('chat_dm_user_id'),
          controller: _id,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: fieldDecoration(Theme.of(context).colorScheme, label: 'Kullanıcı ID').copyWith(errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
          FilledButton(
            key: const ValueKey('chat_dm_submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Açılıyor'),
                  )
                : const Text('Başlat'),
          ),
        ],
      ),
    );
  }
}
