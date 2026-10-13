import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_snack_bar.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _tenantController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _tenantController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isLoading) return;
    if (_formKey.currentState?.validate() ?? false) {
      final success = authProvider.mfaPending
          ? await authProvider.verifyMfa(_codeController.text.trim())
          : await authProvider.login(
              tenantId: _tenantController.text.trim(),
              usernameOrEmail: _emailController.text.trim(),
              password: _passwordController.text,
            );

      // mfaPending after login = code step shown, not an error.
      if (!success && authProvider.errorMessage != null && mounted) {
        showAppSnackBar(context, authProvider.errorMessage ?? 'Giriş başarısız', error: true);
      }
    }
  }

  ColorScheme get _scheme => Theme.of(context).colorScheme;

  void _cancelMfa(AuthProvider authProvider) {
    _codeController.clear();
    authProvider.cancelMfa();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // System back on the 2FA step returns to the credentials form instead of leaving the app.
    return PopScope(
      canPop: !authProvider.mfaPending,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !authProvider.mfaPending || authProvider.isLoading) return;
        _cancelMfa(authProvider);
      },
      child: Scaffold(
        body: AmbientBackground(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_scheme.primary, _scheme.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: _scheme.primary.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 2),
                        ],
                      ),
                      child: Icon(Icons.flash_on_rounded, size: 40, color: _scheme.onPrimary),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Elly Admin',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage your tenant workspace',
                      style: TextStyle(fontSize: 14, color: _scheme.onSurface.withValues(alpha: 0.65)),
                    ),
                    const SizedBox(height: 48),

                    if (authProvider.mfaPending) ...[
                      Text(
                        'Doğrulama uygulamanızdaki 6 haneli kodu girin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _scheme.onSurface.withValues(alpha: 0.75)),
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        key: const ValueKey('mfa_code_field'),
                        controller: _codeController,
                        label: '2FA Kodu',
                        icon: Icons.verified_user_rounded,
                        labelText: '2FA Kodu',
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        autofocus: true,
                        onSubmitted: (_) => _handleLogin(),
                        validator: (val) =>
                            RegExp(r'^\d{6}$').hasMatch(val?.trim() ?? '') ? null : '6 haneli kod girin',
                      ),
                    ] else ...[
                      _buildInputField(
                        controller: _tenantController,
                        label: 'Tenant ID',
                        icon: Icons.business_rounded,
                        validator: (val) => val == null || val.isEmpty ? 'Tenant ID required' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        controller: _emailController,
                        label: 'Email or Username',
                        icon: Icons.person_rounded,
                        validator: (val) => val == null || val.isEmpty ? 'Email required' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        controller: _passwordController,
                        label: 'Password',
                        icon: Icons.lock_rounded,
                        isPassword: true,
                        validator: (val) => val == null || val.isEmpty ? 'Password required' : null,
                      ),
                    ],
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: authProvider.isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _scheme.primary,
                          foregroundColor: _scheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: authProvider.isLoading
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: _scheme.onPrimary,
                                  strokeWidth: 2,
                                  semanticsLabel: 'Giriş yapılıyor',
                                ),
                              )
                            : Text(
                                authProvider.mfaPending ? 'Doğrula' : 'Sign In',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    if (authProvider.mfaPending)
                      TextButton(
                        onPressed: authProvider.isLoading ? null : () => _cancelMfa(authProvider),
                        child: const Text('Geri dön'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    Key? key,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? labelText,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    Iterable<String>? autofillHints,
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _scheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: TextFormField(
        key: key,
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        autofocus: autofocus,
        textInputAction: onSubmitted != null ? TextInputAction.done : null,
        onFieldSubmitted: onSubmitted,
        style: TextStyle(color: _scheme.onSurface),
        decoration: InputDecoration(
          hintText: label,
          labelText: labelText,
          counterText: '',
          hintStyle: TextStyle(color: _scheme.onSurface.withValues(alpha: 0.45)),
          prefixIcon: Icon(icon, color: _scheme.onSurface.withValues(alpha: 0.6)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        validator: validator,
      ),
    );
  }
}
