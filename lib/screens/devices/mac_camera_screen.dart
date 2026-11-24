import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../services/api_service.dart';
import '../../services/call_machine.dart';
import '../../widgets/app_snack_bar.dart';

/// Mac kamerası: elly-mac-agent kullanıcısı aranır — ajan otomatik cevaplar, bağlantı tam ekran çağrı
/// ekranına düşer (AuthWrapper._onCall). İki biçim:
/// - **Görüntülü Konuş**: karşılıklı — bu telefonun kamerası ve mikrofonu da açılır, Mac'in ekranında
///   görüntünüz belirir, ses iki yönde akar (`Sonlandır` = iki tarafta da kamera/mikrofon kapanır).
/// - **İzle ve Dinle**: bu telefondan hiçbir şey gönderilmez; Mac'in kamerası ve mikrofonu izlenir.
///
/// Hedef kullanıcı `GET /users?audience=panel` listesinden seçilir (kullanıcı adı
/// `mac-agent` barındıran otomatik önerilir); seçim `SharedPreferences`ta kalıcı.
class MacCameraScreen extends StatefulWidget {
  const MacCameraScreen({super.key, this.apiService});

  /// Testlerde sahte backend; verilmezse gerçek istemci.
  final ApiService? apiService;

  @override
  State<MacCameraScreen> createState() => _MacCameraScreenState();
}

class _MacCameraScreenState extends State<MacCameraScreen> {
  static const _prefKey = 'mac_camera_target';

  late final _api = widget.apiService ?? ApiService();
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

  /// [talk]: karşılıklı görüşme (bu cihazın kamerası + mikrofonu); yoksa yalnız izle ve dinle.
  void _start({required bool talk}) {
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
    // talk: video true → mikrofon + kamera açılır, standart görüntülü arama ekranı.
    // izle: video false + recvOnly → bu telefondan ses/görüntü gönderilmez.
    context.read<CallProvider>().call(
          target['id'] as int,
          'Mac Kamerası',
          video: talk,
          recvOnly: !talk,
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

    final muted = TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7));
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
                      'Mac\'inizin kamerasını ve mikrofonunu uzaktan açın. Ajan yalnız sizin '
                      'hesabınızdan gelen çağrıları yanıtlar; görüşme sonunda kamera ve mikrofon kapanır.',
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
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const ValueKey('mac_camera_talk'),
                      onPressed: inCall ? null : () => _start(talk: true),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.videocam_rounded),
                      label: const Text('Görüntülü Konuş'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Karşılıklı: bu telefonun kamerası ve mikrofonu da açılır, Mac\'in ekranında görüntünüz '
                      'görünür.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted.color),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const ValueKey('mac_camera_watch'),
                      onPressed: inCall ? null : () => _start(talk: false),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('İzle ve Dinle'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bu telefondan ses ya da görüntü gönderilmez; Mac\'in kamerası ve mikrofonu dinlenir.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted.color),
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
                  title: Text('Bağlantı sürüyor: ${call.peerName}'),
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
