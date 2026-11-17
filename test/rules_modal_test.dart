import 'dart:io';

import 'package:estandarte/core/map_data.dart';
import 'package:estandarte/engine/game_engine.dart';
import 'package:estandarte/game/app_controller.dart';
import 'package:estandarte/platform/storage.dart';
import 'package:estandarte/ui/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Opening Menu -> Regras in rotated 390x844 survives layout resize/reparent without null check error',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late AppController ctrl;
      await tester.runAsync(() async {
        await AppStorage.init();
        final engine = await GameEngine.init();
        final rawMap = File('assets/map_geo.json').readAsStringSync();
        final mapData = MapData.parseJson(rawMap);
        ctrl = AppController(engine: engine, mapData: mapData);
        ctrl.startTutorial();
      });
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameScreen(ctrl: ctrl)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Open Menu via Menu button (tooltip 'Menu (M)' covers compact icon-only mode too)
      await tester.tap(find.byTooltip('Menu (M)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Regras'), findsOneWidget);

      // Simulate transient desktop viewport resize (which unmounts compact _HudPanel) and back
      tester.view.physicalSize = const Size(960, 844);
      await tester.pump();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();

      // Scroll Regras into view inside Menu sheet, then tap it
      await tester.ensureVisible(find.text('Regras'));
      await tester.pump();
      await tester.tap(find.text('Regras'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Manual de Campanha'), findsOneWidget);
    },
    skip: !Platform.isWindows,
  );
}
