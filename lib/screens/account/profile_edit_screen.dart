import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/user_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/save_bar.dart';

/// Admin profile "Profil Bilgilerini Güncelle": `PUT /users/me {firstName, lastName, email}` (DtoUserUpdate; the
/// admin form has no username field). E-mail is required here: the backend's `@Email` accepts "" and would blank it.
class ProfileEditScreen extends StatefulWidget {
  final ApiService? apiService;
  const ProfileEditScreen({super.key, this.apiService});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  static const _labels = {'firstName': 'Ad', 'lastName': 'Soyad', 'email': 'E-posta'};

  late final ApiService _api = widget.apiService ?? ApiService();
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile ?? const {};
    _controllers = {for (final k in _labels.keys) k: TextEditingController(text: '${profile[k] ?? ''}')};
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reportInvalidFields(context, invalid, labelOf: _labelOf);
      return;
    }
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      final updated = await _api.put('/users/me', {for (final e in _controllers.entries) e.key: e.value.text.trim()});
      if (!mounted) return;
      if (updated is Map) auth.setProfile(Map<String, dynamic>.from(updated));
      ScaffoldMessenger.of(context).clearSnackBars();
      showAppSnackBar(context, 'Profil başarıyla güncellendi');
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
    return key is ValueKey<String> ? _labels[key.value.replaceFirst('profile_field_', '')] : null;
  }

  Widget _field(String key, {String? Function(String)? validator, TextInputType? keyboard, bool required = false}) {
    final names = key != 'email';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('profile_field_$key'),
        controller: _controllers[key],
        keyboardType: keyboard,
        autocorrect: false,
        enableSuggestions: names,
        textCapitalization: names ? TextCapitalization.words : TextCapitalization.none,
        decoration: fieldDecoration(
          Theme.of(context).colorScheme,
          label: required ? '${_labels[key]} *' : _labels[key],
        ),
        validator: validator == null ? null : (v) => validator(v ?? ''),
        onChanged: (_) {
          if (!_dirty) setState(() => _dirty = true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeaveForm(context, saving: _saving) && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        title: 'Profili Düzenle',
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _field('firstName'),
              _field('lastName'),
              _field('email', required: true, keyboard: TextInputType.emailAddress, validator: emailError),
            ],
          ),
        ),
        bottomNavigationBar: SaveBar(onPressed: _save, loading: _saving),
      ),
    );
  }
}
