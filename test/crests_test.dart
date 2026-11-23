import 'package:estandarte/game/crests.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> codex(Map<String, int> stars) => {
        for (final e in stars.entries) e.key: {'id': e.key, 'bestStars': e.value, 'bestRounds': 9, 'v': e.value},
      };

  test('brasões seguem as regras do servidor', () {
    final c = codex({'hist_dday_1944': 2, 'hist_britain_1940': 3, 'hist_pacific_1942': 1, 'inventada': 3});
    expect(crestEarned(c, 'hist_dday_1944:2'), isTrue);
    expect(crestEarned(c, 'hist_dday_1944:3'), isFalse);
    expect(crestEarned(c, 'hist_coldwar_1962:1'), isFalse);
    expect(crestEarned(c, 'inventada:1'), isFalse);
    expect(crestEarned(c, 'ins_veterano'), isTrue);
    expect(crestEarned(c, 'ins_estrategista'), isFalse);
    expect(parseCrest('hist_dday_1944:0'), isNull);
    expect(parseCrest('qualquer'), isNull);
    expect(earnedCrests(c), ['hist_dday_1944:2', 'hist_britain_1940:3', 'hist_pacific_1942:1', 'ins_veterano']);
    expect(crestTitle('hist_britain_1940:3'), 'Batalha da Grã-Bretanha · Ouro');
    expect(crestTitle('ins_veterano'), 'Insígnia Veterano');
  });

  test('só a campanha conferida pelo servidor libera brasão', () {
    final c = {'hist_dday_1944': {'bestStars': 3, 'bestRounds': 6}}; // jogada sem conferir
    expect(crestEarned(c, 'hist_dday_1944:1'), isFalse);
    expect(earnedCrests(c), isEmpty);
    expect(codexStars(c, 'hist_dday_1944'), 3);
  });
}
