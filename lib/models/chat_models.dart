/// Chat and notification DTOs of the backend (`DtoChatGroup`, `DtoChatMessage`, `DtoChatMember`,
/// `DtoChatGroupAccess`, `DtoNotification`). Parsing is defensive: the data comes from the network (REST and
/// WebSocket), a wrong type gives a default instead of a crash, a record without its id is rejected (null).
library;

import '../services/chat_format.dart';

String? _str(Object? v) => v == null ? null : '$v';
int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
bool _bool(Object? v) => v == true;

class ChatGroup {
  final String id;
  final String? name;
  final String? description;

  /// GROUP | DM
  final String type;
  final int? createdBy;

  /// 1 everyone · 2 EDITOR+ · 3 ADMIN+ · 4 private (DM always 4).
  final int visibilityLevel;

  /// AC=TC: every group lives in a tenant (the session tenant for panel users).
  final String? tenantId;
  final bool visitorAccess;
  final DateTime? updatedAt;

  const ChatGroup({
    required this.id,
    this.name,
    this.description,
    this.type = 'GROUP',
    this.createdBy,
    this.visibilityLevel = 1,
    this.tenantId,
    this.visitorAccess = false,
    this.updatedAt,
  });

  bool get isDm => type == 'DM';

  /// List/app-bar title (admin shows "DM" for unnamed direct messages).
  String get title => (name ?? '').trim().isEmpty ? (isDm ? 'Direkt mesaj' : 'Adsız grup') : name!;

  static ChatGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    if (id == null || id.isEmpty) return null;
    return ChatGroup(
      id: id,
      name: _str(json['name']),
      description: _str(json['description']),
      type: _str(json['type']) ?? 'GROUP',
      createdBy: _int(json['createdBy']),
      visibilityLevel: _int(json['visibilityLevel']) ?? 1,
      tenantId: _str(json['tenantId']),
      visitorAccess: _bool(json['visitorAccess']),
      updatedAt: parseServerDate(json['updatedAt']),
    );
  }
}

class ChatMessage {
  final String id;
  final String groupId;

  /// ADMIN (panel user) · VISITOR (registered tenant user) · GUEST (anonymous visitor).
  final String senderType;
  final int? senderId;
  final int? visitorId;
  final String? sessionId;
  final String senderName;
  final String content;

  /// TEXT | IMAGE | FILE | SYSTEM
  final String contentType;
  final String? fileUrl;
  final bool deleted;
  final bool edited;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.groupId,
    this.senderType = 'ADMIN',
    this.senderId,
    this.visitorId,
    this.sessionId,
    this.senderName = '',
    this.content = '',
    this.contentType = 'TEXT',
    this.fileUrl,
    this.deleted = false,
    this.edited = false,
    this.createdAt,
  });

  ChatMessage markDeleted() => ChatMessage(
    id: id,
    groupId: groupId,
    senderType: senderType,
    senderId: senderId,
    visitorId: visitorId,
    sessionId: sessionId,
    senderName: senderName,
    content: '',
    contentType: contentType,
    deleted: true,
    createdAt: createdAt,
  );

  bool get isFile => contentType == 'FILE' || contentType == 'IMAGE';

  /// Ban target key of a tenant-side sender (admin `banKey`): GUEST → `s:<sessionId>`, VISITOR → `v:<visitorId>`.
  String? get banKey => senderType == 'GUEST' && sessionId != null
      ? 's:$sessionId'
      : senderType == 'VISITOR' && visitorId != null
      ? 'v:$visitorId'
      : null;

  static ChatMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    final groupId = _str(json['groupId']);
    if (id == null || id.isEmpty || groupId == null) return null;
    final name = _str(json['senderUsername']) ?? _str(json['senderDisplayName']) ?? '';
    return ChatMessage(
      id: id,
      groupId: groupId,
      senderType: _str(json['senderType']) ?? 'ADMIN',
      senderId: _int(json['senderId']),
      visitorId: _int(json['visitorId']),
      sessionId: _str(json['sessionId']),
      senderName: name,
      content: _str(json['content']) ?? '',
      contentType: _str(json['contentType']) ?? 'TEXT',
      fileUrl: _str(json['fileUrl']),
      deleted: _bool(json['deleted']),
      edited: json['editedAt'] != null,
      createdAt: parseServerDate(json['createdAt']),
    );
  }
}

class ChatMember {
  final int userId;
  final String username;
  final String firstName;
  final String lastName;

  /// OWNER | MEMBER (group role, not the user's panel role).
  final String role;

  const ChatMember({
    required this.userId,
    this.username = '',
    this.firstName = '',
    this.lastName = '',
    this.role = 'MEMBER',
  });

  bool get isOwner => role == 'OWNER';

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }

  static ChatMember? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _int(json['userId']);
    if (id == null) return null;
    return ChatMember(
      userId: id,
      username: _str(json['username']) ?? '',
      firstName: _str(json['firstName']) ?? '',
      lastName: _str(json['lastName']) ?? '',
      role: _str(json['role']) ?? 'MEMBER',
    );
  }
}

/// `GET /groups/{id}/access`.
class ChatGroupAccess {
  final bool canRead;
  final bool canWrite;
  final String? denialMessage;

  const ChatGroupAccess({this.canRead = false, this.canWrite = false, this.denialMessage});

  static ChatGroupAccess fromJson(Object? json) => json is Map
      ? ChatGroupAccess(
          canRead: _bool(json['canRead']),
          canWrite: _bool(json['canWrite']),
          denialMessage: _str(json['denialMessage']),
        )
      : const ChatGroupAccess();
}

class AppNotification {
  final int id;

  /// FORM_SUBMISSION · EMAIL_FAILED · CHAT_MESSAGE · USER_REGISTERED · MAIL_VERIFY_FAILED · SYSTEM
  final String type;
  final String title;
  final String message;

  /// Admin panel path (`/chat`, `/forms/12/submissions`, …); mapped to a mobile screen by [notificationTarget].
  final String? link;
  final bool read;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    this.type = 'SYSTEM',
    this.title = '',
    this.message = '',
    this.link,
    this.read = false,
    this.metadata = const {},
    this.createdAt,
  });

  AppNotification asRead() => AppNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    link: link,
    read: true,
    metadata: metadata,
    createdAt: createdAt,
  );

  static AppNotification? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _int(json['id']);
    if (id == null) return null;
    final meta = json['metadata'];
    return AppNotification(
      id: id,
      type: _str(json['type']) ?? 'SYSTEM',
      title: _str(json['title']) ?? '',
      message: _str(json['message']) ?? '',
      link: _str(json['link']),
      read: _bool(json['read']),
      metadata: meta is Map ? Map<String, dynamic>.from(meta) : const {},
      createdAt: parseServerDate(json['createdAt']),
    );
  }
}
