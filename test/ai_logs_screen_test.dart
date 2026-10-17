import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/ai/ai_logs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  testWidgets('AiLogsScreen displays stats, lists logs, and opens detail screen', (tester) async {
    backend.ok('/ai/stats', {
      'totalCalls': 4,
      'successCalls': 3,
      'errorCalls': 1,
      'totalInputTokens': 120,
      'totalOutputTokens': 60,
      'totalThoughtTokens': 300,
      'totalCachedTokens': 0,
      'totalTokens': 480,
      'avgDurationMs': 512.5,
      'byAction': [
        {
          'action': 'slug',
          'endpoint': '/api/v1/ai/slug',
          'callCount': 2,
          'successCount': 2,
          'errorCount': 0,
          'inputTokens': 60,
          'outputTokens': 20,
          'thoughtTokens': 100,
          'totalTokens': 180,
          'avgDurationMs': 310.0,
        },
      ],
    });
    backend.ok('/ai/logs', {
      'content': [
        {
          'id': 11,
          'createdAt': '2026-10-17T13:00:00Z',
          'requestId': 'req-123',
          'stepOrder': 1,
          'endpoint': '/api/v1/ai/slug',
          'action': 'slug',
          'model': 'gemini-3.8-flash',
          'username': 'admin',
          'tenantId': 'tenant1',
          'userInput': '{"title":"Merhaba Dünya"}',
          'promptText': 'Başlık: Merhaba Dünya',
          'responseText': 'merhaba-dunya',
          'parsedOutput': '{"slug":"merhaba-dunya"}',
          'promptChars': 21,
          'responseChars': 13,
          'inputTokens': 30,
          'outputTokens': 10,
          'thoughtTokens': 50,
          'cachedTokens': 0,
          'totalTokens': 90,
          'durationMs': 320,
          'status': 'SUCCESS',
          'httpStatus': 200,
        },
      ],
      'totalElements': 1,
      'totalPages': 1,
    });

    await tester.runAsync(() => backend.signIn(auth, ['posts:read']));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: AiLogsScreen(apiService: backend.api)),
      ),
    );
    await settle(tester);

    expect(find.byKey(const ValueKey('ai_stats_card')), findsOneWidget);
    expect(find.text('480'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_log_11')), findsOneWidget);
    expect(find.textContaining('slug · #11'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai_log_11')));
    await tester.pumpAndSettle();

    expect(find.byType(AiLogDetailScreen), findsOneWidget);
    expect(find.textContaining('Merhaba Dünya'), findsWidgets);
    expect(find.textContaining('merhaba-dunya'), findsWidgets);
  });

  testWidgets('AiLogsScreen opens AI quota management sheet from AppBar', (tester) async {
    backend.ok('/ai/stats', {
      'totalCalls': 1,
      'successCalls': 1,
      'errorCalls': 0,
      'totalInputTokens': 10,
      'totalOutputTokens': 10,
      'totalThoughtTokens': 10,
      'totalCachedTokens': 0,
      'totalTokens': 30,
      'avgDurationMs': 100.0,
      'byAction': [],
    });
    backend.ok('/ai/logs', {'content': [], 'totalElements': 0, 'totalPages': 0});
    backend.ok('/ai/tenant/t1/quota', {
      'tenantId': 't1',
      'monthlyTokenLimit': 1000000,
      'monthlyTokensUsed': 250000,
      'monthlyTokensRemaining': 750000,
      'monthlyTokenUsedPercent': 25.0,
      'dailyRequestLimit': 250,
      'dailyRequestsUsed': 10,
      'dailyRequestsRemaining': 240,
      'dailyRequestUsedPercent': 4.0,
      'dailyTokensUsed': 5000,
      'monthlyInputTokens': 100000,
      'monthlyOutputTokens': 50000,
      'monthlyThoughtTokens': 100000,
      'monthlyCachedTokens': 0,
      'monthlyEstimatedCostUsd': 0.6375,
      'totalEstimatedCostUsd': 0.6375,
    });

    await tester.runAsync(() => backend.signIn(auth, ['posts:read'], roles: const ['SUPER_ADMIN']));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: AiLogsScreen(apiService: backend.api)),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('ai_quota_sheet_button')));
    await settle(tester);

    expect(find.byKey(const ValueKey('ai_quota_card')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_monthly_limit_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_daily_limit_field')), findsOneWidget);
  });
}
