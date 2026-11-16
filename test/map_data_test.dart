import 'dart:io';

import 'package:estandarte/core/map_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('map_geo.json parses 6 continents, 42 territories, and Alaska-FarEast wrap sea route', () {
    final raw = File('assets/map_geo.json').readAsStringSync();
    final map = MapData.parseJson(raw);
    expect(map.width, 1420);
    expect(map.height, 681);
    expect(map.continents.length, 6);
    expect(map.territories.length, 42);
    expect(map.seaRoutes.any((s) => s.wrap), true);
    expect(map.isSea(0, 32), true);
  });
}
