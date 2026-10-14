import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/user_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/info_note.dart';
import '../../widgets/password_field.dart';
import '../../widgets/save_bar.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_badge.dart';

/// Admin users page create / edit modals as one screen.
/// Create: `POST /users` (DtoCreateUser; panel: roleIds, none → backend ADMIN; tenant: TENANT automatically).
/// Edit: `GET /users/{id}` → `PUT /users/{id}` (changed fields; a filled new password is an admin reset that
/// ends the user's sessions) → roles changed: `PUT /roles/users/{id}/roles {roleIds}` (replaces all roles).
/// Roles offered: [canAssignRole] for the caller's level. Own account: no role change, no password reset here
/// (Profil → Şifre Değiştir asks for the current password).
class UserFormScreen extends StatefulWidget {
  /// `panel` | `tenant`.
  final String audience;

  /// List row; null = new user.
  final Map<String, dynamic>? user;
  final ApiService? apiService;

  const UserFormScreen({super.key, required this.audience, this.user, this.apiService});

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  static const _textKeys = ['firstName', 'lastName', 'username', 'email'];
  static const _labels = {
    'firstName': 'Ad',
    'lastName': 'Soyad',
    'username': 'Kullanıcı Adı',
    'email': 'E-posta',
    'password': 'Şifre',
    'roles': 'Roller',
  };

  late final ApiService _api = widget.apiService ?? ApiService();
  final _formKey = GlobalKey<FormState>();
  final _controllers = {for (final k in _textKeys) k: TextEditingController()};
  final _password = TextEditingController();
  Map<String, dynamic>? _record;
  List<Map<String, dynamic>> _roles = const [];
  Set<int> _selectedRoles = {};
  Set<int> _savedRoles = {};
  bool _ready = false;
  String? _loadError;
  bool _saving = false;
  bool _dirty = false;

  bool get _isEditing => widget.user != null;
  bool get _panel => widget.audience == 'panel';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [..._controllers.values, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Own account (pass the auth from `watch` in build, `read` elsewhere).
  bool _isSelfFor(AuthProvider auth) {
    final id = (_record ?? widget.user)?['id'];
    return _isEditing && id != null && id == auth.userId;
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final results = await Future.wait([
        if (_isEditing) _api.get('/users/${widget.user!['id']}') else Future.value(null),
        // GET /roles: roles:read or users:manage (the screen's own permission).
        if (_panel) _api.get('/roles') else Future.value(const []),
      ]);
      if (!mounted) return;
      final record = results[0] is Map ? Map<String, dynamic>.from(results[0] as Map) : null;
      final roles = [for (final r in (results[1] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
      setState(() {
        _record = record;
        _roles = roles;
        for (final k in _textKeys) {
          _controllers[k]!.text = '${record?[k] ?? ''}';
        }
        final names = record == null ? const <String>[] : rolesOf(record);
        _savedRoles = {
          for (final r in roles)
            if (names.contains(r['name'])) (r['id'] as num).toInt(),
        };
        _selectedRoles = {..._savedRoles};
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  bool _fieldsChanged() =>
      _record == null ||
      _textKeys.any((k) => _controllers[k]!.text.trim() != '${_record![k] ?? ''}') ||
      _password.text.isNotEmpty;

  Future<void> _save() async {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reportInvalidFields(context, invalid, labelOf: _labelOf);
      return;
    }
    final c = _controllers;
    final auth = context.read<AuthProvider>();
    final self = _isSelfFor(auth);
    final rolesChanged = _selectedRoles.length != _savedRoles.length || !_selectedRoles.containsAll(_savedRoles);
    setState(() => _saving = true);
    try {
      if (!_isEditing) {
        await _api.post(
          '/users',
          createUserPayload(
            audience: widget.audience,
            username: c['username']!.text,
            email: c['email']!.text,
            password: _password.text,
            firstName: c['firstName']!.text,
            lastName: c['lastName']!.text,
            roleIds: _selectedRoles.toList()..sort(),
          ),
        );
      } else {
        final id = _record!['id'];
        if (_fieldsChanged()) {
          final updated = await _api.put(
            '/users/$id',
            updateUserPayload(
              username: c['username']!.text,
              email: c['email']!.text,
              firstName: c['firstName']!.text,
              lastName: c['lastName']!.text,
              newPassword: self ? '' : _password.text,
            ),
          );
          // A role failure below must not resend the (already saved) fields and password on retry.
          if (updated is Map) _record = Map<String, dynamic>.from(updated);
          _password.clear();
        }
        if (_panel && !self && rolesChanged) {
          await _api.put('/roles/users/$id/roles', {'roleIds': _selectedRoles.toList()..sort()});
          _savedRoles = {..._selectedRoles};
        }
      }
      if (!mounted) return;
      if (self) auth.loadProfile();
      ScaffoldMessenger.of(context).clearSnackBars();
      showAppSnackBar(
        context,
        _isEditing ? 'Kullanıcı güncellendi' : 'Kullanıcı oluşturuldu — doğrulama e-postası gönderildi',
      );
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAppSnackBar(context, userErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _labelOf(FormFieldState<Object?> state) {
    final key = state.widget.key;
    return key is ValueKey<String> ? _labels[key.value.replaceFirst('user_field_', '')] : null;
  }

  Widget _text(
    String key, {
    String? Function(String)? validator,
    bool required = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('user_field_$key'),
      controller: _controllers[key],
      keyboardType: keyboard,
      autocorrect: false,
      enableSuggestions: key == 'firstName' || key == 'lastName',
      textCapitalization: key == 'firstName' || key == 'lastName' ? TextCapitalization.words : TextCapitalization.none,
      decoration: fieldDecoration(Theme.of(context).colorScheme, label: required ? '${_labels[key]} *' : _labels[key]),
      validator: validator == null ? null : (v) => validator(v ?? ''),
      onChanged: (_) => _markDirty(),
    ),
  );

  Widget _rolesField(int myLevel, bool self) {
    final scheme = Theme.of(context).colorScheme;
    if (self) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final r in rolesOf(_record!)) StatusBadge(label: r, color: AppColors.primaryLight)],
          ),
          const SizedBox(height: 8),
          const InfoNote('Kendi rollerinizi değiştiremezsiniz (yetkinizi kaybedebilirsiniz).'),
        ],
      );
    }
    final assignable = _roles.where((r) => canAssignRole(myLevel, '${r['name']}')).toList();
    final defaultAdmin = !_isEditing && canUseDefaultAdminRole(myLevel);
    return FormField<Set<int>>(
      key: const ValueKey('user_field_roles'),
      validator: (_) {
        if (_selectedRoles.isNotEmpty || defaultAdmin) return null;
        return _isEditing ? 'En az bir rol seçin' : 'En az bir rol seçin (varsayılan ADMIN rolünü atayamazsınız)';
      },
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (assignable.isEmpty)
            Text('Atayabileceğiniz rol yok.', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7))),
          for (final role in assignable)
            CheckboxListTile(
              key: ValueKey('role_${role['name']}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('${role['name']}'),
              subtitle: '${role['description'] ?? ''}'.isEmpty ? null : Text('${role['description']}'),
              value: _selectedRoles.contains((role['id'] as num).toInt()),
              onChanged: _saving
                  ? null
                  : (checked) {
                      final id = (role['id'] as num).toInt();
                      setState(() => checked == true ? _selectedRoles.add(id) : _selectedRoles.remove(id));
                      _markDirty();
                      field.didChange(_selectedRoles);
                    },
            ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(field.errorText!, style: TextStyle(color: scheme.onErrorContainer, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          InfoNote(
            _isEditing
                ? 'Kaydedildiğinde kullanıcının tüm rolleri bu seçimle değiştirilir.'
                : defaultAdmin
                ? 'Rol seçilmezse ADMIN rolü atanır.'
                : 'Kendi rol seviyenizin üstündeki roller listelenmez.',
            warning: _isEditing,
          ),
        ],
      ),
    );
  }

  Widget _form() {
    final auth = context.watch<AuthProvider>();
    final myLevel = auth.roleLevel;
    final self = _isSelfFor(auth);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _text('firstName'),
          _text('lastName'),
          _text(
            'username',
            required: !_isEditing,
            validator: (v) => usernameError(v, required: !_isEditing),
          ),
          _text(
            'email',
            required: !_isEditing,
            keyboard: TextInputType.emailAddress,
            validator: (v) => emailError(v, required: !_isEditing),
          ),
          if (!self) ...[
            PasswordField(
              fieldKey: 'user_field_password',
              controller: _password,
              newPassword: true,
              label: _isEditing ? 'Yeni Şifre' : 'Şifre *',
              hint: passwordRuleHint,
              helper: _isEditing ? 'Boş bırakılırsa değişmez' : null,
              validator: (v) => _isEditing && (v ?? '').isEmpty ? null : passwordError(v ?? ''),
              onChanged: (_) => _markDirty(),
            ),
            const SizedBox(height: 16),
            if (_isEditing)
              const InfoNote(
                'Şifre sıfırlanırsa kullanıcının açık oturumları sonlanır ve yeni şifreyle giriş yapması gerekir.',
              ),
          ] else
            const InfoNote('Kendi şifrenizi Profil → Şifre Değiştir ekranından değiştirin (mevcut şifre sorulur).'),
          if (_panel) ...[
            Semantics(header: true, child: Text(_labels['roles']!, style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(height: 8),
            _rolesField(myLevel, self),
          ],
          if (!_isEditing)
            InfoNote(
              _panel
                  ? 'Kullanıcı oluşturulduktan sonra panel domain\'inden doğrulama e-postası gönderilir. TENANT rolü '
                        'bu ekrandan atanamaz.'
                  : 'Kullanıcıya TENANT rolü atanır ve doğrulama e-postası bu tenant\'ın kendi site domain\'inden '
                        'gönderilir.',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loadError != null) {
      body = ErrorView(message: _loadError!, onRetry: _load);
    } else if (!_ready) {
      body = const LoadingView();
    } else {
      body = _form();
    }
    final title = _isEditing
        ? 'Düzenle — @${widget.user!['username']}'
        : (_panel ? 'Yeni Panel Kullanıcısı' : 'Yeni Tenant Kullanıcısı');
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeaveForm(context, saving: _saving) && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        title: title,
        body: body,
        bottomNavigationBar: _ready
            ? SaveBar(onPressed: _save, loading: _saving, label: _isEditing ? 'Kaydet' : 'Oluştur')
            : null,
      ),
    );
  }
}
