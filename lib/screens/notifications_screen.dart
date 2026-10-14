import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/nav_config.dart';
import '../models/chat_models.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../services/api_service.dart';
import '../services/chat_format.dart';
import '../services/stomp_destinations.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/state_views.dart';
import 'chat/chat_screen.dart';
import 'forms/form_submissions_screen.dart';

/// Opens the screen a notification points to (admin `router.push(n.link)`): `/chat` (+ `metadata.groupId` → that
/// conversation), `/forms/{id}/submissions`, or a drawer section (`/email-logs`, `/mail-accounts`, `/users`, …).
/// Only these known paths are followed, never a URL; a section without permission is not opened.
Future<void> openNotification(BuildContext context, AppNotification n, {ApiService? api}) async {
  final target = notificationTarget(n.link, n.metadata);
  final auth = context.read<AuthProvider>();
  final navigator = Navigator.of(context);
  NavItem? item(String id) => [for (final g in NavConfig.groups) ...g.items].where((i) => i.id == id).firstOrNull;
  void unavailable() => showAppSnackBar(context, 'Bu bildirimin mobilde açılacak bir ekranı yok ya da yetkiniz yok.');

  switch (target?.kind) {
    case 'chat':
      final chat = item('chat');
      if (chat == null || !isNavItemVisible(auth, chat)) return unavailable();
      openNavItem(context, chat);
      if (isUuid(target!.id)) await openChatConversation(navigator, target.id!);
    case 'formSubmissions':
      if (!auth.has('forms:read')) return unavailable();
      try {
        final form = await (api ?? ApiService()).get('/forms/${target!.id}');
        if (form is! Map) return;
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => FormSubmissionsScreen(form: Map<String, dynamic>.from(form), apiService: api),
          ),
        );
      } catch (e) {
        if (context.mounted) showAppSnackBar(context, '$e', error: true);
      }
    case 'nav':
      final section = item(target!.id!);
      if (section == null || !isNavItemVisible(auth, section) || navScreen(section) == null) return unavailable();
      openNavItem(context, section);
    default:
      unavailable();
  }
}

/// App-bar bell (admin `NotificationBell`): unread badge, opens [NotificationsScreen]. Hidden when the app runs
/// without the notifications provider (some widget tests).
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationsProvider?>();
    if (notifications == null) return const SizedBox.shrink();
    final count = notifications.unreadCount;
    return IconButton(
      key: const ValueKey('notification_bell'),
      tooltip: count > 0 ? 'Bildirimler, $count okunmamış' : 'Bildirimler',
      // The tooltip carries the count; the badge digits would be read a second time.
      icon: ExcludeSemantics(
        child: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: const Icon(Icons.notifications_none_rounded),
        ),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'notifications'),
          builder: (_) => const NotificationsScreen(),
        ),
      ),
    );
  }
}

/// Notification list: newest first, paged (scroll), pull-to-refresh, "Tümünü okundu", delete. Tapping marks it read
/// and opens its screen ([openNotification]). Title/message come from user data (form titles, chat previews) →
/// plain text through [safeChatText].
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsProvider _provider = context.read<NotificationsProvider>();
  final _scroll = ScrollController();
  bool _markingAll = false;

  /// Deleted on screen, sent once the "Geri al" SnackBar closes without undo (the backend has no restore).
  final Map<int, AppNotification> _pendingDelete = {};

  @override
  void initState() {
    super.initState();
    _provider.listVisible = true;
    _scroll.addListener(() {
      // After a failed page the inline "Tekrar dene" retries; scrolling does not hammer the server.
      if (_provider.loadMoreError == null && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _provider.load());
  }

  @override
  void dispose() {
    _provider.listVisible = false;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    try {
      await _provider.loadMore();
    } catch (_) {
      // shown inline (loadMoreError) with "Tekrar dene"
    }
  }

  Future<void> _markAll() async {
    setState(() => _markingAll = true);
    try {
      await _provider.markAllRead();
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      _provider.markRead(n).catchError((Object e) {
        if (mounted) showAppSnackBar(context, '$e', error: true);
      });
    }
    if (mounted) await openNotification(context, n); // no target: explains why nothing opens
  }

  void _delete(AppNotification n) {
    if (_pendingDelete.containsKey(n.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pendingDelete[n.id] = n);
    final controller = showSnackBarOn(
      messenger,
      'Bildirim silindi',
      duration: const Duration(seconds: 4),
      persist: false, // the undo window ends, then the delete is sent
      action: SnackBarAction(label: 'Geri al', onPressed: () {}),
    );
    controller.closed.then((reason) async {
      if (reason == SnackBarClosedReason.action) {
        if (mounted) setState(() => _pendingDelete.remove(n.id));
        return;
      }
      try {
        await _provider.remove(n);
      } catch (e) {
        showSnackBarOn(messenger, 'Bildirim silinemedi: $e', error: true);
      }
      if (mounted) setState(() => _pendingDelete.remove(n.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationsProvider>();
    return AppScaffold(
      title: 'Bildirimler',
      actions: [
        if (p.unreadCount > 0)
          IconButton(
            key: const ValueKey('notifications_read_all'),
            tooltip: 'Tümünü okundu işaretle',
            icon: const Icon(Icons.done_all_rounded),
            onPressed: _markingAll ? null : _markAll,
          ),
      ],
      body: _body(p),
    );
  }

  Widget _body(NotificationsProvider p) {
    if (!p.loaded) {
      return p.error == null
          ? const LoadingView(label: 'Bildirimler yükleniyor')
          : ErrorView(message: p.error!, onRetry: p.load);
    }
    final items = p.items.where((n) => !_pendingDelete.containsKey(n.id)).toList();
    return RefreshIndicator(
      onRefresh: p.load,
      child: Column(
        children: [
          if (p.loading) const LinearProgressIndicator(minHeight: 2, semanticsLabel: 'Bildirimler yenileniyor'),
          Expanded(
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 80),
                      EmptyView(icon: Icons.notifications_off_outlined, message: 'Bildirim yok'),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: items.length + (p.hasMore ? 1 : 0),
                    itemBuilder: (_, i) => i == items.length ? _moreRow(p) : _tile(items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _moreRow(NotificationsProvider p) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: p.loadMoreError == null
          ? const CircularProgressIndicator(semanticsLabel: 'Daha fazla bildirim yükleniyor')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sonraki sayfa yüklenemedi: ${p.loadMoreError}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                TextButton(
                  key: const ValueKey('notifications_load_more_retry'),
                  onPressed: _loadMore,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
    ),
  );

  Widget _tile(AppNotification n) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 13);
    final title = safeChatText(n.title).trim();
    return Padding(
      key: ValueKey('notification_${n.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: n.read ? scheme.surface.withValues(alpha: 0.5) : scheme.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          leading: n.read
              ? const SizedBox(width: 10)
              : Semantics(
                  label: 'Okunmamış',
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  ),
                ),
          minLeadingWidth: 10,
          title: Text(
            title.isEmpty ? 'Bildirim' : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n.message.isNotEmpty)
                Text(safeChatText(n.message), maxLines: 3, overflow: TextOverflow.ellipsis, style: muted),
              Text(formatRelativeTr(n.createdAt, DateTime.now()), style: muted.copyWith(fontSize: 12)),
              if (notificationTarget(n.link, n.metadata) == null)
                Text(
                  'Mobilde açılacak bir ekranı yok',
                  style: muted.copyWith(fontSize: 12, fontStyle: FontStyle.italic),
                ),
            ],
          ),
          trailing: IconButton(
            key: ValueKey('notification_delete_${n.id}'),
            tooltip: 'Sil: ${title.isEmpty ? 'Bildirim' : title}',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(n),
          ),
          onTap: () => _open(n),
        ),
      ),
    );
  }
}
