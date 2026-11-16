import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

JSObject? _wakeSentinel;

String? getQueryParam(String name) {
  final uri = Uri.tryParse(web.window.location.href);
  return uri?.queryParameters[name];
}

bool hasQueryParam(String name) {
  final uri = Uri.tryParse(web.window.location.href);
  return uri?.queryParameters.containsKey(name) ?? false;
}

String getHash() => web.window.location.hash;

String getBaseUrl() {
  final loc = web.window.location;
  final path = loc.pathname;
  return '${loc.origin}$path';
}

void replaceCleanUrl([String? sala]) {
  try {
    final base = getBaseUrl();
    final next = sala != null && sala.isNotEmpty ? '$base?sala=$sala' : base;
    web.window.history.replaceState(null, '', next);
  } catch (_) {}
}

Future<bool> shareOrCopy({
  required String title,
  required String text,
  required String url,
}) async {
  try {
    final nav = web.window.navigator as JSObject;
    if (nav.has('share')) {
      final data = JSObject();
      data['title'] = title.toJS;
      data['text'] = text.toJS;
      data['url'] = url.toJS;
      final promise = nav.callMethod<JSPromise<JSAny?>>('share'.toJS, data);
      await promise.toDart;
      return true;
    }
  } catch (_) {}
  try {
    await Clipboard.setData(ClipboardData(text: url));
  } catch (_) {}
  return false;
}

void vibrate(int ms) {
  try {
    web.window.navigator.vibrate(ms.toJS);
  } catch (_) {}
}

void setWakeLock(bool hold) {
  try {
    final nav = web.window.navigator as JSObject;
    if (hold && _wakeSentinel == null && nav.has('wakeLock')) {
      final wl = nav['wakeLock'] as JSObject?;
      final promise = wl?.callMethod<JSPromise<JSObject>>('request'.toJS, 'screen'.toJS);
      promise?.toDart.then((sentinel) {
        _wakeSentinel = sentinel;
      }).catchError((_) {});
    } else if (!hold && _wakeSentinel != null) {
      final s = _wakeSentinel!;
      _wakeSentinel = null;
      s.callMethodVarArgs<JSPromise<JSAny?>>('release'.toJS, const []);
    }
  } catch (_) {}
}

bool isOnline() {
  try {
    return web.window.navigator.onLine;
  } catch (_) {
    return true;
  }
}

void Function() listenConnectivity(void Function(bool online) cb) {
  final sub1 = web.EventStreamProviders.onlineEvent.forTarget(web.window).listen((_) => cb(true));
  final sub2 = web.EventStreamProviders.offlineEvent.forTarget(web.window).listen((_) => cb(false));
  return () {
    sub1.cancel();
    sub2.cancel();
  };
}

void Function() listenVisibility(void Function(bool hidden) cb) {
  final sub = const web.EventStreamProvider<web.Event>('visibilitychange')
      .forTarget(web.document)
      .listen((_) => cb(web.document.hidden));
  return () {
    sub.cancel();
  };
}

bool reducedMotion() {
  try {
    return web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch (_) {
    return false;
  }
}
