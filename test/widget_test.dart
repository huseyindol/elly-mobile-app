import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';

void main() {
  testWidgets('Login screen loads correctly smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const EllyMobileApp(),
      ),
    );

    // Verify that the login screen title or button is present.
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Elly Admin'), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
  });
}
