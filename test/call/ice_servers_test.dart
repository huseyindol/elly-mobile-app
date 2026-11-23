import 'package:elly_mobile_app/providers/call_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backend'in ICE listesi (`GET /notifications/ice-servers`) → flutter_webrtc `iceServers`.
void main() {
  group('CallProvider.iceServersFrom', () {
    test('urls stays a list: a comma-joined string is ONE invalid address on iOS, so no peer connection', () {
      final out = CallProvider.iceServersFrom([
        {'urls': ['stun:stun.l.google.com:19302']},
        {
          'urls': ['turn:34.135.64.132:3478', 'turn:34.135.64.132:3478?transport=tcp'],
          'username': 'ellyturn',
          'credential': 'secret',
        },
      ]);
      expect(out, [
        {'urls': ['stun:stun.l.google.com:19302']},
        {
          'urls': ['turn:34.135.64.132:3478', 'turn:34.135.64.132:3478?transport=tcp'],
          'username': 'ellyturn',
          'credential': 'secret',
        },
      ]);
    });

    test('a single string url is kept as is; entries without urls and non-list payloads are dropped', () {
      expect(CallProvider.iceServersFrom([
        {'urls': 'stun:stun.l.google.com:19302'},
      ]), [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]);
      expect(CallProvider.iceServersFrom([{'username': 'u'}, 'x', {'urls': []}]), isEmpty);
      expect(CallProvider.iceServersFrom(null), isEmpty);
      expect(CallProvider.iceServersFrom({'result': true}), isEmpty);
    });
  });
}
