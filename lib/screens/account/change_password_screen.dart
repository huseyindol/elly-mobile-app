import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/user_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/password_field.dart';
import '../../widgets/save_bar.dart';

/// `PUT /users/me/password {currentPassword, newPassword}` (DtoChangePassword). New password: same rule as the
/// backend `@Pattern` / admin forms; must differ from the current one; typed twice (mobile only, no paste-back).
/// A wrong current password is a 400 "Current password is incorrect" → "Mevcut şifre hatalı.".
class ChangePasswordScreen extends StatefulWidget {
  final ApiService? apiService;
  const ChangePasswordScreen({super.key, this.apiService});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _labels = {'current': 'Mevcut Şifre', 'new': 'Yeni Şifre', 'confirm': 'Yeni Şifre (Tekrar)'};

  late final ApiService _api = widget.apiService ?? ApiService();
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
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
    setState(() => _saving = true);
    try {
      await _api.put('/users/me/password', {'currentPassword': _current.text, 'newPassword': _new.text});
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      showAppSnackBar(context, 'Şifreniz değiştirildi');
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
    return key is ValueKey<String> ? _labels[key.value.replaceFirst('password_field_', '')] : null;
  }

  void _markDirty(String _) {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeaveForm(context, saving: _saving) && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        title: 'Şifre Değiştir',
        body: Form(
          key: _formKey,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                PasswordField(
                  fieldKey: 'password_field_current',
                  controller: _current,
                  label: '${_labels['current']} *',
                  validator: (v) => (v ?? '').isEmpty ? 'Mevcut şifre zorunludur' : null,
                  onChanged: _markDirty,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  fieldKey: 'password_field_new',
                  controller: _new,
                  newPassword: true,
                  label: '${_labels['new']} *',
                  helper: passwordRuleHint,
                  validator: (v) =>
                      passwordError(v ?? '') ??
                      (v == _current.text ? 'Yeni şifre mevcut şifreden farklı olmalı' : null),
                  onChanged: _markDirty,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  fieldKey: 'password_field_confirm',
                  controller: _confirm,
                  newPassword: true,
                  label: '${_labels['confirm']} *',
                  validator: (v) => v != _new.text ? 'Şifreler eşleşmiyor' : null,
                  onChanged: _markDirty,
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SaveBar(
          onPressed: _save,
          loading: _saving,
          label: 'Şifreyi Değiştir',
          buttonKey: const ValueKey('password_save_button'),
        ),
      ),
    );
  }
}
