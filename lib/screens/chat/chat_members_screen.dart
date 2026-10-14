import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/chat_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/chat_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/info_note.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';

/// Admin `ChatMemberList`: members (owner badge, online when a presence event said so), invite by user id or e-mail
/// and remove (`chat:manage`). Invites follow the backend hierarchy (own role level and below; SUPER_ADMIN anyone) —
/// the target's level isn't known here, so the rule is shown and a refusal comes back as a readable error.
class ChatMembersScreen extends StatefulWidget {
  final ChatGroup group;
  const ChatMembersScreen({super.key, required this.group});

  @override
  State<ChatMembersScreen> createState() => _ChatMembersScreenState();
}

class _ChatMembersScreenState extends State<ChatMembersScreen> {
  final _invite = TextEditingController();
  List<ChatMember>? _members;
  String? _error;
  String? _inviteError;
  bool _inviting = false;
  final Set<int> _removing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final members = await context.read<ChatProvider>().members(widget.group);
      if (mounted) setState(() => _members = members);
    } catch (e) {
      if (mounted) setState(() => _error = chatErrorText(e));
    }
  }

  Future<void> _sendInvite() async {
    final invalid = inviteInputError(_invite.text);
    if (invalid != null) {
      setState(() => _inviteError = invalid);
      return;
    }
    setState(() {
      _inviting = true;
      _inviteError = null;
    });
    try {
      final member = await context.read<ChatProvider>().invite(widget.group, _invite.text);
      if (!mounted) return;
      _invite.clear();
      setState(() {
        if (member != null) _members = [...?_members?.where((m) => m.userId != member.userId), member];
      });
      showAppSnackBar(context, 'Kullanıcı gruba eklendi');
    } catch (e) {
      if (mounted) setState(() => _inviteError = chatErrorText(e));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _remove(ChatMember m) async {
    final name = safeChatText(m.displayName);
    final ok = await showConfirmDialog(
      context,
      title: 'Üyeyi çıkar',
      message: '"$name" gruptan çıkarılacak ve mesajları göremeyecek.',
      confirmLabel: 'Çıkar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _removing.add(m.userId));
    try {
      await context.read<ChatProvider>().removeMember(widget.group, m.userId);
      if (mounted) setState(() => _members = _members?.where((x) => x.userId != m.userId).toList());
    } catch (e) {
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _removing.remove(m.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();
    final canManage = auth.has('chat:manage');
    final members = _members;
    return AppScaffold(
      title: 'Üyeler${members == null ? '' : ' (${members.length})'}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : members == null
                ? const LoadingView(label: 'Üyeler yükleniyor')
                : members.isEmpty
                ? const EmptyView(icon: Icons.group_off_outlined, message: 'Üye bulunamadı.')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(), // pull-to-refresh also with few members
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: members.length,
                      itemBuilder: (_, i) => _tile(members[i], chat, auth, canManage),
                    ),
                  ),
          ),
          if (canManage) _invitePanel(auth.roleLevel),
        ],
      ),
    );
  }

  Widget _tile(ChatMember m, ChatProvider chat, AuthProvider auth, bool canManage) {
    final scheme = Theme.of(context).colorScheme;
    final online = chat.isOnline(m.userId) == true;
    final name = safeChatText(m.displayName);
    // Own row: no remove (leaving would lock the user out of the group); unknown own id → nobody removable.
    final removable = canManage && !m.isOwner && auth.identityKnown && m.userId != auth.userId;
    return ListTile(
      key: ValueKey('chat_member_${m.userId}'),
      leading: Badge(
        isLabelVisible: online,
        backgroundColor: AppColors.success,
        smallSize: 10,
        alignment: AlignmentDirectional.bottomEnd,
        child: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.2),
          foregroundColor: AppColors.primaryLight,
          child: const Icon(Icons.person_rounded),
        ),
      ),
      title: Text(name.isEmpty ? '#${m.userId}' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '@${safeChatText(m.username)} · ID ${m.userId}',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
          if (m.isOwner) const StatusBadge(label: 'Sahip', color: AppColors.primaryLight),
          if (online) const StatusBadge(label: 'Çevrimiçi', color: AppColors.success),
        ],
      ),
      trailing: removable
          ? IconButton(
              key: ValueKey('chat_remove_${m.userId}'),
              tooltip: 'Gruptan çıkar: $name',
              icon: _removing.contains(m.userId)
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Çıkarılıyor'),
                    )
                  : Icon(Icons.person_remove_outlined, color: scheme.onErrorContainer),
              onPressed: _removing.contains(m.userId) ? null : () => _remove(m),
            )
          : null,
    );
  }

  Widget _invitePanel(int level) {
    final scheme = Theme.of(context).colorScheme;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Scrollable and capped: on small screens with the keyboard open the member list keeps some room.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
      child: SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.1))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (keyboardOpen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      inviteHint(level),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  )
                else
                  InfoNote(inviteHint(level)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('chat_invite_input'),
                        controller: _invite,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.emailAddress,
                        decoration: fieldDecoration(
                          scheme,
                          label: 'Kullanıcı ID veya e-posta',
                        ).copyWith(errorMaxLines: 3),
                        forceErrorText: _inviteError, // input rule or backend refusal (hierarchy, not found, member)
                        onChanged: (_) {
                          if (_inviteError != null) setState(() => _inviteError = null);
                        },
                        onFieldSubmitted: (_) => _sendInvite(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: const ValueKey('chat_invite_submit'),
                        onPressed: _inviting ? null : _sendInvite,
                        child: _inviting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Davet ediliyor'),
                              )
                            : const Text('Davet et'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
