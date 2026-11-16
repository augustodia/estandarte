import 'package:estandarte/core/names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleanName strips control characters, collapses spaces, limits to 14', () {
    expect(cleanName('  João\u202E  Silva   12345 '), 'João Silva 123');
    expect(cleanName('\u0301Maria'), 'Maria');
  });

  test('nameKey folds accents and Cyrillic/Greek homoglyphs', () {
    expect(nameKey('Águia'), nameKey('Aguia'));
    expect(nameKey('Mаria'), nameKey('Maria')); // Cyrillic а
    expect(nameKey('Βοt0'), 'βoto');
  });

  test('uniqueName avoids duplicates and reserved bot pattern for humans', () {
    final seats = ['Bot 1', 'Maria'];
    expect(uniqueName('Bot 2', seats, (s) => s, isBot: false), 'Convidado');
    expect(uniqueName('Bot 2', seats, (s) => s, isBot: true), 'Bot 2');
    expect(uniqueName('Máría', seats, (s) => s), 'Máría 2');
  });
}
