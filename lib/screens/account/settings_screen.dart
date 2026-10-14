import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/password_field.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/storage_quota_card.dart';
import 'mfa_setup_screen.dart';

/// Admin `settings`: "Hesap Güvenliği" (2FA: `GET /auth/mfa/status`, enable → [MfaSetupScreen], disable →
/// `POST /auth/mfa/disable {password}`) and "Depolama" (quota card; limit/recompute only for SUPER_ADMIN, the
/// backend checks `ROLE_SUPER_ADMIN`). Every signed-in user sees this screen.
class SettingsScreen extends StatefulWidget {
  final ApiService? apiService;
  final UriLauncher? launcher;

  const SettingsScreen({super.key, this.apiService, this.launcher});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  final _quotaKey = GlobalKey<StorageQuotaCardState>();
  late Future<bool> _mfa = _loadMfa();

  Future<bool> _loadMfa() async {
    final data = await _api.get('/auth/mfa/status');
    return data is Map && data['mfaEnabled'] == true;
  }

  void _reloadMfa() => setState(() {
    _mfa = _loadMfa();
  });

  Future<void> _refresh() async {
    _reloadMfa();
    await Future.wait([
      _mfa.then((_) {}, onError: (_) {}),
      if (_quotaKey.currentState != null) _quotaKey.currentState!.reload(),
    ]);
  }

  Future<void> _enable() async {
    final enabled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MfaSetupScreen(apiService: _api, launcher: widget.launcher),
      ),
    );
    if (enabled == true && mounted) _reloadMfa();
  }

  Future<void> _disable() async {
    final disabled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MfaDisableDialog(api: _api),
    );
    if (disabled == true && mounted) {
      showAppSnackBar(context, '2FA devre dışı bırakıldı');
      _reloadMfa();
    }
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    ),
  );

  Widget _mfaCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('mfa_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: FutureBuilder<bool>(
        future: _mfa,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final enabled = snapshot.data == true;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    enabled ? Icons.verified_user_rounded : Icons.shield_outlined,
                    color: enabled ? AppColors.success : scheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text(
                        'İki Adımlı Doğrulama (2FA)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (!loading && !snapshot.hasError)
                    StatusBadge(
                      key: const ValueKey('mfa_status'),
                      label: enabled ? 'Aktif' : 'Kapalı',
                      color: enabled ? AppColors.success : null,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Authenticator uygulamasıyla üretilen tek kullanımlık kod ile hesabınıza ekstra güvenlik katmanı ekleyin.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 12),
              if (loading)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: '2FA durumu yükleniyor'),
                )
              else if (snapshot.hasError)
                Row(
                  children: [
                    Expanded(
                      child: Text('2FA durumu yüklenemedi.', style: TextStyle(color: scheme.onErrorContainer)),
                    ),
                    TextButton(onPressed: _reloadMfa, child: const Text('Tekrar Dene')),
                  ],
                )
              else if (enabled)
                OutlinedButton.icon(
                  key: const ValueKey('mfa_disable'),
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                  onPressed: _disable,
                  icon: const Icon(Icons.shield_moon_outlined),
                  label: const Text('Devre Dışı Bırak'),
                )
              else
                ElevatedButton.icon(
                  key: const ValueKey('mfa_enable'),
                  onPressed: _enable,
                  icon: const Icon(Icons.add_moderator_rounded),
                  label: const Text('Etkinleştir'),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return AppScaffold(
      title: 'Ayarlar',
      navId: 'settings',
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _sectionTitle('Hesap Güvenliği'),
            _mfaCard(),
            const SizedBox(height: 16),
            _sectionTitle('Depolama'),
            StorageQuotaCard(
              key: _quotaKey,
              api: _api,
              settings: true,
              canEditLimit: auth.roles.contains('SUPER_ADMIN'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin `MfaDisableDialog`: password confirmation. Wrong password → backend 401 "Şifre hatalı." inline; the
/// dialog cannot be dismissed while the request runs.
class _MfaDisableDialog extends StatefulWidget {
  final ApiService api;
  const _MfaDisableDialog({required this.api});

  @override
  State<_MfaDisableDialog> createState() => _MfaDisableDialogState();
}

class _MfaDisableDialogState extends State<_MfaDisableDialog> {
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/auth/mfa/disable', {'password': _password.text});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: scheme.surface,
        title: const Text('2FA\'yı Devre Dışı Bırak'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '2FA\'yı kapattığınızda hesabınız yalnızca şifreyle korunur. Devam etmek için şifrenizi girin.',
                ),
                const SizedBox(height: 16),
                PasswordField(
                  fieldKey: 'mfa_disable_password',
                  controller: _password,
                  label: 'Şifre *',
                  autofocus: true,
                  enabled: !_busy,
                  validator: (v) => (v ?? '').isEmpty ? 'Şifrenizi girin' : null,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const ValueKey('mfa_disable_error'),
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('İptal')),
          ElevatedButton(
            key: const ValueKey('mfa_disable_confirm'),
            style: ElevatedButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onError,
                      semanticsLabel: 'İşleniyor',
                    ),
                  )
                : const Text('Devre Dışı Bırak'),
          ),
        ],
      ),
    );
  }
}
