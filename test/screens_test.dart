// Fotos das telas para revisão visual (não é um teste de regra).
//
// Só roda com SCREENS=1 e a biblioteca nativa do motor em native/ (o CI copia de tool/screens/):
//   SCREENS=1 flutter test test/screens_test.dart
// As imagens saem em build/screens/*.png.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:estandarte/core/map_data.dart';
import 'package:estandarte/engine/game_engine.dart';
import 'package:estandarte/game/app_controller.dart';
import 'package:estandarte/game/daily_challenge.dart';
import 'package:estandarte/game/fx_models.dart';
import 'package:estandarte/net/account_api.dart';
import 'package:estandarte/net/online_client.dart';
import 'package:estandarte/ui/account_sheet.dart';
import 'package:estandarte/ui/corr_screen.dart';
import 'package:estandarte/ui/crests_sheet.dart';
import 'package:estandarte/platform/storage.dart';
import 'package:estandarte/ui/game_screen.dart';
import 'package:estandarte/ui/daily_screen.dart';
import 'package:estandarte/ui/friends_screen.dart';
import 'package:estandarte/ui/home_screen.dart';
import 'package:estandarte/ui/lobby_screen.dart';
import 'package:estandarte/ui/modals.dart';
import 'package:estandarte/ui/quartel_modal.dart';
import 'package:estandarte/ui/replay_bar.dart';
import 'package:estandarte/ui/rooms_screen.dart';
import 'package:estandarte/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _on = Platform.environment['SCREENS'] == '1';

class _FakeLink extends GameLink {
  @override
  bool get isOpen => true;
  @override
  void send(Map<String, dynamic> msg) {}
  @override
  void close() {}
}

List<AsyncGameInfo> _corrSample() {
  final now = DateTime.now().millisecondsSinceEpoch;
  const h = 3600 * 1000;
  return [
    AsyncGameInfo(
      id: 'K7M2QA', status: 'play', round: 7, yourTurn: true, turnName: 'Luiz', deadlineMs: now + 18 * h + 600000,
      seats: const [
        AsyncSeatInfo(name: 'Luiz', color: 1, you: true),
        AsyncSeatInfo(name: 'Beto', color: 0),
        AsyncSeatInfo(name: 'Carla', color: 2),
      ],
    ),
    AsyncGameInfo(
      id: 'P3XR8D', status: 'play', round: 3, turnName: 'Ana', deadlineMs: now + 5 * h,
      seats: const [
        AsyncSeatInfo(name: 'Ana', color: 4),
        AsyncSeatInfo(name: 'Luiz', color: 1, you: true),
        AsyncSeatInfo(name: 'Bot 3', color: 3, bot: true),
      ],
    ),
    const AsyncGameInfo(
      id: 'H9WQ2E', status: 'lobby', owner: true,
      seats: [AsyncSeatInfo(name: 'Luiz', color: 1, you: true), AsyncSeatInfo(name: 'Davi', color: 5)],
    ),
    AsyncGameInfo(
      id: 'B4NM7T', status: 'over', round: 14, winner: 'Luiz', youWon: true, updatedMs: now - 3 * 24 * h,
      seats: const [
        AsyncSeatInfo(name: 'Luiz', color: 1, you: true),
        AsyncSeatInfo(name: 'Eva', color: 3),
        AsyncSeatInfo(name: 'Fábio', color: 0),
        AsyncSeatInfo(name: 'Gil', color: 2),
      ],
    ),
  ];
}

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

      // conta: entrar, criar, e o início com a conta
      final homeCtx = tester.element(find.byType(HomeScreen));
      showAccountSheet(homeCtx, ctrl);
      await _shot(tester, 'account_$tag');
      Navigator.of(homeCtx, rootNavigator: true).pop();
      showAccountSheet(homeCtx, ctrl);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600)); // a janela anterior termina de fechar
      await tester.ensureVisible(find.text('ESQUECI A SENHA').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('ESQUECI A SENHA').last);
      await _shot(tester, 'account_forgot_$tag');
      Navigator.of(homeCtx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 400));
      showAccountSheet(homeCtx, ctrl, startOnSignUp: true);
      await _shot(tester, 'account_new_$tag');
      Navigator.of(homeCtx, rootNavigator: true).pop();
      ctrl.debugSetAccount(const AccountUser(id: 1, username: 'Luiz', email: 'luiz@gmail.com'));
      await tester.pumpWidget(_app(HomeScreen(ctrl: ctrl)));
      await _shot(tester, 'home_unconf_$tag');
      showAccountSheet(homeCtx, ctrl);
      await _shot(tester, 'account_code_$tag');
      Navigator.of(homeCtx, rootNavigator: true).pop();
      // Códice com algumas crônicas jogadas (brasões em bronze, prata e ouro) e um brasão em destaque
      Map<String, dynamic> rec(int stars) => {'bestStars': stars, 'bestRounds': 9};
      ctrl.codexProgress = {
        'hist_dday_1944': rec(3), 'hist_britain_1940': rec(2), 'hist_pacific_1942': rec(1),
        'hist_stalingrad_1942': rec(3), 'hist_coldwar_1962': rec(2),
      };
      ctrl.debugSetAccount(const AccountUser(
          id: 1, username: 'Luiz', email: 'luiz@gmail.com', emailVerified: true, crest: 'hist_dday_1944:3'));
      await tester.pumpWidget(_app(HomeScreen(ctrl: ctrl)));
      await _shot(tester, 'home_acct_$tag');
      showAccountSheet(homeCtx, ctrl);
      await _shot(tester, 'account_in_$tag');
      Navigator.of(homeCtx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 600));

      // correspondência: o início com partidas esperando, a lista, a lista vazia e a sala de espera
      ctrl.debugSetCorr(_corrSample());
      await tester.pumpWidget(_app(HomeScreen(ctrl: ctrl)));
      await _shot(tester, 'home_corr_$tag');
      await tester.pumpWidget(_app(CorrScreen(ctrl: ctrl)));
      await _shot(tester, 'corr_$tag');

      // amigos: início com pedido e gente online, a lista, convites na correspondência e a lista vazia
      ctrl.debugSetFriends(const FriendLists(
        friends: [FriendInfo('Beto', status: 'playing', crest: 'ins_veterano'), FriendInfo('Carla', status: 'online'), FriendInfo('Davi')],
        incoming: ['Eva'],
        outgoing: ['Fábio'],
      ));
      ctrl.debugSetCorr(_corrSample(), invites: const [
        AsyncInviteInfo(id: 'Q8RT2M', from: 'Carla', seats: [
          AsyncSeatInfo(name: 'Carla', color: 2),
          AsyncSeatInfo(name: 'Gil', color: 4),
        ]),
      ]);
      await tester.pumpWidget(_app(HomeScreen(ctrl: ctrl)));
      await _shot(tester, 'home_social_$tag');
      await tester.pumpWidget(_app(FriendsScreen(ctrl: ctrl)));
      await _shot(tester, 'friends_$tag');
      await tester.pumpWidget(_app(CorrScreen(ctrl: ctrl)));
      await _shot(tester, 'corr_invites_$tag');
      ctrl.debugSetFriends(const FriendLists());
      await tester.pumpWidget(_app(FriendsScreen(ctrl: ctrl)));
      await _shot(tester, 'friends_empty_$tag');
      ctrl.debugSetFriends(const FriendLists(
        friends: [FriendInfo('Beto', status: 'playing'), FriendInfo('Carla', status: 'online'), FriendInfo('Davi')],
      ));

      ctrl.debugSetCorr(const []);
      await tester.pumpWidget(_app(CorrScreen(ctrl: ctrl)));
      await _shot(tester, 'corr_empty_$tag');
      ctrl.online = OnlineSession(server: '', code: 'K7M2QA', host: false, fromRooms: false, name: 'Luiz', corr: true);
      ctrl.guestLink = _FakeLink();
      ctrl.lobbyCode = 'K7M2QA';
      ctrl.lobbyOwner = true;
      ctrl.optHq = true;
      ctrl.me = 0;
      ctrl.seats = [
        LobbySeat(name: 'Luiz', color: 1, ctrl: 'remote', online: true),
        LobbySeat(name: 'Beto', color: 0, ctrl: 'remote'),
      ];
      await tester.pumpWidget(_app(LobbyScreen(ctrl: ctrl)));
      await _shot(tester, 'lobby_corr_$tag');
      final lobbyCtx = tester.element(find.byType(LobbyScreen));
      showCorrInviteSheet(lobbyCtx, ctrl);
      await _shot(tester, 'corr_invite_sheet_$tag');
      Navigator.of(lobbyCtx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 600));
      ctrl.online = null;
      ctrl.guestLink = null;
      ctrl.lobbyCode = null;
      ctrl.lobbyOwner = false;
      ctrl.seats = [];
      ctrl.debugSetCorr(const []);
      ctrl.debugSetFriends(const FriendLists());

      ctrl.debugSetAccount(null);
      await tester.pumpWidget(_app(HomeScreen(ctrl: ctrl)));
      await tester.pump(const Duration(milliseconds: 400));

      // teclado aberto: o navegador encolhe a altura útil (interactive-widget=resizes-content)
      final kbSize = Size(size.width, size.height * (size.width > size.height ? 0.45 : 0.55));
      tester.view.physicalSize = kbSize * 2;
      await tester.pumpWidget(_app(HomeScreen(ctrl: ctrl)));
      await _shot(tester, 'home_kb_$tag');
      await tester.pumpWidget(_app(RoomsScreen(ctrl: ctrl)));
      await _shot(tester, 'rooms_kb_$tag');
      tester.view.physicalSize = size * 2;

      // salas online (sem rede no teste: mostra o estado vazio/erro) e desafio do dia
      await tester.pumpWidget(_app(RoomsScreen(ctrl: ctrl)));
      await _shot(tester, 'rooms_$tag');
      await tester.pumpWidget(_app(DailyScreen(ctrl: ctrl)));
      await _shot(tester, 'daily_$tag');
      await tester.ensureVisible(find.textContaining('Códice &'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.textContaining('Códice &'));
      await _shot(tester, 'codex_$tag');
      showCrestsSheet(tester.element(find.byType(DailyScreen)), ctrl);
      await _shot(tester, 'crests_$tag');
      Navigator.of(tester.element(find.byType(DailyScreen)), rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 400));

      // sala local com bots
      ctrl.startLocalSetup(withP2p: false, hostName: 'Luiz');
      ctrl.seats.addAll([
        LobbySeat(name: 'Bia', color: 0, ctrl: 'bot', crest: 'hist_britain_1940:2'),
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
      ctrl.playerCrests = const ['hist_dday_1944:3', 'ins_historiador', '', 'hist_coldwar_1962:1'];
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl)));
      for (var i = 0; i < 30 && ctrl.view?['turn'] != ctrl.me; i++) {
        await tester.pump(const Duration(milliseconds: 600));
      }
      await _shot(tester, 'game_$tag');

      // recados prontos: balões de quem mandou e o painel aberto
      ctrl.debugCanEmote = true;
      ctrl.debugPushEmote(1, 4);
      ctrl.debugPushEmote(0, 0, mine: true);
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl))); // aqui a tela não escuta o controle sozinha
      await _shot(tester, 'emotes_$tag');
      await tester.tap(find.byTooltip('Recados'));
      await _shot(tester, 'emote_panel_$tag');
      await tester.tap(find.text('Bem jogado!'));
      await tester.pump(const Duration(milliseconds: 4500)); // os balões somem sozinhos
      await tester.pump(const Duration(milliseconds: 3200));
      ctrl.debugCanEmote = false;
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl)));

      // objetivo do desafio: aberto ao começar, recolhido depois de alguns segundos
      ctrl.activeChallenge = const DailyChallengeSpec(
        id: 'd_teste', date: '2026-11-17', seed: 1, kind: 'daily', weekday: 2, flavor: 'daily',
        title: 'Operação Assimetria', subtitle: '', briefing: '', doctrines: [], mutations: [], startRound: 1,
        goal: ChallengeGoal(kind: 'hold_continents', title: 'Fechar América do Norte e do Sul em até 8 rodadas',
            maxRounds: 8, star1Desc: 'S1', star2MaxRound: 6, star2Desc: 'S2', star3Rule: 'never_lost_key',
            star3Desc: 'S3'),
        setup: {},
      );
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl))); // no teste ninguém escuta o controle: redesenha
      await _shot(tester, 'challenge_open_$tag');
      await tester.pump(const Duration(seconds: 7));
      await _shot(tester, 'challenge_closed_$tag');
      ctrl.activeChallenge = null;
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl)));
      await tester.pump(const Duration(milliseconds: 300));

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

      // tutorial
      await tester.pumpWidget(const SizedBox());
      ctrl.startTutorial(playerName: 'Luiz');
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl)));
      await tester.pump(const Duration(seconds: 1));
      await _shot(tester, 'tutorial_$tag');

      // replay de uma partida gravada pelo motor (test/replay_demo.json) e a prova dos dados
      final rep = jsonDecode(File('test/replay_demo.json').readAsStringSync()) as Map<String, dynamic>;
      ctrl.debugOpenReplay('K7M2QAXY', const {'mode': 'online', 'winner': 'Carla'}, rep);
      ctrl.replayGoTo(ctrl.replay!.turns[20].step + 3);
      await tester.pumpWidget(_app(GameScreen(ctrl: ctrl)));
      await _shot(tester, 'replay_$tag');
      final gameCtx = tester.element(find.byType(GameScreen));
      showReplayProofSheet(gameCtx, ctrl);
      await _shot(tester, 'replay_proof_$tag');
      Navigator.of(gameCtx, rootNavigator: true).pop();
      await tester.pump(const Duration(milliseconds: 600));
      ctrl.leaveGame();

      await tester.pumpWidget(const SizedBox());
      ctrl.dispose();
      await tester.pump(const Duration(minutes: 3));
    }, skip: !_on);
  }
}
