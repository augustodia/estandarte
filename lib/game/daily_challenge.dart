import '../core/map_data.dart';

class ChallengeRuleTag {
  const ChallengeRuleTag({
    required this.key,
    required this.name,
    required this.desc,
  });

  final String key;
  final String name;
  final String desc;

  factory ChallengeRuleTag.fromJson(Map<String, dynamic> json) => ChallengeRuleTag(
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        desc: json['desc'] as String? ?? '',
      );
}

class ChallengeGoal {
  const ChallengeGoal({
    required this.kind,
    required this.title,
    this.requiredTerritories = const [],
    this.mustKeepTerritories = const [],
    this.fatalLoss = false,
    this.strikeTerritories = const [],
    this.minStrikeCount = 0,
    this.surviveRounds = 0,
    this.targetCount = 0,
    this.requiredContinents = const [],
    required this.maxRounds,
    required this.star1Desc,
    required this.star2MaxRound,
    required this.star2Desc,
    required this.star3Rule,
    this.star3Target = 0,
    required this.star3Desc,
  });

  final String kind;
  final String title;
  final List<int> requiredTerritories;
  final List<int> mustKeepTerritories;
  final bool fatalLoss;
  final List<int> strikeTerritories;
  final int minStrikeCount;
  final int surviveRounds;
  final int targetCount;
  final List<int> requiredContinents;
  final int maxRounds;
  final String star1Desc;
  final int star2MaxRound;
  final String star2Desc;
  final String star3Rule;
  final int star3Target;
  final String star3Desc;

  factory ChallengeGoal.fromJson(Map<String, dynamic> json) {
    List<int> intList(String k) => [
          for (final x in (json[k] as List<dynamic>? ?? const []))
            if (x is num) x.toInt(),
        ];
    return ChallengeGoal(
      kind: json['kind'] as String? ?? 'territory_count',
      title: json['title'] as String? ?? '',
      requiredTerritories: intList('requiredTerritories'),
      mustKeepTerritories: intList('mustKeepTerritories'),
      fatalLoss: json['fatalLoss'] == true,
      strikeTerritories: intList('strikeTerritories'),
      minStrikeCount: (json['minStrikeCount'] as num?)?.toInt() ?? 0,
      surviveRounds: (json['surviveRounds'] as num?)?.toInt() ?? 0,
      targetCount: (json['targetCount'] as num?)?.toInt() ?? 0,
      requiredContinents: intList('requiredContinents'),
      maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 8,
      star1Desc: json['star1Desc'] as String? ?? 'Cumprir o objetivo principal',
      star2MaxRound: (json['star2MaxRound'] as num?)?.toInt() ?? 6,
      star2Desc: json['star2Desc'] as String? ?? 'Vencer dentro do prazo tático',
      star3Rule: json['star3Rule'] as String? ?? 'no_nuke',
      star3Target: (json['star3Target'] as num?)?.toInt() ?? 0,
      star3Desc: json['star3Desc'] as String? ?? 'Cumprir a restrição de elite',
    );
  }
}

class DailyChallengeSpec {
  const DailyChallengeSpec({
    required this.id,
    required this.date,
    required this.seed,
    required this.kind,
    required this.weekday,
    required this.flavor,
    this.era = '',
    required this.title,
    required this.subtitle,
    required this.briefing,
    this.codexLore = '',
    required this.doctrines,
    required this.mutations,
    this.fixedEvenEvent = '',
    required this.startRound,
    required this.goal,
    required this.setup,
  });

  final String id;
  final String date;
  final int seed;
  final String kind; // 'historical' | 'daily'
  final int weekday;
  final String flavor;
  final String era;
  final String title;
  final String subtitle;
  final String briefing;
  final String codexLore;
  final List<ChallengeRuleTag> doctrines;
  final List<ChallengeRuleTag> mutations;
  final String fixedEvenEvent;
  final int startRound;
  final ChallengeGoal goal;
  final Map<String, dynamic> setup;

  bool get isHistorical => kind == 'historical';

  bool hasDoctrine(String key) => doctrines.any((d) => d.key == key);
  bool hasMutation(String key) => mutations.any((m) => m.key == key);

  factory DailyChallengeSpec.fromJson(Map<String, dynamic> json) => DailyChallengeSpec(
        id: json['id'] as String? ?? '',
        date: json['date'] as String? ?? '',
        seed: (json['seed'] as num?)?.toInt() ?? 1,
        kind: json['kind'] as String? ?? 'daily',
        weekday: (json['weekday'] as num?)?.toInt() ?? 0,
        flavor: json['flavor'] as String? ?? 'daily',
        era: json['era'] as String? ?? '',
        title: json['title'] as String? ?? 'Desafio do Dia',
        subtitle: json['subtitle'] as String? ?? '',
        briefing: json['briefing'] as String? ?? '',
        codexLore: json['codexLore'] as String? ?? '',
        doctrines: [
          for (final e in (json['doctrines'] as List<dynamic>? ?? const []))
            ChallengeRuleTag.fromJson(e as Map<String, dynamic>),
        ],
        mutations: [
          for (final e in (json['mutations'] as List<dynamic>? ?? const []))
            ChallengeRuleTag.fromJson(e as Map<String, dynamic>),
        ],
        fixedEvenEvent: json['fixedEvenEvent'] as String? ?? '',
        startRound: (json['startRound'] as num?)?.toInt() ?? 1,
        goal: ChallengeGoal.fromJson(json['goal'] as Map<String, dynamic>? ?? const {}),
        setup: Map<String, dynamic>.from(json['setup'] as Map<String, dynamic>? ?? const {}),
      );
}

class DailyRankEntry {
  const DailyRankEntry({
    required this.rank,
    required this.playerName,
    required this.difficulty,
    required this.stars,
    required this.rounds,
    required this.armiesLost,
    required this.ordersUsed,
    required this.durationSec,
    required this.submittedAtMs,
    this.crest = '',
    this.replay = '',
  });

  final int rank;
  final String playerName;
  final String crest; // brasão em destaque da conta
  final String replay; // código do replay da partida (só nos dias que já viraram)
  final String difficulty;
  final int stars;
  final int rounds;
  final int armiesLost;
  final int ordersUsed;
  final int durationSec;
  final int submittedAtMs;

  factory DailyRankEntry.fromJson(Map<String, dynamic> json) => DailyRankEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        playerName: json['playerName'] as String? ?? 'Comandante',
        difficulty: json['difficulty'] as String? ?? 'standard',
        stars: (json['stars'] as num?)?.toInt() ?? 1,
        rounds: (json['rounds'] as num?)?.toInt() ?? 1,
        armiesLost: (json['armiesLost'] as num?)?.toInt() ?? 0,
        ordersUsed: (json['ordersUsed'] as num?)?.toInt() ?? 0,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        submittedAtMs: (json['submittedAtMs'] as num?)?.toInt() ?? 0,
        crest: json['crest'] as String? ?? '',
        replay: json['replay'] as String? ?? '',
      );
}

class DailySnapshot {
  const DailySnapshot({
    required this.date,
    required this.resetInSecs,
    required this.weekday,
    required this.challenge,
    required this.ranking,
    required this.totalRanked,
    required this.fromServer,
    this.rankingNote = '',
  });

  final String date;
  final int resetInSecs;
  final int weekday;
  final DailyChallengeSpec challenge;
  final List<DailyRankEntry> ranking;
  final int totalRanked;
  final bool fromServer;
  final String rankingNote;

  factory DailySnapshot.fromServerJson(Map<String, dynamic> json) => DailySnapshot(
        date: json['date'] as String? ?? '',
        resetInSecs: (json['resetInSecs'] as num?)?.toInt() ?? 3600,
        weekday: (json['weekday'] as num?)?.toInt() ?? 0,
        challenge: DailyChallengeSpec.fromJson(json['challenge'] as Map<String, dynamic>),
        ranking: [
          for (final e in (json['ranking'] as List<dynamic>? ?? const []))
            DailyRankEntry.fromJson(e as Map<String, dynamic>),
        ],
        totalRanked: (json['totalRanked'] as num?)?.toInt() ?? 0,
        fromServer: true,
        rankingNote: json['rankingNote'] as String? ?? '',
      );
}

class HistoricalCodexMeta {
  const HistoricalCodexMeta({
    required this.id,
    required this.title,
    required this.era,
    required this.lore,
  });

  final String id;
  final String title;
  final String era;
  final String lore;
}

const List<HistoricalCodexMeta> historicalCodexCatalog = [
  HistoricalCodexMeta(
    id: 'hist_dday_1944',
    title: 'Dia D: Muro do Atlântico',
    era: '06 Jun 1944',
    lore:
        'Em junho de 1944, a maior operação anfíbia da história abriu a frente ocidental europeia cruzando o Canal da Mancha sob forte resistência fortificada.',
  ),
  HistoricalCodexMeta(
    id: 'hist_britain_1940',
    title: 'Batalha da Grã-Bretanha',
    era: 'Verão de 1940',
    lore:
        'Entre julho e outubro de 1940, a defesa aérea e naval britânica conteve a invasão continental, garantindo o bastião aliado na Europa.',
  ),
  HistoricalCodexMeta(
    id: 'hist_constantinople_1453',
    title: 'Corredor dos Estreitos',
    era: '1453',
    lore:
        'O controle do Bósforo definiu rotas comerciais, imperiais e militares entre o Mediterrâneo oriental e as rotas da Ásia.',
  ),
  HistoricalCodexMeta(
    id: 'hist_pacific_1942',
    title: 'Ilhas do Pacífico',
    era: '1942',
    lore:
        'A campanha de ilha em ilha exigiu sincronização precisa entre forças navais, linhas de suprimento longas e domínio da Austrália como base avançada.',
  ),
  HistoricalCodexMeta(
    id: 'hist_stalingrad_1942',
    title: 'Virada no Volga',
    era: 'Inverno 1942',
    lore:
        'Após conter o avanço urbano no inverno de 1942, o contra-ataque em pinça virou toda a iniciativa estratégica da frente oriental.',
  ),
  HistoricalCodexMeta(
    id: 'hist_napoleon_1805',
    title: 'Coalizão Continental',
    era: '1805',
    lore:
        'Campanhas de manobra central dividiram exércitos coligados antes que suas colunas conseguissem se unir no campo de batalha.',
  ),
  HistoricalCodexMeta(
    id: 'hist_thermopylae_480',
    title: 'Portões das Termópilas',
    era: '480 a.C.',
    lore:
        'A defesa em gargalo estreito neutralizou a superioridade numérica inicial, ganhando tempo decisivo para a contraofensiva aliada.',
  ),
  HistoricalCodexMeta(
    id: 'hist_carthage_218',
    title: 'Travessia dos Alpes',
    era: '218 a.C.',
    lore:
        'Contornar o bloqueio naval marchando por rotas montanhosas surpreendeu defesas que só vigiavam o litoral.',
  ),
  HistoricalCodexMeta(
    id: 'hist_spiceroute_1509',
    title: 'Armada do Índico',
    era: '1509',
    lore:
        'O controle de pontos marítimos-chave entre o Mar Vermelho e o Sudeste Asiático estruturou toda a logística oceânica do século XVI.',
  ),
  HistoricalCodexMeta(
    id: 'hist_coldwar_1962',
    title: 'Crise dos Mísseis',
    era: 'Out 1962',
    lore:
        'Durante treze dias de tensão nuclear em 1962, bloqueios estratégicos e inteligência tática evitaram uma guerra aberta entre superpotências.',
  ),
];

class ChallengeLiveStatus {
  const ChallengeLiveStatus({
    required this.progressText,
    required this.star2Active,
    required this.star3Active,
    required this.star3Reason,
    required this.won,
    required this.lost,
    this.endReason = '',
    this.earnedStars = 0,
  });

  final String progressText;
  final bool star2Active;
  final bool star3Active;
  final String star3Reason;
  final bool won;
  final bool lost;
  final String endReason;
  final int earnedStars;
}

ChallengeLiveStatus evaluateChallengeState({
  required DailyChallengeSpec spec,
  required MapData mapData,
  required Map<String, dynamic> view,
  required int nukesUsed,
  required int armiesLost,
  required int ordersUsed,
  required bool lostKeyEver,
}) {
  final goal = spec.goal;
  final round = (view['round'] as num?)?.toInt() ?? 1;
  final turn = (view['turn'] as num?)?.toInt() ?? 0;
  final step = view['step'] as String? ?? 'reinforce';
  final phase = view['phase'] as String? ?? 'play';
  final winner = (view['winner'] as num?)?.toInt();
  final players = view['players'] as List<dynamic>? ?? const [];
  final terrs = view['terr'] as List<dynamic>? ?? const [];
  final occupy = view['occupy'];

  final owned = <int>{};
  for (var i = 0; i < terrs.length; i++) {
    if ((terrs[i]['o'] as num?)?.toInt() == 0) {
      owned.add(i);
    }
  }
  final playerAlive = players.isNotEmpty && (players[0] as Map<String, dynamic>)['alive'] == true;

  bool ownsAllContinents(List<int> contIds) {
    for (final cId in contIds) {
      for (var t = 0; t < mapData.territories.length; t++) {
        if (mapData.territories[t].continent == cId && !owned.contains(t)) {
          return false;
        }
      }
    }
    return contIds.isNotEmpty;
  }

  final anyMustKeepMissing = goal.mustKeepTerritories.any((t) => !owned.contains(t));
  final neverLostCurrently = !lostKeyEver && !anyMustKeepMissing;

  bool star2Met;
  if (goal.kind == 'survive_and_strike') {
    final strikeOwned = goal.strikeTerritories.where(owned.contains).length;
    star2Met = strikeOwned >= 2;
  } else {
    star2Met = round <= goal.star2MaxRound;
  }

  final star3Check = switch (goal.star3Rule) {
    'no_nuke' => (nukesUsed == 0 && neverLostCurrently, nukesUsed > 0 ? 'Ogiva usada' : (neverLostCurrently ? 'Sem Ogiva ✓' : 'Chave perdida')),
    'never_lost_key' => (neverLostCurrently, neverLostCurrently ? 'Base invicta ✓' : 'Território-chave caiu'),
    'max_losses' => (armiesLost <= goal.star3Target && neverLostCurrently, 'Baixas $armiesLost/${goal.star3Target}'),
    'min_orders' => (ordersUsed >= goal.star3Target, 'Ordens $ordersUsed/${goal.star3Target}'),
    _ => (neverLostCurrently, neverLostCurrently ? 'Impecável ✓' : 'Critério falhou'),
  };

  // Defeat conditions first
  if (!playerAlive) {
    return ChallengeLiveStatus(
      progressText: 'Eliminado na rodada $round',
      star2Active: false,
      star3Active: false,
      star3Reason: star3Check.$2,
      won: false,
      lost: true,
      endReason: 'Suas forças foram eliminadas do mapa.',
    );
  }
  if (goal.fatalLoss && anyMustKeepMissing) {
    final lostIdx = goal.mustKeepTerritories.firstWhere((t) => !owned.contains(t));
    final tName = mapData.territories[lostIdx].name;
    return ChallengeLiveStatus(
      progressText: 'Território-chave perdido: $tName',
      star2Active: false,
      star3Active: false,
      star3Reason: star3Check.$2,
      won: false,
      lost: true,
      endReason: 'Você perdeu $tName (território vital da missão).',
    );
  }
  if (phase == 'over' && winner != null && winner != 0) {
    final wName = winner < players.length ? (players[winner]['name'] ?? 'Adversário') : 'Adversário';
    return ChallengeLiveStatus(
      progressText: '$wName venceu antes do prazo',
      star2Active: false,
      star3Active: false,
      star3Reason: star3Check.$2,
      won: false,
      lost: true,
      endReason: '$wName cumpriu o objetivo primeiro.',
    );
  }
  if (round > goal.maxRounds) {
    return ChallengeLiveStatus(
      progressText: 'Prazo limite (${goal.maxRounds} rodadas) excedido',
      star2Active: false,
      star3Active: false,
      star3Reason: star3Check.$2,
      won: false,
      lost: true,
      endReason: 'O prazo máximo de ${goal.maxRounds} rodadas terminou.',
    );
  }

  // Victory checks (do not end mid-occupy prompt so troop advance feels clean, or evaluate right after)
  var won = phase == 'over' && winner == 0;
  late String progress;

  switch (goal.kind) {
    case 'hold_territories':
      final have = goal.requiredTerritories.where(owned.contains).length;
      final total = goal.requiredTerritories.length;
      final missing = [
        for (final t in goal.requiredTerritories)
          if (!owned.contains(t)) mapData.territories[t].name,
      ];
      progress = missing.isEmpty
          ? 'Objetivos assegurados ($have/$total)!'
          : 'Alvos: $have/$total · Faltam: ${missing.take(2).join(', ')}${missing.length > 2 ? '…' : ''}';
      if (occupy == null && have == total) {
        won = true;
      }
    case 'survive_and_strike':
      final strikeOwned = goal.strikeTerritories.where(owned.contains).length;
      progress =
          'Resistência: R$round/${goal.surviveRounds} · Cabeças continentais: $strikeOwned/${goal.minStrikeCount}';
      final reachedSurvive = round > goal.surviveRounds ||
          (round == goal.surviveRounds && turn == 0 && step == 'reinforce' && occupy == null);
      if (occupy == null &&
          (won || (reachedSurvive && !anyMustKeepMissing && strikeOwned >= goal.minStrikeCount))) {
        won = true;
      }
    case 'hold_continents':
      final doneConts = goal.requiredContinents.where((c) => ownsAllContinents([c])).length;
      progress =
          'Continentes dominados: $doneConts/${goal.requiredContinents.length} · Rodada $round/${goal.maxRounds}';
      if (occupy == null && ownsAllContinents(goal.requiredContinents) && !anyMustKeepMissing) {
        won = true;
      }
    default: // territory_count
      final count = owned.length;
      final target = goal.targetCount > 0 ? goal.targetCount : 20;
      progress = 'Territórios: $count/$target · Rodada $round/${goal.maxRounds}';
      if (occupy == null && count >= target && !anyMustKeepMissing) {
        won = true;
      }
  }

  if (won) {
    final stars = 1 + (star2Met ? 1 : 0) + (star3Check.$1 ? 1 : 0);
    return ChallengeLiveStatus(
      progressText: progress,
      star2Active: star2Met,
      star3Active: star3Check.$1,
      star3Reason: star3Check.$2,
      won: true,
      lost: false,
      endReason: 'Missão cumprida!',
      earnedStars: stars,
    );
  }

  return ChallengeLiveStatus(
    progressText: progress,
    star2Active: star2Met,
    star3Active: star3Check.$1,
    star3Reason: star3Check.$2,
    won: false,
    lost: false,
  );
}

String buildChallengeShareReport({
  required DailyChallengeSpec spec,
  required int stars,
  required int rounds,
  required int armiesLost,
  required int ordersUsed,
  required String difficulty,
  int? serverRank,
}) {
  final starsStr = '${'★' * stars}${'☆' * (3 - stars)}';
  final header = spec.isHistorical
      ? 'ULTIMATO · Quinta Histórica (${spec.era})'
      : 'ULTIMATO · Desafio Diário (${spec.date})';
  final diffLabel = difficulty == 'marechal' ? 'Marechal' : 'Padrão';
  final rankPart = serverRank != null && serverRank > 0 ? ' · #$serverRank no ranking' : '';
  return '$header\n'
      '${spec.title}\n'
      '$starsStr Vitória em $rounds rodadas · $diffLabel$rankPart\n'
      'Quartel: $ordersUsed ordens · Baixas: $armiesLost exércitos';
}

/// O desafio no formato que o motor entende (challengeStart): objetivo, doutrinas, mutações e evento fixo.
Map<String, dynamic> challengeSpecJson(DailyChallengeSpec spec) {
  final g = spec.goal;
  return {
    'id': spec.id,
    'date': spec.date,
    'startRound': spec.startRound,
    if (spec.fixedEvenEvent.isNotEmpty) 'fixedEvenEvent': spec.fixedEvenEvent,
    'doctrines': [for (final d in spec.doctrines) d.key],
    'mutations': [for (final m in spec.mutations) m.key],
    'goal': {
      'kind': g.kind,
      'requiredTerritories': g.requiredTerritories,
      'mustKeepTerritories': g.mustKeepTerritories,
      'fatalLoss': g.fatalLoss,
      'strikeTerritories': g.strikeTerritories,
      'minStrikeCount': g.minStrikeCount,
      'surviveRounds': g.surviveRounds,
      'targetCount': g.targetCount,
      'requiredContinents': g.requiredContinents,
      'maxRounds': g.maxRounds,
      'star2MaxRound': g.star2MaxRound,
      'star3Rule': g.star3Rule,
      'star3Target': g.star3Target,
    },
  };
}
