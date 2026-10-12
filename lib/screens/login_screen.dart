import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Giriş başarısız'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background ambient lights
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withOpacity(0.2),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEC4899).withOpacity(0.2),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          
          Center(
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.flash_on_rounded, size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Elly Admin',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage your tenant workspace',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 48),

                    if (authProvider.mfaPending) ...[
                      Text(
                        'Doğrulama uygulamanızdaki 6 haneli kodu girin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
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
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: authProvider.isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                authProvider.mfaPending ? 'Doğrula' : 'Sign In',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    if (authProvider.mfaPending)
                      TextButton(
                        onPressed: authProvider.isLoading
                            ? null
                            : () {
                                _codeController.clear();
                                authProvider.cancelMfa();
                              },
                        child: const Text('Geri dön'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
        color: const Color(0xFF1C1C22).withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
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
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: label,
          labelText: labelText,
          counterText: '',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        validator: validator,
      ),
    );
  }
}
