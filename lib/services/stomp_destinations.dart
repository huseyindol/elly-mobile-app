/// Every STOMP destination the app uses — same ones as elly-admin `chat-ws-store.ts` (backend `ChatTopics`,
/// `ChatWebSocketController`, `NotificationPublisher`, `ChatMembershipNotifier`). Ids are validated before use
/// ([isUuid] / [isSafeTenantId]) so a value can never reach into another destination.
/// Phase 6 (WebRTC) adds `/app/rtc/*` and `/topic/user/{id}/rtc` here and subscribes through `RealtimeService`.
library;

final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _tenant = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Chat group / message ids are UUIDs.
bool isUuid(String? value) => value != null && _uuid.hasMatch(value);

/// Tenant ids are single path/destination segments (`tenant1`).
bool isSafeTenantId(String? value) => value != null && _tenant.hasMatch(value);

abstract final class StompDest {
  // ── Server → client (subscribe) ──
  static const presence = '/topic/presence';
  static const groupsNew = '/topic/groups/new';

  /// Body is the group id.
  static const groupsDeleted = '/topic/groups/deleted';

  /// `DtoChatWsError` of a rejected `/app/...` frame (sender only).
  static const chatErrors = '/user/queue/chat-errors';
  static const notifications = '/user/queue/notifications';
  static const notificationsUnreadCount = '/user/queue/notifications/unread-count';

  /// JOINED (with the group) / REMOVED events of the signed-in user (backend's primary path).
  static String membership(int userId) => '/topic/user/$userId/membership';

  static String group(String tenantId, String groupId) => '/topic/tenant/$tenantId/group/$groupId';
  static String typing(String tenantId, String groupId) => '/topic/tenant/$tenantId/group/$groupId/typing';
  static String read(String tenantId, String groupId) => '/topic/tenant/$tenantId/group/$groupId/read';
  static String bans(String tenantId, String groupId) => '/topic/tenant/$tenantId/group/$groupId/bans';

  // ── Client → server (send) ──
  static String sendTyping(String tenantId, String groupId) => '/app/tenant-chat/$tenantId/$groupId/typing';
  static String sendRead(String tenantId, String groupId) => '/app/tenant-chat/$tenantId/$groupId/read';
}
