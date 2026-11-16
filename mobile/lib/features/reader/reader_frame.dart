import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class ReaderFrame {
  static const channel = MethodChannel('dingdong/reader-frame');

  static Future<void> wait(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is! AndroidWebViewController) {
      throw UnsupportedError('Reader rendering requires Android');
    }
    await channel.invokeMethod<void>('wait', {
      'id': platform.webViewIdentifier,
    });
    // Native drawing and Flutter texture composition use separate frame queues.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
  }

  static Future<void> cancel(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      try {
        await channel.invokeMethod<void>('cancel', {
          'id': platform.webViewIdentifier,
        });
      } on PlatformException {
        // The engine may already have released the native view.
      }
    }
  }
}
