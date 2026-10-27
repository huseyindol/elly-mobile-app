import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:provider/provider.dart';

import 'config/app_theme.dart';
import 'models/chat_models.dart';
import 'providers/auth_provider.dart';
import 'providers/call_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/notifications_provider.dart';
import 'screens/call_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/notifications_screen.dart';
import 'services/api_service.dart';
import 'services/app_settings.dart';
import 'services/call_machine.dart';
import 'services/chat_format.dart';
import 'services/realtime_service.dart';
import 'widgets/app_snack_bar.dart';

void main() {
  final api = ApiService();
  final realtime = RealtimeService(api: api);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuthStatus()),
        ChangeNotifierProvider.value(value: realtime),
        ChangeNotifierProvider(
          create: (_) => NotificationsProvider(api: api, realtime: realtime),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(api: api, realtime: realtime),
        ),
        ChangeNotifierProvider(create: (_) => CallProvider(realtime: realtime)),
      ],
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
///
/// Also owns the live connection's lifecycle (when the realtime providers are present): sign-in → connect +
/// notifications; sign-out → chat/notification state cleared and the socket closed; background → socket closed,
/// foreground → reconnect (+ re-sync). A new notification while the app is open shows an in-app SnackBar.
///
/// Calls (when a [CallProvider] is present): listens for the signed-in user's call signals once the user id is
/// known, shows [CallScreen] over everything while a call is on and removes it when the call ends, shows the call's
/// notices; sign-out and background end the call first (the end frame goes out before the socket closes).
class AuthWrapper extends StatefulWidget {
  final ApiService? apiService;

  /// Test seam: opens the app's system settings (refused microphone/camera permission).
  final Future<bool> Function() openSettings;
  const AuthWrapper({super.key, this.apiService, this.openSettings = openAppSettings});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _wasAuthenticated = false;
  bool _inBackground = false;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<AppNotification>? _incoming;
  CallProvider? _call;
  StreamSubscription<CallNotice>? _callNotices;
  Route<void>? _callRoute;
  int? _callUserId;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _call = context.read<CallProvider?>()?..addListener(_onCall);
    _callNotices = _call?.notices.listen(_showCallNotice);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _incoming?.cancel();
    _call?.removeListener(_onCall);
    _callNotices?.cancel();
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    final realtime = context.read<RealtimeService?>();
    switch (state) {
      case AppLifecycleState.resumed:
        _inBackground = false;
        realtime?.setForeground(true);
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _inBackground = true;
        if (_call?.keepAliveInBackground == true) break;
        _call?.endForBackground();
        realtime?.setForeground(false);
      case AppLifecycleState.detached:
        _inBackground = true;
        _call?.endForBackground();
        realtime?.setForeground(false);
      case AppLifecycleState.inactive:
        break; // transient (app switcher, system sheet): keep the socket
    }
  }

  void _sessionStarted() {
    final notifications = context.read<NotificationsProvider?>();
    context.read<RealtimeService?>()?.start();
    notifications?.start();
    _incoming = notifications?.incoming.listen(_showBanner);
  }

  void _sessionEnded() {
    _call?.reset();
    _callUserId = null;
    _incoming?.cancel();
    _incoming = null;
    context.read<ChatProvider?>()?.reset();
    context.read<NotificationsProvider?>()?.reset();
    context.read<RealtimeService?>()?.stop();
  }

  /// In-app banner for a pushed notification (no push notifications in this plan). Not while the list is open,
  /// for a chat message of the conversation on screen, or during a call ("Aç" would push a screen over it).
  void _showBanner(AppNotification n) {
    if ((_call?.phase ?? CallPhase.idle) != CallPhase.idle) return;
    final notifications = context.read<NotificationsProvider>();
    final activeGroup = context.read<ChatProvider?>()?.activeGroupId;
    if (notifications.listVisible || (activeGroup != null && n.metadata['groupId'] == activeGroup)) return;
    final navContext = EllyMobileApp.navigatorKey.currentContext;
    if (navContext == null) return;
    final (text, _) = clipChatText(
      safeChatText([n.title, n.message].where((s) => s.isNotEmpty).join(': ')),
      maxChars: 140,
      maxLines: 2,
    );
    showAppSnackBar(
      navContext,
      text,
      action: SnackBarAction(
        label: 'Aç',
        onPressed: () {
          notifications.markRead(n).catchError((_) {});
          final ctx = EllyMobileApp.navigatorKey.currentContext;
          if (ctx != null) openNotification(ctx, n, api: widget.apiService);
        },
      ),
    );
  }

  /// Call screen on top of the stack exactly while a call is on.
  void _onCall() {
    final call = _call!;
    final navigator = EllyMobileApp.navigatorKey.currentState;
    if (_callRoute != null && !_callRoute!.isActive) _callRoute = null; // closed by the sign-out popUntil
    if (call.phase != CallPhase.idle && _callRoute == null && navigator != null) {
      navigator.push(_callRoute = CallScreen.route());
    } else if (call.phase == CallPhase.idle && _callRoute != null) {
      navigator?.removeRoute(_callRoute!);
      _callRoute = null;
      if (_inBackground) {
        context.read<RealtimeService?>()?.setForeground(false);
      }
    }
  }

  void _showCallNotice(CallNotice n) {
    final navContext = EllyMobileApp.navigatorKey.currentContext;
    if (navContext == null) return;
    showAppSnackBar(
      navContext,
      n.message,
      error: n.error,
      action: n.openSettings ? SnackBarAction(label: 'Ayarlar', onPressed: () => widget.openSettings()) : null,
      persist: false,
      duration: n.openSettings ? const Duration(seconds: 10) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final authenticated = auth.isAuthenticated;
    // Call signals are per user id (known after /users/me or the login response).
    final callUserId = authenticated ? auth.userId : null;
    if (callUserId != null && callUserId != _callUserId) {
      _callUserId = callUserId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _callUserId == callUserId) _call?.start(callUserId);
      });
    }
    if (_wasAuthenticated != authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (authenticated) {
          _sessionStarted();
        } else {
          _sessionEnded();
          EllyMobileApp.navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _wasAuthenticated = authenticated;
    return authenticated ? DashboardScreen(apiService: widget.apiService) : const LoginScreen();
  }
}
