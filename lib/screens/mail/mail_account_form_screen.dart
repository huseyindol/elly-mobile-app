import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/mail_payload.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/save_bar.dart';
import '../../widgets/state_views.dart';
import 'mail_accounts_screen.dart' show verifyMailAccount;

/// Admin `mail-accounts/new` and `mail-accounts/[id]/edit`. The SMTP password is write-only (see
/// [mailAccountPayload]): never shown or prefilled; blank on edit keeps the stored one.
class MailAccountFormScreen extends StatefulWidget {
  /// List item; null = new account.
  final Map<String, dynamic>? account;
  final ApiService? apiService;

  const MailAccountFormScreen({super.key, this.account, this.apiService});

  @override
  State<MailAccountFormScreen> createState() => _MailAccountFormScreenState();
}

class _MailAccountFormScreenState extends State<MailAccountFormScreen> {
  static const _textKeys = [
    'name',
    'fromAddress',
    'smtpHost',
    'smtpPort',
    'smtpUsername',
    'tenantId',
    'dailyLimit',
  ];
  static const _labels = {
    'name': 'Hesap Adı',
    'fromAddress': 'Gönderen E-posta',
    'smtpHost': 'SMTP Sunucusu',
    'smtpPort': 'SMTP Port',
    'smtpUsername': 'SMTP Kullanıcı Adı',
    'smtpPassword': 'SMTP Şifre',
    'tenantId': 'Tenant',
    'dailyLimit': 'Günlük Gönderim Kotası',
  };

  late final ApiService _api = widget.apiService ?? ApiService();
  final _formKey = GlobalKey<FormState>();
  final _controllers = {for (final k in _textKeys) k: TextEditingController()};
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _isPrimary = false;
  bool _active = true;
  Map<String, dynamic>? _record;
  bool _ready = false;
  String? _loadError;
  bool _saving = false;
  bool _verifying = false;
  bool _dirty = false;

  bool get _isEditing => widget.account != null;

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

  /// Edit from `GET /mail-accounts/{id}` like the admin (never from a possibly stale list row).
  Future<void> _load() async {
    Map<String, dynamic>? record;
    if (_isEditing) {
      try {
        record = Map<String, dynamic>.from(await _api.get('/mail-accounts/${widget.account!['id']}') as Map);
      } catch (e) {
        if (mounted) setState(() => _loadError = e.toString());
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _record = record;
      for (final k in _textKeys) {
        if (record == null) {
          _controllers[k]!.text = switch (k) {
            'smtpPort' => '587',
            'dailyLimit' => '500',
            _ => '',
          };
        } else {
          _controllers[k]!.text = switch (k) {
            'dailyLimit' => '${record[k] ?? 500}',
            _ => '${record[k] ?? ''}',
          };
        }
      }
      _isPrimary = record?['isPrimary'] == true;
      _active = record == null || record['active'] != false;
      _ready = true;
      _loadError = null;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reportInvalidFields(context, invalid, labelOf: _labelOf);
      return;
    }
    final payload = mailAccountPayload({
      for (final k in _textKeys) k: _controllers[k]!.text,
      'isPrimary': _isPrimary,
      'active': _active,
    }, password: _password.text);
    setState(() => _saving = true);
    try {
      _isEditing
          ? await _api.put('/mail-accounts/${_record!['id']}', payload)
          : await _api.post('/mail-accounts', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      showAppSnackBar(context, _isEditing ? 'Mail hesabı güncellendi' : 'Mail hesabı oluşturuldu');
      _dirty = false;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    await verifyMailAccount(context, _api, _record!);
    if (mounted) setState(() => _verifying = false);
  }

  String? _labelOf(FormFieldState<Object?> state) {
    final key = state.widget.key;
    return key is ValueKey<String> ? _labels[key.value.replaceFirst('mail_field_', '')] : null;
  }

  String? _required(String key, String? v) => (v?.trim() ?? '').isEmpty ? '${_labels[key]} zorunlu' : null;

  String? _maxLength(String? v, int max) => (v?.trim().length ?? 0) > max ? 'En fazla $max karakter' : null;

  Widget _text(
    String key, {
    bool required = true,
    String? hint,
    String? helper,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    int max = 255,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('mail_field_$key'),
      controller: _controllers[key],
      keyboardType: keyboard,
      autocorrect: false,
      inputFormatters: formatters,
      decoration: fieldDecoration(
        Theme.of(context).colorScheme,
        label: required ? '${_labels[key]} *' : _labels[key],
        hint: hint,
        helper: helper,
      ),
      validator: (v) => (required ? _required(key, v) : null) ?? _maxLength(v, max) ?? validator?.call(v),
      onChanged: (_) => _markDirty(),
    ),
  );

  Widget _note(String title, String body) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (title.isNotEmpty)
              TextSpan(
                text: '$title\n',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            TextSpan(text: body),
          ],
        ),
        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.85)),
      ),
    );
  }

  Widget _form() {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _text('name', hint: 'Satış Hesabı'),
          _text(
            'fromAddress',
            hint: 'sales@firma.com',
            keyboard: TextInputType.emailAddress,
            validator: (v) => emailPattern.hasMatch(v!.trim()) ? null : 'Geçerli bir e-posta adresi giriniz',
          ),
          _text('smtpHost', hint: 'smtp.gmail.com', keyboard: TextInputType.url),
          _text(
            'smtpPort',
            hint: '587',
            helper: '587 = STARTTLS, 465 = SSL',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              final port = int.tryParse(v!.trim());
              return port == null || port < 1 || port > 65535 ? 'Port 1-65535 aralığında olmalıdır' : null;
            },
          ),
          _text('smtpUsername', hint: 'sales@firma.com'),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
              key: const ValueKey('mail_field_smtpPassword'),
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              decoration:
                  fieldDecoration(
                    scheme,
                    label: _isEditing ? _labels['smtpPassword'] : '${_labels['smtpPassword']} *',
                    hint: _isEditing ? 'Şifreyi değiştirmek için doldurun' : 'SMTP şifreniz',
                    helper: _isEditing ? 'Boş bırakırsanız mevcut şifre korunur' : null,
                  ).copyWith(
                    suffixIcon: IconButton(
                      key: const ValueKey('mail_password_toggle'),
                      tooltip: _showPassword ? 'Şifreyi gizle' : 'Şifreyi göster',
                      icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
              validator: (v) => !_isEditing && (v?.trim() ?? '').isEmpty ? 'Şifre zorunludur' : null,
              onChanged: (_) => _markDirty(),
            ),
          ),
          _note(
            'Gmail kullanıcıları için:',
            'Gmail kullanıyorsanız normal şifre çalışmaz. Google Hesabı → Güvenlik → Uygulama Şifreleri\'nden '
                '16 karakterli şifre oluşturun.',
          ),
          _text(
            'tenantId',
            required: false,
            hint: 'tenant1 (boş bırakılabilir)',
            helper: 'Hangi tenant\'a ait olduğunu belirtir',
            max: 50,
          ),
          _text(
            'dailyLimit',
            required: false,
            hint: '500',
            helper: 'Bir günde gönderilebilecek maksimum e-posta sayısı (varsayılan: 500)',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              final text = v?.trim() ?? '';
              if (text.isEmpty) return null;
              final limit = int.tryParse(text);
              return limit == null || limit < 1 || limit > 100000
                  ? 'Kota 1-100000 aralığında olmalıdır'
                  : null;
            },
          ),
          SwitchListTile(
            key: const ValueKey('mail_field_isPrimary'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Ana hesap olarak ayarla'),
            value: _isPrimary,
            onChanged: (v) {
              _markDirty();
              setState(() => _isPrimary = v);
            },
          ),
          if (_isPrimary) _note('', 'Bu tenant\'ın mevcut ana hesabı varsa otomatik olarak değiştirilecek.'),
          SwitchListTile(
            key: const ValueKey('mail_field_active'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktif'),
            value: _active,
            onChanged: (v) {
              _markDirty();
              setState(() => _active = v);
            },
          ),
          if (_isEditing) ...[
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text('SMTP Bağlantı Doğrulama', style: Theme.of(context).textTheme.titleSmall),
            ),
            const SizedBox(height: 4),
            Text(
              _dirty
                  ? 'Kayıtlı ayarlarla test eder; kaydedilmemiş değişiklikler teste dahil değil.'
                  : 'Mail göndermeden SMTP bağlantısını test eder (sadece handshake).',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('mail_verify_button'),
                onPressed: _verifying || _saving ? null : _verify,
                icon: _verifying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Doğrulanıyor'),
                      )
                    : const Icon(Icons.verified_rounded),
                label: const Text('Bağlantıyı Doğrula'),
              ),
            ),
          ],
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
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeaveForm(context, saving: _saving) && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        title: _isEditing ? 'Mail Hesabı Düzenle' : 'Yeni Mail Hesabı',
        body: body,
        bottomNavigationBar: _ready ? SaveBar(onPressed: _verifying ? null : _save, loading: _saving) : null,
      ),
    );
  }
}
