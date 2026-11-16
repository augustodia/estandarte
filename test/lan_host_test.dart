import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:estandarte/net/online_client.dart';
import 'package:estandarte/platform/lan_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseLanWsUrl normalizes IP, IP:port, and schemes cleanly', () {
    expect(parseLanWsUrl('192.168.1.15'), 'ws://192.168.1.15:7788');
    expect(parseLanWsUrl('192.168.1.15:9001'), 'ws://192.168.1.15:9001');
    expect(parseLanWsUrl('http://10.0.0.4:7788/ws'), 'ws://10.0.0.4:7788');
    expect(parseLanWsUrl('ws://localhost:7788'), 'ws://localhost:7788');
    expect(parseLanWsUrl(''), isNull);
    expect(parseLanWsUrl('http://'), isNull);
  });

  test('LanHost starts native WebSocket server, accepts /ws and closes cleanly', () async {
    expect(LanHost.supported, isTrue);

    GameLink? peerLink;
    final opened = Completer<void>();
    final echoed = Completer<Map<String, dynamic>>();
    final closed = Completer<void>();

    final srv = await LanHost.start(
      port: 0,
      onOpen: (link) {
        peerLink = link;
        if (!opened.isCompleted) opened.complete();
      },
      onMessage: (msg, link) {
        link.send({'t': 'pong', 'got': msg['t']});
        if (!echoed.isCompleted) echoed.complete(msg);
      },
      onClose: (_) {
        if (!closed.isCompleted) closed.complete();
      },
    );

    try {
      expect(srv.port, greaterThan(0));
      expect(srv.primaryAddress, contains(':${srv.port}'));

      final httpClient = HttpClient();
      final req = await httpClient.get('127.0.0.1', srv.port, '/healthz');
      final res = await req.close();
      expect(res.statusCode, 200);
      final body = await res.transform(utf8.decoder).join();
      expect(jsonDecode(body), {'ok': true});
      httpClient.close();

      final ws = await WebSocket.connect('ws://127.0.0.1:${srv.port}/ws?room=lan');
      await opened.future.timeout(const Duration(seconds: 3));
      expect(peerLink?.isOpen, isTrue);

      final reply = Completer<Map<String, dynamic>>();
      ws.listen((data) {
        final decoded = jsonDecode(data as String) as Map<String, dynamic>;
        if (!reply.isCompleted) reply.complete(decoded);
      });

      ws.add(jsonEncode({'t': 'hello', 'name': 'Beto'}));
      final got = await echoed.future.timeout(const Duration(seconds: 3));
      expect(got['name'], 'Beto');

      final pong = await reply.future.timeout(const Duration(seconds: 3));
      expect(pong['got'], 'hello');

      await ws.close();
      await closed.future.timeout(const Duration(seconds: 3));
    } finally {
      await srv.close();
    }
  });
}
