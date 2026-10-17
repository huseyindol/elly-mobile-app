import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:elly_mobile_app/services/call_machine.dart';
import 'package:elly_mobile_app/services/call_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/call_rig.dart';

/// `CallSignal.parse` reads frames from a shared broker topic: any other panel user / compromised tenant path can
/// shape them. Whatever arrives, parsing never throws, and what comes out is bounded, well-formed and safe to show.

final _uuidRe = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Chars that must never reach the screen raw (they are replaced by a visible `⟨U+XXXX⟩` or dropped).
final _forbiddenInName = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069\n\r]');

CallSignal? parseMap(Map<String, Object?> m) => CallSignal.parse(jsonEncode(m));

/// What every non-null result must satisfy.
void expectSane(CallSignal s, {String? reason}) {
  expect(callSignalTypes, contains(s.type), reason: reason);
  if (s.callId != null) expect(_uuidRe.hasMatch(s.callId!), isTrue, reason: '$reason callId=${s.callId}');
  if (s.sdp != null) expect(s.sdp!.length, inInclusiveRange(1, maxSdpLength), reason: reason);
  if (s.candidate != null) expect(s.candidate!.length, inInclusiveRange(1, maxCandidateLength), reason: reason);
  if (s.sdpMid != null) expect(s.sdpMid!.length, inInclusiveRange(1, 64), reason: reason);
  if (s.sdpMLineIndex != null) expect(s.sdpMLineIndex, inInclusiveRange(0, 63), reason: reason);
  if (s.sdpType != null) expect(['offer', 'answer'], contains(s.sdpType), reason: reason);
  expect(s.peerName.length, lessThanOrEqualTo(81), reason: reason);
  expect(s.peerName, isNot(contains(_forbiddenInName)), reason: '$reason peerName=${s.peerName}');
  if (s.reason != null) {
    expect(
      s.reason!,
      isNot(contains(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]'))),
    );
    expect(s.reason!.length, lessThanOrEqualTo(201), reason: reason);
  }
  for (final t in [s.peerName, s.reason]) {
    if (t != null) {
      expect(_wellFormed(t), isTrue, reason: '$reason: lone UTF-16 surrogate in displayed text would throw in Text');
    }
  }
}

bool _wellFormed(String t) {
  final u = t.codeUnits;
  for (var i = 0; i < u.length; i++) {
    if (u[i] >= 0xD800 && u[i] <= 0xDBFF) {
      if (i + 1 >= u.length || u[i + 1] < 0xDC00 || u[i + 1] > 0xDFFF) return false;
      i++;
    } else if (u[i] >= 0xDC00 && u[i] <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

void main() {
  group('CallSignal.parse: structure', () {
    test('top-level values that are not an object are rejected, never thrown on', () {
      for (final body in [
        '',
        ' ',
        'null',
        'true',
        '0',
        '-1',
        '1.5',
        '1e999',
        '"INCOMING_CALL"',
        '[]',
        '[{"type":"INCOMING_CALL","callId":"$c1"}]',
        '[[[[]]]]',
        '{',
        '}',
        '{"type"',
        '{"type":"HANGUP"',
        '{"type":"HANGUP"}}',
        '{"type":"HANGUP"} {"type":"HANGUP"}',
        '{"type":"HANGUP",}',
        "{'type':'HANGUP'}",
        'NaN',
        '{"type":NaN}',
        '{"type":"HANGUP","sdpMLineIndex":NaN}',
        '{"type":"HANGUP","sdpMLineIndex":Infinity}',
        '﻿{"type":"HANGUP"}',
        '\u0000',
        '{"type":"HANGUP"}\u0000',
      ]) {
        CallSignal? s;
        expect(() => s = CallSignal.parse(body), returnsNormally, reason: body);
        expect(s, isNull, reason: body);
      }
    });

    test('a very deep or very large frame: rejected / bounded, no stack overflow, no hang', () {
      final sw = Stopwatch()..start();
      expect(CallSignal.parse('[' * 200000), isNull);
      expect(CallSignal.parse('{"a":' * 100000), isNull);
      expect(
        CallSignal.parse('{"type":"HANGUP","x":${'[' * 100000}${']' * 100000}}'),
        anyOf(isNull, isA<CallSignal>()),
      );
      final huge = CallSignal.parse(
        jsonEncode({'type': 'SDP', 'callId': c1, 'sdpType': 'offer', 'sdp': 'v' * 5000000}),
      );
      expect(huge, isNotNull);
      expect(huge!.sdp, isNull, reason: '5 MB of "SDP" is not a session description');
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('duplicate keys: the last one wins and is validated like any other', () {
      expect(CallSignal.parse('{"type":"HANGUP","type":"NOPE"}'), isNull);
      expect(CallSignal.parse('{"type":"NOPE","type":"HANGUP"}')!.type, 'HANGUP');
      expect(CallSignal.parse('{"type":"HANGUP","callId":"$c1","callId":"x"}'), isNull);
    });

    test('unknown extra fields are ignored; null optional fields are fine', () {
      final s = CallSignal.parse(
        jsonEncode({
          'type': 'HANGUP',
          'callId': c1,
          'evil': {
            'a': [1],
          },
          'sdp': null,
          'reason': null,
        }),
      );
      expect(s, isNotNull);
      expect(s!.sdp, isNull);
      expect(s.reason, isNull);
    });
  });

  group('CallSignal.parse: every field with every wrong type', () {
    const fields = [
      'type',
      'callId',
      'peerUserId',
      'peerDisplayName',
      'ringAll',
      'sdpType',
      'sdp',
      'candidate',
      'sdpMid',
      'sdpMLineIndex',
      'reason',
    ];
    final values = <Object?>[
      null,
      true,
      false,
      0,
      -1,
      7,
      1.5,
      -0.0,
      1e308,
      9223372036854775807,
      '',
      ' ',
      'x',
      '0',
      '-1',
      'NaN',
      'true',
      <Object?>[],
      <Object?>[1],
      <Object?>['x'],
      <Object?>[<Object?>[]],
      <String, Object?>{},
      <String, Object?>{'a': 1},
      <String, Object?>{'callId': c1},
      'x' * 100000,
    ];
    final base = {
      'type': 'ICE',
      'callId': c1,
      'peerUserId': 5,
      'peerDisplayName': 'ayse',
      'ringAll': false,
      'sdpType': 'offer',
      'sdp': 'v=0',
      'candidate': 'candidate:1',
      'sdpMid': '0',
      'sdpMLineIndex': 0,
      'reason': 'x',
    };

    for (final field in fields) {
      test(field, () {
        for (final value in values) {
          final body = jsonEncode({...base, field: value});
          CallSignal? s;
          expect(
            () => s = CallSignal.parse(body),
            returnsNormally,
            reason: '$field=${body.length > 200 ? '(big)' : value}',
          );
          if (s != null) expectSane(s!, reason: '$field=$value');
          // the same without the other fields (only the odd one)
          final alone = jsonEncode({'type': 'HANGUP', field: value});
          expect(() => CallSignal.parse(alone), returnsNormally);
        }
      });
    }

    test('type and callId of the wrong type reject the whole frame', () {
      for (final value in values.where((v) => v is! String)) {
        expect(parseMap({...base, 'type': value}), isNull, reason: 'type=$value');
        if (value != null) expect(parseMap({...base, 'callId': value}), isNull, reason: 'callId=$value');
      }
    });

    test('a list or object where a scalar is expected never yields a value', () {
      for (final wrong in <Object?>[
        <Object?>['x'],
        <Object?>[1],
        <String, Object?>{'a': 'x'},
      ]) {
        final s = parseMap({
          ...base,
          'type': 'SDP',
          'sdp': wrong,
          'sdpType': wrong,
          'candidate': wrong,
          'sdpMid': wrong,
          'sdpMLineIndex': wrong,
          'peerUserId': wrong,
          'peerDisplayName': wrong,
          'reason': wrong,
          'ringAll': wrong,
        })!;
        expect(
          (s.sdp, s.sdpType, s.candidate, s.sdpMid, s.sdpMLineIndex, s.peerUserId, s.reason),
          (null, null, null, null, null, null, null),
        );
        expect(s.peerName, '');
        expect(s.ringAll, isFalse);
      }
    });
  });

  group('CallSignal.parse: call id', () {
    test('only a UUID is a call id (it is spliced into /app/rtc/{id}/… destinations)', () {
      final bad = <String>[
        '',
        ' ',
        c1.toUpperCase().replaceAll('A', 'G'),
        '$c1\n',
        '\n$c1',
        '$c1\r\n',
        ' $c1',
        '$c1 ',
        '$c1\u0000',
        '\u0000$c1',
        '{$c1}',
        'urn:uuid:$c1',
        c1.replaceAll('-', ''),
        '${c1}0',
        c1.substring(1),
        c1.replaceFirst('a', 'ａ'), // fullwidth look-alike
        c1.replaceFirst('a', '١'), // arabic-indic digit
        '$c1/answer',
        '../$c1',
        '$c1/../x',
        '$c1?x=1',
        '$c1#x',
        '$c1%2F',
        '*',
        '+',
        '.',
        '..',
        'null',
        '0',
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'a' * 100000,
      ];
      for (final id in bad) {
        expect(
          parseMap({'type': 'INCOMING_CALL', 'callId': id}),
          isNull,
          reason: 'callId=${id.length > 80 ? '(big)' : id.codeUnits}',
        );
      }
      for (final id in [c1, c1.toUpperCase(), 'AAAAaaaa-AAAA-4aaa-8AAA-aaaaAAAAaaaa']) {
        expect(parseMap({'type': 'INCOMING_CALL', 'callId': id})!.callId, id);
      }
      expect(parseMap({'type': 'RINGING'})!.callId, isNull);
      expect(parseMap({'type': 'RINGING', 'callId': null})!.callId, isNull);
    });
  });

  group('CallSignal.parse: size limits (±1)', () {
    CallSignal sdp(int n) => parseMap({'type': 'SDP', 'callId': c1, 'sdpType': 'offer', 'sdp': 'v' * n})!;
    CallSignal ice(int n) => parseMap({'type': 'ICE', 'callId': c1, 'candidate': 'c' * n})!;

    test('SDP: 64 KB − 1, 64 KB kept; 64 KB + 1 dropped', () {
      expect(sdp(maxSdpLength - 1).sdp, hasLength(maxSdpLength - 1));
      expect(sdp(maxSdpLength).sdp, hasLength(maxSdpLength));
      expect(sdp(maxSdpLength + 1).sdp, isNull);
      expect(sdp(1).sdp, 'v');
      expect(sdp(0).sdp, isNull, reason: 'empty is nothing');
    });

    test('ICE candidate: 2 KB − 1, 2 KB kept; 2 KB + 1 dropped', () {
      expect(ice(maxCandidateLength - 1).candidate, hasLength(maxCandidateLength - 1));
      expect(ice(maxCandidateLength).candidate, hasLength(maxCandidateLength));
      expect(ice(maxCandidateLength + 1).candidate, isNull);
    });

    test('limits count UTF-16 units, not characters (an emoji is 2)', () {
      expect(
        parseMap({'type': 'ICE', 'callId': c1, 'candidate': '😀' * (maxCandidateLength ~/ 2)})!.candidate,
        isNotNull,
      );
      expect(
        parseMap({'type': 'ICE', 'callId': c1, 'candidate': '😀' * (maxCandidateLength ~/ 2 + 1)})!.candidate,
        isNull,
      );
    });

    test('sdpMid ≤ 64, sdpType exactly offer / answer', () {
      expect(parseMap({'type': 'ICE', 'sdpMid': 'm' * 64})!.sdpMid, hasLength(64));
      expect(parseMap({'type': 'ICE', 'sdpMid': 'm' * 65})!.sdpMid, isNull);
      for (final t in ['offer', 'answer']) {
        expect(parseMap({'type': 'SDP', 'sdpType': t})!.sdpType, t);
      }
      for (final t in ['OFFER', 'Offer', ' offer', 'offer ', 'offer\n', 'pranswer', 'rollback', 'answerx', 'offe']) {
        expect(parseMap({'type': 'SDP', 'sdpType': t})!.sdpType, isNull, reason: t);
      }
    });

    test('sdpMLineIndex: 0 and 63 kept; −1, 64, 2^63−1 dropped', () {
      for (final i in [0, 1, 62, 63]) {
        expect(parseMap({'type': 'ICE', 'sdpMLineIndex': i})!.sdpMLineIndex, i);
      }
      for (final i in [-1, 64, 65, 1000000, 9223372036854775807, -9223372036854775808]) {
        expect(parseMap({'type': 'ICE', 'sdpMLineIndex': i})!.sdpMLineIndex, isNull, reason: '$i');
      }
    });

    test('reason ≤ 500 in, then shown ≤ 200 chars / 3 lines; display name ≤ 500 in, shown ≤ 80 on one line', () {
      expect(parseMap({'type': 'ERROR', 'reason': 'r' * 500})!.reason, isNotNull);
      expect(parseMap({'type': 'ERROR', 'reason': 'r' * 501})!.reason, isNull);
      expect(parseMap({'type': 'ERROR', 'reason': 'r' * 500})!.reason!.length, lessThanOrEqualTo(201));
      expect(parseMap({'type': 'ERROR', 'reason': 'a\nb\nc\nd\ne'})!.reason!.split('\n').length, lessThanOrEqualTo(3));
      expect(parseMap({'type': 'INCOMING_CALL', 'peerDisplayName': 'n' * 500})!.peerName.length, lessThanOrEqualTo(81));
      expect(parseMap({'type': 'INCOMING_CALL', 'peerDisplayName': 'n' * 501})!.peerName, '');
      expect(parseMap({'type': 'INCOMING_CALL', 'peerDisplayName': 'n' * 80})!.peerName, 'n' * 80);
      expect(parseMap({'type': 'INCOMING_CALL', 'peerDisplayName': 'n' * 81})!.peerName, '${'n' * 80}…');
    });

    test('cutting a display name never splits an emoji', () {
      for (final pad in [78, 79, 80]) {
        final s = parseMap({'type': 'INCOMING_CALL', 'peerDisplayName': '${'x' * pad}😀😀😀'})!;
        expect(_wellFormed(s.peerName), isTrue, reason: 'pad=$pad');
      }
    });
  });

  group('CallSignal.parse: numbers', () {
    test('peerUserId: only a positive integer', () {
      expect(parseMap({'type': 'RINGING', 'peerUserId': 5})!.peerUserId, 5);
      for (final raw in ['"5"', '5.5', '5.0', '1e2', '1e999', 'true', 'null', '[5]', '{"id":5}']) {
        expect(CallSignal.parse('{"type":"RINGING","peerUserId":$raw}')!.peerUserId, isNull, reason: raw);
      }
    });

    test('peerUserId: negative / zero ids are rejected', () {
      for (final v in [-1, 0, -9223372036854775808]) {
        expect(parseMap({'type': 'RINGING', 'peerUserId': v})!.peerUserId, isNull, reason: '$v');
      }
    });

    test('numbers outside the JSON int range or in exponent form are not integers', () {
      for (final raw in ['99999999999999999999', '1e2', '1E2', '5.0', '0.5', '-0.0', '1e-5']) {
        final s = CallSignal.parse('{"type":"ICE","sdpMLineIndex":$raw,"peerUserId":$raw}');
        expect(s, isNotNull, reason: raw);
        expect(s!.sdpMLineIndex, isNull, reason: raw);
        expect(s.peerUserId, isNull, reason: raw);
      }
    });

    test('ringAll is true only for the JSON literal true', () {
      expect(parseMap({'type': 'INCOMING_CALL', 'ringAll': true})!.ringAll, isTrue);
      for (final v in <Object?>[
        'true',
        'TRUE',
        1,
        'yes',
        <Object?>[true],
        <String, Object?>{'a': true},
        null,
        0,
        false,
      ]) {
        expect(parseMap({'type': 'INCOMING_CALL', 'ringAll': v})!.ringAll, isFalse, reason: '$v');
      }
    });
  });

  group('CallSignal.parse: display texts of the peer (bidi / control characters)', () {
    String name(String raw) => parseMap({'type': 'INCOMING_CALL', 'callId': c1, 'peerDisplayName': raw})!.peerName;
    String reasonOf(String raw) => parseMap({'type': 'ERROR', 'reason': raw})!.reason!;

    test('every bidi embedding / override / isolate is shown as a visible marker, never raw', () {
      for (final unit in [...List.generate(5, (i) => 0x202A + i), ...List.generate(4, (i) => 0x2066 + i)]) {
        final c = String.fromCharCode(unit);
        final hex = unit.toRadixString(16).toUpperCase();
        for (final out in [name('evil${c}gpj.exe'), reasonOf('evil${c}gpj.exe')]) {
          expect(out, isNot(contains(c)), reason: 'U+$hex raw');
          expect(out, contains('⟨U+$hex⟩'));
        }
      }
    });

    test('C0 / C1 controls, NUL, DEL, CR, LF, TAB, line separators leave no raw control character', () {
      for (var u = 0; u < 0x20; u++) {
        final c = String.fromCharCode(u);
        expect(name('a${c}b'), isNot(contains(_forbiddenInName)), reason: 'U+${u.toRadixString(16)}');
      }
      for (var u = 0x7F; u <= 0x9F; u++) {
        expect(
          name('a${String.fromCharCode(u)}b'),
          isNot(contains(_forbiddenInName)),
          reason: 'U+${u.toRadixString(16)}',
        );
      }
      expect(name('a\u2028b\u2029c'), isNot(contains(RegExp('[\u2028\u2029\n]'))), reason: 'one line');
      expect(name('line1\nline2\r\nline3'), isNot(contains('\n')));
      expect(name('\u0000\u0001\u0002'), '');
    });

    test('entities that decode to a bidi override are still defused (decoded before the marker pass)', () {
      expect(name('x&#x202E;y'), isNot(contains('\u202E')));
      expect(name('x&#8238;y'), contains('⟨U+202E⟩'));
      expect(name('x&amp;#x202E;y'), 'x&#x202E;y', reason: 'only one decoding round');
    });

    test('lone surrogates become U+FFFD (they would throw inside Text)', () {
      for (final raw in ['a\uD800b', 'a\uDC00b', 'a\uD800', '\uDFFF', 'a\uD83Db\uDE00']) {
        expect(_wellFormed(name(raw)), isTrue, reason: raw.codeUnits.toString());
        expect(_wellFormed(reasonOf(raw)), isTrue);
      }
    });

    test('a long RTL/LTR mixture with all the controls at once', () {
      final nasty = '\u202E${'abc' * 20}\u202D\u2066\u2067\u2068\u2069\u202C\u0000\n\r\u0085\u2028\uD800' * 5;
      final s = parseMap({'type': 'INCOMING_CALL', 'callId': c1, 'peerDisplayName': nasty, 'reason': nasty})!;
      expectSane(s);
      expect(s.peerName.length, lessThanOrEqualTo(81));
    });

    test('implicit directional marks (LRM / RLM / ALM)', () {
      for (final u in [0x200E, 0x200F, 0x061C]) {
        final c = String.fromCharCode(u);
        final hex = u.toRadixString(16).toUpperCase().padLeft(4, '0');
        expect(name('a${c}b'), isNot(contains(c)), reason: 'U+$hex stays raw');
        expect(name('a${c}b'), 'a⟨U+$hex⟩b');
      }
    });
  });

  group('random fuzz (seeded)', () {
    const keys = [
      'type',
      'callId',
      'peerUserId',
      'peerDisplayName',
      'ringAll',
      'sdpType',
      'sdp',
      'candidate',
      'sdpMid',
      'sdpMLineIndex',
      'reason',
      'x',
      '',
      'TYPE',
    ];
    const types = [...callSignalTypes, 'RING', '', 'incoming_call'];

    Object? value(Random rnd, int depth) {
      switch (rnd.nextInt(depth > 2 ? 9 : 12)) {
        case 0:
          return null;
        case 1:
          return rnd.nextBool();
        case 2:
          return rnd.nextInt(200) - 100;
        case 3:
          return (rnd.nextDouble() - 0.5) * pow(10, rnd.nextInt(400) - 100);
        case 4:
          return rnd.nextBool() ? c1 : c2;
        case 5:
          return types[rnd.nextInt(types.length)];
        case 6:
          return String.fromCharCodes(
            List.generate(rnd.nextInt(90), (_) => rnd.nextInt(rnd.nextBool() ? 0x80 : 0xFFFF)),
          );
        case 7:
          return 'x' * rnd.nextInt(rnd.nextBool() ? 70000 : 600);
        case 8:
          return ['offer', 'answer', 'candidate:1 1 udp 1 1.2.3.4 5 typ host', '0', '\u202E', '&#x202E;'][rnd.nextInt(
            6,
          )];
        case 9:
          return [for (var i = rnd.nextInt(4); i > 0; i--) value(rnd, depth + 1)];
        default:
          return {for (var i = rnd.nextInt(4); i > 0; i--) keys[rnd.nextInt(keys.length)]: value(rnd, depth + 1)};
      }
    }

    test('5000 random frames: never throws, results are sane', () {
      final rnd = Random(20260714);
      var parsed = 0;
      for (var i = 0; i < 5000; i++) {
        final obj = <String, Object?>{
          for (final k in keys.take(11))
            if (rnd.nextInt(4) != 0) k: rnd.nextInt(5) == 0 ? value(rnd, 0) : _plausible(rnd, k),
        };
        final body = jsonEncode(rnd.nextInt(10) == 0 ? value(rnd, 0) : obj);
        CallSignal? s;
        expect(() => s = CallSignal.parse(body), returnsNormally, reason: 'seed 20260714 #$i');
        if (s != null) {
          parsed++;
          expectSane(s!, reason: '#$i');
        }
      }
      expect(parsed, greaterThan(500), reason: 'the generator produces real signals too (guards a vacuous test)');
    });

    test('mutated valid frames (byte flips, truncation): never throws', () {
      final rnd = Random(7);
      final valid = jsonEncode({
        'type': 'SDP',
        'callId': c1,
        'peerUserId': 5,
        'peerDisplayName': 'ayse',
        'sdpType': 'offer',
        'sdp': 'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n',
        'sdpMLineIndex': 0,
      });
      for (var i = 0; i < 3000; i++) {
        final units = valid.codeUnits.toList();
        for (var k = rnd.nextInt(4); k >= 0; k--) {
          final at = rnd.nextInt(units.length);
          units[at] = rnd.nextInt(3) == 0 ? rnd.nextInt(0xFFFF) : rnd.nextInt(128);
        }
        final body = String.fromCharCodes(units.take(rnd.nextInt(units.length) + 1));
        CallSignal? s;
        expect(() => s = CallSignal.parse(body), returnsNormally, reason: body);
        if (s != null) expectSane(s!, reason: body);
      }
    });
  });

  group('the machine and the provider under hostile input', () {
    test('random signal + action sequences keep the machine consistent (3000 sequences)', () {
      final rnd = Random(99);
      final ids = [c1, c2, c3, null];
      for (var seq = 0; seq < 3000; seq++) {
        final m = CallMachine();
        var generation = m.generation;
        for (var step = 0; step < 30; step++) {
          List<CallEffect> effects = const [];
          switch (rnd.nextInt(8)) {
            case 0:
              m.begin(9, 'x', groupId: rnd.nextBool() ? g1 : 'not-a-uuid');
            case 1:
              effects = m.dial(rnd.nextBool() ? m.generation : m.generation - 1);
            case 2:
              m.beginAnswer();
            case 3:
              effects = m.confirmAnswer(m.generation);
            case 4:
              effects = m.end();
            case 5:
              m.markConnected(m.generation);
            case 6:
              m.connectionReset();
            default:
              final type = callSignalTypes.elementAt(rnd.nextInt(callSignalTypes.length));
              final s = parseMap({
                'type': type,
                'callId': ids[rnd.nextInt(ids.length)],
                'peerUserId': rnd.nextInt(10),
                'sdpType': rnd.nextBool() ? 'offer' : 'answer',
                'sdp': rnd.nextBool() ? 'v=0' : null,
                'candidate': rnd.nextBool() ? 'candidate:1' : null,
                'peerDisplayName': 'n${rnd.nextInt(3)}',
                'ringAll': rnd.nextBool(),
              })!;
              effects = m.handle(s);
          }
          final why = 'seq $seq step $step';
          expect(m.generation, greaterThanOrEqualTo(generation), reason: '$why: generation never goes back');
          generation = m.generation;
          if (m.phase == CallPhase.idle) {
            expect(
              (m.callId, m.dialed, m.answering, m.isCaller, m.ringAll, m.peerName),
              (null, false, false, false, false, ''),
              reason: why,
            );
          }
          if (m.callId != null) expect(_uuidRe.hasMatch(m.callId!), isTrue, reason: why);
          for (final e in effects) {
            if (e is CallRemoteSdp || e is CallRemoteIce) {
              expect(m.phase, anyOf(CallPhase.connecting, CallPhase.active), reason: '$why: SDP/ICE only in a call');
            }
            if (e is CallSend) {
              expect(e.destination, startsWith('/app/rtc'), reason: why);
              expect(
                e.destination,
                matches(RegExp(r'^/app/rtc(/call|/[0-9a-fA-F-]{36}/(answer|reject|cancel|hangup|sdp|ice))$')),
                reason: why,
              );
            }
          }
        }
        final after = m.reset();
        expect(m.phase, CallPhase.idle);
        expect(after.every((e) => e is CallSend), isTrue, reason: 'sign-out sends frames only, no notice');
      }
    });

    test('random hostile traffic through the provider: after sign-out nothing is held (60 sequences)', () async {
      final rnd = Random(1234);
      for (var seq = 0; seq < 60; seq++) {
        final rig = CallRig(ringGuard: const Duration(minutes: 5), connectGuard: const Duration(minutes: 5));
        final gates = <Completer<void>>[];
        rig.calls.setup = (m) {
          if (rnd.nextInt(3) == 0) {
            final g = Completer<void>();
            gates.add(g);
            m.openGate = g;
          } else if (rnd.nextInt(6) == 0) {
            m.openError = (_) => const CallMediaException(CallMediaError.denied);
          }
        };
        try {
          await rig.start();
          final ids = [c1, c2, c3];
          for (var step = 0; step < 25; step++) {
            final id = ids[rnd.nextInt(ids.length)];
            switch (rnd.nextInt(12)) {
              case 0:
                unawaited(rig.provider.call(9 + rnd.nextInt(3), 'x', video: rnd.nextBool()));
              case 1:
                unawaited(rig.provider.answer(video: rnd.nextBool()));
              case 2:
                rig.provider.end();
              case 3:
                rig.provider.endForBackground();
              case 4:
                if (gates.isNotEmpty) gates.removeAt(rnd.nextInt(gates.length)).complete();
              case 5:
                if (rig.calls.medias.isNotEmpty) {
                  final onState = rig.calls.media.onState;
                  onState?.call(PeerState.values[rnd.nextInt(PeerState.values.length)]);
                }
              case 6:
                rig.incoming(id: id, ringAll: rnd.nextBool());
              case 7:
                if (rnd.nextInt(4) == 0) await rig.dropAndReconnect();
              default:
                final type = callSignalTypes.elementAt(rnd.nextInt(callSignalTypes.length));
                rig.signal({
                  'type': type,
                  if (rnd.nextInt(5) != 0) 'callId': id,
                  'peerUserId': 9,
                  'sdpType': rnd.nextBool() ? 'offer' : 'answer',
                  'sdp': 'v=0',
                  'candidate': 'candidate:${rnd.nextInt(5)}',
                  'sdpMid': '0',
                  'sdpMLineIndex': 0,
                });
            }
            await Future<void>.delayed(Duration.zero);
          }
          rig.provider.reset(); // sign-out
          for (final g in gates) {
            g.complete();
          }
          await flush();
          expect(
            rig.leaks,
            isEmpty,
            reason: 'sequence $seq (seed 1234): a media kept the microphone/camera/connection',
          );
          expect(rig.provider.phase, CallPhase.idle, reason: 'sequence $seq');
        } finally {
          await rig.dispose();
        }
      }
    });
  });
}

/// A value of the right shape for [key] (so that many random frames get through to the interesting code).
Object? _plausible(Random rnd, String key) => switch (key) {
  'type' => callSignalTypes.elementAt(rnd.nextInt(callSignalTypes.length)),
  'callId' => rnd.nextBool() ? c1 : null,
  'peerUserId' => rnd.nextInt(20) - 3,
  'peerDisplayName' => String.fromCharCodes(
    List.generate(rnd.nextInt(30), (_) => [0x41, 0x202E, 0x0, 0x2066, 0xD800, 0x10, 0x65E5][rnd.nextInt(7)]),
  ),
  'ringAll' => rnd.nextBool(),
  'sdpType' => ['offer', 'answer', 'x'][rnd.nextInt(3)],
  'sdp' => 'v' * [0, 1, maxSdpLength, maxSdpLength + 1][rnd.nextInt(4)],
  'candidate' => 'c' * [0, 1, maxCandidateLength, maxCandidateLength + 1][rnd.nextInt(4)],
  'sdpMid' => 'm' * [0, 1, 64, 65][rnd.nextInt(4)],
  'sdpMLineIndex' => [-1, 0, 1, 63, 64][rnd.nextInt(5)],
  _ => 'r' * [0, 1, 500, 501][rnd.nextInt(4)],
};
