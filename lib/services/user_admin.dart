/// Pure rules of the System & account screens (users, roles, profile, password, 2FA). No Flutter deps.
library;

import 'api_service.dart';
import 'mail_payload.dart' show emailPattern;

// ── Role hierarchy (backend UserService/RoleService.roleLevel) ──────────────────────────────────────

/// Backend levels; any other role (VIEWER, TENANT, custom) is 1.
const roleLevels = {'SUPER_ADMIN': 4, 'ADMIN': 3, 'EDITOR': 2, 'VIEWER': 1};

/// Admin user-page labels of the panel roles.
const roleLabels = {'SUPER_ADMIN': 'Süper Admin', 'ADMIN': 'Admin', 'EDITOR': 'Editör', 'VIEWER': 'Görüntüleyici'};

int roleLevel(String role) => roleLevels[role] ?? 1;

/// Highest level of [roles]; none → 1 (backend `getUserRoleLevel` / admin `useMyRoleLevel`).
int maxRoleLevel(Iterable<String> roles) => roles.fold(1, (max, r) => roleLevel(r) > max ? roleLevel(r) : max);

/// A role offered in the user form: never TENANT (tenant users are a separate audience) and never above the
/// caller's own level (backend rejects it with 403; admin hides it the same way).
bool canAssignRole(int myLevel, String role) => role != 'TENANT' && roleLevel(role) <= myLevel;

/// Edit / status / delete / password reset of a user whose highest role is above the caller's is hidden.
/// The backend only checks the roles being *assigned*: an ADMIN editing a SUPER_ADMIN's roles in the admin panel
/// silently drops SUPER_ADMIN (it is not in the ADMIN's role list) — the mobile app does not offer that.
bool canManageUser(int myLevel, Iterable<String> targetRoles) => maxRoleLevel(targetRoles) <= myLevel;

/// Panel create without roles gets ADMIN (backend default) — only offered to callers who could assign ADMIN.
bool canUseDefaultAdminRole(int myLevel) => myLevel >= roleLevel('ADMIN');

List<String> rolesOf(Map<String, dynamic> user) => [for (final r in (user['roles'] as List? ?? const [])) '$r'];

/// "Ad Soyad", or the username when both are empty (admin `useMyFullName`).
String displayNameOf(Map<String, dynamic>? user) {
  if (user == null) return '';
  final full = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
  return full.isNotEmpty ? full : '${user['username'] ?? ''}';
}

// ── Payloads ───────────────────────────────────────────────────────────────────────────────────────

/// `POST /users` (DtoCreateUser). audience `panel`: [roleIds] (empty → key omitted → backend assigns ADMIN);
/// `tenant`: no roleIds (backend assigns TENANT and rejects roleIds).
Map<String, dynamic> createUserPayload({
  required String audience,
  required String username,
  required String email,
  required String password,
  required String firstName,
  required String lastName,
  List<int> roleIds = const [],
}) => {
  'username': username.trim(),
  'email': email.trim(),
  'password': password,
  'firstName': firstName.trim(),
  'lastName': lastName.trim(),
  if (audience == 'panel' && roleIds.isNotEmpty) 'roleIds': roleIds,
  'audience': audience,
};

/// `PUT /users/{id}` (DtoAdminUserUpdate, "only filled fields apply"): blank username/email are left out like the
/// admin; names are sent as typed (empty clears); a blank [newPassword] is left out (no reset).
Map<String, dynamic> updateUserPayload({
  required String username,
  required String email,
  required String firstName,
  required String lastName,
  String newPassword = '',
}) => {
  if (username.trim().isNotEmpty) 'username': username.trim(),
  if (email.trim().isNotEmpty) 'email': email.trim(),
  'firstName': firstName.trim(),
  'lastName': lastName.trim(),
  if (newPassword.isNotEmpty) 'newPassword': newPassword,
};

// ── Validation (backend Dto* annotations) ──────────────────────────────────────────────────────────

/// DtoCreateUser / DtoChangePassword / DtoAdminUserUpdate `@Pattern`: ≥8 chars, lower + upper case + digit.
final _passwordRule = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$');

const passwordRuleHint = 'En az 8 karakter, büyük/küçük harf + rakam';

/// null = valid. Edge whitespace is rejected instead of trimmed silently (the user would not know their password).
String? passwordError(String value) {
  if (value.isEmpty) return 'Şifre zorunludur';
  if (value.trim() != value) return 'Şifre boşlukla başlayamaz veya bitemez';
  if (!_passwordRule.hasMatch(value)) return 'Şifre $passwordRuleHint olmalıdır';
  return null;
}

/// Username `@Size(min = 3, max = 50)`.
String? usernameError(String value, {bool required = true}) {
  final v = value.trim();
  if (v.isEmpty) return required ? 'Kullanıcı adı zorunludur' : null;
  if (v.length < 3 || v.length > 50) return 'Kullanıcı adı 3-50 karakter olmalıdır';
  return null;
}

String? emailError(String value, {bool required = true}) {
  final v = value.trim();
  if (v.isEmpty) return required ? 'E-posta zorunludur' : null;
  return emailPattern.hasMatch(v) ? null : 'Geçerli bir e-posta adresi giriniz';
}

// ── Backend messages → Turkish ─────────────────────────────────────────────────────────────────────

const _messages = {
  'Current password is incorrect': 'Mevcut şifre hatalı.',
  'New password must be different from current password': 'Yeni şifre mevcut şifreden farklı olmalı.',
  'Password change is not available for OAuth users': 'Sosyal giriş hesaplarında şifre değiştirilemez.',
  'Password reset is not available for OAuth users': 'Sosyal giriş hesaplarında şifre sıfırlanamaz.',
  'Username already exists': 'Bu kullanıcı adı zaten kullanılıyor.',
  'Email already exists': 'Bu e-posta adresi zaten kullanılıyor.',
  'Password must be at least 8 characters': 'Şifre $passwordRuleHint olmalıdır.',
};

/// User/profile error text: known backend (English) messages in Turkish; 403 explains the role hierarchy.
String userErrorText(Object error) {
  final text = error.toString();
  final role = RegExp(r"Cannot assign role '([^']+)'").firstMatch(text)?.group(1);
  if (role != null) return '"$role" rolünü atayamazsınız: kendi yetki seviyenizin üstünde.';
  for (final e in _messages.entries) {
    if (text.contains(e.key)) return e.value;
  }
  if (error is ApiException && error.statusCode == 403) {
    return 'Bu işlem için yetkiniz yok. Kendi rol seviyenizin üstündeki işlemler reddedilir.';
  }
  return text;
}

// ── 2FA setup ──────────────────────────────────────────────────────────────────────────────────────

/// The backend's `qrUri` (TotpService.buildQrUri) is only opened when it is a TOTP URI for this very [secret]:
/// a server value must not launch an arbitrary scheme or a different key.
bool isValidOtpauthUri(String uri, String secret) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'otpauth' || parsed.host != 'totp') return false;
  if (secret.isEmpty || parsed.pathSegments.isEmpty) return false;
  return parsed.queryParameters['secret'] == secret;
}

/// Base32 secret in groups of four ("ABCD EFGH …") for reading/typing; masked: same length, all "•".
String formatSecret(String secret, {bool masked = false}) {
  final chars = masked ? '•' * secret.length : secret;
  final groups = <String>[];
  for (var i = 0; i < chars.length; i += 4) {
    groups.add(chars.substring(i, i + 4 > chars.length ? chars.length : i + 4));
  }
  return groups.join(' ');
}

/// Profile "İzinler": `posts:read` keys grouped by module, both sorted (admin `groupPermissionsByModule`).
Map<String, List<String>> groupPermissions(Iterable<String> permissions) {
  final groups = <String, List<String>>{};
  for (final p in permissions) {
    final i = p.indexOf(':');
    if (i <= 0) continue;
    groups.putIfAbsent(p.substring(0, i), () => []).add(p.substring(i + 1));
  }
  for (final list in groups.values) {
    list.sort();
  }
  return Map.fromEntries(groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

/// Admin profile `moduleLabels`.
const permissionModuleLabels = {
  'posts': 'Yazılar',
  'pages': 'Sayfalar',
  'components': 'Bileşenler',
  'widgets': "Widget'lar",
  'banners': "Banner'lar",
  'assets': 'Medya',
  'comments': 'Yorumlar',
  'forms': 'Formlar',
  'ratings': 'Puanlamalar',
  'contents': 'İçerikler',
  'basic_infos': 'Temel Bilgiler',
  'mail': 'Mail Hesapları',
  'emails': 'E-postalar',
  'email_templates': 'E-posta Şablonları',
  'cache': 'Cache',
  'tenants': "Tenant'lar",
  'users': 'Kullanıcılar',
  'roles': 'Roller',
  'rabbit': 'RabbitMQ',
  'chat': 'Chat',
};
