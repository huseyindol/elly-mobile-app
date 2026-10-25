import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// C1: Mobile push notification device token registration service.
/// Registers / unregisters FCM/APNs/VoIP device tokens with backend `/notifications/devices`.
class PushNotificationService {
  final ApiService _api;

  PushNotificationService({ApiService? apiService}) : _api = apiService ?? ApiService();

  static String get defaultPlatform {
    if (kIsWeb) return 'WEB';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'IOS',
      _ => 'ANDROID',
    };
  }

  /// Registers the device's push token (and optional iOS PushKit VoIP token) for the signed-in user.
  Future<Map<String, dynamic>?> registerDeviceToken({
    required String token,
    String? platform,
    String? voipToken,
    String? deviceName,
  }) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;
    final res = await _api.post('/notifications/devices', {
      'token': trimmed,
      'platform': (platform ?? defaultPlatform).toUpperCase(),
      if (voipToken != null && voipToken.trim().isNotEmpty) 'voipToken': voipToken.trim(),
      if (deviceName != null && deviceName.trim().isNotEmpty) 'deviceName': deviceName.trim(),
    });
    return (res as Map?)?.cast<String, dynamic>();
  }

  /// Removes a device push token on sign-out.
  Future<bool> unregisterDeviceToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    final encoded = Uri.encodeQueryComponent(trimmed);
    final res = await _api.delete('/notifications/devices?token=$encoded');
    return res == true;
  }

  /// Lists registered push devices for the current user.
  Future<List<Map<String, dynamic>>> fetchDevices() async {
    final res = await _api.get('/notifications/devices');
    if (res is List) {
      return res.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }
}
