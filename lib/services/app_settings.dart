import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens this app's page in the system settings (a refused microphone/camera permission can only be granted there).
/// iOS: `app-settings:`; Android: the app details screen through `MainActivity`'s channel. False if it did not open.
Future<bool> openAppSettings() async {
  try {
    if (Platform.isIOS) return await launchUrl(Uri.parse('app-settings:'));
    if (Platform.isAndroid) {
      return await const MethodChannel('elly/app_settings').invokeMethod<bool>('open') ?? false;
    }
  } catch (_) {}
  return false;
}
