import 'dart:io';

import 'package:elly_mobile_app/services/stomp_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

const gid = '3f2b8c1e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';

/// Characters that could widen / redirect a destination or confuse a viewer: path, wildcards (STOMP / AMQP topic
/// style), whitespace, control, bidi, zero width, look-alike and full-width characters, URL escapes.
const _hostile = [
  '/',
  '\\',
  '*',
  '>',
  '#',
  '+',
  '.',
  ':',
  '?',
  '%',
  ' ',
  '\t',
  '\n',
  '\r',
  '\u0000',
  '\u202E',
  '\u2066',
  '\u200B',
  '\uFEFF',
  'а', // Cyrillic а (looks like Latin a)
  'ａ', // full-width a
  '١', // Arabic-indic digit 1
  'é',
];

/// Destination ids are validated before they are put into `/topic/tenant/{tid}/group/{gid}/…` — the validators are
/// the only barrier (the builders concatenate), so they must be strict.
void main() {
  group('isUuid', () {
    test('accepts canonical UUIDs (any case), nothing else', () {
      expect(isUuid(gid), isTrue);
      expect(isUuid(gid.toUpperCase()), isTrue);
      expect(isUuid('00000000-0000-0000-0000-000000000000'), isTrue);
    });

    test('rejects null / empty / structural variants', () {
      final bad = <String?>[
        null,
        '',
        ' ',
        gid.replaceAll('-', ''),
        gid.substring(1),
        '${gid}0',
        '$gid ',
        ' $gid',
        '$gid\n',
        '\n$gid',
        '$gid\r\n',
        '$gid\u0000',
        '{$gid}',
        'urn:uuid:$gid',
        '$gid/typing',
        '$gid/../x',
        '../$gid',
        '$gid%2F..',
        '$gid..',
        '${gid.substring(0, 35)}g',
        '${gid.substring(0, 35)}*',
        '*',
        '#',
        '>',
        '+',
        '.',
        '..',
        '*' * 36,
        '${gid.substring(0, 8)}--${gid.substring(9)}',
        gid + gid,
      ];
      for (final v in bad) {
        expect(isUuid(v), isFalse, reason: '"$v"');
      }
    });

    test('inserting or substituting ANY hostile character at ANY position is rejected', () {
      for (var i = 0; i <= gid.length; i++) {
        for (final c in _hostile) {
          expect(isUuid(gid.substring(0, i) + c + gid.substring(i)), isFalse, reason: 'insert ${c.codeUnits} at $i');
          if (i < gid.length) {
            expect(
              isUuid(gid.substring(0, i) + c + gid.substring(i + 1)),
              isFalse,
              reason: 'replace ${c.codeUnits} at $i',
            );
          }
        }
      }
    });
  });

  group('isSafeTenantId', () {
    test('accepts one path segment of [A-Za-z0-9_-], 1..64', () {
      for (final ok in ['t1', 'tenant_1-a', 'A', '-', '_', '0', 'Tenant1', 'a' * 64]) {
        expect(isSafeTenantId(ok), isTrue, reason: ok);
      }
    });

    test('rejects traversal, wildcards, whitespace, escapes, unicode, length', () {
      final bad = <String?>[
        null,
        '',
        ' ',
        '.',
        '..',
        '../t2',
        't1/../t2',
        't1/',
        '/t1',
        't/1',
        't\\1',
        't1/group/x',
        't1/group/$gid',
        't 1',
        ' t1',
        't1 ',
        't1\n',
        't1\r\n',
        '\nt1',
        '*',
        't*',
        '>',
        '#',
        '+',
        't1.',
        't1:',
        't1?x=1',
        '%2e%2e',
        'a%2Fb',
        'ｔ1',
        'tenant１',
        'ténant',
        't\u200B1',
        't1\u202E',
        't1\u0000',
        'a' * 65,
        'a' * 4096,
      ];
      for (final v in bad) {
        expect(isSafeTenantId(v), isFalse, reason: '"$v"');
      }
    });

    test('inserting or substituting ANY hostile character at ANY position is rejected', () {
      for (final base in ['t1', 'tenant_1-a']) {
        for (var i = 0; i <= base.length; i++) {
          for (final c in _hostile) {
            expect(
              isSafeTenantId(base.substring(0, i) + c + base.substring(i)),
              isFalse,
              reason: 'insert ${c.codeUnits} at $i of $base',
            );
            if (i < base.length) {
              expect(
                isSafeTenantId(base.substring(0, i) + c + base.substring(i + 1)),
                isFalse,
                reason: 'replace ${c.codeUnits} at $i of $base',
              );
            }
          }
        }
      }
    });
  });

  group('destinations built from validated ids', () {
    test('fixed shape: exactly the expected segments, no wildcard anywhere', () {
      final built = {
        StompDest.group('t1', gid): 5,
        StompDest.typing('t1', gid): 6,
        StompDest.read('t1', gid): 6,
        StompDest.bans('t1', gid): 6,
        StompDest.sendTyping('t1', gid): 5,
        StompDest.sendRead('t1', gid): 5,
        StompDest.membership(7): 4,
        StompDest.presence: 2,
        StompDest.groupsNew: 3,
        StompDest.groupsDeleted: 3,
        StompDest.chatErrors: 3,
        StompDest.notifications: 3,
        StompDest.notificationsUnreadCount: 4,
        StompDest.userRtc(7): 4,
        StompDest.rtcCall: 3,
        StompDest.rtcAnswer(gid): 4,
        StompDest.rtcReject(gid): 4,
        StompDest.rtcCancel(gid): 4,
        StompDest.rtcHangup(gid): 4,
        StompDest.rtcSdp(gid): 4,
        StompDest.rtcIce(gid): 4,
      };
      for (final e in built.entries) {
        expect(e.key.split('/').where((p) => p.isNotEmpty), hasLength(e.value), reason: e.key);
        expect(e.key.split('/').where((p) => p.isEmpty), hasLength(1), reason: 'only the leading slash: ${e.key}');
        expect(e.key, isNot(matches(RegExp(r'[*>#+\s]'))), reason: e.key);
        expect(e.key, isNot(contains('..')), reason: e.key);
        expect(e.key, startsWith('/'));
      }
    });

    test('membership takes an int: nothing but digits (and a sign) can ever be injected', () {
      for (final id in [0, 7, 9223372036854775807, -1]) {
        expect(StompDest.membership(id), matches(RegExp(r'^/topic/user/-?\d+/membership$')));
      }
    });

    test('the group-scoped destinations of two different groups / tenants never collide or nest', () {
      const other = '99999999-9999-4999-8999-999999999999';
      final all = [
        for (final t in ['t1', 't2'])
          for (final g in [gid, other]) ...[
            StompDest.group(t, g),
            StompDest.typing(t, g),
            StompDest.read(t, g),
            StompDest.bans(t, g),
          ],
      ];
      expect(all.toSet(), hasLength(all.length));
    });
  });

  test('WebRTC destinations: backend CallSignalController / CallSessionService shapes', () {
    expect(StompDest.userRtc(7), '/topic/user/7/rtc');
    expect(StompDest.rtcCall, '/app/rtc/call');
    for (final action in ['answer', 'reject', 'cancel', 'hangup', 'sdp', 'ice']) {
      final built = switch (action) {
        'answer' => StompDest.rtcAnswer(gid),
        'reject' => StompDest.rtcReject(gid),
        'cancel' => StompDest.rtcCancel(gid),
        'hangup' => StompDest.rtcHangup(gid),
        'sdp' => StompDest.rtcSdp(gid),
        _ => StompDest.rtcIce(gid),
      };
      expect(built, '/app/rtc/$gid/$action');
    }
  });

  group('source guard: every destination goes through StompDest', () {
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    String code(File f) => f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

    test('no STOMP destination literal outside stomp_destinations.dart (Phase 6 /app/rtc/* must join it)', () {
      final literal = RegExp('''['"]/(topic|app|queue|user/queue)/''');
      for (final f in libFiles.where((f) => !f.path.endsWith('stomp_destinations.dart'))) {
        expect(literal.hasMatch(code(f)), isFalse, reason: '${f.path} builds a destination by hand');
      }
    });

    test('RealtimeService subscribe / send callers pass StompDest values only', () {
      final call = RegExp(r'realtime\.(subscribe|send)\(\s*([^,)]+)');
      var seen = 0;
      for (final f in libFiles.where((f) => !f.path.endsWith('realtime_service.dart'))) {
        for (final m in call.allMatches(code(f))) {
          seen++;
          // CallProvider._send forwards CallSend destinations (checked below) and its own StompDest.rtcSdp/rtcIce.
          if (f.path.endsWith('call_provider.dart') && m[2]!.trim() == 'destination') continue;
          expect(m[2]!.trim(), startsWith('StompDest.'), reason: '${f.path}: ${m[0]}');
        }
      }
      expect(seen, greaterThan(10), reason: 'the scan actually found the call sites');
    });

    test('call signalling destinations (CallSend / _send) are StompDest values only', () {
      final call = RegExp(r'(CallSend|_send)\(\s*([^,)]+)');
      var seen = 0;
      for (final f in libFiles.where((f) => f.path.contains('call_'))) {
        for (final m in call.allMatches(code(f))) {
          // declarations / the pattern match that unpacks a CallSend
          if (const [
            'String destination',
            'this.destination',
            ':final destination',
            r'$destination',
          ].contains(m[2]!.trim())) {
            continue;
          }
          if (f.path.endsWith('call_provider.dart') && m[2]!.trim() == 'destination') continue; // forwards CallSend
          seen++;
          expect(m[2]!.trim(), startsWith('StompDest.'), reason: '${f.path}: ${m[0]}');
        }
      }
      expect(seen, greaterThan(8), reason: 'the scan actually found the call sites');
    });
  });
}
