/// Pure rules of the RabbitMQ screens (backend `RabbitAdminController`, `/api/v1/admin/rabbit`). No Flutter deps.
library;

import 'dart:convert';

import 'api_service.dart';

const rabbitBase = '/admin/rabbit';

/// `/admin/rabbit/queues/{name}` (+ `/messages`, `/purge`, `/republish`); the name is one path segment. "." and
/// ".." are encoded too (`encodeComponent` leaves them; a proxy would normalize `/queues/../purge`).
String queuePath(String name, [String suffix = '']) {
  final segment = name == '.' || name == '..' ? '%2E' * name.length : Uri.encodeComponent(name);
  return '$rabbitBase/queues/$segment$suffix';
}

/// Backend `peekMessages`: count 1–100 (admin input min/max); default 10.
const peekDefault = 10;
int clampPeekCount(int? count) => (count ?? peekDefault).clamp(1, 100);

/// Republish target for [source]: a dead-letter queue (`x.dlq`, `x-dlq`, `x_dlq`) goes back to its main queue;
/// any other source gets no default — the target has to be chosen on purpose.
String republishTargetFor(String source) {
  final match = RegExp(r'^(.+)[._-]dlq$', caseSensitive: false).firstMatch(source);
  return match?.group(1) ?? '';
}

/// Display only (the republish form keeps the raw text): valid JSON object/array re-indented by 2 without
/// re-encoding, so numbers (`12345678901234567890`, `1.10`, `1e3`) and escapes stay exactly as sent; anything else
/// (HTML too) is returned as it is — never rendered.
String prettyPayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty || (text[0] != '{' && text[0] != '[')) return raw;
  try {
    jsonDecode(text);
  } catch (_) {
    return raw;
  }
  final out = StringBuffer();
  var depth = 0;
  var inString = false;
  var escaped = false;
  void newline() => out
    ..write('\n')
    ..write('  ' * depth);
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inString) {
      out.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    switch (c) {
      case '"':
        inString = true;
        out.write(c);
      case '{' || '[':
        var j = i + 1;
        while (j < text.length && ' \t\n\r'.contains(text[j])) {
          j++;
        }
        if (j < text.length && (text[j] == '}' || text[j] == ']')) {
          out.write('$c${text[j]}'); // empty {} / []
          i = j;
        } else {
          depth++;
          out.write(c);
          newline();
        }
      case '}' || ']':
        depth--;
        newline();
        out.write(c);
      case ',':
        out.write(',');
        newline();
      case ':':
        out.write(': ');
      case ' ' || '\t' || '\n' || '\r':
        break;
      default:
        out.write(c);
    }
  }
  return out.toString();
}

/// Cuts [text] after at most [max] UTF-16 units without splitting a surrogate pair (a lone high surrogate makes
/// `SelectableText` throw "not well-formed UTF-16").
String clipText(String text, {int max = 10000}) {
  if (text.length <= max) return text;
  var end = max;
  final unit = text.codeUnitAt(end - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) end--; // high surrogate: keep the pair together
  return '${text.substring(0, end)}\n… (${text.length - end} karakter daha)';
}

/// Bidi controls (U+202A–202E, U+2066–2069) in an untrusted payload could reorder what the admin reads
/// ("Trojan Source"); they are shown as visible `⟨U+202E⟩` markers instead.
String revealBidi(String text) => text.replaceAllMapped(
  RegExp('[\u202A-\u202E\u2066-\u2069]'),
  (m) => '⟨U+${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}⟩',
);

/// What the message card shows: clipped first (a huge payload is never re-indented on the UI thread), then
/// indented (valid JSON only), bidi controls visible.
String payloadPreview(String raw) => revealBidi(prettyPayload(clipText(raw)));

/// "Tümünü göster": the whole payload, indented; run through `compute` for large payloads.
String payloadFull(String raw) => revealBidi(prettyPayload(raw));

/// `RepublishRequest` {targetQueue, payload, contentType}; payload is sent as typed.
Map<String, dynamic> republishPayload({
  required String targetQueue,
  required String payload,
  required String contentType,
}) => {
  'targetQueue': targetQueue.trim(),
  'payload': payload,
  'contentType': contentType.trim().isEmpty ? 'application/json' : contentType.trim(),
};

/// A JSON content type with a body that does not parse would be dead-lettered by the consumer. A blank content
/// type is sent as `application/json` ([republishPayload]) → checked as JSON too.
String? republishPayloadError(String payload, String contentType) {
  if (payload.trim().isEmpty) return 'Payload zorunludur';
  if (contentType.trim().isNotEmpty && !contentType.toLowerCase().contains('json')) return null;
  try {
    jsonDecode(payload);
    return null;
  } catch (_) {
    return 'Content type JSON ama payload geçerli JSON değil';
  }
}

/// Admin `mapRabbitApiError`.
String rabbitErrorText(Object error) {
  if (error is ApiException) {
    switch (error.statusCode) {
      case 503:
        return 'RabbitMQ şu an erişilemez';
      case 403:
        return 'Bu işlem için yetkin yok';
      case 404:
        return 'Queue bulunamadı';
      case 409:
        return 'Queue şu an kullanımda';
    }
  }
  return error.toString();
}

int countOf(Object? value) => value is num ? value.toInt() : 0;
