import 'package:flutter/services.dart';

/// C2: Native incoming call screen bridge (iOS CallKit / Android ConnectionService)
/// over MethodChannel('elly/callkit'). Gracefully degrades when native plugin/channel
/// is not bound (e.g. in widget tests or foreground-only builds).
class IncomingCallService {
  static const MethodChannel _channel = MethodChannel('elly/callkit');

  final Future<void> Function({required bool video})? onAccept;
  final void Function()? onReject;

  IncomingCallService({this.onAccept, this.onReject}) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onAcceptCall':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        final video = args['video'] == true;
        if (onAccept != null) await onAccept!(video: video);
      case 'onRejectCall':
        onReject?.call();
    }
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
