import '../net/online_client.dart';
import 'p2p_native.dart' if (dart.library.js_interop) 'p2p_web.dart' as impl;

class P2PInvite {
  const P2PInvite({
    required this.code,
    required this.link,
    required this.accept,
    required this.cancel,
  });

  final String code;
  final GameLink link;
  final Future<void> Function(String answerCode) accept;
  final void Function() cancel;
}

class P2PJoinResult {
  const P2PJoinResult({
    required this.code,
    required this.getLink,
    required this.cancel,
  });

  final String code;
  final GameLink? Function() getLink;
  final void Function() cancel;
}

class P2PArmedSpare {
  const P2PArmedSpare({
    required this.link,
    required this.code,
    required this.gu,
    required this.gp,
    required this.cancel,
  });

  final GameLink link;
  final String code;
  final String gu;
  final String gp;
  final void Function() cancel;
}

class P2PSpareAttempt {
  const P2PSpareAttempt({
    required this.link,
    required this.cancel,
    required this.opened,
  });

  final GameLink link;
  final void Function() cancel;
  final Future<bool> Function(Duration timeout) opened;
}

abstract final class P2P {
  static bool get supported => impl.p2pSupported();
  static Future<bool> initCert() => impl.initCert();

  static Future<P2PInvite> createInvite({
    required void Function(GameLink link) onOpen,
    required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
    required void Function(GameLink link) onClose,
  }) =>
      impl.createInvite(onOpen: onOpen, onMessage: onMessage, onClose: onClose);

  static Future<P2PJoinResult> joinInvite(
    String offerCode, {
    required void Function(GameLink link) onOpen,
    required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
    required void Function(GameLink link) onClose,
  }) =>
      impl.joinInvite(offerCode, onOpen: onOpen, onMessage: onMessage, onClose: onClose);

  static Future<P2PArmedSpare> armSpare(
    String guestFp, {
    required void Function(GameLink link) onOpen,
    required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
    required void Function(GameLink link) onClose,
  }) =>
      impl.armSpare(guestFp, onOpen: onOpen, onMessage: onMessage, onClose: onClose);

  static Future<P2PSpareAttempt> useSpare(
    Map<String, dynamic> spare, {
    required void Function(GameLink link) onOpen,
    required void Function(Map<String, dynamic> msg, GameLink link) onMessage,
    required void Function(GameLink link) onClose,
  }) =>
      impl.useSpare(spare, onOpen: onOpen, onMessage: onMessage, onClose: onClose);
}
