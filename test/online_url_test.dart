import 'package:estandarte/net/online_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allowedServer allows official backend and LAN/local targets only', () {
    expect(allowedServer(defaultServerUrl), true);
    expect(allowedServer('ws://localhost:8080'), true);
    expect(allowedServer('ws://127.0.0.1:8080'), true);
    expect(allowedServer('ws://192.168.1.50:8080'), true);
    expect(allowedServer('ws://10.0.0.2:8080'), true);
    expect(allowedServer('wss://evil.example.com/ws'), false);
    expect(allowedServer('javascript:alert(1)'), false);
  });

  test('roomCode extracts 5-char codes from bare text or URL', () {
    expect(roomCode('a7k3p'), 'A7K3P');
    expect(roomCode('https://example.com/estandarte/?sala=b9x2q'), 'B9X2Q');
    expect(roomCode('invalid-code'), null);
  });
}
