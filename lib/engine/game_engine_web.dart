import 'dart:js_interop';

import 'game_engine.dart';

@JS('__estandarteEngineReady')
external JSPromise<JSBoolean>? get _engineReady;

@JS('estandarteEngine.call')
external JSString _jsEngineCall(JSString op, JSString payload);

class WebEngineBackend implements EngineBackend {
  @override
  Future<void> init() async {
    final ready = _engineReady;
    if (ready != null) {
      await ready.toDart;
    }
  }

  @override
  String call(String op, String payload) {
    return _jsEngineCall(op.toJS, payload.toJS).toDart;
  }
}

EngineBackend createEngineBackend() => WebEngineBackend();
