import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/chat_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/chat_format.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/info_note.dart';
import '../../widgets/save_bar.dart';

/// Admin `CreateGroupDialog`: name (≤100), description (≤500), scope Admin Chat / Tenant Chat (Tenant Chat only for
/// ADMIN+, session tenant, optional visitor access). Visibility is set by the backend from the creator's role.
/// The backend has no group update endpoint → no edit screen. Pops with the created [ChatGroup].
class ChatGroupFormScreen extends StatefulWidget {
  const ChatGroupFormScreen({super.key});

  @override
  State<ChatGroupFormScreen> createState() => _ChatGroupFormScreenState();
}

class _ChatGroupFormScreenState extends State<ChatGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _tenantChat = false;
  bool _visitorAccess = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reportInvalidFields(context, invalid);
      return;
    }
    setState(() => _saving = true);
    try {
      final group = await context.read<ChatProvider>().createGroup(
        name: _name.text,
        description: _description.text,
        tenantChat: _tenantChat,
        visitorAccess: _tenantChat && _visitorAccess,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      _dirty = false;
      Navigator.of(context).pop<ChatGroup>(group);
    } catch (e) {
      if (mounted) showAppSnackBar(context, chatErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = context.watch<AuthProvider>().roleLevel;
    final tenantId = context.watch<ChatProvider>().tenantId ?? '';
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeaveForm(context, saving: _saving) && context.mounted) Navigator.of(context).pop();
      },
      child: AppScaffold(
        title: 'Yeni Grup',
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                key: const ValueKey('chat_group_name'),
                controller: _name,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                decoration: fieldDecoration(scheme, label: 'Grup adı *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Grup adı zorunlu' : null,
                onChanged: (_) => _touch(),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('chat_group_description'),
                controller: _description,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: fieldDecoration(scheme, label: 'Açıklama'),
                onChanged: (_) => _touch(),
              ),
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: const Text('Kapsam', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              RadioGroup<bool>(
                groupValue: _tenantChat,
                onChanged: (v) => setState(() {
                  _tenantChat = v ?? false;
                  if (!_tenantChat) _visitorAccess = false;
                  _dirty = true;
                }),
                child: Column(
                  children: [
                    const RadioListTile<bool>(
                      key: ValueKey('chat_scope_admin'),
                      value: false,
                      title: Text('Admin Chat'),
                      subtitle: Text('Panel kullanıcıları arasında'),
                    ),
                    // Backend: a tenant chat needs ADMIN or SUPER_ADMIN.
                    if (level >= 3)
                      const RadioListTile<bool>(
                        key: ValueKey('chat_scope_tenant'),
                        value: true,
                        title: Text('Tenant Chat'),
                        subtitle: Text('Site ziyaretçilerine açılabilir'),
                      ),
                  ],
                ),
              ),
              if (_tenantChat) ...[
                InfoNote(
                  tenantId.isEmpty
                      ? 'Oturumunuzda tenant bilgisi yok; Tenant Chat oluşturulamaz.'
                      : 'Oturumunuzdaki tenant kullanılır: $tenantId',
                  warning: tenantId.isEmpty,
                ),
                SwitchListTile(
                  key: const ValueKey('chat_visitor_access'),
                  value: _visitorAccess,
                  title: const Text('Ziyaretçilere açık'),
                  subtitle: const Text('Web sitesi ziyaretçileri de bu gruba yazabilir'),
                  onChanged: (v) => setState(() {
                    _visitorAccess = v;
                    _dirty = true;
                  }),
                ),
              ] else
                InfoNote('Grup, rolünüze göre "${chatVisibilityLabel(level)}" görünürlüğünde oluşturulur.'),
            ],
          ),
        ),
        bottomNavigationBar: SaveBar(
          onPressed: _tenantChat && tenantId.isEmpty ? null : _save,
          loading: _saving,
          label: 'Oluştur',
          buttonKey: const ValueKey('chat_group_save'),
        ),
      ),
    );
  }
}
