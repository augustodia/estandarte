import 'dart:ui';

import '../net/online_client.dart';

enum AppScreen { home, rooms, corr, friends, lobby, daily, game }

/// Início de um turno no replay (para pular de turno em turno).
class ReplayTurn {
  const ReplayTurn(this.step, this.round, this.turn);
  final int step;
  final int round;
  final int turn;
}

/// Replay aberto: a partida refeita pelo motor, passo a passo.
class ReplaySession {
  ReplaySession({
    required this.code,
    required this.engineId,
    required this.steps,
    required this.turns,
    required this.meta,
    required this.rep,
    this.proof = const [],
  });

  /// Por jogador (na ordem da partida): nome, chaves usadas, contribuição e quem fez as jogadas (assinadas, sem
  /// assinatura, bot, prazo esgotado, aparelhos).
  final List<Map<String, dynamic>> proof;

  final String code;
  final int engineId;
  final int steps;
  final List<ReplayTurn> turns;
  final Map<String, dynamic> meta;
  final Map<String, dynamic> rep;
  int pos = 0;
  bool playing = false;
  int speed = 1;

  /// Índice do turno em que o replay está.
  int get turnIndex {
    var i = 0;
    for (var k = 0; k < turns.length; k++) {
      if (turns[k].step <= pos) i = k;
    }
    return i;
  }

  String get commit => rep['commit'] as String? ?? '';
  String get server => rep['server'] as String? ?? '';
  List<String> get clients => [for (final c in (rep['clients'] as List<dynamic>? ?? const [])) '$c'];
}

class LobbySeat {
  LobbySeat({
    required this.name,
    required this.color,
    required this.ctrl,
    this.online = false,
    this.lag = false,
    this.seenMs = 0,
    this.token,
    this.link,
    this.spare,
  });

  String name;
  int color;
  String ctrl; // 'local' | 'bot' | 'remote'
  bool online;
  bool lag;
  int seenMs;
  String? token;
  GameLink? link;
  Map<String, dynamic>? spare;

  Map<String, dynamic> toEngineSeat() => {
        'name': name,
        'color': color,
        'ctrl': ctrl,
      };

  Map<String, dynamic> toLobbyJson() => {
        'name': name,
        'color': color,
        'ctrl': ctrl,
        'on': link != null && link!.isOpen,
      };
}

class MapPulse {
  const MapPulse({
    required this.terr,
    required this.color,
    required this.startMs,
    this.durMs = 700,
  });

  final int terr;
  final Color color;
  final int startMs;
  final int durMs;
}

class MapStrike {
  const MapStrike({
    required this.from,
    required this.to,
    required this.color,
    required this.won,
    required this.startMs,
    this.durMs = 520,
  });

  final int from;
  final int to;
  final Color color;
  final bool won;
  final int startMs;
  final int durMs;
}

class MapArrow {
  const MapArrow({
    required this.from,
    required this.to,
    required this.color,
    required this.startMs,
    this.durMs = 700,
  });

  final int from;
  final int to;
  final Color color;
  final int startMs;
  final int durMs;
}

class MapFloatText {
  const MapFloatText({
    required this.terr,
    required this.text,
    required this.color,
    required this.startMs,
    this.durMs = 950,
  });

  final int terr;
  final String text;
  final Color color;
  final int startMs;
  final int durMs;
}

class MissileCinema {
  const MissileCinema({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    required this.targetTerr,
    required this.startMs,
    required this.alarmMs,
    required this.flightMs,
  });

  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final int targetTerr;
  final int startMs;
  final int alarmMs;
  final int flightMs;
}

class NukeImpactFx {
  const NukeImpactFx({
    required this.terr,
    required this.x,
    required this.y,
    required this.startMs,
  });

  final int terr;
  final double x;
  final double y;
  final int startMs;
}

class DiceBannerState {
  const DiceBannerState({
    required this.att,
    required this.def,
    required this.attName,
    required this.attColor,
    required this.defName,
    required this.defColor,
    required this.low,
    required this.untilMs,
  });

  final List<int> att;
  final List<int> def;
  final String attName;
  final Color attColor;
  final String defName;
  final Color defColor;
  final bool low;
  final int untilMs;
}

class FlashBannerState {
  const FlashBannerState({
    required this.title,
    required this.color,
    required this.sub,
    required this.big,
    required this.top,
    required this.durMs,
    required this.urgent,
    required this.untilMs,
  });

  final String title;
  final Color color;
  final String sub;
  final bool big;
  final bool top;
  final int durMs;
  final bool urgent;
  final int untilMs;
}

class OnlineSession {
  OnlineSession({
    required this.server,
    this.code,
    required this.host,
    required this.fromRooms,
    required this.name,
    this.token,
    this.owner = false,
    this.isPublic = false,
    this.lan = false,
    this.corr = false,
    this.gone = false,
    this.waitMsg = '',
  });

  final String server;
  String? code;
  final bool host;
  final bool fromRooms;
  final String name;
  String? token;
  bool owner;
  bool isPublic;
  final bool lan;

  /// Partida por correspondência (24 h por jogada): fica no servidor, sair só fecha neste aparelho.
  final bool corr;
  bool gone;
  String waitMsg;
  GameLink? pendingLink;
}
