import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:provider/provider.dart';

import 'config/app_theme.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuthStatus())],
      child: const EllyMobileApp(),
    ),
  );
}

/// Rich text editor toolbar strings + Flutter SDK Material/Widgets/Cupertino strings (each once).
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  FlutterQuillLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class EllyMobileApp extends StatelessWidget {
  /// Test seam: ApiService for the dashboard.
  final ApiService? apiService;

  const EllyMobileApp({super.key, this.apiService});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elly Mobile App',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: appTheme,
      localizationsDelegates: appLocalizationsDelegates,
      // The UI is Turkish only: system strings (date picker, list reorder actions, …) follow it whatever
      // the device language is.
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      home: AuthWrapper(apiService: apiService),
    );
  }
}

/// Root route: login ↔ dashboard. On sign-out (logout or expired session) every screen, dialog
/// and sheet above it is closed, so the next user never lands on the previous user's screen.
class AuthWrapper extends StatefulWidget {
  final ApiService? apiService;
  const AuthWrapper({super.key, this.apiService});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _wasAuthenticated = false;

  @override
  Widget build(BuildContext context) {
    final authenticated = context.watch<AuthProvider>().isAuthenticated;
    if (_wasAuthenticated && !authenticated) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => EllyMobileApp.navigatorKey.currentState?.popUntil((route) => route.isFirst),
      );
    }
    _wasAuthenticated = authenticated;
    return authenticated ? DashboardScreen(apiService: widget.apiService) : const LoginScreen();
  }
}
