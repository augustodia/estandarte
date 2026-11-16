import 'web_env_native.dart' if (dart.library.js_interop) 'web_env_web.dart' as impl;

abstract final class WebEnv {
  static String? getQueryParam(String name) => impl.getQueryParam(name);
  static bool hasQueryParam(String name) => impl.hasQueryParam(name);
  static String getHash() => impl.getHash();
  static String getBaseUrl() => impl.getBaseUrl();
  static void replaceCleanUrl([String? sala]) => impl.replaceCleanUrl(sala);
  static Future<bool> shareOrCopy({
    required String title,
    required String text,
    required String url,
  }) =>
      impl.shareOrCopy(title: title, text: text, url: url);
  static void vibrate(int ms) => impl.vibrate(ms);
  static void setWakeLock(bool hold) => impl.setWakeLock(hold);
  static bool get isOnline => impl.isOnline();
  static void Function() listenConnectivity(void Function(bool online) cb) =>
      impl.listenConnectivity(cb);
  static void Function() listenVisibility(void Function(bool hidden) cb) =>
      impl.listenVisibility(cb);
  static bool get reducedMotion => impl.reducedMotion();
}
