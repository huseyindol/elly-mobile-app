import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:elly_mobile_app/providers/chat_provider.dart';
import 'package:elly_mobile_app/providers/notifications_provider.dart';
import 'package:elly_mobile_app/services/realtime_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'fake_backend.dart';

/// One fake STOMP connection: records CONNECT headers, subscriptions and SENDs; the test drives it.
class FakeStompLink implements StompLink {
  final String url;
  final Map<String, String> headers;
  final void Function() _onConnected;
  final void Function(String message) _onError;
  final void Function() _onClosed;

  FakeStompLink(this.url, this.headers, this._onConnected, this._onError, this._onClosed);

  final Map<String, List<void Function(String)>> subscriptions = {};
  final List<(String, String)> sent = [];
  bool closed = false;

  @override
  void Function() subscribe(String destination, void Function(String body) onMessage) {
    subscriptions.putIfAbsent(destination, () => []).add(onMessage);
    return () => subscriptions[destination]?.remove(onMessage);
  }

  @override
  void send(String destination, String body) => sent.add((destination, body));

  @override
  void close() => closed = true;

  Set<String> get destinations => {
    for (final e in subscriptions.entries)
      if (e.value.isNotEmpty) e.key,
  };

  void connected() => _onConnected();
  void stompError([String message = 'Invalid or expired JWT token']) => _onError(message);
  void drop() => _onClosed();

  /// MESSAGE frame to every subscriber of [destination] ([body] JSON-encoded unless it is a String).
  void deliver(String destination, Object body) {
    final text = body is String ? body : jsonEncode(body);
    for (final handler in List.of(subscriptions[destination] ?? const <void Function(String)>[])) {
      handler(text);
    }
  }
}

/// RealtimeService + notification/chat providers over [FakeBackend] and fake STOMP links (no network).
class FakeRealtime {
  final FakeBackend backend;

  /// true: every new link reports CONNECTED in a microtask.
  bool autoConnect;

  FakeRealtime(this.backend, {this.autoConnect = true});

  final List<FakeStompLink> links = [];

  late final RealtimeService realtime = RealtimeService(api: backend.api, connector: _connect, random: Random(1));
  late final NotificationsProvider notifications = NotificationsProvider(api: backend.api, realtime: realtime);
  late final ChatProvider chat = ChatProvider(api: backend.api, realtime: realtime);

  FakeStompLink get link => links.last;

  StompLink _connect({
    required String url,
    required Map<String, String> headers,
    required void Function() onConnected,
    required void Function(String message) onError,
    required void Function() onClosed,
  }) {
    final link = FakeStompLink(url, headers, onConnected, onError, onClosed);
    links.add(link);
    if (autoConnect) scheduleMicrotask(link.connected);
    return link;
  }

  List<SingleChildWidget> get providers => [
    ChangeNotifierProvider<RealtimeService>.value(value: realtime),
    ChangeNotifierProvider<NotificationsProvider>.value(value: notifications),
    ChangeNotifierProvider<ChatProvider>.value(value: chat),
  ];

  /// Delivers on the current link.
  void push(String destination, Object body) => link.deliver(destination, body);

  /// Ends everything that could leave timers behind.
  void dispose() {
    chat.reset();
    notifications.reset();
    realtime.stop();
  }
}
