import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import 'api_service.dart';

/// One physical STOMP connection. Production: [stompClientConnector]; tests: a fake.
abstract class StompLink {
  /// Returns the unsubscribe callback.
  void Function() subscribe(String destination, void Function(String body) onMessage);
  void send(String destination, String body);
  void close();
}

/// Opens a [StompLink] to [url] with the STOMP CONNECT [headers]. [onConnected]: CONNECTED frame; [onError]: STOMP
/// ERROR frame (the server closes afterwards); [onClosed]: the socket failed or closed. Callbacks may repeat.
typedef StompConnector = StompLink Function({
  required String url,
  required Map<String, String> headers,
  required void Function() onConnected,
  required void Function(String message) onError,
  required void Function() onClosed,
});

/// `stomp_dart_client` over SockJS's WebSocket transport (`/ws/{server}/{session}/websocket`) — the admin's
/// sockjs-client path. SockJS's 25 s heartbeat frames keep idle connections alive through the ingress (the simple
/// broker sends no STOMP heartbeats); the socket ping detects dead networks. The client never reconnects itself:
/// [RealtimeService] does, with backoff and a fresh token.
StompLink stompClientConnector({
  required String url,
  required Map<String, String> headers,
  required void Function() onConnected,
  required void Function(String message) onError,
  required void Function() onClosed,
}) => _StompClientLink(
  StompClient(
    config: StompConfig.sockJS(
      url: url,
      stompConnectHeaders: headers,
      reconnectDelay: Duration.zero,
      connectionTimeout: const Duration(seconds: 15),
      heartbeatIncoming: const Duration(seconds: 20),
      heartbeatOutgoing: const Duration(seconds: 20),
      pingInterval: const Duration(seconds: 20),
      onConnect: (_) => onConnected(),
      onStompError: (frame) => onError(frame.headers['message'] ?? frame.body ?? ''),
      onWebSocketError: (_) => onClosed(),
      onWebSocketDone: onClosed,
    ),
  )..activate(),
);

class _StompClientLink implements StompLink {
  final StompClient _client;
  _StompClientLink(this._client);

  @override
  void Function() subscribe(String destination, void Function(String body) onMessage) {
    final unsubscribe = _client.subscribe(destination: destination, callback: (f) => onMessage(f.body ?? ''));
    return () => unsubscribe();
  }

  @override
  void send(String destination, String body) => _client.send(destination: destination, body: body);

  @override
  void close() => _client.deactivate();
}

/// Handle returned by [RealtimeService.subscribe].
class RealtimeSubscription {
  final void Function() cancel;
  RealtimeSubscription._(this.cancel);
}

class _Sub {
  final String destination;
  final void Function(String body) onMessage;
  void Function()? detach;
  _Sub(this.destination, this.onMessage);
}

/// The app's single STOMP connection (`${API origin}/ws`, CONNECT `Authorization: Bearer`). Screens and providers
/// [subscribe] / [send]; subscriptions outlive reconnects (re-subscribed on every CONNECTED, [connectionSeq] bumps
/// so listeners can re-sync what they missed).
///
/// Lifecycle: [start] after sign-in, [stop] on sign-out (closes and forgets every subscription), [setForeground]
/// closes the socket in the background (the OS would kill it anyway; presence goes offline) and reconnects on resume.
/// A dropped connection is retried with exponential backoff (1 s … 30 s, ±20 %). A STOMP ERROR before CONNECTED
/// (expired/revoked token) runs [checkSession] — an authenticated REST call, so `ApiService` refreshes the token on
/// 401 or ends the session through its own logout flow — then reconnects at once with the token in storage.
class RealtimeService extends ChangeNotifier {
  final StompConnector _connector;
  final Future<String?> Function() _readToken;
  final Future<void> Function() _checkSession;
  final Random _random;

  RealtimeService({
    ApiService? api,
    StompConnector? connector,
    Future<String?> Function()? readToken,
    Future<void> Function()? checkSession,
    Random? random,
  }) : this._(api ?? ApiService(), connector, readToken, checkSession, random);

  RealtimeService._(
    ApiService api,
    StompConnector? connector,
    Future<String?> Function()? readToken,
    Future<void> Function()? checkSession,
    Random? random,
  ) : _connector = connector ?? stompClientConnector,
      _readToken = readToken ?? (() => api.secureStorage.read(key: 'accessToken')),
      _checkSession = checkSession ?? (() => api.get('/notifications/unread-count')),
      _random = random ?? Random();

  /// SockJS endpoint on the API origin (`/ws` is outside `/api/v1`).
  static String get url => '${Uri.parse(ApiService.baseUrl).origin}/ws';

  static const maxBackoff = Duration(seconds: 30);

  bool _started = false;
  bool _foreground = true;
  bool _connected = false;
  int _seq = 0;
  int _attempt = 0;
  int _generation = 0;
  bool _sessionChecked = false;
  StompLink? _link;
  Timer? _retry;
  final List<_Sub> _subs = [];

  bool get connected => _connected;

  /// Bumps on every CONNECTED (first connect and each reconnect).
  int get connectionSeq => _seq;

  bool get started => _started;

  void start() {
    if (_started) return;
    _started = true;
    _attempt = 0;
    _sessionChecked = false; // a new session starts with a clean rejection streak
    _connect();
  }

  /// Sign-out: closes the connection and drops every subscription.
  void stop() {
    _started = false;
    _subs.clear();
    _teardown();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _teardown();
    } else if (_started) {
      _attempt = 0;
      _connect();
    }
  }

  /// "Şimdi dene": skips the backoff wait (no-op while connected / connecting or signed out / in background).
  void retryNow() {
    if (!_started || !_foreground || _link != null) return;
    _attempt = 0;
    _connect();
  }

  /// Registers [onMessage] for [destination]; active now if connected, and after every reconnect.
  RealtimeSubscription subscribe(String destination, void Function(String body) onMessage) {
    final sub = _Sub(destination, onMessage);
    _subs.add(sub);
    if (_connected) _attach(sub);
    return RealtimeSubscription._(() {
      if (!_subs.remove(sub)) return;
      try {
        sub.detach?.call();
      } catch (_) {}
      sub.detach = null;
    });
  }

  /// Fire-and-forget SEND; false when not connected (typing/read signals are best effort).
  bool send(String destination, [String body = '']) {
    final link = _link;
    if (!_connected || link == null) return false;
    try {
      link.send(destination, body);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _attach(_Sub sub) {
    final link = _link;
    if (link == null) return;
    try {
      sub.detach = link.subscribe(sub.destination, (body) {
        // A frame still in flight on a dead/replaced link, or for a cancelled / signed-out subscription, is dropped:
        // it must never reach the next session's handlers or be handled twice after a reconnect.
        if (_link != link || !_connected || !_subs.contains(sub)) return;
        try {
          sub.onMessage(body);
        } catch (_) {
          // a bad payload must not break the connection or other subscribers
        }
      });
    } catch (_) {
      sub.detach = null;
    }
  }

  Future<void> _connect() async {
    if (!_started || !_foreground || _link != null) return;
    _retry?.cancel();
    final generation = ++_generation;
    final token = await _readToken();
    if (generation != _generation || !_started || !_foreground || _link != null) return;
    if (token == null || token.isEmpty) return; // signed out meanwhile
    late final StompLink link;
    link = _connector(
      url: url,
      headers: {'Authorization': 'Bearer $token'},
      onConnected: () {
        if (_link != link || _connected) return;
        _connected = true;
        _attempt = 0;
        _sessionChecked = false;
        _seq++;
        for (final sub in List.of(_subs)) {
          _attach(sub);
        }
        notifyListeners();
      },
      onError: (_) => _drop(link, rejected: !_connected),
      onClosed: () => _drop(link, rejected: false),
    );
    _link = link;
  }

  /// [link] is gone: forget it, then reconnect — at once after a session check when CONNECT was rejected
  /// (once per failure streak), otherwise after the backoff delay.
  void _drop(StompLink link, {required bool rejected}) {
    if (_link != link) return;
    _closeLink();
    if (!_started || !_foreground) return;
    if (rejected && !_sessionChecked) {
      _sessionChecked = true;
      final generation = _generation;
      _checkSession().then((_) {}, onError: (_) {}).whenComplete(() {
        if (generation == _generation) _connect();
      });
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    final base = min(maxBackoff.inMilliseconds, 1000 * (1 << min(_attempt, 5)));
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: (base * jitter).round()), _connect);
  }

  void _closeLink() {
    final link = _link;
    _link = null;
    for (final sub in _subs) {
      sub.detach = null; // the server drops subscriptions with the session
    }
    final wasConnected = _connected;
    _connected = false;
    try {
      link?.close();
    } catch (_) {}
    if (wasConnected) notifyListeners();
  }

  void _teardown() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _closeLink();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
