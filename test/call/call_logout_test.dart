import 'dart:async';

import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/call_screen.dart';
import 'package:elly_mobile_app/screens/login_screen.dart';
import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_call_media.dart';
import '../helpers/fake_realtime.dart';

/// Sign-out order and robustness through the real `AuthWrapper`: the end frame (cancel / reject / hang up) goes out
/// before the socket closes (a frame sent after `stop()` is silently dropped, so "frame present" proves the order);
/// a socket that is already down must neither hang the sign-out nor keep the microphone.
const me = 7;
const c1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _meJson = {'id': me, 'username': 'ben', 'firstName': 'Ben', 'lastName': 'Admin'};
const _bJson = {'id': 8, 'username': 'can', 'firstName': 'Can', 'lastName': 'Admin'};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late FakeCalls calls;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    calls = FakeCalls(live);
  });

  tearDown(() {
    calls.dispose();
    live.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, ['chat:read'], roles: ['ADMIN'], me: _meJson));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ...live.providers,
          ...calls.providers,
        ],
        child: MaterialApp(
          navigatorKey: EllyMobileApp.navigatorKey,
          theme: appTheme,
          localizationsDelegates: appLocalizationsDelegates,
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr')],
          home: AuthWrapper(apiService: backend.api, openSettings: () async => true),
        ),
      ),
    );
    await settle(tester);
    expect(live.link.destinations, contains('/topic/user/$me/rtc'));
  }

  Future<void> signal(WidgetTester tester, Map<String, Object?> body, {int user = me}) async {
    calls.signal(user, body);
    await settle(tester);
  }

  Future<void> logout(WidgetTester tester) async {
    // A hung sign-out (waiting for something that never comes) fails here instead of timing the suite out.
    await tester.runAsync(() => auth.logout().timeout(const Duration(seconds: 3)));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    calls.provider.reset();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  void expectSignedOutClean(FakeStompLink link, {bool socketWasUp = true}) {
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(CallScreen), findsNothing);
    expect(calls.provider.phase, CallPhase.idle);
    expect(calls.leaks, isEmpty, reason: 'microphone/camera released, peer connection closed, renderers disposed');
    expect(link.closed, isTrue);
    if (socketWasUp) {
      expect(link.destinations, isEmpty, reason: 'every subscription unsubscribed');
    } else {
      // a dead link keeps its handlers in the fake; the service must drop whatever they still deliver
      link.deliver('/topic/user/$me/rtc', {'type': 'INCOMING_CALL', 'callId': c1, 'peerUserId': 5});
      expect(calls.provider.phase, CallPhase.idle, reason: 'a frame of the signed-out session is ignored');
    }
    expect(live.realtime.started, isFalse);
  }

  testWidgets('sign-out while our outgoing call rings: cancel goes out before the socket closes', (tester) async {
    await pumpApp(tester);
    unawaited(calls.provider.call(9, 'Ayşe', video: true));
    await settle(tester);
    await signal(tester, {'type': 'RINGING', 'callId': c1, 'peerUserId': 9});
    final link = live.link;
    expect(calls.media.leaks, isNotEmpty, reason: 'the media is open before the sign-out');

    await logout(tester);
    expect(calls.sentTo, ['/app/rtc/call', '/app/rtc/$c1/cancel']);
    expectSignedOutClean(link);
    await finish(tester);
  });

  testWidgets('sign-out while a call rings for us: reject goes out before the socket closes, no media', (tester) async {
    await pumpApp(tester);
    await signal(tester, {'type': 'INCOMING_CALL', 'callId': c1, 'peerUserId': 5, 'peerDisplayName': 'mehmet'});
    expect(find.byType(CallScreen), findsOneWidget);
    final link = live.link;

    await logout(tester);
    expect(calls.sentTo, ['/app/rtc/$c1/reject']);
    expect(calls.medias, isEmpty);
    expectSignedOutClean(link);
    await finish(tester);
  });

  testWidgets('sign-out while the permission prompt is open: rejected, the late stream is stopped, never answered', (
    tester,
  ) async {
    await pumpApp(tester);
    final prompt = Completer<void>();
    calls.setup = (m) => m.openGate = prompt;
    await signal(tester, {'type': 'INCOMING_CALL', 'callId': c1, 'peerUserId': 5, 'ringAll': true});
    unawaited(calls.provider.answer(video: true));
    await settle(tester);
    expect(calls.provider.answering, isTrue);
    final link = live.link;

    await logout(tester);
    prompt.complete(); // the user taps "Allow" on the OS prompt after the sign-out
    await settle(tester);
    expect(calls.sentTo, ['/app/rtc/$c1/reject']);
    expect(calls.media.opened, isFalse, reason: 'the stream arrived after the call was gone');
    expect(calls.media.tracksStopped, isTrue);
    expectSignedOutClean(link);
    await finish(tester);
  });

  testWidgets('sign-out with the socket already down: the sign-out does not hang, the media is released', (
    tester,
  ) async {
    await pumpApp(tester);
    unawaited(calls.provider.call(9, 'Ayşe', video: false));
    await settle(tester);
    await signal(tester, {'type': 'RINGING', 'callId': c1, 'peerUserId': 9});
    await signal(tester, {'type': 'ANSWERED', 'callId': c1, 'peerUserId': 9});
    final link = live.link;
    link.drop(); // network gone: the reconnect backoff is pending
    await settle(tester);
    expect(live.realtime.connected, isFalse);
    expect(calls.media.leaks, isNotEmpty);
    final sentBefore = link.sent.length;

    await logout(tester);
    expect(link.sent.length, sentBefore, reason: 'no frame can be sent on a dead socket (and none is queued)');
    expectSignedOutClean(link, socketWasUp: false);
    expect(live.links, hasLength(1), reason: 'no reconnect after the sign-out');
    await finish(tester);
  });

  testWidgets('sign-out, then another user signs in: the old call is gone, the new session starts clean', (
    tester,
  ) async {
    await pumpApp(tester);
    unawaited(calls.provider.call(9, 'Ayşe', video: true));
    await settle(tester);
    await signal(tester, {'type': 'RINGING', 'callId': c1, 'peerUserId': 9});
    final first = calls.media;
    final oldLink = live.link;

    await logout(tester);
    expectSignedOutClean(oldLink);

    await tester.runAsync(() => backend.signIn(auth, ['chat:read'], roles: ['ADMIN'], me: _bJson));
    await settle(tester);
    expect(live.link.destinations, contains('/topic/user/8/rtc'));
    expect(live.link.destinations, isNot(contains('/topic/user/$me/rtc')), reason: 'only the new user\'s signals');
    expect(calls.provider.phase, CallPhase.idle);
    expect(first.leaks, isEmpty);

    // the old session's leftovers (RINGING/ANSWERED/HANGUP of c1) reach neither the old nor the new topic's handler
    for (final user in [me, 8]) {
      calls.signal(user, {'type': 'ANSWERED', 'callId': c1, 'peerUserId': 9});
      calls.signal(user, {'type': 'HANGUP', 'callId': c1});
    }
    await settle(tester);
    expect(calls.provider.phase, CallPhase.idle);
    expect(calls.medias, hasLength(1), reason: 'no media was opened for the new session');
    expect(find.byType(CallScreen), findsNothing);
    await finish(tester);
  });

  testWidgets('app to background with the socket already down: call ends and media is released', (tester) async {
    await pumpApp(tester);
    unawaited(calls.provider.call(9, 'Ayşe', video: true));
    await settle(tester);
    await signal(tester, {'type': 'RINGING', 'callId': c1, 'peerUserId': 9});
    live.link.drop();
    await settle(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await settle(tester);
    expect(calls.provider.phase, CallPhase.idle);
    expect(calls.leaks, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); // frames are paused while hidden
    await settle(tester);
    expect(find.byType(CallScreen), findsNothing);
    await finish(tester);
  });
}
