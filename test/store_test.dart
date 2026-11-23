import 'dart:convert';

import 'package:estandarte/game/crests.dart';
import 'package:estandarte/game/daily_challenge.dart';
import 'package:estandarte/net/account_api.dart';
import 'package:flutter_test/flutter_test.dart';

String _token(Map<String, dynamic> body) {
  final b64 = base64Url.encode(utf8.encode(jsonEncode(body))).replaceAll('=', ''); // como o servidor (sem preenchimento)
  return 'ult1.$b64.assinatura';
}

void main() {
  test('token de direitos: lê a carga e o prazo', () {
    final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final e = Entitlements.fromToken(_token({'v': 1, 'a': 7, 's': ['comandante_fundador'], 'f': 12, 'i': 1, 'e': exp}), tag: 't');
    expect(e.comandante, isTrue);
    expect(e.fundador, 12);
    expect(e.valid, isTrue);
    expect(e.tag, 't');

    final plain = Entitlements.fromToken(_token({'v': 1, 'a': 7, 's': ['comandante'], 'f': 0, 'i': 1, 'e': exp}));
    expect(plain.comandante, isTrue);
    expect(plain.fundador, 0);

    final none = Entitlements.fromToken(_token({'v': 1, 'a': 7, 's': <String>[], 'f': 0, 'i': 1, 'e': exp}));
    expect(none.comandante, isFalse);

    final old = Entitlements.fromToken(_token({'v': 1, 'a': 7, 's': ['comandante'], 'f': 0, 'i': 1, 'e': 1}));
    expect(old.valid, isFalse); // vencido: o app não confia mais nele sem falar com o servidor

    expect(Entitlements.fromToken('lixo').comandante, isFalse);
    expect(Entitlements.fromToken('ult1.%%%.x').comandante, isFalse);
  });

  test('preço em reais', () {
    const it = StoreItem(sku: 'comandante', name: 'Comandante', desc: '', cents: 2990, available: true);
    expect(it.price, r'R$ 29,90');
    const fnd = StoreItem(sku: 'comandante_fundador', name: '', desc: '', cents: 1905, available: true);
    expect(fnd.price, r'R$ 19,05');
  });

  test('insígnias da loja não saem do Códice', () {
    final codex = <String, dynamic>{
      for (final m in historicalCodexCatalog) m.id: {'bestStars': 3, 'v': 3},
    };
    expect(crestEarned(codex, 'ins_historiador'), isTrue);
    expect(crestEarned(codex, 'ins_comandante'), isFalse);
    expect(crestEarned(codex, 'ins_fundador'), isFalse);
    expect(crestTitle('ins_fundador'), 'Insígnia Fundador');
  });
}
