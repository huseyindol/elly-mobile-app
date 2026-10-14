import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../config/nav_config.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/crud_payload.dart';
import '../services/mail_payload.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/state_views.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/storage_quota_card.dart';

export '../widgets/storage_quota_card.dart' show quotaColor;

/// A summary card of the elly-admin dashboard (`(baseLayout)/dashboard/page.tsx`).
class _Stat {
  /// [NavConfig] item opened on tap; also keys the card's request.
  final String navId;
  final String title;
  final String permission;
  final String endpoint;
  final Color color;
  const _Stat(this.navId, this.title, this.permission, this.endpoint, this.color);
}

// Card accents identify a card (like the admin's per-card gradients); shared colors live in app_theme.dart.
// Same cards, permissions and endpoints as the admin dashboard; a card without its
// permission is neither shown nor requested (no 403s).
const _stats = [
  _Stat('posts', 'Yazılar', 'posts:read', '/posts/list/summary', Color(0xFF8B5CF6)),
  _Stat('forms', 'Formlar', 'forms:read', '/forms/list', Color(0xFF06B6D4)),
  _Stat('users', 'Kullanıcılar', 'users:manage', '/users', Color(0xFF10B981)),
  _Stat('mail-accounts', 'Aktif Mail Hesabı', 'mail:read', '/mail-accounts/active', Color(0xFFF97316)),
  _Stat('chat', 'Chat Grupları', 'chat:read', '/chat/groups', Color(0xFFD946EF)),
  _Stat('email-logs', 'E-postalar', 'emails:read', '/emails?size=8', Color(0xFFF59E0B)),
  _Stat('banners', 'Bannerlar', 'banners:read', '/banners/list/summary', Color(0xFF0EA5E9)),
  _Stat('assets', 'Medya', 'assets:read', '/assets/list/paged?page=0&size=1', Color(0xFF84CC16)),
];

/// 1234567 → "1.234.567" (tr-TR grouping, like the admin).
String _formatCount(int? n) =>
    n == null ? '—' : n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Backend dates arrive as epoch millis or ISO strings → "dd.MM HH:mm".
String _formatDateTime(dynamic value) {
  final date = value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : DateTime.tryParse('$value');
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final d = date.toLocal();
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

class DashboardScreen extends StatefulWidget {
  /// Test seam: lets tests inject an [ApiService] with a mock http client.
  final ApiService? apiService;

  const DashboardScreen({super.key, this.apiService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();

  /// One request per card, started when the card first becomes visible; cards load and fail independently.
  final Map<String, Future<dynamic>> _futures = {};

  Future<dynamic> _future(_Stat stat) => _futures.putIfAbsent(stat.navId, () => _api.get(stat.endpoint));

  _Stat _stat(String navId) => _stats.firstWhere((s) => s.navId == navId);

  final _quotaKey = GlobalKey<StorageQuotaCardState>();

  bool _refreshing = false;

  void _retry(_Stat stat) => setState(() {
    _futures.remove(stat.navId);
  });

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final auth = context.read<AuthProvider>();
      await auth.loadPermissions(); // also picks up role changes
      if (!mounted) return;
      if (auth.permissionsError != null && auth.permissionsLoaded) {
        // The last known permissions stay in effect; tell the user they may be stale.
        showAppSnackBar(context, 'Yetkiler yenilenemedi: ${auth.permissionsError}', error: true);
      }
      setState(() {
        _futures.clear();
        for (final stat in _stats.where((s) => auth.has(s.permission))) {
          _future(stat);
        }
      });
      await Future.wait([
        ..._futures.values.map((f) => f.then((_) {}, onError: (_) {})),
        if (_quotaKey.currentState != null) _quotaKey.currentState!.reload(),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Content scrolls under the glass app bar, so the top inset is applied here.
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return AppScaffold(
      title: 'Gösterge Paneli',
      navId: NavConfig.dashboard.id,
      safeArea: false,
      actions: [
        IconButton(
          tooltip: 'Yenile',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refreshing ? null : _refresh,
        ),
      ],
      body: RefreshIndicator(
        edgeOffset: topInset,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(20, topInset + 20, 20, 40 + MediaQuery.paddingOf(context).bottom),
          children: _content(auth),
        ),
      ),
    );
  }

  List<Widget> _content(AuthProvider auth) {
    if (!auth.permissionsLoaded) {
      // Nothing is gated-in until permissions are known; offer a retry instead of locking the user out.
      return [
        const SizedBox(height: 80),
        auth.permissionsError == null
            ? const LoadingView(label: 'Yetkiler yükleniyor')
            : ErrorView(message: 'Yetkiler yüklenemedi: ${auth.permissionsError}', onRetry: auth.loadPermissions),
      ];
    }
    final hasAnyModule = NavConfig.groups
        .expand((g) => g.items)
        .any((item) => item.permission != null && isNavItemVisible(auth, item));
    if (!hasAnyModule) {
      return [
        const SizedBox(height: 80),
        EmptyView(
          icon: Icons.lock_outline_rounded,
          message: 'Erişim yetkiniz olan modül yok.',
          actionLabel: 'Yenile',
          onAction: auth.loadPermissions,
        ),
      ];
    }

    final stats = _stats.where((s) => auth.has(s.permission)).toList();
    final canEmails = auth.has(_stat('email-logs').permission);
    final canPosts = auth.has(_stat('posts').permission);
    return [
      _greeting(auth.displayName),
      const SizedBox(height: 24),
      if (stats.isNotEmpty) _statsGrid(stats),
      const SizedBox(height: 24),
      StorageQuotaCard(key: _quotaKey, api: _api, onManage: () => openNavItem(context, NavConfig.byId('settings'))),
      if (canEmails) ...[
        const SizedBox(height: 24),
        _recentSection(
          title: 'Son E-postalar',
          stat: _stat('email-logs'),
          rows: (data) => [
            for (final log in extractItems(data))
              _recentRow(
                title: (log['subject']?.toString() ?? '').isEmpty ? '(konu yok)' : log['subject'].toString(),
                subtitle: '${log['recipient'] ?? ''} · ${_formatDateTime(log['createdAt'])}',
                badge: emailStatusLabels[log['status']] ?? '${log['status'] ?? ''}',
                badgeColor: switch (log['status']) {
                  'SENT' => AppColors.success,
                  'FAILED' => Theme.of(context).colorScheme.onErrorContainer,
                  _ => AppColors.warning,
                },
              ),
          ],
        ),
      ],
      if (canPosts) ...[
        const SizedBox(height: 24),
        _recentSection(
          title: 'Son Yazılar',
          stat: _stat('posts'),
          rows: (data) => [
            for (final post in extractItems(data).take(8))
              _recentRow(
                title: post['title']?.toString() ?? '#${post['id']}',
                subtitle: post['slug']?.toString() ?? '',
                badge: post['status'] == true ? 'Yayında' : 'Taslak',
                badgeColor: post['status'] == true
                    ? AppColors.success
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _greeting(String? name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tekrar hoş geldin,', style: TextStyle(fontSize: 16, color: _muted(context))),
        const SizedBox(height: 8),
        Text(
          (name == null || name.isEmpty) ? 'Yönetici' : name,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Color _muted(BuildContext context) => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05)),
  );

  /// Cards size to their content (no fixed aspect ratio) → no overflow at large text scales.
  /// Two columns while a column keeps ≥130 dp of *scaled* room: every phone (320–430 dp) at
  /// normal text, one column once the text scale makes cards too narrow (≈1.4× on 393 dp).
  Widget _statsGrid(List<_Stat> stats) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = constraints.maxWidth / textScale >= 260 ? 2 : 1;
        const spacing = 16.0;
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final stat in stats) SizedBox(width: width, child: _statCard(stat))],
        );
      },
    );
  }

  Widget _statCard(_Stat stat) {
    final item = NavConfig.byId(stat.navId);
    return FutureBuilder<dynamic>(
      future: _future(stat),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final failed = !loading && snapshot.hasError;
        final Widget value;
        if (loading) {
          value = SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: '${stat.title} yükleniyor'),
          );
        } else if (failed) {
          value = Text(
            'Yüklenemedi · tekrar dene',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          );
        } else {
          value = Text(
            _formatCount(totalCount(snapshot.data)),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          );
        }
        return Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: MergeSemantics(
            child: InkWell(
              key: ValueKey('stat_${stat.navId}'),
              onTap: loading ? null : (failed ? () => _retry(stat) : () => openNavItem(context, item)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: stat.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(item.icon, color: stat.color, size: 20),
                        ),
                        const Spacer(),
                        if (failed)
                          Icon(Icons.refresh_rounded, color: Theme.of(context).colorScheme.onErrorContainer, size: 20),
                      ],
                    ),
                    const SizedBox(height: 12),
                    value,
                    const SizedBox(height: 4),
                    Text(stat.title, style: TextStyle(fontSize: 13, color: _muted(context))),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// "Son …" list under the cards; shares the card's request (same as the admin).
  Widget _recentSection({
    required String title,
    required _Stat stat,
    required List<Widget> Function(dynamic data) rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              TextButton(onPressed: () => openNavItem(context, NavConfig.byId(stat.navId)), child: const Text('Tümü')),
            ],
          ),
          FutureBuilder<dynamic>(
            future: _future(stat),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: LoadingView(label: '$title yükleniyor'),
                );
              }
              if (snapshot.hasError) return ErrorView(message: '${snapshot.error}', onRetry: () => _retry(stat));
              final children = rows(snapshot.data);
              if (children.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Kayıt yok',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted(context)),
                  ),
                );
              }
              return Column(children: children);
            },
          ),
        ],
      ),
    );
  }

  Widget _recentRow({
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: _muted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Capped so the title keeps room at large text scales.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: badgeColor, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
