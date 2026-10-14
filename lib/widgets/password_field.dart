import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Password input: obscured with a show/hide toggle, no autocorrect/suggestions, [fieldDecoration] look.
/// [newPassword] → the platform offers to generate/save a new password instead of filling the stored one.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool newPassword;
  final bool enabled;
  final bool autofocus;

  /// The show/hide button gets `<fieldKey>_toggle`.
  final String fieldKey;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.fieldKey,
    this.hint,
    this.helper,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.newPassword = false,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      key: ValueKey(widget.fieldKey),
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
      decoration: fieldDecoration(scheme, label: widget.label, hint: widget.hint, helper: widget.helper).copyWith(
        suffixIcon: IconButton(
          key: ValueKey('${widget.fieldKey}_toggle'),
          tooltip: _visible ? 'Şifreyi gizle' : 'Şifreyi göster',
          icon: Icon(_visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}
