import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

bool qrScannerSupported() {
  try {
    final nav = web.window.navigator as JSObject;
    return nav.has('mediaDevices');
  } catch (_) {
    return false;
  }
}

Widget buildQrScannerWidget({
  required void Function(String code) onCode,
  required void Function(String message) onError,
}) {
  return _WebQrScanner(onCode: onCode, onError: onError);
}

class _WebQrScanner extends StatefulWidget {
  const _WebQrScanner({required this.onCode, required this.onError});

  final void Function(String code) onCode;
  final void Function(String message) onError;

  @override
  State<_WebQrScanner> createState() => _WebQrScannerState();
}

class _WebQrScannerState extends State<_WebQrScanner> {
  web.HTMLVideoElement? _video;
  web.MediaStream? _stream;
  Timer? _timer;
  bool _disposed = false;
  bool _found = false;
  bool _scanning = false;
  JSObject? _detector;
  JSFunction? _jsQr;
  web.HTMLCanvasElement? _canvas;
  web.CanvasRenderingContext2D? _ctx;

  @override
  void initState() {
    super.initState();
    _initReader();
  }

  Future<void> _initReader() async {
    final win = web.window as JSObject;
    if (win.has('BarcodeDetector')) {
      try {
        final ctor = win['BarcodeDetector'] as JSFunction;
        final opts = JSObject();
        opts['formats'] = <JSString>['qr_code'.toJS].toJS;
        _detector = ctor.callAsConstructor<JSObject>(opts);
      } catch (_) {}
    }
    if (_detector == null) {
      await _loadJsQr();
      _jsQr = win['jsQR'] as JSFunction?;
    }
  }

  Future<void> _loadJsQr() async {
    final win = web.window as JSObject;
    if (win.has('jsQR')) return;
    final c = Completer<void>();
    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.src = 'vendor/jsQR.js';
    script.onload = ((JSAny? _) {
      if (!c.isCompleted) c.complete();
    }).toJS;
    script.onerror = ((JSAny? _) {
      if (!c.isCompleted) c.complete();
    }).toJS;
    web.document.head?.appendChild(script);
    return c.future;
  }

  Future<void> _startCamera(web.HTMLVideoElement video) async {
    _video = video;
    try {
      final md = web.window.navigator.mediaDevices;
      final facing = JSObject();
      facing['ideal'] = 'environment'.toJS;
      final vidCfg = JSObject();
      vidCfg['facingMode'] = facing;
      final constraints = web.MediaStreamConstraints(video: vidCfg);
      final stream = await md.getUserMedia(constraints).toDart;
      if (_disposed) {
        _stopStream(stream);
        return;
      }
      _stream = stream;
      video.srcObject = stream;
      await video.play().toDart;
      _timer = Timer.periodic(const Duration(milliseconds: 180), (_) => _tick());
    } catch (_) {
      if (!_disposed) {
        widget.onError('Sem acesso à câmera — use colar.');
      }
    }
  }

  Future<void> _tick() async {
    if (_disposed || _found || _scanning) return;
    final v = _video;
    if (v == null || v.videoWidth <= 0 || v.videoHeight <= 0) return;
    _scanning = true;
    try {
      if (_detector != null) {
        final hits = await _detector!
            .callMethod<JSPromise<JSArray<JSObject>>>('detect'.toJS, v)
            .toDart;
        final list = hits.toDart;
        if (list.isNotEmpty) {
          final raw = (list.first['rawValue'] as JSString?)?.toDart;
          if (raw != null && raw.isNotEmpty) {
            _found = true;
            _stopAll();
            widget.onCode(raw);
            return;
          }
        }
      } else if (_jsQr != null) {
        final w = v.videoWidth;
        final h = v.videoHeight;
        _canvas ??= web.document.createElement('canvas') as web.HTMLCanvasElement;
        if (_canvas!.width != w || _canvas!.height != h) {
          _canvas!.width = w;
          _canvas!.height = h;
          _ctx = _canvas!.getContext('2d') as web.CanvasRenderingContext2D?;
        }
        final ctx = _ctx;
        if (ctx != null) {
          ctx.drawImage(v, 0, 0, w.toDouble(), h.toDouble());
          final img = ctx.getImageData(0, 0, w, h);
          final res = _jsQr!.callAsFunction(null, img.data, w.toJS, h.toJS);
          if (res != null && res.isA<JSObject>()) {
            final obj = res as JSObject;
            final data = (obj['data'] as JSString?)?.toDart;
            if (data != null && data.isNotEmpty) {
              _found = true;
              _stopAll();
              widget.onCode(data);
              return;
            }
          }
        }
      }
    } catch (_) {}
    _scanning = false;
  }

  void _stopStream(web.MediaStream? stream) {
    if (stream == null) return;
    try {
      final tracks = stream.getTracks().toDart;
      for (final t in tracks) {
        t.stop();
      }
    } catch (_) {}
  }

  void _stopAll() {
    _timer?.cancel();
    _timer = null;
    _stopStream(_stream);
    _stream = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: const Color(0xFF000000),
        height: 220,
        child: HtmlElementView.fromTagName(
          tagName: 'video',
          onElementCreated: (Object el) {
            final video = el as web.HTMLVideoElement;
            video.setAttribute('playsinline', 'true');
            video.muted = true;
            video.autoplay = true;
            video.style.width = '100%';
            video.style.height = '100%';
            video.style.objectFit = 'cover';
            _startCamera(video);
          },
        ),
      ),
    );
  }
}
