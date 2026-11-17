import 'dart:io';

import 'package:estandarte/core/map_data.dart';
import 'package:estandarte/game/daily_challenge.dart';
import 'package:flutter_test/flutter_test.dart';

MapData _loadRealMap() {
  final raw = File('assets/map_geo.json').readAsStringSync();
  return MapData.parseJson(raw);
}

DailyChallengeSpec _holdSpec() => const DailyChallengeSpec(
      id: 'hist_dday_1944',
      date: '2026-11-19',
      seed: 123,
      kind: 'historical',
      weekday: 4,
      flavor: 'historical',
      era: '06 Jun 1944',
      title: 'Dia D: Muro do Atlântico',
      subtitle: 'Quinta Histórica',
      briefing: 'Teste',
      doctrines: [],
      mutations: [],
      startRound: 1,
      goal: ChallengeGoal(
        kind: 'hold_territories',
        title: 'Hold UK + EU',
        requiredTerritories: [13, 15, 16],
        mustKeepTerritories: [13],
        maxRounds: 7,
        star1Desc: 'S1',
        star2MaxRound: 5,
        star2Desc: 'S2',
        star3Rule: 'no_nuke',
        star3Desc: 'S3',
      ),
      setup: {},
    );

void main() {
  test('evaluateChallengeState grants 3 stars when required territories held <= star2MaxRound without nuke', () {
    final mapData = _loadRealMap();
    final spec = _holdSpec();
    final terrView = [
      for (var i = 0; i < 42; i++) {'o': (i == 13 || i == 15 || i == 16) ? 0 : 1, 'a': 3},
    ];
    final status = evaluateChallengeState(
      spec: spec,
      mapData: mapData,
      view: {
        'round': 4,
        'turn': 0,
        'step': 'attack',
        'phase': 'play',
        'winner': null,
        'players': [
          {'alive': true},
          {'alive': true},
        ],
        'terr': terrView,
      },
      nukesUsed: 0,
      armiesLost: 10,
      ordersUsed: 2,
      lostKeyEver: false,
    );
    expect(status.won, true);
    expect(status.lost, false);
    expect(status.earnedStars, 3);
  });

  test('evaluateChallengeState triggers defeat when fatalLoss mustKeep territory drops', () {
    final mapData = _loadRealMap();
    const spec = DailyChallengeSpec(
      id: 'hist_britain_1940',
      date: '2026-11-26',
      seed: 456,
      kind: 'historical',
      weekday: 4,
      flavor: 'historical',
      era: '1940',
      title: 'Batalha da Grã-Bretanha',
      subtitle: 'Defesa',
      briefing: 'Defenda',
      doctrines: [],
      mutations: [],
      startRound: 1,
      goal: ChallengeGoal(
        kind: 'survive_and_strike',
        title: 'Segurar UK',
        mustKeepTerritories: [13],
        fatalLoss: true,
        strikeTerritories: [14, 15, 16, 17],
        minStrikeCount: 1,
        surviveRounds: 5,
        maxRounds: 6,
        star1Desc: 'S1',
        star2MaxRound: 5,
        star2Desc: 'S2',
        star3Rule: 'max_losses',
        star3Target: 25,
        star3Desc: 'S3',
      ),
      setup: {},
    );
    final terrView = [
      for (var i = 0; i < 42; i++) {'o': 1, 'a': 3},
    ];
    final status = evaluateChallengeState(
      spec: spec,
      mapData: mapData,
      view: {
        'round': 2,
        'turn': 1,
        'step': 'attack',
        'phase': 'play',
        'winner': null,
        'players': [
          {'alive': true},
          {'alive': true},
        ],
        'terr': terrView,
      },
      nukesUsed: 0,
      armiesLost: 5,
      ordersUsed: 1,
      lostKeyEver: true,
    );
    expect(status.won, false);
    expect(status.lost, true);
  });

  test('buildChallengeShareReport formats historical era, stars, and rank', () {
    final txt = buildChallengeShareReport(
      spec: _holdSpec(),
      stars: 3,
      rounds: 4,
      armiesLost: 11,
      ordersUsed: 2,
      difficulty: 'marechal',
      serverRank: 1,
    );
    expect(txt.contains('Quinta Histórica (06 Jun 1944)'), true);
    expect(txt.contains('★★★'), true);
    expect(txt.contains('#1 no ranking'), true);
  });

  test('historicalCodexCatalog has 10 unique historical chronicles', () {
    final ids = historicalCodexCatalog.map((e) => e.id).toSet();
    expect(historicalCodexCatalog.length, 10);
    expect(ids.length, 10);
  });
}
