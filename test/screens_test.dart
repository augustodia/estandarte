// Fotos das telas para revisão visual (não é um teste de regra).
//
// Só roda com SCREENS=1 e a biblioteca nativa do motor em native/ (o CI copia de tool/screens/):
//   SCREENS=1 flutter test test/screens_test.dart
// As imagens saem em build/screens/*.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:estandarte/core/map_data.dart';
import 'package:estandarte/engine/game_engine.dart';
import 'package:estandarte/game/app_controller.dart';
import 'package:estandarte/game/fx_models.dart';
import 'package:estandarte/platform/storage.dart';
import 'package:estandarte/ui/game_screen.dart';
import 'package:estandarte/ui/daily_screen.dart';
import 'package:estandarte/ui/home_screen.dart';
import 'package:estandarte/ui/lobby_screen.dart';
import 'package:estandarte/ui/modals.dart';
import 'package:estandarte/ui/quartel_modal.dart';
import 'package:estandarte/ui/rooms_screen.dart';
import 'package:estandarte/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _on = Platform.environment['SCREENS'] == '1';

Future<void> _loadFonts() async {
  Future<void> fam(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
    }
    await l.load();
  }

  await fam('Barlow', [
    'assets/fonts/Barlow-Regular.ttf',
    'assets/fonts/Barlow-Medium.ttf',
    'assets/fonts/Barlow-SemiBold.ttf',
    'assets/fonts/Barlow-Bold.ttf',
  ]);
  await fam('Barlow Condensed', [
    'assets/fonts/BarlowCondensed-Medium.ttf',
    'assets/fonts/BarlowCondensed-SemiBold.ttf',
    'assets/fonts/BarlowCondensed-Bold.ttf',
  ]);
  await fam('UltSymbols', ['assets/fonts/SymbolsMath-Subset.ttf']);
  await fam('UltSymbols2', ['assets/fonts/Symbols2-Subset.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) await fam('MaterialIcons', [icons.path]);
  }
}

final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/screens/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _app(Widget child) => RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: child),
    );

void main() {
  late AppController ctrl;

  setUpAll(() async {
    if (!_on) return;
    SharedPreferences.setMockInitialValues({'estandarte.name': 'Luiz'});
    await AppStorage.init();
    await _loadFonts();
  });

  Future<AppController> newCtrl() async {
    final engine = await GameEngine.init();
    final mapData = MapData.parseJson(File('assets/map_geo.json').readAsStringSync());
    return AppController(mapData: mapData, engine: engine);
  }

  for (final size in const [Size(844, 390), Size(1280, 800), Size(390, 844)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('telas $tag', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      ctrl = await tester.runAsync(newCtrl) as AppController;

      // início
      await tester.pumpWidget(_app(HomeScreen(ctrl: ctrl)));
      await _shot(tester, 'home_$tag');

      // salas online (sem rede no teste: mostra o estado vazio/erro) e desafio do dia
      await tester.pumpWidget(_app(RoomsScreen(ctrl: ctrl)));
      await _shot(tester, 'rooms_$tag');
      await tester.pumpWidget(_app(DailyScreen(ctrl: ctrl)));
      await _shot(tester, 'daily_$tag');

      // sala local com bots
      ctrl.startLocalSetup(withP2p: false, hostName: 'Luiz');
      ctrl.seats.addAll([
        LobbySeat(name: 'Bia', color: 0, ctrl: 'bot'),
        LobbySeat(name: 'Bot 2', color: 2, ctrl: 'bot'),
        LobbySeat(name: 'Caio', color: 3, ctrl: 'bot'),
      ]);
      ctrl.seats[0] = LobbySeat(name: 'Luiz', color: 1, ctrl: 'local');
      await tester.pumpWidget(_app(LobbyScreen(ctrl: ctrl)));
      await _shot(tester, 'lobby_$tag');

      // partida (com todos os extras, para as janelas)
      ctrl.optEvents = true;
      ctrl.optPacts = true;
      ctrl.optNukes = true;
      ctrl.beginGame();
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl)));
      for (var i = 0; i < 30 && ctrl.view?['turn'] != ctrl.me; i++) {
        await tester.pump(const Duration(milliseconds: 600));
      }
      await _shot(tester, 'game_$tag');

      final ctx = tester.element(find.byType(GameScreen));

      // reforça um território de fronteira e ataca: seleção e dados
      final v0 = ctrl.view!;
      final terrs = v0['terr'] as List<dynamic>;
      int? from;
      int? to;
      for (var t = 0; t < terrs.length && from == null; t++) {
        if ((terrs[t]['o'] as num).toInt() != ctrl.me) continue;
        for (final j in ctrl.mapData.territories[t].adj) {
          if ((terrs[j]['o'] as num).toInt() != ctrl.me) {
            from = t;
            to = j;
            break;
          }
        }
      }
      if (from != null && ctrl.view?['turn'] == ctrl.me) {
        for (var k = 0; k < 80 && ctrl.view?['step'] == 'reinforce' && ctrl.view?['turn'] == ctrl.me; k++) {
          ctrl.sel = from;
          ctrl.stepValue = 1;
          ctrl.placeReinforce();
          await tester.pump(const Duration(milliseconds: 30));
        }
        await _shot(tester, 'attackstep_$tag');
        ctrl.tapTerritory(from);
        await tester.pump(const Duration(milliseconds: 50));
        ctrl.tapTerritory(to!);
        await _shot(tester, 'select_$tag');
        ctrl.attack();
        await tester.pump(const Duration(milliseconds: 250));
        await _shot(tester, 'dice_$tag');
        await tester.pump(const Duration(seconds: 3));
      }

      showMenuModal(ctx, ctrl);
      await _shot(tester, 'menu_$tag');
      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 300));

      showExtrasModal(ctx, ctrl);
      await _shot(tester, 'extras_$tag');
      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 300));

      showPactsModal(ctx, ctrl);
      await _shot(tester, 'pacts_$tag');
      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 300));
      showObjectiveModal(ctx, ctrl);
      await _shot(tester, 'objective_$tag');
      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 300));

      showQuartelModal(ctx, ctrl);
      await _shot(tester, 'quartel_$tag');
      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 300));

      showRulesModal(ctx, ctrl);
      await _shot(tester, 'rules_$tag');
      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 300));

      // fim de partida: o assento humano vira bot e os bots terminam a partida
      ctrl.convertSeatToBot(0);
      for (var k = 0; k < 4000 && ctrl.view?['phase'] == 'play'; k++) {
        await tester.pump(const Duration(seconds: 2));
      }
      if (ctrl.view?['phase'] != 'play') await _shot(tester, 'victory_$tag');

      // tutorial
      await tester.pumpWidget(const SizedBox());
      ctrl.startTutorial(playerName: 'Luiz');
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl)));
      await tester.pump(const Duration(seconds: 1));
      await _shot(tester, 'tutorial_$tag');

      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      await tester.pump(const Duration(minutes: 3));
    }, skip: !_on);
  }
}
