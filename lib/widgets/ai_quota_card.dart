import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../services/api_service.dart';
import 'app_snack_bar.dart';
import 'state_views.dart';
import 'storage_quota_card.dart' show quotaColor;

String _fmtInt(Object? v) {
  final n = (v as num?)?.toInt() ?? 0;
  return n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}

String _fmtUsd(Object? v) {
  final n = (v as num?)?.toDouble() ?? 0.0;
  if (n <= 0) return '\$0.00';
  if (n < 0.01) return '\$${n.toStringAsFixed(4)}';
  return '\$${n.toStringAsFixed(2)}';
}

/// Session tenant's AI token & request quota card — mirrors admin `AiUsageWidget`.
/// `GET /ai/tenant/{tenantId}/quota` (or `/ai/quota` when no session tenant).
/// When [showManagement] and [canEditLimit] (`ROLE_SUPER_ADMIN`) are true, allows editing
/// `monthlyTokenLimit` and `dailyRequestLimit` via `PUT .../limit`.
class AiQuotaCard extends StatefulWidget {
  final ApiService api;
  final VoidCallback? onManage;
  final bool showManagement;
  final bool canEditLimit;

  const AiQuotaCard({
    super.key,
    required this.api,
    this.onManage,
    this.showManagement = false,
    this.canEditLimit = false,
  });

  @override
  State<AiQuotaCard> createState() => AiQuotaCardState();
}

class AiQuotaCardState extends State<AiQuotaCard> {
  Future<dynamic>? _quota;
  final _monthlyCtrl = TextEditingController();
  final _dailyCtrl = TextEditingController();
  bool _busy = false;

  Future<String> _base() async {
    final tenantId = await widget.api.secureStorage.read(key: 'tenantId');
    return tenantId == null || tenantId.isEmpty
        ? '/ai/quota'
        : '/ai/tenant/${Uri.encodeComponent(tenantId)}/quota';
  }

  Future<dynamic> _future() => _quota ??= () async {
    final quota = await widget.api.get(await _base());
    if (quota is Map && mounted) {
      _monthlyCtrl.text = '${quota['monthlyTokenLimit'] ?? 1000000}';
      _dailyCtrl.text = '${quota['dailyRequestLimit'] ?? 250}';
    }
    return quota;
  }();

  Future<void> reload() {
    setState(() => _quota = null);
    return _future().then((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _monthlyCtrl.dispose();
    _dailyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLimits() async {
    final monthly = int.tryParse(_monthlyCtrl.text.trim());
    final daily = int.tryParse(_dailyCtrl.text.trim());
    if (monthly == null || monthly <= 0) {
      showAppSnackBar(context, 'Geçerli bir aylık token limiti girin', error: true);
      return;
    }
    if (daily == null || daily <= 0) {
      showAppSnackBar(context, 'Geçerli bir günlük istek limiti girin', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final base = await _base();
      final updated = await widget.api.put('$base/limit', {
        'monthlyTokenLimit': monthly,
        'dailyRequestLimit': daily,
      });
      if (!mounted) return;
      if (updated is Map) {
        _monthlyCtrl.text = '${updated['monthlyTokenLimit'] ?? monthly}';
        _dailyCtrl.text = '${updated['dailyRequestLimit'] ?? daily}';
      }
      setState(() {
        _quota = Future.value(updated);
      });
      showAppSnackBar(context, 'AI kullanım limitleri güncellendi');
    } catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _muted(BuildContext context) => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

  Widget _metric(String label, String value, {String? sub}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: _muted(context))),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace')),
      if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: _muted(context))),
    ],
  );

  Widget _management() {
    final scheme = Theme.of(context).colorScheme;
    if (!widget.canEditLimit) {
      return Text(
        'AI limitleri yalnızca Süper Admin tarafından değiştirilebilir.',
        key: const ValueKey('ai_quota_readonly_note'),
        style: TextStyle(fontSize: 12, color: _muted(context)),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 155,
          child: TextField(
            key: const ValueKey('ai_monthly_limit_field'),
            controller: _monthlyCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: fieldDecoration(scheme, label: 'Aylık Token Limiti'),
            onSubmitted: (_) => _saveLimits(),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            key: const ValueKey('ai_daily_limit_field'),
            controller: _dailyCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: fieldDecoration(scheme, label: 'Günlük İstek Limiti'),
            onSubmitted: (_) => _saveLimits(),
          ),
        ),
        ElevatedButton(
          key: const ValueKey('ai_limit_save'),
          onPressed: _busy ? null : _saveLimits,
          child: const Text('Limitleri Kaydet'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('ai_quota_card'),
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
          final monthlyPct = ((quota?['monthlyTokenUsedPercent'] as num?)?.toDouble() ?? 0).clamp(0.0, 100.0);
          final dailyPct = ((quota?['dailyRequestUsedPercent'] as num?)?.toDouble() ?? 0).clamp(0.0, 100.0);
          final monthlyColor = quotaColor(monthlyPct, scheme);
          final dailyColor = quotaColor(dailyPct, scheme);

          final Widget body;
          if (snapshot.connectionState != ConnectionState.done) {
            body = const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingView(label: 'AI kotası yükleniyor'),
            );
          } else if (snapshot.hasError || quota == null) {
            body = Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('AI kota bilgisi yüklenemedi.', style: TextStyle(color: scheme.onErrorContainer)),
                TextButton(onPressed: reload, child: const Text('Tekrar Dene')),
              ],
            );
          } else {
            final inputTok = (quota['monthlyInputTokens'] as num?) ?? 0;
            final outTok = (quota['monthlyOutputTokens'] as num?) ?? 0;
            final thoughtTok = (quota['monthlyThoughtTokens'] as num?) ?? 0;
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '%${monthlyPct.toStringAsFixed(1).replaceAll('.', ',')}',
                  key: const ValueKey('ai_monthly_percent'),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: monthlyColor),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: monthlyPct / 100,
                    minHeight: 10,
                    color: monthlyColor,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                    semanticsLabel: 'Aylık AI token kullanımı',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      'Günlük İstek: ${_fmtInt(quota['dailyRequestsUsed'])} / ${_fmtInt(quota['dailyRequestLimit'])}',
                      style: TextStyle(fontSize: 12, color: _muted(context)),
                    ),
                    Text(
                      '%${dailyPct.toStringAsFixed(1).replaceAll('.', ',')}',
                      key: const ValueKey('ai_daily_percent'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dailyColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: dailyPct / 100,
                    minHeight: 7,
                    color: dailyColor,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                    semanticsLabel: 'Günlük AI istek kullanımı',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _metric(
                      'Bu Ay Kullanılan',
                      '${_fmtInt(quota['monthlyTokensUsed'])} tok',
                      sub: 'Limit: ${_fmtInt(quota['monthlyTokenLimit'])}',
                    ),
                    _metric(
                      'Kalan Token',
                      '${_fmtInt(quota['monthlyTokensRemaining'])} tok',
                      sub: 'Girdi: ${_fmtInt(inputTok)}',
                    ),
                    _metric(
                      'Çıktı + Düşünme',
                      '${_fmtInt(outTok + thoughtTok)} tok',
                      sub: 'Ç: ${_fmtInt(outTok)} · D: ${_fmtInt(thoughtTok)}',
                    ),
                    _metric(
                      'Bugün Kalan İstek',
                      '${_fmtInt(quota['dailyRequestsRemaining'])} istek',
                      sub: 'Bugün: ${_fmtInt(quota['dailyTokensUsed'])} tok',
                    ),
                    _metric(
                      'Tahmini Maliyet (Ay)',
                      _fmtUsd(quota['monthlyEstimatedCostUsd']),
                      sub: 'Toplam: ${_fmtUsd(quota['totalEstimatedCostUsd'])}',
                    ),
                  ],
                ),
                if (monthlyPct >= 70 || dailyPct >= 70) ...[
                  const SizedBox(height: 12),
                  Text(
                    monthlyPct >= 100 || dailyPct >= 100
                        ? 'AI kullanım kotası doldu — yeni AI üretim istekleri kota sıfırlanana veya limit artırılana kadar engellenir.'
                        : 'AI kullanım kotası dolmak üzere.',
                    style: TextStyle(
                      color: (monthlyPct >= 90 || dailyPct >= 90) ? monthlyColor : AppColors.warning,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (widget.showManagement) ...[
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
                  Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: const Text(
                            'AI Kullanımı',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
