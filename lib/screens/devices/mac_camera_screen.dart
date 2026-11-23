import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../services/api_service.dart';
import '../../services/call_machine.dart';
import '../../widgets/app_snack_bar.dart';

/// Mac kamerası: elly-mac-agent kullanıcıını recvonly arar — ajan otomatik cevaplar,
/// görüntü tam ekran çağrı ekranına düşer (AuthWrapper._onCall). `Sonlandır` = kamera kapar.
///
/// Hedef kullanıcı `GET /users?audience=panel` listesinden seçilir (kullanıcı adı
/// `mac-agent` barındıran otomatik önerilir); seçim `SharedPreferences`ta kalıcı.
class MacCameraScreen extends StatefulWidget {
  const MacCameraScreen({super.key});

  @override
  State<MacCameraScreen> createState() => _MacCameraScreenState();
}

class _MacCameraScreenState extends State<MacCameraScreen> {
  static const _prefKey = 'mac_camera_target';

  final _api = ApiService();
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _target;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('/users?audience=panel');
      final users = data is List ? data.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getInt(_prefKey);
      var target = users.where((u) => u['id'] == savedId).firstOrNull;
      target ??= users.where((u) => '${u['username'] ?? ''}'.contains('mac-agent')).firstOrNull;
      if (!mounted) return;
      setState(() {
        _users = users;
        _target = target;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Cihaz kullanıcıları yüklenemedi.';
      });
    }
  }

  Future<void> _pick(Map<String, dynamic>? user) async {
    setState(() => _target = user);
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, user['id'] as int);
    }
  }

  void _start() {
    final target = _target;
    if (target == null) {
      showAppSnackBar(context, 'Önce bir cihaz kullanıcısı seçin.', error: true);
      return;
    }
    final auth = context.read<AuthProvider>();
    if (auth.userId != null && target['id'] == auth.userId) {
      showAppSnackBar(context, 'Kendi hesabınızı arayamazsınız.', error: true);
      return;
    }
    // video: false + recvOnly: bu telefonun kamerası/mikrofonu hiç açılmaz.
    context.read<CallProvider>().call(
          target['id'] as int,
          'Mac Kamerası',
          video: false,
          recvOnly: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final call = context.watch<CallProvider>();
    final inCall = call.phase != CallPhase.idle;

    // Derin bağlantı savunması: sayfa yalnız sahibin hesabında (kullanıcı adı
    // bilinmiyorsa da kapalı — fail-closed).
    if (context.watch<AuthProvider>().username != 'huseyindol') {
      return Scaffold(
        appBar: AppBar(title: const Text('Mac Kamerası')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              const Text('Bu alan erişiminize kapalı.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mac Kamerası')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.videocam_rounded, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      'Mac\'inizin kamerasını uzaktan açın ve izleyin. Ajan yalnız sizin '
                      'hesabınızdan gelen çağrıları yanıtlar; oturum sonunda kamera kapanır.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                    else if (_error != null)
                      Column(
                        children: [
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                          const SizedBox(height: 8),
                          OutlinedButton(onPressed: _load, child: const Text('Tekrar Dene')),
                        ],
                      )
                    else ...[
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: _target,
                      decoration: const InputDecoration(
                        labelText: 'Cihaz kullanıcısı',
                        prefixIcon: Icon(Icons.computer_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final u in _users)
                          DropdownMenuItem(
                            value: u,
                            child: Text('${u['username']} (#${u['id']})'),
                          ),
                      ],
                      onChanged: _pick,
                      menuMaxHeight: 320,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: inCall ? null : _start,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Yayını Aç'),
                    ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (inCall)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.phone_in_talk_rounded),
                  title: Text('Yayın sürüyor: ${call.peerName}'),
                  subtitle: Text(call.phase == CallPhase.active ? 'Bağlandı' : 'Bağlanıyor…'),
                  trailing: OutlinedButton(
                    onPressed: () => context.read<CallProvider>().end(),
                    child: const Text('Sonlandır'),
                  ),
                ),
              ),
            if (_target == null && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Cihaz kullanıcısı bulunamadı. Yönetim panelinden "mac-agent" adında bir '
                  'panel kullanıcısı oluşturup Mac ajanını o hesapla yapılandırın.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
