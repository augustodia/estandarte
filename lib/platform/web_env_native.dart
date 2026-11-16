import 'package:flutter/services.dart';

String? getQueryParam(String name) => null;
bool hasQueryParam(String name) => false;
String getHash() => '';
String getBaseUrl() => 'https://estandarte.app/';
void replaceCleanUrl([String? sala]) {}

Future<bool> shareOrCopy({
  required String title,
  required String text,
  required String url,
}) async {
  await Clipboard.setData(ClipboardData(text: url));
  return false;
}

void vibrate(int ms) {}
void setWakeLock(bool hold) {}
bool isOnline() => true;
void Function() listenConnectivity(void Function(bool online) cb) => () {};
void Function() listenVisibility(void Function(bool hidden) cb) => () {};
bool reducedMotion() => false;
