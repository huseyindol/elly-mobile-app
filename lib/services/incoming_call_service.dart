import 'package:flutter/services.dart';

/// C2: Native incoming call screen & PushKit VoIP token bridge (iOS CallKit / Android ConnectionService)
/// over MethodChannel('elly/callkit'). Gracefully degrades when native plugin/channel
/// is not bound (e.g. in widget tests or foreground-only builds).
class IncomingCallService {
  static const MethodChannel _channel = MethodChannel('elly/callkit');

  final Future<void> Function({required bool video})? onAccept;
  final void Function()? onReject;
  final void Function(String voipToken)? onVoipToken;

  IncomingCallService({this.onAccept, this.onReject, this.onVoipToken}) {
    try {
      _channel.setMethodCallHandler(_handleNativeCall);
    } catch (_) {
      // Pure Dart unit tests without ServicesBinding initialized.
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onAcceptCall':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        final video = args['video'] == true;
        if (onAccept != null) await onAccept!(video: video);
      case 'onRejectCall':
        onReject?.call();
      case 'onVoipToken':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        final token = '${args['voipToken'] ?? ''}'.trim();
        if (token.isNotEmpty) onVoipToken?.call(token);
    }
  }

  /// Queries the cached iOS PushKit VoIP token from native `AppDelegate`, if available.
  static Future<String?> getVoipToken() async {
    try {
      final token = await _channel.invokeMethod<String>('getVoipToken');
      if (token != null && token.trim().isNotEmpty) return token.trim();
    } on MissingPluginException {
      // Ignore in widget tests / non-iOS platforms.
    } catch (_) {}
    return null;
  }

  /// Displays native full-screen incoming call UI (CallKit / ConnectionService).
  static Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    int? callerUserId,
    bool ringAll = false,
  }) async {
    try {
      await _channel.invokeMethod('showIncomingCall', {
        'callId': callId,
        'callerName': callerName,
        'callerUserId': callerUserId,
        'ringAll': ringAll,
      });
    } on MissingPluginException {
      // Native channel not registered in current build/test environment — ignore.
    } catch (_) {}
  }

  /// Dismisses native incoming call UI when call is answered, rejected, or timed out.
  static Future<void> endNativeCall([String? callId]) async {
    try {
      await _channel.invokeMethod('endCall', {'callId': callId});
    } on MissingPluginException {
      // Ignore in test / non-native environment.
    } catch (_) {}
  }
}
