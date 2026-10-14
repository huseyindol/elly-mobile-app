import 'package:elly_mobile_app/models/chat_models.dart';
import 'package:elly_mobile_app/services/api_service.dart';
import 'package:elly_mobile_app/services/chat_format.dart';
import 'package:elly_mobile_app/services/stomp_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

const gid = '3f2b8c1e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';

void main() {
  group('untrusted message text', () {
    test('Jsoup entities are decoded for display (never rendered as HTML)', () {
      expect(decodeHtmlEntities('a &lt;b&gt;x&lt;/b&gt; &amp; &quot;q&quot; &apos;s&apos;'), 'a <b>x</b> & "q" \'s\'');
      expect(decodeHtmlEntities('&#39;&#x41;&#65;&nbsp;'), "'AA ");
      expect(decodeHtmlEntities('&amp;lt;'), '&lt;', reason: 'single pass: no double decoding');
      expect(decodeHtmlEntities('&#0; &#xD800; &#x110000;'), '� � �', reason: 'invalid code points');
      expect(decodeHtmlEntities('&unknown; & plain'), '&unknown; & plain');
    });

    test('safeChatText: bidi controls visible, control characters dropped, newlines kept', () {
      expect(safeChatText('abc\u202Edef'), 'abc⟨U+202E⟩def');
      expect(safeChatText('x\u2066y\u2069'), 'x⟨U+2066⟩y⟨U+2069⟩');
      expect(safeChatText('&#x202E;evil'), '⟨U+202E⟩evil', reason: 'an encoded bidi control is revealed too');
      expect(safeChatText('a\u0000b\u0007c\u001Bd\u007Fe\u0085f'), 'abcdef');
      expect(safeChatText('line1\r\nline2\rline3\tend'), 'line1\nline2\nline3\tend');
      expect(safeChatText('<script>alert(1)</script>'), '<script>alert(1)</script>', reason: 'plain text');
    });

    test('clipChatText: short text untouched; long text cut by chars or lines', () {
      expect(clipChatText('kısa'), ('kısa', false));
      final (byChars, cut1) = clipChatText('a' * 1500);
      expect(cut1, isTrue);
      expect(byChars, '${'a' * 1000}…');
      final (byLines, cut2) = clipChatText(List.generate(30, (i) => 'satır $i').join('\n'));
      expect(cut2, isTrue);
      expect('\n'.allMatches(byLines).length, 19);
    });

    test('clipChatText never splits a surrogate pair', () {
      final text = '${'a' * 999}😀rest';
      final (clipped, cut) = clipChatText(text);
      expect(cut, isTrue);
      expect(clipped, '${'a' * 999}…');
      expect(clipped.codeUnits.any((u) => u >= 0xD800 && u <= 0xDBFF), isFalse);
    });

    test('linkSegments: only http(s) URLs are links; trailing punctuation stays text', () {
      expect(linkSegments('bak https://elly.dev/a?b=1, sonra'), [
        ('bak ', null),
        ('https://elly.dev/a?b=1', Uri.parse('https://elly.dev/a?b=1')),
        (', sonra', null),
      ]);
      expect(linkSegments('(http://x.com/y).'), [
        ('(', null),
        ('http://x.com/y', Uri.parse('http://x.com/y')),
        (').', null),
      ]);
      for (final unsafe in ['javascript:alert(1)', 'data:text/html,<b>', 'file:///etc/passwd', 'ftp://x.com']) {
        expect(linkSegments('x $unsafe y').every((s) => s.$2 == null), isTrue, reason: unsafe);
      }
    });

    test('linkSegments: non-ASCII hosts are not linked (look-alike domains); no host → no link', () {
      expect(linkSegments('https://аpple.com').every((s) => s.$2 == null), isTrue);
      expect(linkSegments('https:// boş').every((s) => s.$2 == null), isTrue);
      expect(linkSegments('HTTPS://ELLY.DEV').single.$2, isNotNull);
    });
  });

  group('files', () {
    test('only our own upload paths are files; anything else stays text', () {
      expect(chatFilePath(contentType: 'FILE', content: 'assets/chat/a b.png'), isNull);
      expect(chatFilePath(contentType: 'FILE', content: 'assets/chat/rapor-1.pdf'), 'assets/chat/rapor-1.pdf');
      expect(chatFilePath(contentType: 'IMAGE', fileUrl: 'assets/chat/x.png', content: 'ignored'), 'assets/chat/x.png');
      expect(chatFilePath(contentType: 'FILE', content: 'assets/../secret'), isNull);
      expect(chatFilePath(contentType: 'FILE', content: 'https://evil.com/x.png'), isNull);
      expect(chatFilePath(contentType: 'FILE', content: 'javascript:alert(1)'), isNull);
      expect(chatFilePath(contentType: 'TEXT', content: 'assets/chat/x.png'), isNull);
    });

    test('file URL is on the API origin; image detection by extension', () {
      expect(chatFileUrl('assets/chat/x.png'), '${Uri.parse(ApiService.baseUrl).origin}/assets/chat/x.png');
      expect(isImagePath('assets/chat/x.JPEG'), isTrue);
      expect(isImagePath('assets/chat/x.svg'), isFalse, reason: 'SVG is not rendered');
      expect(fileNameOf('assets/chat/2026/rapor.pdf'), 'rapor.pdf');
    });
  });

  group('labels and rules', () {
    test('visibility labels (admin visibilityLabel)', () {
      expect(
        [for (var i = 0; i <= 5; i++) chatVisibilityLabel(i)],
        ['Bilinmiyor', 'Herkese açık', 'Editör+', 'Admin+', 'Gizli', 'Bilinmiyor'],
      );
    });

    test('invite hierarchy: own level and below; SUPER_ADMIN anyone (backend addMemberInTenant)', () {
      for (var me = 1; me <= 4; me++) {
        for (var target = 1; target <= 4; target++) {
          expect(canInviteLevel(me, target), me == 4 || target <= me, reason: '$me → $target');
        }
      }
      expect(inviteHint(4), contains('herkesi'));
      expect(inviteHint(3), contains('altındaki'));
    });

    test('invite input: e-mail or positive id', () {
      expect(inviteInputError(''), isNotNull);
      expect(inviteInputError('12'), isNull);
      expect(inviteInputError(' a@b.co '), isNull);
      expect(inviteInputError('0'), isNotNull);
      expect(inviteInputError('-3'), isNotNull);
      expect(inviteInputError('abc'), isNotNull);
      expect(inviteInputError('a@b'), isNotNull);
    });

    test('backend errors in Turkish', () {
      expect(
        chatErrorText(ApiException('You can only invite users with your role level or lower', statusCode: 403)),
        contains('kendi rol seviyenizdeki'),
      );
      expect(chatErrorText(ApiException('User is already a member of this group', statusCode: 409)), contains('zaten'));
      expect(chatErrorText(ApiException('User not found with email : x@y.z', statusCode: 404)), contains('e-postayla'));
      expect(
        chatErrorText(ApiException('Rate limit exceeded: max 5 messages/second', statusCode: 429)),
        contains('hızlı'),
      );
      expect(chatErrorText(ApiException('Başka bir hata', statusCode: 500)), 'Başka bir hata');
    });

    test('typing label and relative times', () {
      expect(typingLabel([]), isNull);
      expect(typingLabel(['Ayşe']), 'Ayşe yazıyor…');
      expect(typingLabel(['A', 'B', 'C']), '3 kişi yazıyor…');
      final now = DateTime(2026, 10, 14, 12);
      expect(formatRelativeTr(now.subtract(const Duration(seconds: 10)), now), 'az önce');
      expect(formatRelativeTr(now.subtract(const Duration(minutes: 5)), now), '5 dk önce');
      expect(formatRelativeTr(now.subtract(const Duration(hours: 3)), now), '3 sa önce');
      expect(formatRelativeTr(now.subtract(const Duration(days: 2)), now), '2 gün önce');
      expect(formatRelativeTr(DateTime(2026, 9, 1, 8), now), '01.09');
      expect(formatMessageTime(DateTime(2026, 10, 14, 9, 5), now), '09:05');
      expect(formatMessageTime(DateTime(2026, 10, 13, 9, 5), now), '13.10 09:05');
    });

    test('server dates: ISO string or epoch millis', () {
      expect(parseServerDate('2026-10-14T09:00:00.000+00:00'), DateTime.utc(2026, 10, 14, 9));
      expect(parseServerDate(0), DateTime.fromMillisecondsSinceEpoch(0));
      expect(parseServerDate('bozuk'), isNull);
      expect(parseServerDate(null), isNull);
    });
  });

  group('notification targets: only known admin paths, never a URL', () {
    test('mapping', () {
      expect(notificationTarget('/chat', {'groupId': gid}), const NotificationTarget('chat', gid));
      expect(notificationTarget('/chat', const {}), const NotificationTarget('chat'));
      expect(notificationTarget('/forms/12/submissions', const {}), const NotificationTarget('formSubmissions', '12'));
      expect(notificationTarget('/email-logs', const {}), const NotificationTarget('nav', 'email-logs'));
      expect(notificationTarget('/users?x=1', const {}), const NotificationTarget('nav', 'users'));
    });

    test('anything else opens nothing', () {
      for (final link in [
        null,
        '',
        'https://evil.com',
        '//evil.com',
        'javascript:alert(1)',
        '/forms/abc/submissions',
        '/forms/1/submissions/../../x',
        '/a/b',
        '/USERS',
      ]) {
        expect(notificationTarget(link, const {}), isNull, reason: '$link');
      }
    });
  });

  group('STOMP destinations', () {
    test('same shapes as the admin / backend ChatTopics', () {
      expect(StompDest.group('t1', gid), '/topic/tenant/t1/group/$gid');
      expect(StompDest.typing('t1', gid), '/topic/tenant/t1/group/$gid/typing');
      expect(StompDest.read('t1', gid), '/topic/tenant/t1/group/$gid/read');
      expect(StompDest.bans('t1', gid), '/topic/tenant/t1/group/$gid/bans');
      expect(StompDest.sendTyping('t1', gid), '/app/tenant-chat/t1/$gid/typing');
      expect(StompDest.sendRead('t1', gid), '/app/tenant-chat/t1/$gid/read');
      expect(StompDest.membership(7), '/topic/user/7/membership');
    });

    test('id guards', () {
      expect(isUuid(gid), isTrue);
      for (final bad in [null, '', 'x', '$gid/typing', '../$gid', '${gid}0']) {
        expect(isUuid(bad), isFalse, reason: '$bad');
      }
      expect(isSafeTenantId('tenant_1-a'), isTrue);
      for (final bad in [null, '', 't/1', 't 1', '*', 'a' * 65]) {
        expect(isSafeTenantId(bad), isFalse, reason: '$bad');
      }
    });
  });

  group('DTO parsing is defensive', () {
    test('records without an id are rejected; wrong types fall back', () {
      expect(ChatGroup.fromJson({'name': 'x'}), isNull);
      expect(ChatGroup.fromJson('nope'), isNull);
      final g = ChatGroup.fromJson({'id': gid, 'name': 7, 'visibilityLevel': 'x', 'visitorAccess': 'true'})!;
      expect(g.name, '7');
      expect(g.visibilityLevel, 1);
      expect(g.visitorAccess, isFalse);
      expect(ChatMessage.fromJson({'id': 'm'}), isNull, reason: 'no groupId');
      expect(AppNotification.fromJson({'id': 'x'}), isNull);
      expect(ChatMember.fromJson({'userId': '5', 'role': 'OWNER'})!.isOwner, isTrue);
    });

    test('message: sender name falls back to senderDisplayName; ban key by sender type', () {
      final guest = ChatMessage.fromJson({
        'id': 'm1',
        'groupId': gid,
        'senderType': 'GUEST',
        'sessionId': 's-1',
        'senderDisplayName': 'Ziyaretçi 1',
        'editedAt': '2026-10-14T09:00:00Z',
      })!;
      expect(guest.senderName, 'Ziyaretçi 1');
      expect(guest.banKey, 's:s-1');
      expect(guest.edited, isTrue);
      expect(ChatMessage.fromJson({'id': 'm', 'groupId': gid, 'senderType': 'VISITOR', 'visitorId': 9})!.banKey, 'v:9');
      expect(ChatMessage.fromJson({'id': 'm', 'groupId': gid, 'senderType': 'ADMIN', 'senderId': 1})!.banKey, isNull);
    });
  });
}
