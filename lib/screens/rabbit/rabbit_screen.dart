import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/rabbit_admin.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/searchable_paged_list.dart';
import '../../widgets/status_badge.dart';
import 'queue_detail_screen.dart';

/// Admin `infrastructure/rabbitmq` (`rabbit:read`): broker overview (`GET /admin/rabbit/overview`) and queues
/// (`GET /admin/rabbit/queues`); tap → [QueueDetailScreen]. Purge needs `rabbit:manage` and the queue name typed.
/// No auto refresh (admin polls every 15–30 s): pull-to-refresh / refresh button.
class RabbitScreen extends StatefulWidget {
  final ApiService? apiService;
  const RabbitScreen({super.key, this.apiService});

  @override
  State<RabbitScreen> createState() => _RabbitScreenState();
}

class _RabbitScreenState extends State<RabbitScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  final _listKey = GlobalKey<SearchablePagedListState>();
  late Future<dynamic> _overview = _getOverview();

  /// The card (list header) is not built while the queue list is loading → no FutureBuilder listens yet; the
  /// error is still shown by the card once it subscribes.
  Future<dynamic> _getOverview() => _api.get('$rabbitBase/overview')..ignore();

  Future<void> _refreshOverview() async {
    setState(() {
      _overview = _getOverview();
    });
    await _overview.then((_) {}, onError: (_) {});
  }

  Future<void> _reloadAll() => Future.wait([_refreshOverview(), _listKey.currentState?.reload() ?? Future.value()]);

  Future<void> _openDetail(Map<String, dynamic> queue) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QueueDetailScreen(queue: queue, apiService: _api),
      ),
    );
    if (mounted) _reloadAll(); // counts may have changed (purge, republish, consumers)
  }

  Widget _overviewCard() {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 12);
    return Container(
      key: const ValueKey('rabbit_overview'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: FutureBuilder<dynamic>(
        future: _overview,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(semanticsLabel: 'Broker durumu yükleniyor')),
            );
          }
          final data = snapshot.data is Map ? snapshot.data as Map : null;
          if (snapshot.hasError || data == null) {
            return Row(
              children: [
                Expanded(
                  child: Text(
                    'RabbitMQ broker durumu alınamadı: ${snapshot.hasError ? rabbitErrorText(snapshot.error!) : ''}',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
                TextButton(onPressed: _refreshOverview, child: const Text('Tekrar Dene')),
              ],
            );
          }
          Widget stat(String label, Object? value) => MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: muted),
                Text('${value ?? '—'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'RabbitMQ ${data['rabbitmqVersion'] ?? '—'}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Text('${data['clusterName'] ?? 'Cluster —'} · Erlang ${data['erlangVersion'] ?? '—'}', style: muted),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  stat('Toplam Mesaj', data['totalMessages']),
                  stat('Consumer', data['totalConsumers']),
                  stat('Queue', data['queueCount']),
                  stat('Exchange', data['exchangeCount']),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> queue, bool canManage) {
    final scheme = Theme.of(context).colorScheme;
    final name = '${queue['name'] ?? ''}';
    final total = countOf(queue['messages']);
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 12);
    Widget metric(String label, Object? value) => Text('$label: ${countOf(value)}', style: muted);
    return Card(
      key: ValueKey('queue_$name'),
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surface.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(queue),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                    ),
                  ),
                  QueueStateBadge(state: queue['state']?.toString()),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text('Toplam: $total', style: const TextStyle(fontWeight: FontWeight.w600)),
                  metric('Ready', queue['messagesReady']),
                  metric('Unacked', queue['messagesUnacknowledged']),
                  metric('Consumer', queue['consumers']),
                ],
              ),
              if (canManage)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: ValueKey('purge_$name'),
                    style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
                    onPressed: total == 0
                        ? null
                        : () async {
                            if (await purgeQueue(context, _api, queue) && mounted) _reloadAll();
                          },
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(total == 0 ? 'Kuyruk boş' : 'Purge', semanticsLabel: 'Purge: $name'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthProvider>().has('rabbit:manage');
    return AppScaffold(
      title: 'RabbitMQ',
      navId: 'rabbitmq',
      actions: [IconButton(tooltip: 'Yenile', icon: const Icon(Icons.refresh_rounded), onPressed: _reloadAll)],
      body: SearchablePagedList(
        key: _listKey,
        api: _api,
        endpoint: '$rabbitBase/queues',
        header: _overviewCard(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        emptyMessage: 'Henüz queue yok.',
        searchText: (q) => '${q['name'] ?? ''}',
        onRefresh: _refreshOverview,
        itemBuilder: (_, queue) => _card(queue, canManage),
      ),
    );
  }
}

/// Admin `StateBadge`: running green, idle muted, anything else (flow, …) amber.
class QueueStateBadge extends StatelessWidget {
  final String? state;
  const QueueStateBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: state ?? '—',
    color: switch (state) {
      'running' => AppColors.success,
      'idle' || null => null,
      _ => AppColors.warning,
    },
  );
}

/// `POST /admin/rabbit/queues/{name}/purge` (204) after the user typed the queue name (admin
/// `DestructiveConfirmDialog`). Pass the screen's context. true = purged.
Future<bool> purgeQueue(BuildContext context, ApiService api, Map<String, dynamic> queue) async {
  final name = '${queue['name']}';
  final ok = await showConfirmDialog(
    context,
    title: 'Queue Purge',
    message:
        '"$name" kuyruğundaki ${countOf(queue['messages'])} mesaj kalıcı olarak silinecek. Bu işlem geri alınamaz.',
    confirmLabel: 'Kuyruğu Temizle',
    destructive: true,
    requiredText: name,
    confirmKey: const ValueKey('confirm_purge_button'),
  );
  if (!ok || !context.mounted) return false;
  try {
    await api.post(queuePath(name, '/purge'), const {});
    if (context.mounted) showAppSnackBar(context, 'Queue "$name" temizlendi');
    return true;
  } catch (e) {
    if (context.mounted) showAppSnackBar(context, rabbitErrorText(e), error: true);
    return false;
  }
}
