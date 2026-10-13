import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/coming_soon_screen.dart';
import 'package:elly_mobile_app/screens/dashboard_screen.dart';
import 'package:elly_mobile_app/screens/login_screen.dart';
import 'package:flutter/material.dart';
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

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  /// Signed-in app with a section screen and a dialog on top of the dashboard.
  Future<void> pumpDeepStack(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, ['chat:read']));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: EllyMobileApp(apiService: backend.api),
      ),
    );
    await settle(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav_chat')));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.byType(ComingSoonScreen)),
      builder: (_) => const AlertDialog(content: Text('Açık dialog')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Açık dialog'), findsOneWidget);
  }

  void expectLoginOnly() {
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ComingSoonScreen), findsNothing);
    expect(find.text('Açık dialog'), findsNothing);
  }

  testWidgets('logout closes every screen and dialog above the root; re-login starts at the dashboard', (tester) async {
    await pumpDeepStack(tester);

    await tester.runAsync(() => auth.logout());
    await tester.pumpAndSettle();
    expectLoginOnly();

    backend.ok('/auth/login', {'token': 'b', 'refreshToken': 'r2', 'username': 'baska'});
    await tester.runAsync(() => auth.login(usernameOrEmail: 'baska', password: 'p', tenantId: 't1'));
    await tester.pump();
    await settle(tester);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(ComingSoonScreen), findsNothing, reason: "previous user's screen must be gone");
  });

  testWidgets('an expired session (401 + failed refresh) also clears the stack', (tester) async {
    await pumpDeepStack(tester);
    backend.routes['/anything'] = (_) => http.Response('', 401);

    await tester.runAsync(() async {
      await expectLater(backend.api.get('/anything'), throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(auth.isAuthenticated, isFalse);
    expectLoginOnly();
  });
}
