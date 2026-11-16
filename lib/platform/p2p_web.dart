import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../net/online_client.dart';
import 'p2p.dart';
import 'sdp_pack.dart';

const _gatherTimeout = Duration(milliseconds: 2500);
JSObject? _cert;
final _rng = Random.secure();

bool p2pSupported() {
  try {
    return (web.window as JSObject).has('RTCPeerConnection');
  } catch (_) {
    return false;
  }
}

JSObject _rtcConfig() {
  final ice = JSObject();
  ice['urls'] = 'stun:stun.l.google.com:19302'.toJS;
  final servers = <JSAny>[ice].toJS;
  final cfg = JSObject();
  cfg['iceServers'] = servers;
  if (_cert != null) {
    cfg['certificates'] = <JSAny>[_cert!].toJS;
  }
  return cfg;
}

JSObject _newPc() {
  final ctor = (web.window as JSObject)['RTCPeerConnection'] as JSFunction;
  return ctor.callAsConstructor<JSObject>(_rtcConfig());
}

Future<bool> initCert() async {
  try {
    final win = web.window as JSObject;
    if (!win.has('indexedDB') || !win.has('RTCPeerConnection')) return false;
    final idb = win['indexedDB'] as JSObject;
    final req = idb.callMethod<JSObject>('open'.toJS, 'estandarte'.toJS, 1.toJS);

    final db = await _idbOpen(req);
    var cert = await _idbGetCert(db);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final rtcCtor = win['RTCPeerConnection'] as JSFunction;
    final rtcCertCtor = win['RTCCertificate'] as JSFunction?;
    final isCert = cert != null && rtcCertCtor != null && cert.instanceof(rtcCertCtor);
    final expires = isCert ? ((cert['expires'] as JSNumber?)?.toDartDouble ?? 0) : 0;
    if (!isCert || expires - nowMs < 3 * 864e5) {
      final alg = JSObject();
      alg['name'] = 'ECDSA'.toJS;
      alg['namedCurve'] = 'P-256'.toJS;
      cert = await rtcCtor
          .callMethod<JSPromise<JSObject>>('generateCertificate'.toJS, alg)
          .toDart;
      await _idbPutCert(db, cert);
    }
    final fps = cert.callMethod<JSArray<JSObject>>('getFingerprints'.toJS).toDart;
    final hasSha256 = fps.any((f) => (f['algorithm'] as JSString?)?.toDart == 'sha-256');
    if (!hasSha256) return false;
    _cert = cert;
    return true;
  } catch (_) {
    return false;
  }
}

Future<JSObject> _idbOpen(JSObject req) {
  final c = Completer<JSObject>();
  req['onupgradeneeded'] = ((JSAny? _) {
    final res = req['result'] as JSObject;
    res.callMethod<JSAny?>('createObjectStore'.toJS, 'kv'.toJS);
  }).toJS;
  req['onsuccess'] = ((JSAny? _) {
    c.complete(req['result'] as JSObject);
  }).toJS;
  req['onerror'] = ((JSAny? _) {
    c.completeError(StateError('IndexedDB open failed'));
  }).toJS;
  return c.future;
}

Future<JSObject?> _idbGetCert(JSObject db) {
  final c = Completer<JSObject?>();
  final tx = db.callMethod<JSObject>('transaction'.toJS, 'kv'.toJS);
  final store = tx.callMethod<JSObject>('objectStore'.toJS, 'kv'.toJS);
  final q = store.callMethod<JSObject>('get'.toJS, 'cert'.toJS);
  q['onsuccess'] = ((JSAny? _) {
    final res = q['result'];
    c.complete((res != null && res.isA<JSObject>()) ? res as JSObject : null);
  }).toJS;
  q['onerror'] = ((JSAny? _) => c.completeError(StateError('idb get'))).toJS;
  return c.future;
}

Future<void> _idbPutCert(JSObject db, JSObject cert) {
  final c = Completer<void>();
  final tx = db.callMethod<JSObject>('transaction'.toJS, 'kv'.toJS, 'readwrite'.toJS);
  final store = tx.callMethod<JSObject>('objectStore'.toJS, 'kv'.toJS);
  store.callMethod<JSAny?>('put'.toJS, cert, 'cert'.toJS);
  tx['oncomplete'] = ((JSAny? _) => c.complete()).toJS;
  tx['onerror'] = ((JSAny? _) => c.completeError(StateError('idb put'))).toJS;
  return c.future;
}

class _RtcGameLink extends GameLink {
  _RtcGameLink(
    this._pc,
    this._dc, {
    required void Function(GameLink link) onOpen,
    required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
    required void Function(GameLink link) onClose,
  }) {
    void down([JSAny? _]) {
      if (_closed) return;
      _closed = true;
      _open = false;
      onClose(this);
    }

    void up([JSAny? _]) {
      if (_open || _closed) return;
      _open = true;
      onOpen(this);
    }

    _dc['onopen'] = up.toJS;
    if ((_dc['readyState'] as JSString?)?.toDart == 'open') {
      scheduleMicrotask(up);
    }
    _dc['onmessage'] = ((JSObject e) {
      try {
        final raw = (e['data'] as JSString?)?.toDart;
        if (raw == null) return;
        final m = jsonDecode(raw);
        if (m is Map<String, dynamic>) {
          onMessage(m, this);
        }
      } catch (_) {}
    }).toJS;
    _dc['onclose'] = down.toJS;
    _pc.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'connectionstatechange'.toJS,
      ((JSAny? _) {
        final st = (_pc['connectionState'] as JSString?)?.toDart;
        if (st == 'failed' || st == 'closed') down();
      }).toJS,
    );
  }

  final JSObject _pc;
  final JSObject _dc;
  bool _open = false;
  bool _closed = false;

  @override
  bool get isOpen => _open;

  @override
  String? get peerFp {
    final rd = _pc['remoteDescription'] as JSObject?;
    final sdp = (rd?['sdp'] as JSString?)?.toDart ?? '';
    final m = RegExp(r'a=fingerprint:sha-256 ([0-9A-Fa-f:]+)').firstMatch(sdp);
    if (m == null) return null;
    final bytes = m.group(1)!.split(':').map((h) => int.parse(h, radix: 16)).toList();
    return b64uEncode(bytes);
  }

  @override
  void send(Map<String, dynamic> msg) {
    if ((_dc['readyState'] as JSString?)?.toDart == 'open') {
      _dc.callMethod<JSAny?>('send'.toJS, jsonEncode(msg).toJS);
    }
  }

  @override
  void close() {
    try {
      _dc.callMethod<JSAny?>('close'.toJS);
    } catch (_) {}
    try {
      _pc.callMethod<JSAny?>('close'.toJS);
    } catch (_) {}
  }
}

Future<void> _gathered(JSObject pc) {
  bool hasCand() {
    final ld = pc['localDescription'] as JSObject?;
    final sdp = (ld?['sdp'] as JSString?)?.toDart ?? '';
    return sdp.contains('a=candidate:');
  }

  if ((pc['iceGatheringState'] as JSString?)?.toDart == 'complete') {
    return hasCand() ? Future.value() : Future.error(StateError('sem-rede'));
  }
  final c = Completer<void>();
  Timer? timer;
  void finish() {
    timer?.cancel();
    if (c.isCompleted) return;
    if (hasCand()) {
      c.complete();
    } else {
      c.completeError(StateError('sem-rede'));
    }
  }

  timer = Timer(_gatherTimeout, () {
    if (hasCand()) {
      finish();
    } else {
      timer = Timer(const Duration(seconds: 4), finish);
    }
  });

  pc.callMethod<JSAny?>(
    'addEventListener'.toJS,
    'icegatheringstatechange'.toJS,
    ((JSAny? _) {
      if ((pc['iceGatheringState'] as JSString?)?.toDart == 'complete') {
        finish();
      }
    }).toJS,
  );
  return c.future;
}

({String type, String sdp}) _readLocalDesc(JSObject pc) {
  final ld = pc['localDescription'] as JSObject;
  return (
    type: (ld['type'] as JSString).toDart,
    sdp: (ld['sdp'] as JSString).toDart,
  );
}

JSObject _makeDesc(String type, String sdp) {
  final d = JSObject();
  d['type'] = type.toJS;
  d['sdp'] = sdp.toJS;
  return d;
}

String _token(int n) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(n, (_) => chars[_rng.nextInt(chars.length)]).join();
}

Future<P2PInvite> createInvite({
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) async {
  final pc = _newPc();
  final dcOpts = JSObject();
  dcOpts['ordered'] = true.toJS;
  final dc = pc.callMethod<JSObject>('createDataChannel'.toJS, 'jogo'.toJS, dcOpts);
  final link = _RtcGameLink(pc, dc, onOpen: onOpen, onMessage: onMessage, onClose: onClose);
  final offer = await pc.callMethod<JSPromise<JSObject>>('createOffer'.toJS).toDart;
  await pc.callMethod<JSPromise<JSAny?>>('setLocalDescription'.toJS, offer).toDart;
  await _gathered(pc);
  final ld = _readLocalDesc(pc);
  return P2PInvite(
    code: packSdp(type: ld.type, sdp: ld.sdp),
    link: link,
    accept: (answerCode) async {
      final ans = unpackSdp(answerCode);
      await pc
          .callMethod<JSPromise<JSAny?>>(
            'setRemoteDescription'.toJS,
            _makeDesc(ans.type, ans.sdp),
          )
          .toDart;
    },
    cancel: () => link.close(),
  );
}

Future<P2PJoinResult> joinInvite(
  String offerCode, {
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) async {
  final offer = unpackSdp(offerCode);
  if (offer.type != 'offer') {
    throw FormatException('Este código não é um convite.');
  }
  final pc = _newPc();
  GameLink? created;
  pc['ondatachannel'] = ((JSObject e) {
    final dc = e['channel'] as JSObject;
    created = _RtcGameLink(pc, dc, onOpen: onOpen, onMessage: onMessage, onClose: onClose);
  }).toJS;
  await pc
      .callMethod<JSPromise<JSAny?>>(
        'setRemoteDescription'.toJS,
        _makeDesc(offer.type, offer.sdp),
      )
      .toDart;
  final ans = await pc.callMethod<JSPromise<JSObject>>('createAnswer'.toJS).toDart;
  await pc.callMethod<JSPromise<JSAny?>>('setLocalDescription'.toJS, ans).toDart;
  await _gathered(pc);
  final ld = _readLocalDesc(pc);
  return P2PJoinResult(
    code: packSdp(type: ld.type, sdp: ld.sdp),
    getLink: () => created,
    cancel: () {
      try {
        pc.callMethod<JSAny?>('close'.toJS);
      } catch (_) {}
    },
  );
}

Future<P2PArmedSpare> armSpare(
  String guestFp, {
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) async {
  final pc = _newPc();
  final dcOpts = JSObject();
  dcOpts['negotiated'] = true.toJS;
  dcOpts['id'] = 0.toJS;
  final dc = pc.callMethod<JSObject>('createDataChannel'.toJS, 'jogo'.toJS, dcOpts);
  final link = _RtcGameLink(pc, dc, onOpen: onOpen, onMessage: onMessage, onClose: onClose);
  final offer = await pc.callMethod<JSPromise<JSObject>>('createOffer'.toJS).toDart;
  await pc.callMethod<JSPromise<JSAny?>>('setLocalDescription'.toJS, offer).toDart;
  await _gathered(pc);
  final gu = _token(8);
  final gp = _token(24);
  final remote = unpackSdp(['1', 'aa', gu, gp, guestFp, ''].join('~'));
  await pc
      .callMethod<JSPromise<JSAny?>>(
        'setRemoteDescription'.toJS,
        _makeDesc(remote.type, remote.sdp),
      )
      .toDart;
  final ld = _readLocalDesc(pc);
  return P2PArmedSpare(
    link: link,
    code: packSdp(type: ld.type, sdp: ld.sdp),
    gu: gu,
    gp: gp,
    cancel: () => link.close(),
  );
}

Future<P2PSpareAttempt> useSpare(
  Map<String, dynamic> spare, {
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) async {
  if (_cert == null) throw StateError('sem-certificado');
  final pc = _newPc();
  final dcOpts = JSObject();
  dcOpts['negotiated'] = true.toJS;
  dcOpts['id'] = 0.toJS;
  final dc = pc.callMethod<JSObject>('createDataChannel'.toJS, 'jogo'.toJS, dcOpts);
  final link = _RtcGameLink(pc, dc, onOpen: onOpen, onMessage: onMessage, onClose: onClose);
  final remote = unpackSdp(spare['code'] as String);
  await pc
      .callMethod<JSPromise<JSAny?>>(
        'setRemoteDescription'.toJS,
        _makeDesc(remote.type, remote.sdp),
      )
      .toDart;
  final ans = await pc.callMethod<JSPromise<JSObject>>('createAnswer'.toJS).toDart;
  var sdp = (ans['sdp'] as JSString).toDart;
  sdp = sdp
      .replaceFirst(RegExp(r'a=ice-ufrag:\S+'), 'a=ice-ufrag:${spare['gu']}')
      .replaceFirst(RegExp(r'a=ice-pwd:\S+'), 'a=ice-pwd:${spare['gp']}')
      .replaceFirst(RegExp(r'a=setup:\w+'), 'a=setup:active');
  await pc
      .callMethod<JSPromise<JSAny?>>('setLocalDescription'.toJS, _makeDesc('answer', sdp))
      .toDart;
  return P2PSpareAttempt(
    link: link,
    cancel: () => link.close(),
    opened: (timeout) async {
      final start = DateTime.now();
      while (!link.isOpen && DateTime.now().difference(start) < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return link.isOpen;
    },
  );
}
