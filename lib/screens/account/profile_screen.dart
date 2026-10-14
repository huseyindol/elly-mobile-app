import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/text_format.dart';
import '../../services/user_admin.dart';
import '../../widgets/app_drawer.dart' show avatarInitials;
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';
import 'change_password_screen.dart';
import 'profile_edit_screen.dart';

/// Admin `profile`: `GET /users/me` (personal + account info), roles and permissions from
/// `/users/me/permissions`; "Düzenle" (`PUT /users/me`) and "Şifre Değiştir" (`PUT /users/me/password`, local
/// accounts only — the backend rejects OAuth users).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Always refetched on open (the drawer's copy may be stale); a cached profile stays visible meanwhile.
  Future<void> _load() async {
    setState(() => _error = null);
    final auth = context.read<AuthProvider>();
    try {
      await auth.fetchProfile();
    } catch (e) {
      if (!mounted) return;
      // A cached profile stays on screen: say the refresh failed instead of silently showing stale data.
      if (auth.profile != null) {
        showAppSnackBar(context, 'Profil yenilenemedi: $e', error: true);
      } else {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Widget _section(String title, IconData icon, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha: 0.65))),
              const SizedBox(width: 8),
              Semantics(
                header: true,
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, Object? value) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final text = '${value ?? ''}'.trim();
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          children: [
            Text(label, style: TextStyle(color: muted)),
            Text(text.isEmpty ? '—' : text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _header(AuthProvider auth, Map<String, dynamic> profile) {
    final scheme = Theme.of(context).colorScheme;
    final name = displayNameOf(profile);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Text(avatarInitials(name), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(
                  '@${profile['username'] ?? ''}',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusBadge(label: auth.roleLabel, color: AppColors.primaryLight),
                    StatusBadge.active(profile['isActive'] != false),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final local = profile?['provider'] == null || profile?['provider'] == 'local';
    final Widget body;
    if (profile == null) {
      body = _error == null
          ? const LoadingView(label: 'Profil yükleniyor')
          : ErrorView(message: _error!, onRetry: _load);
    } else {
      final groups = groupPermissions(auth.permissions);
      final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _header(auth, profile),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const ValueKey('profile_edit'),
                  onPressed: () => _push(const ProfileEditScreen()),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Düzenle'),
                ),
                if (local)
                  OutlinedButton.icon(
                    key: const ValueKey('profile_change_password'),
                    onPressed: () => _push(const ChangePasswordScreen()),
                    icon: const Icon(Icons.lock_reset_rounded),
                    label: const Text('Şifre Değiştir'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _section('Kişisel Bilgiler', Icons.person_outline_rounded, [
              _row('Ad', profile['firstName']),
              _row('Soyad', profile['lastName']),
              _row('E-posta', profile['email']),
              _row('Kullanıcı Adı', profile['username']),
            ]),
            _section('Hesap Bilgileri', Icons.settings_outlined, [
              _row('Giriş Yöntemi', local ? 'E-posta / Şifre' : profile['provider']),
              _row('Kayıt Tarihi', formatDateTimeTr(profile['createdAt']).split(' ').first),
            ]),
            _section('Roller', Icons.shield_outlined, [
              if (auth.roles.isEmpty)
                Text('Atanmış rol bulunmuyor.', style: TextStyle(color: muted))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final r in auth.roles) StatusBadge(label: r, color: AppColors.primaryLight)],
                ),
            ]),
            _section('İzinler (${auth.permissions.length})', Icons.verified_user_outlined, [
              if (groups.isEmpty)
                Text('Atanmış izin bulunmuyor.', style: TextStyle(color: muted))
              else
                for (final e in groups.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            permissionModuleLabels[e.key] ?? e.key,
                            style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 6, children: [for (final a in e.value) StatusBadge(label: a)]),
                        ],
                      ),
                    ),
                  ),
            ]),
          ],
        ),
      );
    }
    return AppScaffold(title: 'Profil', navId: 'profile', body: body);
  }
}
