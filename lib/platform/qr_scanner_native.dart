import 'package:flutter/widgets.dart';

bool qrScannerSupported() => false;

Widget buildQrScannerWidget({
  required void Function(String code) onCode,
  required void Function(String message) onError,
}) {
  return const Center(
    child: Text('Leitor de câmera indisponível nesta plataforma — cole o código abaixo.'),
  );
}
