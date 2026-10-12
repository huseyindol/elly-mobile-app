import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
  });

  /// Simulates app start with a stored token: loads permissions through the fake backend.
  Future<void> startApp() {
    FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
    return auth.checkAuthStatus();
  }

  Future<void> pumpDashboard(WidgetTester tester) async {
    // The app bar avatar is a NetworkImage; flutter_test blocks real HTTP (400) and the image
    // error would fail the test. Ignore only that error, everything else still fails.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    // Tall surface so every module card is built by the lazy ListView.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
  }

  Future<void> run(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(action);
    await tester.pump();
  }

  List<String> allTitles() => ModulesConfig.allModules.map((m) => m.title).toList();

  testWidgets('shows only modules with <key>:read; create/update/delete alone do not reveal a module',
      (tester) async {
    backend.permissions(['posts:read', 'pages:read', 'pages:update', 'forms:create', 'assets:delete']);
    await run(tester, () => startApp());
    await pumpDashboard(tester);

    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Pages'), findsOneWidget);
    for (final hidden in allTitles().where((t) => t != 'Posts' && t != 'Pages')) {
      expect(find.text(hidden), findsNothing, reason: '$hidden must be hidden without :read');
    }
  });

  testWidgets('read on every module shows every module card', (tester) async {
    backend.permissions([for (final m in ModulesConfig.allModules) '${m.permissionKey}:read']);
    await run(tester, () => startApp());
    await pumpDashboard(tester);

    for (final title in allTitles()) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('no read permission at all shows the empty-access message', (tester) async {
    backend.permissions(['posts:create']);
    await run(tester, () => startApp());
    await pumpDashboard(tester);

    expect(find.text('Erişim yetkiniz olan modül yok.'), findsOneWidget);
    for (final title in allTitles()) {
      expect(find.text(title), findsNothing);
    }
  });

  testWidgets('permission load failure shows error + "Tekrar Dene"; retry reveals modules', (tester) async {
    backend.routes['/users/me/permissions'] = (_) => http.Response('', 500);
    await run(tester, () => startApp());
    await pumpDashboard(tester);

    expect(find.textContaining('Yetkiler yüklenemedi'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
    for (final title in allTitles()) {
      expect(find.text(title), findsNothing);
    }

    backend.permissions(['posts:read']);
    await tester.tap(find.text('Tekrar Dene'));
    await run(tester, () => Future<void>.delayed(const Duration(milliseconds: 50)));

    expect(find.text('Tekrar Dene'), findsNothing);
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Pages'), findsNothing);
  });
}
