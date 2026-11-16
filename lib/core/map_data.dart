import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_drawing/path_drawing.dart';

class ContinentGeo {
  ContinentGeo({
    required this.name,
    required this.bonus,
    required this.colorHex,
    required this.color,
    required this.x,
    required this.y,
    required this.svgPath,
    required this.path,
  });

  final String name;
  final int bonus;
  final String colorHex;
  final Color color;
  final double x;
  final double y;
  final String svgPath;
  final Path path;
}

class TerritoryGeo {
  TerritoryGeo({
    required this.index,
    required this.name,
    required this.continent,
    required this.x,
    required this.y,
    required this.svgPath,
    required this.path,
    required this.bounds,
    required this.adj,
  });

  final int index;
  final String name;
  final int continent;
  final double x;
  final double y;
  final String svgPath;
  final Path path;
  final Rect bounds;
  final List<int> adj;
}

class SeaRouteGeo {
  SeaRouteGeo({
    required this.a,
    required this.b,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.wrap,
  });

  final int a;
  final int b;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final bool wrap;
}

class MapData {
  MapData._({
    required this.width,
    required this.height,
    required this.continents,
    required this.territories,
    required this.seaRoutes,
    required this._seaPairs,
  });

  final double width;
  final double height;
  final List<ContinentGeo> continents;
  final List<TerritoryGeo> territories;
  final List<SeaRouteGeo> seaRoutes;
  final Set<int> _seaPairs;

  double get aspect => width / height;

  bool isSea(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return _seaPairs.contains((lo << 8) | hi);
  }

  static Future<MapData> load() async {
    final raw = await rootBundle.loadString('assets/map_geo.json');
    return parseJson(raw);
  }

  static MapData parseJson(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final w = (j['w'] as num).toDouble();
    final h = (j['h'] as num).toDouble();

    final conts = <ContinentGeo>[];
    for (final c in (j['continents'] as List<dynamic>)) {
      final m = c as Map<String, dynamic>;
      final hex = m['color'] as String;
      final svg = m['d'] as String;
      final path = parseSvgPathData(svg)..fillType = PathFillType.evenOdd;
      conts.add(
        ContinentGeo(
          name: m['n'] as String,
          bonus: (m['bonus'] as num).toInt(),
          colorHex: hex,
          color: parseHexColor(hex),
          x: (m['x'] as num).toDouble(),
          y: (m['y'] as num).toDouble(),
          svgPath: svg,
          path: path,
        ),
      );
    }

    final terrs = <TerritoryGeo>[];
    final terrList = j['terr'] as List<dynamic>;
    for (var i = 0; i < terrList.length; i++) {
      final m = terrList[i] as Map<String, dynamic>;
      final svg = m['d'] as String;
      final path = parseSvgPathData(svg)..fillType = PathFillType.evenOdd;
      terrs.add(
        TerritoryGeo(
          index: i,
          name: m['n'] as String,
          continent: (m['c'] as num).toInt(),
          x: (m['x'] as num).toDouble(),
          y: (m['y'] as num).toDouble(),
          svgPath: svg,
          path: path,
          bounds: path.getBounds(),
          adj: (m['adj'] as List<dynamic>).map((e) => (e as num).toInt()).toList(),
        ),
      );
    }

    final seas = <SeaRouteGeo>[];
    final seaPairs = <int>{};
    for (final s in (j['sea'] as List<dynamic>)) {
      final l = s as List<dynamic>;
      final a = (l[0] as num).toInt();
      final b = (l[1] as num).toInt();
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      seaPairs.add((lo << 8) | hi);
      seas.add(
        SeaRouteGeo(
          a: a,
          b: b,
          x1: (l[2] as num).toDouble(),
          y1: (l[3] as num).toDouble(),
          x2: (l[4] as num).toDouble(),
          y2: (l[5] as num).toDouble(),
          wrap: l.length > 6 && (l[6] as num) != 0,
        ),
      );
    }

    return MapData._(
      width: w,
      height: h,
      continents: conts,
      territories: terrs,
      seaRoutes: seas,
      seaPairs: seaPairs,
    );
  }
}

Color parseHexColor(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  if (clean.length == 8) {
    return Color(int.parse(clean, radix: 16));
  }
  return const Color(0xFF999999);
}
