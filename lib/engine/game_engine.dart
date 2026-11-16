import 'dart:convert';

import 'game_engine_stub.dart'
    if (dart.library.js_interop) 'game_engine_web.dart'
    if (dart.library.ffi) 'game_engine_native.dart';

class EngineColor {
  const EngineColor({required this.name, required this.hex});

  final String name;
  final String hex;
}

class EventCatalogEntry {
  const EventCatalogEntry({
    required this.key,
    required this.name,
    required this.cont,
    required this.desc,
  });

  final String key;
  final String name;
  final bool cont;
  final String desc;
}

/// Ordem tática do Quartel (catálogo fixo do motor).
class OrderCatalogEntry {
  const OrderCatalogEntry({
    required this.key,
    required this.name,
    required this.cost,
    required this.desc,
  });

  final String key;
  final String name;
  final int cost;
  final String desc;
}

/// Ordem aberta na vitrine do Quartel, com o motivo de não poder comprar agora (vazio se pode).
class HqOrder {
  const HqOrder({
    required this.key,
    required this.name,
    required this.cost,
    required this.desc,
    required this.block,
  });

  final String key;
  final String name;
  final int cost;
  final String desc;
  final String block;
}

/// Relatório de espionagem sobre o jogador [q]: objetivos possíveis, um deles verdadeiro.
class HqIntel {
  const HqIntel({required this.q, required this.texts});

  final int q;
  final List<String> texts;
}

/// O que o motor diz sobre o Quartel para quem está olhando a partida.
class HqEval {
  const HqEval({
    required this.effort,
    required this.medalMax,
    required this.mobilizeCost,
    required this.mobilizeBlock,
    required this.orders,
    required this.spyBlocks,
    required this.sabotageBlocks,
    required this.trenchBlocks,
    required this.airliftBlocks,
    required this.intel,
  });

  /// Relatórios de espionagem de quem está olhando (só ele os recebe).
  final List<HqIntel> intel;
  final int effort;
  final int medalMax;
  final int mobilizeCost;
  final String mobilizeBlock;
  final List<HqOrder> orders;
  final Map<int, String> spyBlocks;
  final Map<int, String> sabotageBlocks;
  final Map<int, String> trenchBlocks;
  final Map<int, String> airliftBlocks;

  static HqEval? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    Map<int, String> strMap(String key) {
      final m = raw[key] as Map<String, dynamic>? ?? const {};
      return {for (final e in m.entries) int.parse(e.key): e.value.toString()};
    }

    final orders = (raw['orders'] as List<dynamic>? ?? const []).map((e) {
      final m = e as Map<String, dynamic>;
      return HqOrder(
        key: m['k'] as String? ?? '',
        name: m['n'] as String? ?? '',
        cost: (m['cost'] as num?)?.toInt() ?? 0,
        desc: m['desc'] as String? ?? '',
        block: m['block'] as String? ?? '',
      );
    }).toList();
    return HqEval(
      effort: (raw['effort'] as num?)?.toInt() ?? 4,
      medalMax: (raw['medalMax'] as num?)?.toInt() ?? 6,
      mobilizeCost: (raw['mobilizeCost'] as num?)?.toInt() ?? 3,
      mobilizeBlock: raw['mobilizeBlock'] as String? ?? '',
      orders: orders,
      spyBlocks: strMap('spyBlocks'),
      sabotageBlocks: strMap('sabotageBlocks'),
      trenchBlocks: strMap('trenchBlocks'),
      airliftBlocks: strMap('airliftBlocks'),
      intel: (raw['intel'] as List<dynamic>? ?? const []).map((e) {
        final m = e as Map<String, dynamic>;
        return HqIntel(
          q: (m['q'] as num?)?.toInt() ?? -1,
          texts: (m['texts'] as List<dynamic>? ?? const []).map((t) => t.toString()).toList(),
        );
      }).toList(),
    );
  }
}

class EngineConstants {
  const EngineConstants({
    required this.colors,
    required this.nt,
    required this.pactRounds,
    required this.pactPenalty,
    required this.pactCool,
    required this.events,
    required this.orders,
    required this.medalMax,
    required this.mobilizeCost,
  });

  final List<EngineColor> colors;
  final int nt;
  final int pactRounds;
  final int pactPenalty;
  final int pactCool;
  final List<EventCatalogEntry> events;
  final List<OrderCatalogEntry> orders;
  final int medalMax;
  final int mobilizeCost;

  factory EngineConstants.fromJson(Map<String, dynamic> j) {
    final cols = (j['colors'] as List<dynamic>? ?? const [])
        .map(
          (e) => EngineColor(
            name: (e as Map<String, dynamic>)['N'] as String? ?? '',
            hex: e['C'] as String? ?? '#999999',
          ),
        )
        .toList();
    final evs = (j['events'] as List<dynamic>? ?? const [])
        .map((e) {
          final m = e as Map<String, dynamic>;
          return EventCatalogEntry(
            key: m['k'] as String? ?? '',
            name: m['n'] as String? ?? '',
            cont: m['cont'] == true,
            desc: m['desc'] as String? ?? '',
          );
        })
        .toList();
    final ords = (j['orders'] as List<dynamic>? ?? const []).map((e) {
      final m = e as Map<String, dynamic>;
      return OrderCatalogEntry(
        key: m['k'] as String? ?? '',
        name: m['n'] as String? ?? '',
        cost: (m['cost'] as num?)?.toInt() ?? 0,
        desc: m['desc'] as String? ?? '',
      );
    }).toList();
    return EngineConstants(
      colors: cols,
      nt: (j['nt'] as num?)?.toInt() ?? 42,
      pactRounds: (j['pactRounds'] as num?)?.toInt() ?? 2,
      pactPenalty: (j['pactPenalty'] as num?)?.toInt() ?? 3,
      pactCool: (j['pactCool'] as num?)?.toInt() ?? 2,
      events: evs,
      orders: ords,
      medalMax: (j['medalMax'] as num?)?.toInt() ?? 6,
      mobilizeCost: (j['mobilizeCost'] as num?)?.toInt() ?? 3,
    );
  }
}

class EvalViewResult {
  const EvalViewResult({
    required this.tradeValue,
    required this.nukeDamage,
    required this.nukeRefund,
    required this.mustTrade,
    required this.pactPenalty,
    required this.eventText,
    required this.nukeBlock,
    required this.bestTrade,
    required this.nukeTrade,
    required this.attackBlocks,
    required this.moveBlocks,
    required this.directAttackFrom,
    required this.directAttackBlock,
    required this.nukeTargetBlocks,
    required this.nukeTargetDamages,
    required this.pactBlocks,
    required this.objectiveTexts,
    this.hq,
  });

  /// Só vem em partidas com Quartel.
  final HqEval? hq;
  final int tradeValue;
  final int nukeDamage;
  final int nukeRefund;
  final bool mustTrade;
  final int pactPenalty;
  final String eventText;
  final String nukeBlock;
  final List<int>? bestTrade;
  final List<int>? nukeTrade;
  final Map<int, String> attackBlocks;
  final Map<int, String> moveBlocks;
  final Map<int, int> directAttackFrom;
  final Map<int, String> directAttackBlock;
  final Map<int, String> nukeTargetBlocks;
  final Map<int, int> nukeTargetDamages;
  final Map<int, String> pactBlocks;
  final Map<int, String> objectiveTexts;

  factory EvalViewResult.fromJson(Map<String, dynamic> j) {
    Map<int, String> parseStrMap(String key) {
      final raw = j[key] as Map<String, dynamic>? ?? const {};
      return {for (final e in raw.entries) int.parse(e.key): e.value.toString()};
    }

    Map<int, int> parseIntMap(String key) {
      final raw = j[key] as Map<String, dynamic>? ?? const {};
      return {for (final e in raw.entries) int.parse(e.key): (e.value as num).toInt()};
    }

    final daFrom = <int, int>{};
    final daBlock = <int, String>{};
    final rawDa = j['directAttack'] as Map<String, dynamic>? ?? const {};
    for (final e in rawDa.entries) {
      final t = int.parse(e.key);
      final m = e.value as Map<String, dynamic>;
      if (m['from'] != null) daFrom[t] = (m['from'] as num).toInt();
      if (m['block'] != null) daBlock[t] = m['block'] as String;
    }

    return EvalViewResult(
      tradeValue: (j['tradeValue'] as num?)?.toInt() ?? 4,
      nukeDamage: (j['nukeDamage'] as num?)?.toInt() ?? 5,
      nukeRefund: (j['nukeRefund'] as num?)?.toInt() ?? 4,
      mustTrade: j['mustTrade'] == true,
      pactPenalty: (j['pactPenalty'] as num?)?.toInt() ?? 0,
      eventText: j['eventText'] as String? ?? '',
      nukeBlock: j['nukeBlock'] as String? ?? '',
      bestTrade: (j['bestTrade'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList(),
      nukeTrade: (j['nukeTrade'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList(),
      attackBlocks: parseStrMap('attackBlocks'),
      moveBlocks: parseStrMap('moveBlocks'),
      directAttackFrom: daFrom,
      directAttackBlock: daBlock,
      nukeTargetBlocks: parseStrMap('nukeTargetBlocks'),
      nukeTargetDamages: parseIntMap('nukeTargetDamages'),
      pactBlocks: parseStrMap('pactBlocks'),
      objectiveTexts: parseStrMap('objectiveTexts'),
      hq: HqEval.fromJson(j['hq']),
    );
  }
}

class GameEngine {
  GameEngine._(this._backend);

  static late GameEngine instance;
  final EngineBackend _backend;
  late final EngineConstants constants;

  static Future<GameEngine> init() async {
    final backend = createEngineBackend();
    await backend.init();
    final engine = GameEngine._(backend);
    engine.constants = engine._fetchConstants();
    instance = engine;
    return engine;
  }

  Map<String, dynamic> callJson(String op, [Object? payload]) {
    final encoded = payload == null
        ? '{}'
        : payload is String
            ? payload
            : jsonEncode(payload);
    final raw = _backend.call(op, encoded);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      throw StateError('Engine error in $op: ${decoded['error']}');
    }
    return decoded;
  }

  EngineConstants _fetchConstants() => EngineConstants.fromJson(callJson('constants'));

  int newGame({
    required List<Map<String, dynamic>> seats,
    required Map<String, dynamic> opts,
    int? seed,
  }) {
    final res = callJson('newGame', {
      'seats': seats,
      'opts': opts,
      'seed': ?seed,
    });
    return (res['id'] as num).toInt();
  }

  int loadGame(Map<String, dynamic> state) {
    final res = callJson('loadGame', state);
    return (res['id'] as num).toInt();
  }

  Map<String, dynamic> exportGame(int id) => callJson('exportGame', {'id': id});

  void dropGame(int id) => callJson('dropGame', {'id': id});

  void setPlayerCtrl(int id, int player, String ctrl) =>
      callJson('setPlayerCtrl', {'id': id, 'player': player, 'ctrl': ctrl});

  String apply(int id, int player, Map<String, dynamic> action) {
    final res = callJson('apply', {'id': id, 'player': player, 'action': action});
    return res['err'] as String? ?? '';
  }

  Map<String, dynamic> viewFor(int id, int player) =>
      callJson('viewFor', {'id': id, 'player': player});

  Map<String, dynamic>? botAction(int id, {bool noNuke = false}) {
    final raw = _backend.call('botAction', jsonEncode({'id': id, 'noNuke': noNuke}));
    if (raw == 'null') return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('error')) {
        throw StateError('Engine error in botAction: ${decoded['error']}');
      }
      return decoded;
    }
    return null;
  }

  Map<String, dynamic>? botPactReply(int id) {
    final raw = _backend.call('botPactReply', jsonEncode({'id': id}));
    if (raw == 'null') return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('error')) {
        throw StateError('Engine error in botPactReply: ${decoded['error']}');
      }
      return decoded;
    }
    return null;
  }

  void forceEnd(int id) => callJson('forceEnd', {'id': id});

  EvalViewResult evalView({
    required Map<String, dynamic> view,
    required int viewer,
    int? sel,
    bool nuke = false,
  }) {
    final res = callJson('evalView', {
      'view': view,
      'viewer': viewer,
      'sel': ?sel,
      'nuke': nuke,
    });
    return EvalViewResult.fromJson(res);
  }

  bool validTrade(List<int> cards) {
    final res = callJson('validTrade', {'cards': cards});
    return res['valid'] == true;
  }

  ({int symbol, String name}) cardInfo(int card) {
    final res = callJson('cardInfo', {'card': card});
    return (
      symbol: (res['symbol'] as num).toInt(),
      name: res['name'] as String? ?? '',
    );
  }
}

abstract class EngineBackend {
  Future<void> init();
  String call(String op, String payload);
}
