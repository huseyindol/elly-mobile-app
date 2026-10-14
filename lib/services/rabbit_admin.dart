/// Pure rules of the RabbitMQ screens (backend `RabbitAdminController`, `/api/v1/admin/rabbit`). No Flutter deps.
library;

import 'dart:convert';

import 'api_service.dart';

const rabbitBase = '/admin/rabbit';

/// `/admin/rabbit/queues/{name}` (+ `/messages`, `/purge`, `/republish`); the name is one path segment.
String queuePath(String name, [String suffix = '']) => '$rabbitBase/queues/${Uri.encodeComponent(name)}$suffix';

/// Backend `peekMessages`: count 1–100 (admin input min/max); default 10.
const peekDefault = 10;
int clampPeekCount(int? count) => (count ?? peekDefault).clamp(1, 100);

/// Admin RepublishDialog default target (DLQ → main queue is the usual case).
const defaultRepublishTarget = 'email-queue';

/// Messages are untrusted text: JSON is pretty-printed, anything else is shown as it is (never rendered).
String prettyPayload(String raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw;
  }
}

/// A peeked payload can be large; the list shows at most [max] characters (the republish form gets it all).
String clipText(String text, {int max = 10000}) =>
    text.length <= max ? text : '${text.substring(0, max)}\n… (${text.length - max} karakter daha)';

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

/// A JSON content type with a body that does not parse would be dead-lettered by the consumer.
String? republishPayloadError(String payload, String contentType) {
  if (payload.trim().isEmpty) return 'Payload zorunludur';
  if (!contentType.toLowerCase().contains('json')) return null;
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
