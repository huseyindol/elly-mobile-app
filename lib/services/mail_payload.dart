/// Pure request / label helpers of the communication screens (mail accounts, e-mail templates, e-mail logs).
library;

/// Admin `MailAccountRequest` (backend `DtoMailAccountRequest`) from the form [values].
///
/// The SMTP password is write-only: the backend never returns it and, on update, keeps the stored one when the
/// field is null/blank (`MailAccountService.update`). It is sent only when typed (as typed, not trimmed), so an
/// edit can never blank it; create requires it (form validation, backend `ValidationException`).
/// An empty tenant is sent as null ("atanmamış").
Map<String, dynamic> mailAccountPayload(Map<String, Object?> values, {required String password}) {
  String text(String key) => '${values[key] ?? ''}'.trim();
  final tenant = text('tenantId');
  return {
    'name': text('name'),
    'fromAddress': text('fromAddress'),
    'smtpHost': text('smtpHost'),
    'smtpPort': int.tryParse(text('smtpPort')),
    'smtpUsername': text('smtpUsername'),
    if (password.trim().isNotEmpty) 'smtpPassword': password,
    'isPrimary': values['isPrimary'] == true,
    'active': values['active'] != false,
    'tenantId': tenant.isEmpty ? null : tenant,
  };
}

/// Backend `DtoEmailTemplateIU`. PUT validates `templateKey` too (`@NotBlank`), so an update sends the record's
/// key back; [optimisticLockVersion] comes from the loaded record (admin sends it as well).
Map<String, dynamic> emailTemplatePayload({
  required String templateKey,
  required String subject,
  required String htmlBody,
  required String description,
  required bool active,
  Object? optimisticLockVersion,
}) => {
  'templateKey': templateKey.trim(),
  'subject': subject.trim(),
  'htmlBody': htmlBody,
  'description': description.trim().isEmpty ? null : description.trim(),
  'active': active,
  'optimisticLockVersion': ?optimisticLockVersion,
};

/// Backend `EmailStatus` → label (dashboard "Son E-postalar", e-mail logs).
const emailStatusLabels = {'PENDING': 'Beklemede', 'SENT': 'Gönderildi', 'FAILED': 'Başarısız'};

/// `GET /emails` (newest first like the admin), optionally filtered by `status`; page/size are appended by the list.
String emailLogsEndpoint(String? status) =>
    status == null ? '/emails?sort=id,desc' : '/emails?status=${Uri.encodeQueryComponent(status)}&sort=id,desc';

/// Backend `EmailService.retry` rejects SENT logs (400); FAILED and stuck PENDING ones can be re-queued.
bool canRetryEmail(Map<String, dynamic> log) => log['status'] != 'SENT';

/// Backend `DtoEmailTemplateIU.templateKey` pattern (+ admin min 2).
final templateKeyPattern = RegExp(r'^[a-z0-9-]+$');

/// Loose e-mail check for form fields (the backend `@Email` has the final say).
final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
