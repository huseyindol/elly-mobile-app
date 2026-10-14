import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/text_format.dart';
import '../../services/user_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/searchable_paged_list.dart';
import '../../widgets/status_badge.dart';
import 'user_form_screen.dart';

/// Admin `users` page: panel users (SUPER_ADMIN/ADMIN/EDITOR/VIEWER) and tenant users (TENANT) in two tabs,
/// `GET /users?audience=panel|tenant` (whole list, client search). Everything needs `users:manage` (drawer gate).
/// Role hierarchy ([canManageUser]): users above the caller's level are listed but not editable; the caller
/// cannot delete or deactivate themselves (backend guards both, the UI does not offer them).
class UsersScreen extends StatefulWidget {
  final ApiService? apiService;
  const UsersScreen({super.key, this.apiService});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  final _listKeys = {'panel': GlobalKey<SearchablePagedListState>(), 'tenant': GlobalKey<SearchablePagedListState>()};
  String _audience = 'panel';
  final Set<Object?> _busy = {};

  @override
  void initState() {
    super.initState();
    // Self guards need the signed-in user's id; the startup profile load may have failed.
    final auth = context.read<AuthProvider>();
    if (auth.profile == null) auth.loadProfile();
  }

  Future<void> _reload() async => _listKeys[_audience]!.currentState?.reload();

  bool _isSelf(AuthProvider auth, Map<String, dynamic> user) =>
      (auth.userId != null && user['id'] == auth.userId) ||
      (auth.profile == null && user['username'] == auth.currentUser?.username);

  Future<void> _openForm([Map<String, dynamic>? user]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UserFormScreen(audience: _audience, user: user, apiService: _api),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _setActive(Map<String, dynamic> user, bool active) async {
    if (!active) {
      final ok = await showConfirmDialog(
        context,
        title: 'Kullanıcıyı Pasifleştir',
        message: '@${user['username']} pasifleştirilecek; açık oturumları sonlanır ve giriş yapamaz.',
        confirmLabel: 'Pasifleştir',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    final id = user['id'];
    setState(() => _busy.add(id));
    try {
      await _api.patch('/users/$id/status?isActive=$active');
      if (mounted) showAppSnackBar(context, active ? 'Kullanıcı aktifleştirildi' : 'Kullanıcı pasifleştirildi');
      await _reload();
    } catch (e) {
      if (mounted) showAppSnackBar(context, userErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _delete(Map<String, dynamic> user) async {
    final username = '${user['username']}';
    final ok = await showConfirmDialog(
      context,
      title: _audience == 'panel' ? 'Kullanıcıyı Sil' : 'Tenant Kullanıcısını Sil',
      message: '@$username kullanıcısı kalıcı olarak silinecek. Aktif oturumları sonlanır. Bu işlem geri alınamaz.',
      confirmLabel: 'Evet, Sil',
      destructive: true,
      requiredText: username,
      confirmKey: const ValueKey('confirm_delete_button'),
    );
    if (!ok || !mounted) return;
    final id = user['id'];
    setState(() => _busy.add(id));
    try {
      await _api.delete('/users/$id');
      if (mounted) showAppSnackBar(context, 'Kullanıcı silindi');
      await _reload();
    } catch (e) {
      if (mounted) showAppSnackBar(context, userErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  static Color? _roleColor(String role) => switch (role) {
    'SUPER_ADMIN' || 'ADMIN' => AppColors.primaryLight,
    'EDITOR' => AppColors.success,
    _ => null,
  };

  Widget _card(BuildContext itemContext, Map<String, dynamic> user, AuthProvider auth) {
    final scheme = Theme.of(itemContext).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65));
    final id = user['id'];
    final username = '${user['username'] ?? ''}';
    final roles = rolesOf(user);
    final active = user['isActive'] != false;
    final self = _isSelf(auth, user);
    final manageable = canManageUser(auth.roleLevel, roles);
    final busy = _busy.contains(id);
    final created = formatDateTimeTr(user['createdAt']).split(' ').first;
    Text label(String action) => Text(action, semanticsLabel: '$action: @$username');

    return Container(
      key: ValueKey('user_$id'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: active ? 0.7 : 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(displayNameOf(user), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          Text('@$username', style: muted),
          Text('${user['email'] ?? ''}', style: muted),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (self) const StatusBadge(label: 'Siz', color: AppColors.warning),
              if (_audience == 'panel') ...[
                for (final role in roles) StatusBadge(label: role, color: _roleColor(role)),
                if (roles.isEmpty) const StatusBadge(label: 'Rol yok'),
              ],
              StatusBadge.active(active),
            ],
          ),
          if (created.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Kayıt: $created', style: muted.copyWith(fontSize: 12)),
          ],
          if (!manageable) ...[
            const SizedBox(height: 6),
            Text(
              'Üst seviye kullanıcı — rolünüz bu kullanıcıyı yönetmeye yetmez.',
              key: ValueKey('user_locked_$id'),
              style: muted.copyWith(fontSize: 12),
            ),
          ],
          if (manageable)
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  key: ValueKey('edit_$id'),
                  onPressed: busy ? null : () => _openForm(user),
                  icon: const Icon(Icons.edit_rounded),
                  label: label('Düzenle'),
                ),
                if (!active || !self)
                  TextButton.icon(
                    key: ValueKey('status_$id'),
                    onPressed: busy ? null : () => _setActive(user, !active),
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'İşleniyor'),
                          )
                        : Icon(active ? Icons.block_rounded : Icons.check_circle_outline_rounded),
                    label: label(active ? 'Pasifleştir' : 'Aktifleştir'),
                  ),
                if (!self)
                  TextButton.icon(
                    key: ValueKey('delete_$id'),
                    style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                    onPressed: busy ? null : () => _delete(user),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: label('Sil'),
                  ),
              ],
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget chip(String audience, String text) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('audience_$audience'),
        label: Text(text),
        selected: _audience == audience,
        onSelected: (_) => setState(() => _audience = audience),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [chip('panel', 'Panel Kullanıcıları'), chip('tenant', 'Tenant Kullanıcıları')]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final panel = _audience == 'panel';
    return AppScaffold(
      title: 'Kullanıcılar',
      navId: 'users',
      actions: [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reload)],
      body: Column(
        children: [
          _tabs(),
          Expanded(
            child: SearchablePagedList(
              key: _listKeys[_audience],
              api: _api,
              endpoint: '/users?audience=$_audience',
              emptyMessage: panel ? 'Panel kullanıcısı bulunamadı.' : 'Tenant kullanıcısı bulunamadı.',
              searchText: (u) =>
                  [u['username'], u['email'], u['firstName'], u['lastName']].map((v) => v ?? '').join(' '),
              itemBuilder: (itemContext, user) => _card(itemContext, user, auth),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: panel ? 'Yeni Panel Kullanıcısı' : 'Yeni Tenant Kullanıcısı',
        onPressed: () => _openForm(),
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
    );
  }
}
