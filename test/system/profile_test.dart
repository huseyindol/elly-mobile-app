import 'dart:convert';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/account/change_password_screen.dart';
import 'package:elly_mobile_app/screens/account/profile_edit_screen.dart';
import 'package:elly_mobile_app/screens/account/profile_screen.dart';
import 'package:elly_mobile_app/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _me({String provider = 'local', String first = 'Hüseyin', String last = 'Dol'}) => {
  'id': 7,
  'username': 'hdol',
  'email': 'h@x.com',
  'firstName': first,
  'lastName': last,
  'provider': provider,
  'isActive': true,
  'roles': ['ADMIN'],
  'createdAt': '2025-03-04T10:00:00Z',
};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, Widget home, {Map<String, dynamic>? me}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => backend.signIn(auth, const ['posts:read', 'posts:update', 'pages:read'], roles: ['ADMIN'], me: me ?? _me()),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(theme: appTheme, home: home),
      ),
    );
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  group('app start profile (/users/me)', () {
    test('a stored session loads the profile next to the permissions; logout clears it', () async {
      backend.permissions(const ['posts:read']);
      backend.ok('/users/me', _me());
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
      await auth.checkAuthStatus();
      expect(auth.displayName, 'Hüseyin Dol');
      expect(auth.userId, 7);
      await auth.logout();
      expect(auth.profile, isNull);
      expect(auth.displayName, '');
    });

    test('profile failure is silent: name falls back to the login username', () async {
      backend.permissions(const ['posts:read']);
      backend.ok('/auth/login', {'token': 't', 'refreshToken': 'r', 'userId': '7', 'username': 'hdol'});
      await auth.login(usernameOrEmail: 'hdol', password: 'p', tenantId: 't1');
      expect(auth.isAuthenticated, isTrue);
      expect(auth.displayName, 'hdol');
      expect(auth.userId, 7);
    });

    testWidgets('drawer header shows the full name and its initials (not "Kullanıcı")', (tester) async {
      await pump(tester, const Scaffold(drawer: AppDrawer(currentId: 'dashboard')));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      final header = key('drawer_profile');
      expect(find.descendant(of: header, matching: find.text('Hüseyin Dol')), findsOneWidget);
      expect(find.descendant(of: header, matching: find.text('HD')), findsOneWidget);
      expect(find.descendant(of: header, matching: find.text('Kullanıcı')), findsNothing);
    });

    test('avatarInitials: two words → first letters (admin sidebar)', () {
      expect(avatarInitials('hüseyin dol'), 'HD');
      expect(avatarInitials('ışık  irmak  üç'), 'Iİ');
    });
  });

  group('profile screen', () {
    testWidgets('shows /users/me, roles and grouped permissions', (tester) async {
      await pump(tester, const ProfileScreen());
      expect(find.text('Hüseyin Dol'), findsWidgets);
      expect(find.text('@hdol'), findsOneWidget);
      expect(find.text('h@x.com'), findsOneWidget);
      expect(find.text('E-posta / Şifre'), findsOneWidget);
      expect(find.text('04.03.2025'), findsOneWidget);
      expect(find.text('Yazılar'), findsOneWidget);
      expect(find.text('Sayfalar'), findsOneWidget);
      expect(find.text('İzinler (3)'), findsOneWidget);
      expect(key('profile_change_password'), findsOneWidget);
    });

    testWidgets('OAuth account: no password change', (tester) async {
      await pump(tester, const ProfileScreen(), me: _me(provider: 'google'));
      expect(key('profile_change_password'), findsNothing);
      expect(find.text('google'), findsOneWidget);
    });

    testWidgets('load error with nothing cached → error + retry', (tester) async {
      backend.routes['/users/me'] = (_) => jsonResponse({'message': 'boom'}, 500);
      await tester.runAsync(() => backend.signIn(auth, const ['posts:read']));
      expect(auth.profile, isNull);
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(theme: appTheme, home: const ProfileScreen()),
        ),
      );
      await settle(tester);
      expect(find.text('boom'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });
  });

  group('profile edit (PUT /users/me)', () {
    testWidgets('sends first/last name + e-mail; drawer name follows the response', (tester) async {
      await pump(tester, ProfileEditScreen(apiService: backend.api));
      backend.routes['/users/me'] = (req) =>
          okData(req.method == 'PUT' ? {..._me(), ...jsonDecode(req.body) as Map} : _me());
      await tester.enterText(key('profile_field_firstName'), 'Ali');
      await tester.tap(key('crud_save_button'));
      await settle(tester);
      final put = backend.requests.where((r) => r.method == 'PUT').single;
      expect(jsonDecode(put.body), {'firstName': 'Ali', 'lastName': 'Dol', 'email': 'h@x.com'});
      expect(auth.displayName, 'Ali Dol');
    });

    testWidgets('blank e-mail is refused locally (backend would store "")', (tester) async {
      await pump(tester, ProfileEditScreen(apiService: backend.api));
      await tester.enterText(key('profile_field_email'), '');
      await tester.tap(key('crud_save_button'));
      await settle(tester);
      expect(backend.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(find.text('E-posta zorunludur'), findsOneWidget);
    });

    testWidgets('e-mail taken (409) → Turkish message', (tester) async {
      await pump(tester, ProfileEditScreen(apiService: backend.api));
      backend.routes['/users/me'] = (_) => jsonResponse({'message': 'Email already exists: b@x.com'}, 409);
      await tester.enterText(key('profile_field_email'), 'b@x.com');
      await tester.tap(key('crud_save_button'));
      await settle(tester);
      expect(find.text('Bu e-posta adresi zaten kullanılıyor.'), findsOneWidget);
    });
  });

  group('change password (PUT /users/me/password)', () {
    Future<void> fill(WidgetTester tester, String current, String next, String confirm) async {
      await tester.enterText(key('password_field_current'), current);
      await tester.enterText(key('password_field_new'), next);
      await tester.enterText(key('password_field_confirm'), confirm);
      await tester.tap(key('password_save_button'));
      await settle(tester);
    }

    Iterable<dynamic> puts() => backend.requestsTo('/users/me/password');

    testWidgets('rules checked before sending: strength, same as current, mismatch', (tester) async {
      await pump(tester, ChangePasswordScreen(apiService: backend.api));
      await fill(tester, 'Aa1aaaaa', 'zayif', 'zayif'); // ggignore
      expect(find.textContaining('büyük/küçük harf + rakam olmalıdır'), findsOneWidget);
      await fill(tester, 'Aa1aaaaa', 'Aa1aaaaa', 'Aa1aaaaa'); // ggignore
      expect(find.text('Yeni şifre mevcut şifreden farklı olmalı'), findsOneWidget);
      await fill(tester, 'Aa1aaaaa', 'Bb2bbbbb', 'Bb2bbbbbb'); // ggignore
      expect(find.text('Şifreler eşleşmiyor'), findsOneWidget);
      expect(puts(), isEmpty);
    });

    testWidgets('wrong current password (400) → "Mevcut şifre hatalı."; stays on the screen', (tester) async {
      backend.routes['/users/me/password'] = (_) => jsonResponse({'message': 'Current password is incorrect'}, 400);
      await pump(tester, ChangePasswordScreen(apiService: backend.api));
      await fill(tester, 'Cc3ccccc', 'Bb2bbbbb', 'Bb2bbbbb'); // ggignore
      expect(find.text('Mevcut şifre hatalı.'), findsOneWidget);
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(auth.isAuthenticated, isTrue);
    });

    testWidgets('success sends exactly the two passwords', (tester) async {
      backend.routes['/users/me/password'] = (_) => jsonResponse({'result': true, 'data': null}, 200);
      await pump(tester, ChangePasswordScreen(apiService: backend.api));
      await fill(tester, 'Aa1aaaaa', 'Bb2bbbbb', 'Bb2bbbbb'); // ggignore
      expect(jsonDecode(puts().single.body), {'currentPassword': 'Aa1aaaaa', 'newPassword': 'Bb2bbbbb'}); // ggignore
    });
  });
}
