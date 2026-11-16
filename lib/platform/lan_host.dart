import '../net/online_client.dart';
import 'lan_host_native.dart' if (dart.library.js_interop) 'lan_host_web.dart' as impl;

const int defaultLanPort = 7788;

abstract class LanServerHandle {
  int get port;
  String get primaryAddress;
  List<String> get addresses;
  Future<void> close();
}

String? parseLanWsUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('https://')) {
    s = 'wss://${s.substring(8)}';
  } else if (s.startsWith('http://')) {
    s = 'ws://${s.substring(7)}';
  } else if (!s.startsWith('ws://') && !s.startsWith('wss://')) {
    s = 'ws://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme == 'wss' ? 'wss' : 'ws';
  final port = uri.hasPort ? uri.port : defaultLanPort;
  if (port <= 0 || port > 65535) return null;
  final host = uri.host.contains(':') && !uri.host.startsWith('[') ? '[${uri.host}]' : uri.host;
  return '$scheme://$host:$port';
}

abstract final class LanHost {
  /// Verdadeiro em plataformas nativas (Windows, macOS, Linux, Android, iOS) com dart:io.
  static bool get supported => impl.lanHostSupported();

  /// Verdadeiro onde é possível conectar via IP/WebSocket local (nativos, ou Web em HTTP local).
  static bool get canJoinByIp => impl.lanJoinSupported();

  static Future<LanServerHandle> start({
    int port = defaultLanPort,
    required void Function(GameLink link) onOpen,
    required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
    required void Function(GameLink link) onClose,
  }) =>
      impl.startLanServer(
        port: port,
        onOpen: onOpen,
        onMessage: onMessage,
        onClose: onClose,
      );
}
