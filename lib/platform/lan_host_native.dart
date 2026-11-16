import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../net/online_client.dart';
import 'lan_host.dart';

bool lanHostSupported() => true;

bool lanJoinSupported() => true;

class _IoWsGameLink extends GameLink {
  _IoWsGameLink(
    this._ws, {
    required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
    required void Function(GameLink link) onClose,
  }) {
    _sub = _ws.listen(
      (data) {
        if (data is! String) return;
        try {
          final m = jsonDecode(data);
          if (m is Map<String, dynamic> && m['t'] is String) {
            onMessage(m, this);
          }
        } catch (_) {}
      },
      onError: (_) => _finish(onClose),
      onDone: () => _finish(onClose),
      cancelOnError: true,
    );
  }

  final WebSocket _ws;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  void _finish(void Function(GameLink link) onClose) {
    if (_closed) return;
    _closed = true;
    onClose(this);
  }

  @override
  bool get isOpen => !_closed && _ws.readyState == WebSocket.open;

  @override
  void send(Map<String, dynamic> msg) {
    if (!isOpen) return;
    try {
      _ws.add(jsonEncode(msg));
    } catch (_) {}
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _sub?.cancel();
    _sub = null;
    try {
      unawaited(_ws.close());
    } catch (_) {}
  }
}

class _IoLanServerHandle implements LanServerHandle {
  _IoLanServerHandle(this._server, this._links, this.addresses);

  final HttpServer _server;
  final Set<_IoWsGameLink> _links;

  @override
  int get port => _server.port;

  @override
  final List<String> addresses;

  @override
  String get primaryAddress => addresses.isNotEmpty ? addresses.first : '127.0.0.1:$port';

  @override
  Future<void> close() async {
    for (final l in _links.toList()) {
      l.close();
    }
    _links.clear();
    await _server.close(force: true);
  }
}

Future<List<String>> _detectLanAddresses(int port) async {
  final candidates = <(int score, String addr)>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      final lowName = iface.name.toLowerCase();
      final isVirtual = lowName.contains('vethernet') ||
          lowName.contains('wsl') ||
          lowName.contains('virtualbox') ||
          lowName.contains('vmware') ||
          lowName.contains('docker') ||
          lowName.contains('loopback');
      for (final a in iface.addresses) {
        final ip = a.address;
        if (ip.startsWith('169.254.')) continue; // link-local sem DHCP
        var score = isVirtual ? 10 : 0;
        if (ip.startsWith('192.168.')) {
          score += 0;
        } else if (ip.startsWith('10.')) {
          score += 1;
        } else if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
          score += 2;
        } else {
          score += 5;
        }
        candidates.add((score, '$ip:$port'));
      }
    }
  } catch (_) {}
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  final unique = <String>[];
  for (final c in candidates) {
    if (!unique.contains(c.$2)) unique.add(c.$2);
  }
  if (unique.isEmpty) unique.add('127.0.0.1:$port');
  return unique;
}

Future<LanServerHandle> startLanServer({
  int port = defaultLanPort,
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) async {
  HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  } catch (_) {
    server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
  }

  final links = <_IoWsGameLink>{};
  server.listen((req) async {
    if (req.uri.path == '/healthz') {
      req.response.headers
        ..set('Access-Control-Allow-Origin', '*')
        ..set('Cache-Control', 'no-store')
        ..set('Content-Type', 'application/json');
      req.response.write('{"ok":true}');
      await req.response.close();
      return;
    }
    if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        late final _IoWsGameLink link;
        link = _IoWsGameLink(
          ws,
          onMessage: onMessage,
          onClose: (l) {
            links.remove(l);
            onClose(l);
          },
        );
        links.add(link);
        onOpen(link);
      } catch (_) {}
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  });

  final addrs = await _detectLanAddresses(server.port);
  return _IoLanServerHandle(server, links, addrs);
}
