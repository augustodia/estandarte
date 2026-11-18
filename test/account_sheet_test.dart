import 'dart:io';

import 'package:estandarte/core/map_data.dart';
import 'package:estandarte/engine/game_engine.dart';
import 'package:estandarte/game/app_controller.dart';
import 'package:estandarte/platform/storage.dart';
import 'package:estandarte/ui/account_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Gerenciadores de senha (1Password e outros) põem o menu deles por cima da página: o clique nele chegava ao fundo da
// janela de entrar e a fechava antes de preencher. A janela só fecha pelo × e pelos botões, e com o formulário
// preenchido nem o "voltar" do sistema a fecha.
void main() {
  testWidgets('janela de entrar não fecha com toque fora, Esc ou voltar com o formulário preenchido', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late AppController ctrl;
    await tester.runAsync(() async {
      await AppStorage.init();
      final engine = await GameEngine.init();
      final mapData = MapData.parseJson(File('assets/map_geo.json').readAsStringSync());
      ctrl = AppController(engine: engine, mapData: mapData);
    });
    addTearDown(ctrl.dispose);

    late BuildContext home;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      home = ctx;
      return const Scaffold(body: SizedBox.expand());
    })));
    showAccountSheet(home, ctrl);
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsWidgets);

    // toque fora (o fundo escuro) e Esc: continua aberta, mesmo vazia
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);

    // preenchido (como faz o gerenciador de senhas): o "voltar" do sistema também não fecha
    await tester.enterText(find.byType(TextField).first, 'luiz@gmail.com');
    await tester.enterText(find.byType(TextField).at(1), 'senha-forte-1');
    await tester.pump();
    await Navigator.of(home, rootNavigator: true).maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);

    // o × fecha
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  }, skip: Platform.environment['SCREENS'] != '1'); // precisa do motor nativo, que só o job das telas tem
}
