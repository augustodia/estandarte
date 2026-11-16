import '../net/online_client.dart';
import 'p2p.dart';

bool p2pSupported() => false;

Future<bool> initCert() async => false;

Future<P2PInvite> createInvite({
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) =>
    Future.error(UnsupportedError('Rede local por QR code requer navegador ou flutter_webrtc nativo.'));

Future<P2PJoinResult> joinInvite(
  String offerCode, {
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) =>
    Future.error(UnsupportedError('Rede local por QR code requer navegador ou flutter_webrtc nativo.'));

Future<P2PArmedSpare> armSpare(
  String guestFp, {
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) =>
    Future.error(UnsupportedError('Conexão reserva P2P disponível apenas na versão Web.'));

Future<P2PSpareAttempt> useSpare(
  Map<String, dynamic> spare, {
  required void Function(GameLink link) onOpen,
  required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
  required void Function(GameLink link) onClose,
}) =>
    Future.error(UnsupportedError('Conexão reserva P2P disponível apenas na versão Web.'));
