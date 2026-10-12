import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';

// Credentials via --dart-define (device runs don't see the host environment):
//   flutter test integration_test --dart-define=ELLY_USER=... --dart-define=ELLY_PASS=... [--dart-define=ELLY_TENANT=...]
const _tenant = String.fromEnvironment('ELLY_TENANT', defaultValue: 'tenant1');
const _user = String.fromEnvironment('ELLY_USER');
const _pass = String.fromEnvironment('ELLY_PASS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-End automated UI test (Login and Module Navigation)', skip: _user.isEmpty || _pass.isEmpty,
      (tester) async {
    // Uygulamayı MultiProvider ile başlatıyoruz
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const EllyMobileApp(),
      ),
    );

    // Animasyonların bitmesini bekle
    await tester.pumpAndSettle();

    // 1. Giriş Bilgilerini Doldur (Tenant, Kullanıcı Adı, Şifre)
    // TextFormField'leri sırasıyla buluyoruz
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(3), reason: 'Login ekranında 3 input alanı olmalı');

    // Tenant ID
    await tester.enterText(textFields.at(0), _tenant);
    // Username
    await tester.enterText(textFields.at(1), _user);
    // Password
    await tester.enterText(textFields.at(2), _pass);

    await tester.pumpAndSettle();

    // 2. Sign In Butonuna Tıkla
    final signInBtn = find.text('Sign In');
    await tester.tap(signInBtn);

    // API isteği ve sayfa geçişi için yeterince bekle (animasyonlar vb.)
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 3. Dashboard'a başarıyla girildiğini doğrula
    expect(find.text('Gösterge Paneli'), findsWidgets, reason: 'Giriş başarılı olmalı ve Dashboard açılmalı');

    // 4. Drawer'dan bir modüle git (Örnek: Sayfalar)
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    final pagesItem = find.byKey(const ValueKey('nav_pages'));
    if (pagesItem.evaluate().isNotEmpty) {
      await tester.tap(pagesItem);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Liste ekranı açıldığını onayla
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Sayfalar')), findsWidgets,
          reason: 'Sayfalar liste ekranı yüklenmeli');

      // Geri dön
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
