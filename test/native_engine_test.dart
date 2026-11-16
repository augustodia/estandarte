import 'dart:convert';
import 'dart:io';

import 'package:estandarte/engine/game_engine_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'NativeEngineBackend initializes and executes RPC constants on Windows',
    () async {
      final backend = NativeEngineBackend();
      try {
        await backend.init();
        final raw = backend.call('constants', '{}');
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['nt'], 42);
        expect((decoded['colors'] as List<dynamic>).length, greaterThanOrEqualTo(6));
      } finally {
        backend.dispose();
      }
    },
    skip: !Platform.isWindows ? 'Windows only' : null,
  );
}
