import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../platform/storage.dart';
import '../platform/web_env.dart';

const String defaultServerUrl = String.fromEnvironment(
  'ESTANDARTE_SERVER_URL',
  defaultValue: 'wss://estandarte-backend.onrender.com',
);
const String _serverStorageKey = 'estandarte.server';

bool allowedServer(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  try {
    final normalized = raw.replaceFirst(RegExp(r'^http'), 'ws');
    final u = Uri.parse(normalized);
    if (u.scheme != 'ws' && u.scheme != 'wss') return false;
    final def = Uri.parse(defaultServerUrl.replaceFirst(RegExp(r'^http'), 'ws'));
    if (u.scheme == def.scheme && u.host == def.host && u.port == def.port) {
      return true;
    }
    final h = u.host.toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h == '[::1]' ||
        h.endsWith('.local') ||
        RegExp(r'^10\.').hasMatch(h) ||
        RegExp(r'^192\.168\.').hasMatch(h) ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h);
  } catch (_) {
    return false;
  }
}

String serverUrl() {
  if (WebEnv.hasQueryParam('server')) {
    final v = (WebEnv.getQueryParam('server') ?? '').trim();
    if (v.isEmpty) {
      AppStorage.instance.remove(_serverStorageKey);
    } else if (allowedServer(v)) {
      AppStorage.instance.setString(_serverStorageKey, v);
    }
  }
  var s = defaultServerUrl;
  final saved = AppStorage.instance.getString(_serverStorageKey);
  if (saved != null && allowedServer(saved)) {
    s = saved;
  }
  return s.replaceFirst(RegExp(r'^http'), 'ws').replaceAll(RegExp(r'/+$'), '');
}

String? roomCode(String? raw) {
  final s = (raw ?? '').trim();
  final m1 = RegExp(r'[?&]sala=([A-Za-z0-9]{5})').firstMatch(s);
  if (m1 != null) return m1.group(1)!.toUpperCase();
  final m2 = RegExp(r'^([A-Za-z0-9]{5})$').firstMatch(s);
  return m2?.group(1)!.toUpperCase();
}

abstract class GameLink {
  bool get isOpen;
  String? get peerFp => null;
  void send(Map<String, dynamic> msg);
  void close();
}

class OnlineLink extends GameLink {
  OnlineLink._();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _open = false;
  bool _stopped = false;
  int _tries = 0;
  Timer? _retryTimer;

  @override
  bool get isOpen => _open;

  @override
  void send(Map<String, dynamic> msg) {
    if (!_open) return;
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  @override
  void close() {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _open = false;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}

OnlineLink connectOnline(
  String server,
  String query, {
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
  void Function(int seconds, int tries)? onWait,
  void Function()? onFail,
}) {
  final started = DateTime.now();
  final link = OnlineLink._();
  final httpBase = server.replaceFirst(RegExp(r'^ws'), 'http');

  void wake() {
    http.get(Uri.parse('$httpBase/healthz')).then((_) {}, onError: (_) {});
  }

  void attempt() {
    if (link._stopped) return;
    link._tries++;
    WebSocketChannel ws;
    try {
      ws = WebSocketChannel.connect(Uri.parse('$server/ws?$query'));
    } catch (_) {
      onFail?.call();
      return;
    }
    link._channel = ws;
    var opened = false;

    void handleClosed() {
      if (opened) {
        link._open = false;
        onClose(link);
        return;
      }
      if (link._stopped) return;
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      if (elapsedMs > 100000) {
        onFail?.call();
        return;
      }
      onWait?.call((elapsedMs / 1000).round(), link._tries);
      if (link._tries % 4 == 1) wake();
      final delayMs = (800 * link._tries).clamp(800, 4000);
      link._retryTimer = Timer(Duration(milliseconds: delayMs), attempt);
    }

    ws.ready.then((_) {
      if (link._stopped) {
        ws.sink.close();
        return;
      }
      opened = true;
      link._open = true;
      onOpen(link);
    }).catchError((_) {
      // Errors arrive on stream onError/onDone too; handle if stream never opens cleanly.
    });

    link._sub = ws.stream.listen(
      (data) {
        if (!opened && !link._stopped) {
          opened = true;
          link._open = true;
          onOpen(link);
        }
        if (data is! String) return;
        try {
          final m = jsonDecode(data);
          if (m is Map<String, dynamic> && m['t'] is String) {
            onMessage(m, link);
          }
        } catch (_) {}
      },
      onError: (_) {
        link._sub?.cancel();
        link._sub = null;
        handleClosed();
      },
      onDone: () {
        link._sub = null;
        handleClosed();
      },
      cancelOnError: true,
    );
  }

  wake();
  attempt();
  return link;
}

String _httpBase(String server) => server.replaceFirst(RegExp(r'^ws'), 'http');

Future<Map<String, dynamic>> listRooms(String server, {Duration timeout = const Duration(seconds: 75)}) async {
  final r = await http
      .get(
        Uri.parse('${_httpBase(server)}/rooms?_=${DateTime.now().millisecondsSinceEpoch}'),
      )
      .timeout(timeout);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('http ${r.statusCode}');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> fetchDailyChallenge(
  String server, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final r = await http
      .get(
        Uri.parse('${_httpBase(server)}/daily?_=${DateTime.now().millisecondsSinceEpoch}'),
      )
      .timeout(timeout);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('http ${r.statusCode}');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> startDailyRun(
  String server, {
  required String clientId,
  required String difficulty,
  required String platform,
  required String appVersion,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final r = await http
      .post(
        Uri.parse('${_httpBase(server)}/daily/start'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientId': clientId,
          'difficulty': difficulty,
          'platform': platform,
          'appVersion': appVersion,
        }),
      )
      .timeout(timeout);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('http ${r.statusCode}');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> submitDailyRun(
  String server,
  Map<String, dynamic> payload, {
  String? accountToken,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final r = await http
      .post(
        Uri.parse('${_httpBase(server)}/daily/submit'),
        // com conta, o servidor grava o resultado nela (nome da conta, vale em qualquer aparelho)
        headers: {
          'Content-Type': 'application/json',
          if (accountToken != null && accountToken.isNotEmpty) 'Authorization': 'Bearer $accountToken',
        },
        body: jsonEncode(payload),
      )
      .timeout(timeout);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('http ${r.statusCode}');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> fetchDailyRanking(
  String server, {
  String? date,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final q = date != null && date.isNotEmpty ? '?date=${Uri.encodeQueryComponent(date)}' : '';
  final r = await http
      .get(Uri.parse('${_httpBase(server)}/daily/ranking$q'))
      .timeout(timeout);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('http ${r.statusCode}');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<void> sendMetricsBatch(
  String server,
  List<Map<String, dynamic>> events, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (events.isEmpty) return;
  final r = await http
      .post(
        Uri.parse('${_httpBase(server)}/metrics'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'events': events}),
      )
      .timeout(timeout);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('http ${r.statusCode}');
  }
}
