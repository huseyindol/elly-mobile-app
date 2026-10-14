/// Pure rules of chat and notifications (no Flutter deps, unit-tested): untrusted message text, links, files,
/// dates, labels, the invite hierarchy, error texts and where a notification leads.
library;

import 'api_service.dart';
import 'text_format.dart';

/// REST base of a group's tenant (AC=TC; admin `chatBase`). The backend routes by the JWT tenant, the path tenant is
/// the URL scheme shared with the WebSocket destinations.
String chatBase(String tenantId) => '/chat/tenant/${Uri.encodeComponent(tenantId)}';

/// History page size (admin `getHistoryService` limit).
const chatPageSize = 50;

/// Backend dates arrive as ISO strings or epoch millis.
DateTime? parseServerDate(Object? value) {
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) return DateTime.tryParse(value);
  return null;
}

final _entity = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|amp|lt|gt|quot|apos|nbsp);');

/// The backend stores messages through `Jsoup.clean(…, Safelist.none())`, which HTML-escapes them (`&amp;`, `&lt;`).
/// The app never renders HTML, so the text is decoded back for display (invalid code points → U+FFFD).
String decodeHtmlEntities(String text) => text.replaceAllMapped(_entity, (m) {
  final e = m[1]!;
  switch (e) {
    case 'amp':
      return '&';
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'quot':
      return '"';
    case 'apos':
      return "'";
    case 'nbsp':
      return ' ';
  }
  final hex = e.startsWith('#x') || e.startsWith('#X');
  final code = int.tryParse(e.substring(hex ? 2 : 1), radix: hex ? 16 : 10) ?? 0;
  final valid = code > 0 && code <= 0x10FFFF && (code < 0xD800 || code > 0xDFFF);
  return String.fromCharCode(valid ? code : 0xFFFD);
});

/// Untrusted chat text → plain display text: entities decoded, CR/LF normalized, other C0/C1 control characters
/// dropped, bidi controls shown as visible `⟨U+202E⟩` markers (cannot reorder what the admin reads).
String safeChatText(String text) => revealBidi(
  decodeHtmlEntities(text)
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'), ''),
);

/// Long messages show a preview + "Tümünü göster": at most [maxLines] lines and [maxChars] UTF-16 units, never
/// splitting a surrogate pair. Returns the preview and whether it was cut.
(String, bool) clipChatText(String text, {int maxChars = 1000, int maxLines = 20}) {
  var out = text;
  var cut = false;
  final lines = out.split('\n');
  if (lines.length > maxLines) {
    out = lines.take(maxLines).join('\n');
    cut = true;
  }
  if (out.length > maxChars) {
    var end = maxChars;
    final unit = out.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    out = out.substring(0, end);
    cut = true;
  }
  return (cut ? '${out.trimRight()}…' : out, cut);
}

// ASCII only: a link can't hide a look-alike (IDN) host; the confirm dialog shows the exact URL.
final _url = RegExp(r'https?://[!#-;=?-~]+', caseSensitive: false);
const _trailing = '.,;:!?)]}\'"';

/// Text split into plain parts and http(s) links (anything else stays plain text).
List<(String, Uri?)> linkSegments(String text) {
  final out = <(String, Uri?)>[];
  var last = 0;
  for (final m in _url.allMatches(text)) {
    var raw = m[0]!;
    while (raw.isNotEmpty && _trailing.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty || !(uri.scheme == 'http' || uri.scheme == 'https')) continue;
    if (m.start > last) out.add((text.substring(last, m.start), null));
    out.add((raw, uri));
    last = m.start + raw.length;
  }
  if (last < text.length) out.add((text.substring(last), null));
  return out;
}

final _chatFile = RegExp(r'^assets/[\w\-./]+$');
final _imageExt = RegExp(r'\.(png|jpe?g|gif|webp|avif)$', caseSensitive: false);

/// Stored path of a FILE/IMAGE message (admin: `fileUrl ?? content`); only our own upload paths (backend
/// `DtoChatMessageSend.fileUrl` pattern, no `..`) — anything else is shown as text.
String? chatFilePath({required String contentType, String? fileUrl, required String content}) {
  if (contentType != 'FILE' && contentType != 'IMAGE') return null;
  final path = (fileUrl ?? '').isNotEmpty ? fileUrl! : content.trim();
  return _chatFile.hasMatch(path) && !path.contains('..') ? path : null;
}

/// Absolute URL of a chat upload (`assets/chat/…` on the API origin).
String chatFileUrl(String path) => ApiService.fileUrl(path);

bool isImagePath(String path) => _imageExt.hasMatch(path);

String fileNameOf(String path) => path.split('/').last;

/// Admin `visibilityLabel`.
String chatVisibilityLabel(int level) => switch (level) {
  1 => 'Herkese açık',
  2 => 'Editör+',
  3 => 'Admin+',
  4 => 'Gizli',
  _ => 'Bilinmiyor',
};

/// Backend invite rule: own role level and below; SUPER_ADMIN (4) anyone.
bool canInviteLevel(int myLevel, int targetLevel) => myLevel >= 4 || targetLevel <= myLevel;

/// The invite-hierarchy hint of the members screen (admin `ChatMemberList`).
String inviteHint(int myLevel) => myLevel >= 4
    ? 'Süper Admin olarak herkesi davet edebilirsiniz.'
    : 'Kendi rol seviyenizdeki ve altındaki kullanıcıları davet edebilirsiniz.';

const _errorTexts = {
  'You can only invite users with your role level or lower':
      'Yalnız kendi rol seviyenizdeki ve altındaki kullanıcıları davet edebilirsiniz.',
  'User is already a member of this group': 'Kullanıcı zaten bu grubun üyesi.',
  'Only the group owner or SUPER_ADMIN can delete this group': 'Grubu yalnız sahibi ya da Süper Admin silebilir.',
  'You do not have access to this group': 'Bu gruba erişiminiz yok.',
};

/// Backend error → message for the user (known English backend texts in Turkish).
String chatErrorText(Object error) {
  final message = '$error'.replaceFirst('Exception: ', '');
  if (error is ApiException && error.statusCode == 429) return 'Çok hızlı mesaj gönderiyorsunuz; biraz bekleyin.';
  for (final e in _errorTexts.entries) {
    if (message.contains(e.key)) return e.value;
  }
  if (error is ApiException && error.statusCode == 404 && message.contains('email')) {
    return 'Bu e-postayla kayıtlı kullanıcı bulunamadı.';
  }
  return message;
}

/// Invite input: an e-mail or a positive user id (admin: one field for both). Returns an error text or null.
String? inviteInputError(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'Kullanıcı ID veya e-posta girin';
  if (v.contains('@')) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v) ? null : 'Geçerli bir e-posta girin';
  }
  final id = int.tryParse(v);
  return id != null && id > 0 ? null : 'Geçerli bir kullanıcı ID girin';
}

/// Where a notification leads on mobile. [kind]: `chat` (optional group [id]), `nav` (drawer item [id]),
/// `formSubmissions` (form [id]); null = nothing to open. Only known admin paths are followed — never a URL.
class NotificationTarget {
  final String kind;
  final String? id;
  const NotificationTarget(this.kind, [this.id]);

  @override
  bool operator ==(Object other) => other is NotificationTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'NotificationTarget($kind, $id)';
}

NotificationTarget? notificationTarget(String? link, Map<String, dynamic> metadata) {
  final path = (link ?? '').split(RegExp('[?#]')).first;
  if (path == '/chat') {
    final groupId = '${metadata['groupId'] ?? ''}';
    return NotificationTarget('chat', groupId.isEmpty ? null : groupId);
  }
  final form = RegExp(r'^/forms/(\d{1,18})/submissions$').firstMatch(path);
  if (form != null) return NotificationTarget('formSubmissions', form[1]);
  final nav = RegExp(r'^/([a-z][a-z-]{0,40})$').firstMatch(path);
  return nav == null ? null : NotificationTarget('nav', nav[1]);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Admin `NotificationBell.formatRelative`: "az önce", "5 dk önce", "3 sa önce", "2 gün önce", then "dd.MM".
String formatRelativeTr(DateTime? date, DateTime now) {
  if (date == null) return '';
  final sec = now.difference(date).inSeconds;
  if (sec < 60) return 'az önce';
  final min = sec ~/ 60;
  if (min < 60) return '$min dk önce';
  final hr = min ~/ 60;
  if (hr < 24) return '$hr sa önce';
  final day = hr ~/ 24;
  if (day < 7) return '$day gün önce';
  final d = date.toLocal();
  return '${_two(d.day)}.${_two(d.month)}';
}

/// Bubble time: "14:05" today, else "13.10 14:05".
String formatMessageTime(DateTime? date, DateTime now) {
  if (date == null) return '';
  final d = date.toLocal();
  final n = now.toLocal();
  final time = '${_two(d.hour)}:${_two(d.minute)}';
  return d.year == n.year && d.month == n.month && d.day == n.day ? time : '${_two(d.day)}.${_two(d.month)} $time';
}

/// "Ayşe yazıyor…" / "3 kişi yazıyor…" (admin `ChatTypingIndicator`).
String? typingLabel(List<String> names) => names.isEmpty
    ? null
    : names.length == 1
    ? '${names.first} yazıyor…'
    : '${names.length} kişi yazıyor…';
