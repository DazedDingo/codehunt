import 'package:flutter/services.dart';

/// Bridge to the native Android MainActivity that receives `Intent.ACTION_SEND`
/// payloads from Chrome's share sheet. No third-party plugin — just a method
/// channel into the Kotlin code that `scripts/patch_android.py` injects.
///
/// Cold launch: app started via share → call [getInitialShare] once after
/// the engine is up to fetch and consume the queued text.
///
/// Hot share: app already running → Kotlin invokes `shareReceived` on the
/// channel. Register a handler with [setHandler].
class ShareReceiver {
  static const _channel = MethodChannel('codehunt.share');

  static Future<String?> getInitialShare() async {
    try {
      return await _channel.invokeMethod<String>('getInitialShare');
    } catch (_) {
      return null;
    }
  }

  static void setHandler(void Function(String text) onShare) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareReceived' && call.arguments is String) {
        onShare(call.arguments as String);
      }
    });
  }
}
