import '../net/online_client.dart';
import 'lan_host.dart';
import 'web_env.dart';

bool lanHostSupported() => false;

bool lanJoinSupported() => WebEnv.getBaseUrl().startsWith('http://');

Future<LanServerHandle> startLanServer({
  int port = defaultLanPort,
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) =>
    Future.error(UnsupportedError('Navegadores não permitem abrir servidor TCP/WebSocket local.'));
