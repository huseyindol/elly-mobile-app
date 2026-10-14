import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/user_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/info_note.dart';
import '../../widgets/save_bar.dart';
import '../../widgets/state_views.dart';

/// Opens an `otpauth://` URI in the authenticator app; false when none handles it.
typedef UriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternal(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Admin `MfaSetupDialog` for a phone: the authenticator usually runs on this same device, so instead of a QR code
/// the `otpauth://` link opens it directly ("Authenticator'da aç"), with the secret for manual entry as fallback.
/// `GET /auth/mfa/setup` (new secret each call, not active yet) → `POST /auth/mfa/setup/verify {code}`.
/// The secret lives only in this State: masked by default (screenshots / screen sharing), masked again whenever the
/// app leaves the foreground (app switcher snapshot), never logged or stored; copying is the user's explicit action.
class MfaSetupScreen extends StatefulWidget {
  final ApiService? apiService;

  /// Test seam (url_launcher in the app).
  final UriLauncher? launcher;

  const MfaSetupScreen({super.key, this.apiService, this.launcher});

  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  late final AppLifecycleListener _lifecycle;
  String? _secret;
  String? _uri;
  String? _issuer;
  String? _loadError;
  String? _verifyError;
  bool _revealed = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed && _revealed && mounted) setState(() => _revealed = false);
      },
    );
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _code.dispose();
    _secret = null;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _secret = null;
      _revealed = false;
    });
    try {
      final data = await _api.get('/auth/mfa/setup');
      if (!mounted) return;
      final map = data is Map ? data : const {};
      final secret = '${map['secret'] ?? ''}';
      if (secret.isEmpty) throw ApiException('Kurulum anahtarı alınamadı');
      setState(() {
        _secret = secret;
        _uri = '${map['qrUri'] ?? ''}';
        _issuer = map['issuer']?.toString();
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _openAuthenticator() async {
    final ok = await (widget.launcher ?? _launchExternal)(Uri.parse(_uri!));
    if (!ok && mounted) {
      showAppSnackBar(
        context,
        'Authenticator uygulaması açılamadı. Anahtarı kopyalayıp uygulamaya elle girin.',
        error: true,
      );
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _secret!));
    if (mounted) showAppSnackBar(context, 'Anahtar kopyalandı. Authenticator\'a ekledikten sonra panoyu temizleyin.');
  }

  Future<void> _verify() async {
    setState(() => _verifyError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _verifying = true);
    try {
      await _api.post('/auth/mfa/setup/verify', {'code': _code.text});
      if (!mounted) return;
      _secret = null;
      ScaffoldMessenger.of(context).clearSnackBars();
      showAppSnackBar(context, '2FA başarıyla etkinleştirildi');
      Navigator.of(context).pop(true);
    } catch (e) {
      // Wrong code: backend 401 "Geçersiz doğrulama kodu…" (the session is kept, see ApiService).
      if (mounted) setState(() => _verifyError = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<bool> _confirmLeave() => showConfirmDialog(
    context,
    title: '2FA kurulumu tamamlanmadı',
    message:
        'Çıkarsanız 2FA etkinleşmez. Yeniden kurulumda yeni bir anahtar üretilir; authenticator\'a eklediğiniz '
        'kaydı silmeniz gerekir.',
    confirmLabel: 'Çık',
    cancelLabel: 'Kal',
    destructive: true,
    confirmKey: const ValueKey('confirm_leave_button'),
  );

  Widget _step(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 12),
    child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
  );

  Widget _secretBox() {
    final scheme = Theme.of(context).colorScheme;
    final secret = _secret!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: _revealed ? null : 'Gizli anahtar gizlendi',
              excludeSemantics: !_revealed,
              child: Text(
                formatSecret(secret, masked: !_revealed),
                key: const ValueKey('mfa_secret_text'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 1),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('mfa_secret_toggle'),
            tooltip: _revealed ? 'Anahtarı gizle' : 'Anahtarı göster',
            icon: Icon(_revealed ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
          IconButton(
            key: const ValueKey('mfa_secret_copy'),
            tooltip: 'Anahtarı kopyala',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copy,
          ),
        ],
      ),
    );
  }

  Widget _form() {
    final scheme = Theme.of(context).colorScheme;
    final canOpen = isValidOtpauthUri(_uri ?? '', _secret!);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const InfoNote(
            'Authenticator uygulaması (Google Authenticator, Microsoft Authenticator, Authy vb.) ile üretilen tek '
            'kullanımlık kod, girişte şifrenize ek olarak sorulur.',
          ),
          _step('1. Hesabı authenticator uygulamasına ekleyin'),
          if (canOpen) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const ValueKey('mfa_open_authenticator'),
                onPressed: _openAuthenticator,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Authenticator\'da aç'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ya da anahtarı uygulamaya elle girin:',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.75)),
            ),
          ] else
            Text(
              'Anahtarı authenticator uygulamasına elle girin:',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.75)),
            ),
          const SizedBox(height: 8),
          _secretBox(),
          if (_issuer != null && _issuer!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Uygulama adı: $_issuer · Tür: zaman tabanlı (TOTP), 6 hane',
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ],
          const SizedBox(height: 8),
          _step('2. Uygulamadaki 6 haneli kodu girin'),
          TextFormField(
            key: const ValueKey('mfa_setup_code'),
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 22, letterSpacing: 8),
            decoration: fieldDecoration(
              scheme,
              label: 'Doğrulama Kodu *',
              hint: '000000',
            ).copyWith(errorText: _verifyError, errorMaxLines: 4, counterText: ''),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : '6 haneli kodu girin',
            onChanged: (_) {
              if (_verifyError != null) setState(() => _verifyError = null);
            },
            onFieldSubmitted: (_) => _verifying ? null : _verify(),
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
    } else if (_secret == null) {
      body = const LoadingView(label: 'Kurulum hazırlanıyor');
    } else {
      body = _form();
    }
    final pending = _secret != null;
    return PopScope(
      canPop: !pending && !_verifying,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _verifying) return;
        if (await _confirmLeave() && context.mounted) {
          _secret = null; // Navigator.pop does not consult PopScope
          Navigator.of(context).pop();
        }
      },
      child: AppScaffold(
        title: '2FA\'yı Etkinleştir',
        body: body,
        bottomNavigationBar: pending
            ? SaveBar(
                onPressed: _verify,
                loading: _verifying,
                label: 'Doğrula ve Etkinleştir',
                buttonKey: const ValueKey('mfa_verify_button'),
              )
            : null,
      ),
    );
  }
}
