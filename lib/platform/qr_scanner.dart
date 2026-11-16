import 'package:flutter/widgets.dart';

import 'qr_scanner_native.dart' if (dart.library.js_interop) 'qr_scanner_web.dart' as impl;

class QrScannerView extends StatelessWidget {
  const QrScannerView({
    super.key,
    required this.onCode,
    required this.onError,
  });

  final void Function(String code) onCode;
  final void Function(String message) onError;

  static bool get supported => impl.qrScannerSupported();

  @override
  Widget build(BuildContext context) {
    return impl.buildQrScannerWidget(onCode: onCode, onError: onError);
  }
}
