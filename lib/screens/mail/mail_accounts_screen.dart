import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/crud_payload.dart';
import '../../services/mail_payload.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/searchable_paged_list.dart';
import '../../widgets/status_badge.dart';
import 'mail_account_form_screen.dart';

/// Admin `mail-accounts`: SMTP accounts with tenant filter (client side, like the admin), verify / test mail /
/// edit / delete. Custom screen: the generic CRUD engine has no per-row actions and no write-only password field.
class MailAccountsScreen extends StatefulWidget {
  final ApiService? apiService;
  const MailAccountsScreen({super.key, this.apiService});

  @override
  State<MailAccountsScreen> createState() => _MailAccountsScreenState();
}

class _MailAccountsScreenState extends State<MailAccountsScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  final _listKey = GlobalKey<SearchablePagedListState>();
  List<String> _tenants = const [];
  String? _tenant; // null = Tümü
  final Set<Object?> _verifying = {};

  Future<void> _reload() async => _listKey.currentState?.reload();

  void _onLoad(dynamic data) {
    final tenants = {
      for (final a in extractItems(data))
        if ('${a['tenantId'] ?? ''}'.isNotEmpty) '${a['tenantId']}',
    }.toList()..sort();
    setState(() {
      _tenants = tenants;
      if (!tenants.contains(_tenant)) _tenant = null;
    });
  }

  Future<void> _openForm([Map<String, dynamic>? account]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MailAccountFormScreen(account: account, apiService: _api),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _verify(Map<String, dynamic> account) async {
    final id = account['id'];
    setState(() => _verifying.add(id));
    await verifyMailAccount(context, _api, account);
    if (mounted) setState(() => _verifying.remove(id));
  }

  Future<void> _delete(Map<String, dynamic> account) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Hesabı Sil',
      message:
          '"${account['name']}" hesabını silmek istediğinizden emin misiniz? Bu hesabı kullanan formlar varsayılan '
          'hesaba geçecektir.',
      confirmLabel: 'Sil',
      destructive: true,
      confirmKey: const ValueKey('confirm_delete_button'),
    );
    if (!ok || !mounted) return;
    try {
      await _api.delete('/mail-accounts/${account['id']}');
      if (mounted) showAppSnackBar(context, 'Mail hesabı silindi');
      _reload();
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    }
  }

  Widget _card(BuildContext context, Map<String, dynamic> account, AuthProvider auth) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65));
    final id = account['id'];
    final active = account['active'] == true;
    final tenant = '${account['tenantId'] ?? ''}';
    final verifying = _verifying.contains(id);
    return Container(
      key: ValueKey('mail_account_$id'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: active ? 0.7 : 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: account['isPrimary'] == true
              ? AppColors.success.withValues(alpha: 0.5)
              : scheme.onSurface.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${account['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          Text('${account['fromAddress'] ?? ''}', style: muted),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (account['isPrimary'] == true) const StatusBadge(label: 'Ana Hesap', color: AppColors.success),
              StatusBadge(label: tenant.isEmpty ? 'Atanmamış' : tenant, color: tenant.isEmpty ? null : scheme.primary),
              StatusBadge.active(active),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${account['smtpHost'] ?? ''}:${account['smtpPort'] ?? ''}',
            style: muted.copyWith(fontFamily: 'monospace'),
          ),
          Text('${account['smtpUsername'] ?? ''}', style: muted.copyWith(fontSize: 12)),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              if (auth.can('mail', 'update'))
                TextButton.icon(
                  key: ValueKey('edit_$id'),
                  onPressed: () => _openForm(account),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Düzenle'),
                ),
              // Backend: /test needs mail:create (it sends a real e-mail), /verify mail:read.
              if (auth.can('mail', 'create'))
                TextButton.icon(
                  key: ValueKey('test_$id'),
                  onPressed: () => showSmtpTestDialog(context, _api, account),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Test Et'),
                ),
              TextButton.icon(
                key: ValueKey('verify_$id'),
                onPressed: verifying ? null : () => _verify(account),
                icon: verifying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Doğrulanıyor'),
                      )
                    : const Icon(Icons.verified_rounded),
                label: const Text('Doğrula'),
              ),
              if (auth.can('mail', 'delete'))
                TextButton.icon(
                  key: ValueKey('delete_$id'),
                  style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                  onPressed: () => _delete(account),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Sil'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tenantChips() {
    Widget chip(String? value) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('tenant_${value ?? 'all'}'),
        label: Text(value ?? 'Tümü'),
        selected: _tenant == value,
        onSelected: (_) => setState(() => _tenant = value),
      ),
    );
    return Semantics(
      label: 'Tenant',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [chip(null), for (final t in _tenants) chip(t)]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return AppScaffold(
      title: 'Mail Hesapları',
      navId: 'mail-accounts',
      actions: [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reload)],
      body: Column(
        children: [
          if (_tenants.isNotEmpty) _tenantChips(),
          Expanded(
            child: SearchablePagedList(
              key: _listKey,
              api: _api,
              endpoint: '/mail-accounts',
              onLoad: _onLoad,
              emptyMessage: _tenant == null
                  ? 'Henüz mail hesabı eklenmemiş.'
                  : '"$_tenant" tenant\'ına ait mail hesabı bulunamadı.',
              searchText: (a) =>
                  [a['name'], a['fromAddress'], a['smtpHost'], a['smtpUsername']].map((v) => v ?? '').join(' '),
              itemFilter: _tenant == null ? null : (a) => a['tenantId'] == _tenant,
              itemBuilder: (context, account) => _card(context, account, auth),
            ),
          ),
        ],
      ),
      floatingActionButton: auth.can('mail', 'create')
          ? FloatingActionButton(
              tooltip: 'Yeni Hesap Ekle',
              onPressed: () => _openForm(),
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}

/// `POST /mail-accounts/{id}/verify` (SMTP handshake with the saved settings, no e-mail) → result dialog.
/// The backend rejects inactive accounts and returns the SMTP error text on failure.
Future<void> verifyMailAccount(BuildContext context, ApiService api, Map<String, dynamic> account) async {
  String? error;
  try {
    await api.post('/mail-accounts/${account['id']}/verify', const {});
  } catch (e) {
    error = e.toString();
  }
  if (!context.mounted) return;
  // Not awaited: the caller's "Doğrulanıyor" state ends when the result is on screen.
  unawaited(
    showDialog<void>(
      context: context,
      builder: (ctx) => _ResultDialog(
        success: error == null,
        title: error == null ? 'SMTP bağlantısı başarılı' : 'SMTP doğrulama başarısız',
        message: error ?? '"${account['name']}" hesabının SMTP sunucusuna bağlanıldı (e-posta gönderilmedi).',
      ),
    ),
  );
}

class _ResultDialog extends StatelessWidget {
  final bool success;
  final String title;
  final String message;
  const _ResultDialog({required this.success, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: ValueKey(success ? 'verify_success' : 'verify_failure'),
      backgroundColor: scheme.surface,
      icon: Icon(
        success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: success ? AppColors.success : scheme.onErrorContainer,
      ),
      title: Text(title),
      content: SingleChildScrollView(child: SelectableText(message)),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam'))],
    );
  }
}

/// Admin `SmtpTestModal`: `POST /mail-accounts/{id}/test {testTo}` sends a real test e-mail; the result stays in
/// the dialog.
Future<void> showSmtpTestDialog(BuildContext context, ApiService api, Map<String, dynamic> account) => showDialog<void>(
  context: context,
  builder: (_) => _SmtpTestDialog(api: api, account: account),
);

class _SmtpTestDialog extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> account;
  const _SmtpTestDialog({required this.api, required this.account});

  @override
  State<_SmtpTestDialog> createState() => _SmtpTestDialogState();
}

class _SmtpTestDialogState extends State<_SmtpTestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _to = TextEditingController();
  bool _sending = false;
  String? _result;
  bool _failed = false;

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _result = null;
    });
    try {
      final data = await widget.api.post('/mail-accounts/${widget.account['id']}/test', {'testTo': _to.text.trim()});
      _result = data is String && data.isNotEmpty ? data : 'Test maili başarıyla gönderildi';
      _failed = false;
    } catch (e) {
      _result = e.toString();
      _failed = true;
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surface,
      title: const Text('SMTP Bağlantı Testi'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.account['name'] ?? ''}', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7))),
              const SizedBox(height: 16),
              if (_result != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _result!,
                    key: const ValueKey('smtp_test_result'),
                    style: TextStyle(color: _failed ? scheme.onErrorContainer : AppColors.success),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                key: const ValueKey('smtp_test_to'),
                controller: _to,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: fieldDecoration(scheme, label: 'Test E-posta Adresi *', hint: 'test@ornek.com'),
                validator: (v) => emailPattern.hasMatch(v?.trim() ?? '') ? null : 'Geçerli bir e-posta adresi giriniz',
                onFieldSubmitted: (_) => _sending ? null : _send(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Kapat')),
        ElevatedButton(
          key: const ValueKey('smtp_test_send'),
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Gönderiliyor'),
                )
              : const Text('Test Gönder'),
        ),
      ],
    );
  }
}
