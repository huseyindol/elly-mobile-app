import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/devices/mac_camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_call_media.dart';
import '../helpers/fake_realtime.dart';

/// Hızlı Arama sayfası: iki çağrı biçimi ve huseyindol/zehradol dışına kapalı olması.
void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late FakeRealtime live;
  late FakeCalls calls;

  const me = {
    'id': 4,
    'username': 'huseyindol',
    'firstName': 'Hüseyin',
    'lastName': 'Dol',
    'email': 'h@x.com',
    'provider': 'local',
    'isActive': true,
    'roles': ['SUPER_ADMIN'],
    'createdAt': '2026-01-01T10:00:00Z',
  };

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    live = FakeRealtime(backend);
    calls = FakeCalls(live);
    SharedPreferences.setMockInitialValues({});
    // Sahte backend sorgu dizesini yok sayar: /users?audience=panel → '/users'.
    backend.ok('/users', [
      {'id': 4, 'username': 'huseyindol', 'email': 'h@x.com', 'isActive': true},
      {'id': 21, 'username': 'mac-agent', 'email': 'agent@x.com', 'isActive': true},
      {'id': 23, 'username': 'zehradol', 'firstName': 'Zehra', 'lastName': 'DOL', 'email': 'z@x.com', 'isActive': true},
    ]);
  });

  tearDown(() {
    calls.dispose();
    live.dispose();
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pump(WidgetTester tester, {Map<String, dynamic> who = me}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => backend.signIn(auth, const [], roles: ['SUPER_ADMIN'], me: who));
    // Çağrı canlı bağlantı gerektirir: sahte bağlantıyı kur ve bağlı duruma gelmesini bekle.
    live.realtime.start();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    calls.provider.start(who['id'] as int, tenantId: 't1');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ...live.providers,
          ...calls.providers,
        ],
        child: MaterialApp(home: MacCameraScreen(apiService: backend.api)),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.tap(key(k));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('"Görüntülü Konuş": karşılıklı — bu cihazın mikrofonu ve kamerası açılır', (tester) async {
    await pump(tester);

    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Hızlı Arama')), findsOneWidget);
    await tap(tester, 'mac_camera_talk');

    expect(calls.media.ops.first, 'open:true', reason: 'standart görüntülü arama: getUserMedia ses + görüntü');
    expect(calls.media.recvOnlyOpen, isFalse);
    expect(calls.sentTo, contains('/app/rtc/call'));
    expect((calls.sent.single[1] as Map)['calleeUserId'], 21, reason: 'önerilen cihaz: mac-agent');
    expect(calls.provider.peerName, 'Hızlı Arama');
    calls.provider.reset();
    await tester.pump();
  });

  testWidgets('"İzle ve Dinle": bu telefondan hiçbir şey gönderilmez', (tester) async {
    await pump(tester);

    await tap(tester, 'mac_camera_watch');

    expect(calls.media.ops.first, 'open:false:recvonly');
    expect(calls.media.tracksLive, isFalse, reason: 'mikrofon/kamera hiç açılmaz');
    expect(calls.provider.hasLocalAudio, isFalse);
    expect(calls.sentTo, contains('/app/rtc/call'));
    calls.provider.reset();
    await tester.pump();
  });

  testWidgets('zehradol hesabı da Hızlı Arama sayfasına erişip çağrı başlatabilir', (tester) async {
    await pump(tester, who: {...me, 'id': 23, 'username': 'zehradol', 'firstName': 'Zehra', 'lastName': 'DOL'});

    expect(find.text('Bu alan erişiminize kapalı.'), findsNothing);
    expect(key('mac_camera_talk'), findsOneWidget);
    expect(key('mac_camera_watch'), findsOneWidget);

    await tap(tester, 'mac_camera_talk');
    expect((calls.sent.single[1] as Map)['calleeUserId'], 21);
    calls.provider.reset();
    await tester.pump();
  });

  testWidgets('yetkisiz hesap: sayfa kapalı, çağrı düğmeleri yok', (tester) async {
    await pump(tester, who: {...me, 'id': 13, 'username': 'diger-admin'});

    expect(find.text('Bu alan erişiminize kapalı.'), findsOneWidget);
    expect(key('mac_camera_talk'), findsNothing);
    expect(key('mac_camera_watch'), findsNothing);
    expect(calls.medias, isEmpty);
  });
}
