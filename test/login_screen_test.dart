import 'dart:convert';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

const _mfaField = ValueKey('mfa_code_field');

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend()..permissions(['posts:read']);
    backend.routes['/auth/login'] = (_) => okData({'mfaRequired': true, 'mfaToken': 'm1'});
    backend.routes['/auth/mfa/verify'] = (_) => okData({'token': 'a', 'refreshToken': 'r', 'username': 'u'});
    auth = backend.newAuth();
  });

  Future<void> pumpLogin(WidgetTester tester) => tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

  /// Lets the fake backend / mock storage futures complete, then rebuilds.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> submitCredentials(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'tenant1');
    await tester.enterText(fields.at(1), 'user@example.com');
    await tester.enterText(fields.at(2), 'not-a-real-password');
    await tester.tap(find.text('Sign In'));
    await settle(tester);
  }

  Future<void> submitCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(_mfaField), code);
    await tester.tap(find.text('Doğrula'));
    await settle(tester);
  }

  testWidgets('mfaRequired response switches to the 6-digit code step', (tester) async {
    await pumpLogin(tester);
    expect(find.byKey(_mfaField), findsNothing);

    await submitCredentials(tester);

    expect(auth.mfaPending, isTrue);
    expect(find.byKey(_mfaField), findsOneWidget);
    expect(find.text('Doğrula'), findsOneWidget);
    expect(find.text('Geri dön'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
    expect(find.text('Tenant ID'), findsNothing);
    expect(find.byType(SnackBar), findsNothing); // code step is not an error
  });

  testWidgets('valid code verifies with mfaToken + tenant header and authenticates', (tester) async {
    await pumpLogin(tester);
    await submitCredentials(tester);
    await submitCode(tester, '123456');

    final verify = backend.requestsTo('/auth/mfa/verify').single;
    expect(jsonDecode(verify.body), {'mfaToken': 'm1', 'code': '123456'});
    expect(verify.headers['X-Tenant-Id'], 'tenant1');
    expect(auth.isAuthenticated, isTrue);
    expect(auth.mfaPending, isFalse);
    expect(auth.can('posts', 'read'), isTrue);
  });

  testWidgets('"Geri dön" returns to the credentials step without calling verify', (tester) async {
    await pumpLogin(tester);
    await submitCredentials(tester);
    await tester.enterText(find.byKey(_mfaField), '12');

    await tester.tap(find.text('Geri dön'));
    await tester.pump();

    expect(auth.mfaPending, isFalse);
    expect(find.byKey(_mfaField), findsNothing);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Geri dön'), findsNothing);
    expect(backend.requestsTo('/auth/mfa/verify'), isEmpty);
    expect(auth.isAuthenticated, isFalse);
  });

  for (final bad in ['12345', '12345a', '']) {
    testWidgets('invalid code "$bad" is rejected locally and not sent', (tester) async {
      await pumpLogin(tester);
      await submitCredentials(tester);
      await submitCode(tester, bad);

      expect(find.text('6 haneli kod girin'), findsOneWidget);
      expect(backend.requestsTo('/auth/mfa/verify'), isEmpty);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.mfaPending, isTrue);
    });
  }

  for (final (input, sent) in [('123 456', '123456'), ('1234567', '123456'), ('12-34-56', '123456')]) {
    testWidgets('code field keeps digits only, max 6: "$input" → "$sent"', (tester) async {
      await pumpLogin(tester);
      await submitCredentials(tester);
      await submitCode(tester, input);

      expect(jsonDecode(backend.requestsTo('/auth/mfa/verify').single.body)['code'], sent);
    });
  }

  testWidgets('keyboard "done" on the code field submits', (tester) async {
    await pumpLogin(tester);
    await submitCredentials(tester);
    await tester.enterText(find.byKey(_mfaField), '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(backend.requestsTo('/auth/mfa/verify'), hasLength(1));
    expect(auth.isAuthenticated, isTrue);
  });

  testWidgets('API rejection of the code shows an error snackbar and keeps the code step', (tester) async {
    backend.routes['/auth/mfa/verify'] = (_) => jsonResponse({'message': 'Geçersiz kod'}, 401);
    await pumpLogin(tester);
    await submitCredentials(tester);
    await submitCode(tester, '000000');

    expect(backend.requestsTo('/auth/mfa/verify'), hasLength(1));
    expect(find.descendant(of: find.byType(SnackBar), matching: find.text('Geçersiz kod')), findsOneWidget);
    expect(find.byKey(_mfaField), findsOneWidget);
    expect(auth.isAuthenticated, isFalse);
  });
}
