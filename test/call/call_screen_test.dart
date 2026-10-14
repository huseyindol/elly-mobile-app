import 'package:elly_mobile_app/config/app_theme.dart';
import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/call_screen.dart';
import 'package:elly_mobile_app/screens/chat/chat_members_screen.dart';
import 'package:elly_mobile_app/screens/login_screen.dart';
import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_call_media.dart';
import '../helpers/fake_realtime.dart';

const me = 7;
const c1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const g1 = '11111111-1111-4111-8111-111111111111';
const _me = {'id': me, 'username': 'ben', 'firstName': 'Ben', 'lastName': 'Admin'};

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late FakeCalls calls;
  late int settingsOpened;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    calls = FakeCalls(live);
    settingsOpened = 0;
    backend.ok('/chat/tenant/t1/groups', [
      {'id': g1, 'name': 'Ekip', 'type': 'GROUP', 'createdBy': 1, 'visibilityLevel': 1, 'tenantId': 't1'},
    ]);
    backend.ok('/chat/tenant/t1/groups/$g1/members', [
      {'userId': me, 'username': 'ben', 'firstName': 'Ben', 'lastName': 'Admin', 'role': 'OWNER'},
      {'userId': 5, 'username': 'ayse', 'firstName': 'Ayşe', 'lastName': 'Y', 'role': 'MEMBER'},
    ]);
  });

  tearDown(() {
    calls.dispose();
    live.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // route transitions
  }

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(400, 860), double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => backend.signIn(auth, ['chat:read'], roles: ['ADMIN'], me: _me));
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
          home: AuthWrapper(
            apiService: backend.api,
            openSettings: () async {
              settingsOpened++;
              return true;
            },
          ),
        ),
      ),
    );
    await settle(tester);
    expect(live.link.destinations, contains('/topic/user/$me/rtc'), reason: 'listening once the user id is known');
  }

  Future<void> signal(WidgetTester tester, Map<String, Object?> body) async {
    calls.signal(me, body);
    await settle(tester);
  }

  Future<void> incoming(WidgetTester tester, {bool ringAll = false}) => signal(tester, {
    'type': 'INCOMING_CALL',
    'callId': c1,
    'peerUserId': 5,
    'peerDisplayName': 'mehmet',
    'ringAll': ringAll,
  });

  Future<void> tapCall(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  /// Ends whatever is on and removes the tree (no call timers left behind).
  Future<void> finish(WidgetTester tester) async {
    calls.provider.reset();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Finder status(String text) =>
      find.descendant(of: find.byKey(const ValueKey('call_status')), matching: find.text(text), matchRoot: true);

  testWidgets('incoming call: full screen over the app, announced, three labelled 64 dp actions', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await incoming(tester);

    expect(find.byType(CallScreen), findsOneWidget);
    expect(status('Gelen çağrı'), findsOneWidget);
    expect(find.text('mehmet'), findsOneWidget);
    expect(find.text('ID 5'), findsOneWidget);
    expect(calls.medias, isEmpty, reason: 'no microphone/camera before the user accepts');

    final statusNode = tester.getSemantics(find.byKey(const ValueKey('call_status')));
    expect(statusNode.flagsCollection.isLiveRegion, isTrue);
    for (final label in ['Reddet', 'Sesli cevapla', 'Görüntülü cevapla']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
    await finish(tester);
  });

  testWidgets('answer (voice) → connecting → in call: controls, duration; hang up closes the screen', (tester) async {
    await pumpApp(tester);
    await incoming(tester);
    await tapCall(tester, 'call_answer_audio');
    expect(calls.media.ops, ['open:false', 'connect']);
    expect(calls.sentTo, ['/app/rtc/$c1/answer']);
    expect(status('Bağlanıyor…'), findsOneWidget);
    final answerVideo = tester.widget<InkWell>(
      find.descendant(of: find.byKey(const ValueKey('call_answer_video')), matching: find.byType(InkWell)),
    );
    expect(answerVideo.onTap, isNull, reason: 'accepting: answer buttons locked, reject still possible');

    await signal(tester, {'type': 'ANSWERED', 'callId': c1, 'peerUserId': 5, 'peerDisplayName': 'mehmet'});
    expect(status('Bağlanıyor…'), findsOneWidget);
    expect(find.byKey(const ValueKey('call_camera')), findsNothing, reason: 'no camera in a voice call');
    calls.media.onState!(PeerState.connected);
    await tester.pump();
    expect(status('Görüşmede'), findsOneWidget);
    expect(find.byKey(const ValueKey('call_duration')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Görüşme süresi \d\d:\d\d$')), findsOneWidget);

    await tapCall(tester, 'call_mic');
    expect(calls.media.mic, isFalse);
    expect(find.bySemanticsLabel('Mikrofonu aç'), findsOneWidget);
    await tapCall(tester, 'call_speaker');
    expect(calls.media.speaker, isTrue);
    expect(find.bySemanticsLabel('Hoparlörü kapat'), findsOneWidget);

    await tapCall(tester, 'call_hangup');
    expect(calls.sentTo.last, '/app/rtc/$c1/hangup');
    expect(calls.media.tracksStopped, isTrue);
    expect(find.byType(CallScreen), findsNothing);
    await finish(tester);
  });

  testWidgets('video: own preview, remote video when it arrives, camera off hides the preview', (tester) async {
    await pumpApp(tester);
    await incoming(tester);
    await tapCall(tester, 'call_answer_video');
    await signal(tester, {'type': 'ANSWERED', 'callId': c1, 'peerUserId': 5});
    expect(find.byKey(const ValueKey('fake_local_video')), findsOneWidget);
    expect(find.bySemanticsLabel('Kendi görüntünüz'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake_remote_video')), findsNothing);

    calls.media.remoteVideo = true;
    calls.media.onRemote!();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake_remote_video')), findsOneWidget);
    expect(find.bySemanticsLabel('Karşı tarafın görüntüsü'), findsOneWidget);

    await tapCall(tester, 'call_switch_camera');
    expect(calls.media.switches, 1);
    await tapCall(tester, 'call_camera');
    expect(calls.media.camera, isFalse);
    expect(find.byKey(const ValueKey('fake_local_video')), findsNothing);
    await finish(tester);
  });

  testWidgets('caller cancels while ringing: screen closes, "Cevapsız çağrı" SnackBar', (tester) async {
    await pumpApp(tester);
    await incoming(tester);
    await signal(tester, {'type': 'CANCELLED', 'callId': c1});
    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('Cevapsız çağrı: mehmet'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('ring-all support call: labelled, explained; taken by someone else → closes with a notice', (
    tester,
  ) async {
    await pumpApp(tester);
    await incoming(tester, ringAll: true);
    expect(status('Gelen destek çağrısı'), findsOneWidget);
    expect(find.textContaining('ilk cevaplayan görüşmeyi alır'), findsOneWidget);
    await signal(tester, {'type': 'CALL_TAKEN', 'callId': c1});
    expect(find.byType(CallScreen), findsNothing);
    expect(find.textContaining('başka bir panel kullanıcısı'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('no notification banner during a call (its "Aç" would push a screen over the call)', (tester) async {
    await pumpApp(tester);
    await incoming(tester);
    live.push('/user/queue/notifications', {
      'id': 9,
      'type': 'SYSTEM',
      'title': 'Duyuru',
      'message': 'metin',
      'read': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await tester.pump();
    expect(find.text('Duyuru: metin'), findsNothing);
    await finish(tester);
  });

  testWidgets('back button does not leave a call', (tester) async {
    await pumpApp(tester);
    await incoming(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(CallScreen), findsOneWidget);
    expect(calls.sent, isEmpty);
    await finish(tester);
  });

  testWidgets('sign-out during a call: hang-up sent, media released, login screen without the call', (tester) async {
    await pumpApp(tester);
    await incoming(tester);
    await tapCall(tester, 'call_answer_video');
    await signal(tester, {'type': 'ANSWERED', 'callId': c1, 'peerUserId': 5});
    final sentBefore = List.of(live.link.sent);

    await tester.runAsync(() => auth.logout());
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(CallScreen), findsNothing);
    expect(live.link.sent.skip(sentBefore.length).map((s) => s.$1), ['/app/rtc/$c1/hangup']);
    expect(live.link.closed, isTrue, reason: 'socket closed after the hang-up frame');
    expect(calls.media.tracksStopped, isTrue);
    expect(calls.media.closed, isTrue);
    await finish(tester);
  });

  testWidgets('app to background during a call: hang up before the socket closes', (tester) async {
    await pumpApp(tester);
    await incoming(tester);
    await tapCall(tester, 'call_answer_audio');
    await signal(tester, {'type': 'ANSWERED', 'callId': c1, 'peerUserId': 5});
    final link = live.link;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(calls.provider.phase, CallPhase.connecting, reason: 'inactive (system sheet) keeps the call');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await settle(tester);
    expect(link.sent.last.$1, '/app/rtc/$c1/hangup');
    expect(link.closed, isTrue);
    expect(calls.media.tracksStopped, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.byType(CallScreen), findsNothing);
    expect(find.textContaining('arka plana geçtiği için'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('permission refused on answer: call rejected, SnackBar offers the settings', (tester) async {
    calls.setup = (m) => m.openError = (_) => const CallMediaException(CallMediaError.denied);
    await pumpApp(tester);
    await incoming(tester);
    await tapCall(tester, 'call_answer_audio');
    expect(calls.sentTo, ['/app/rtc/$c1/reject']);
    expect(find.byType(CallScreen), findsNothing);
    expect(find.textContaining('izni verilmedi'), findsOneWidget);
    await tester.tap(find.text('Ayarlar'));
    await tester.pump();
    expect(settingsOpened, 1);
    await finish(tester);
  });

  testWidgets('member list: call others (not yourself), voice or video; outgoing screen; cancel', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() => live.chat.open(myUserId: me, myLevel: 3));
    EllyMobileApp.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => ChatMembersScreen(group: live.chat.groupById(g1)!)),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('chat_call_$me')), findsNothing);
    expect(find.byTooltip('Ara: Ayşe Y'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_call_5')));
    await settle(tester);
    expect(find.text('Sesli ara'), findsOneWidget);
    await tester.tap(find.text('Görüntülü ara'));
    await settle(tester);
    expect(calls.media.ops.first, 'open:true');
    expect(calls.sent.single, [
      '/app/rtc/call',
      {'calleeUserId': 5, 'groupId': g1},
    ]);
    expect(find.byType(CallScreen), findsOneWidget);
    expect(status('Aranıyor…'), findsOneWidget);
    expect(find.text('Ayşe Y'), findsWidgets);

    await signal(tester, {'type': 'RINGING', 'callId': c1, 'peerUserId': 5, 'peerDisplayName': 'ayse'});
    expect(status('Çalıyor…'), findsOneWidget);
    await tapCall(tester, 'call_cancel');
    expect(calls.sentTo.last, '/app/rtc/$c1/cancel');
    expect(find.byType(CallScreen), findsNothing);
    expect(find.byType(ChatMembersScreen), findsOneWidget, reason: 'back where the call started');
    await finish(tester);
  });

  testWidgets('small screen + 200 % text: in-call controls fit (scrolls, no overflow)', (tester) async {
    await pumpApp(tester, size: const Size(320, 568), textScale: 2);
    await incoming(tester);
    await tapCall(tester, 'call_answer_video');
    await signal(tester, {'type': 'ANSWERED', 'callId': c1, 'peerUserId': 5});
    calls.media.onState!(PeerState.connected);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('call_hangup')));
    await tester.pump();
    expect(find.byKey(const ValueKey('call_hangup')).hitTestable(), findsOneWidget);
    await finish(tester);
  });
}
