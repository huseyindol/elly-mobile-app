import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/text_format.dart';
import 'app_snack_bar.dart';
import 'confirm_dialog.dart';
import 'state_views.dart';

/// Storage usage color, same thresholds as the admin StorageUsageWidget: <70 ok, 70–90 warning, ≥90 critical.
Color quotaColor(double percent, ColorScheme scheme) =>
    percent >= 90 ? scheme.onErrorContainer : (percent >= 70 ? AppColors.warning : AppColors.success);

const _gib = 1024 * 1024 * 1024;

/// "2,5" / "2.5" GB → bytes (admin `gbToBytes`); null unless the byte count is finite, fits an int64 and is > 0
/// (a tiny value rounding to 0 B would block every upload).
int? gbToBytes(String text) {
  final gb = double.tryParse(text.trim().replaceAll(',', '.'));
  if (gb == null || !gb.isFinite || gb <= 0) return null;
  final bytes = gb * _gib;
  if (!bytes.isFinite || bytes >= 9.2e18) return null;
  final rounded = bytes.round();
  return rounded > 0 ? rounded : null;
}

/// Limit field text: GB with up to 2 decimals ("1", "2,5"), not rounded to whole GB.
String gbText(Object? bytes) {
  if (bytes is! num) return '';
  final text = (bytes / _gib).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return text.replaceAll('.', ',');
}

/// Storage quota of the session tenant — admin `StorageUsageWidget` (dashboard) and `StorageQuotaCard` (settings).
/// `GET /storage/tenant/{tenantId}/quota` (no session tenant → `/storage/quota`); any signed-in user may read it.
/// [canEditLimit] (backend `ROLE_SUPER_ADMIN`): limit in GB (`PUT …/limit {limitBytes}`) and recompute
/// (`POST …/recompute`); otherwise settings shows the admin's read-only note.
class StorageQuotaCard extends StatefulWidget {
  final ApiService api;

  /// Dashboard: "Yönet" opens the settings screen. null = no button.
  final VoidCallback? onManage;

  /// Settings screen: management row (SUPER_ADMIN) or the read-only note.
  final bool settings;
  final bool canEditLimit;

  const StorageQuotaCard({
    super.key,
    required this.api,
    this.onManage,
    this.settings = false,
    this.canEditLimit = false,
  });

  @override
  State<StorageQuotaCard> createState() => StorageQuotaCardState();
}

class StorageQuotaCardState extends State<StorageQuotaCard> {
  Future<dynamic>? _quota;
  final _limit = TextEditingController();
  num? _currentLimit;
  bool _busy = false;

  Future<String> _base() async {
    final tenantId = await widget.api.secureStorage.read(key: 'tenantId');
    // Same URL as the admin: target tenant in the path; none → own context.
    return tenantId == null || tenantId.isEmpty
        ? '/storage/quota'
        : '/storage/tenant/${Uri.encodeComponent(tenantId)}/quota';
  }

  Future<dynamic> _future() => _quota ??= () async {
    final quota = await widget.api.get(await _base());
    if (quota is Map && mounted) {
      _limit.text = gbText(quota['limitBytes']);
      _currentLimit = quota['limitBytes'] as num?;
    }
    return quota;
  }();

  /// Reloads the quota; completes when it is on screen (dashboard pull-to-refresh awaits it).
  Future<void> reload() {
    setState(() => _quota = null);
    return _future().then((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _mutate(Future<dynamic> Function(String base) request, String success) async {
    setState(() => _busy = true);
    try {
      final quota = await request(await _base());
      if (!mounted) return;
      if (quota is Map) {
        _limit.text = gbText(quota['limitBytes']);
        _currentLimit = quota['limitBytes'] as num?;
      }
      setState(() {
        _quota = Future.value(quota);
      });
      showAppSnackBar(context, success);
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLimit() async {
    final bytes = gbToBytes(_limit.text);
    if (bytes == null) {
      showAppSnackBar(context, 'Geçerli bir limit (GB) girin', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    final current = _currentLimit;
    if (current != null && bytes < current) {
      final ok = await showConfirmDialog(
        context,
        title: 'Limiti düşür',
        message:
            'Limit ${formatBytes(current)} → ${formatBytes(bytes)} olacak. Kullanım yeni limiti aşarsa yeni yüklemeler '
            'reddedilir.',
        confirmLabel: 'Düşür',
        destructive: true,
        confirmKey: const ValueKey('storage_limit_confirm'),
      );
      if (!ok || !mounted) return;
    }
    _mutate((base) => widget.api.put('$base/limit', {'limitBytes': bytes}), 'Limit güncellendi');
  }

  void _recompute() => _mutate((base) => widget.api.post('$base/recompute', const {}), 'Kullanım yeniden hesaplandı');

  Color _muted(BuildContext context) => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: _muted(context))),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );

  Widget _management() {
    final scheme = Theme.of(context).colorScheme;
    if (!widget.canEditLimit) {
      return Text(
        'Limit yalnızca Süper Admin tarafından değiştirilebilir — bu bölüm bilgi amaçlıdır.',
        key: const ValueKey('storage_readonly_note'),
        style: TextStyle(fontSize: 12, color: _muted(context)),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: TextField(
            key: const ValueKey('storage_limit_field'),
            controller: _limit,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: fieldDecoration(scheme, label: 'Limit (GB)'),
            onSubmitted: (_) => _setLimit(),
          ),
        ),
        ElevatedButton(
          key: const ValueKey('storage_limit_save'),
          onPressed: _busy ? null : _setLimit,
          child: const Text('Limiti Kaydet'),
        ),
        TextButton.icon(
          key: const ValueKey('storage_recompute'),
          onPressed: _busy ? null : _recompute,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'İşleniyor'),
                )
              : const Icon(Icons.refresh_rounded),
          label: const Text('Yeniden hesapla'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('storage_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: FutureBuilder<dynamic>(
        future: _future(),
        builder: (context, snapshot) {
          final quota = snapshot.data is Map ? snapshot.data as Map : null;
          final percent = ((quota?['usedPercent'] as num?)?.toDouble() ?? 0).clamp(0.0, 100.0);
          final color = quotaColor(percent, scheme);
          final used = (quota?['usedBytes'] as num?) ?? 0;
          final limit = (quota?['limitBytes'] as num?) ?? 0;
          final Widget body;
          if (snapshot.connectionState != ConnectionState.done) {
            body = const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingView(label: 'Depolama yükleniyor'),
            );
          } else if (snapshot.hasError || quota == null) {
            body = Row(
              children: [
                Expanded(
                  child: Text('Depolama bilgisi yüklenemedi.', style: TextStyle(color: scheme.onErrorContainer)),
                ),
                TextButton(onPressed: reload, child: const Text('Tekrar Dene')),
              ],
            );
          } else {
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '%${percent.toStringAsFixed(1).replaceAll('.', ',')}',
                  key: const ValueKey('storage_percent'),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 10,
                    color: color,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                    semanticsLabel: 'Depolama kullanımı',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _metric('Kullanılan', formatBytes(used)),
                    _metric('Toplam Limit', formatBytes(limit)),
                    _metric('Kalan', formatBytes(limit - used < 0 ? 0 : limit - used)),
                  ],
                ),
                if (percent >= 70) ...[
                  const SizedBox(height: 12),
                  Text(
                    percent >= 90 ? 'Kota neredeyse dolu — yeni yüklemeler reddedilebilir.' : 'Kota dolmak üzere.',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
                if (widget.settings) ...[
                  const SizedBox(height: 12),
                  Divider(color: scheme.onSurface.withValues(alpha: 0.08)),
                  const SizedBox(height: 8),
                  _management(),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.storage_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            widget.settings ? 'Depolama Kotası' : 'Depolama Kullanımı',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '${quota?['tenantId'] ?? 'Genel / Admin'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: _muted(context)),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onManage != null) TextButton(onPressed: widget.onManage, child: const Text('Yönet')),
                ],
              ),
              const SizedBox(height: 12),
              body,
            ],
          );
        },
      ),
    );
  }
}
