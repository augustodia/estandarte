import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../core/names.dart';
import '../engine/game_engine.dart';
import '../net/online_client.dart';
import '../platform/p2p.dart';
import '../platform/sound.dart';
import '../platform/storage.dart';
import '../platform/web_env.dart';
import 'fx_models.dart';
import 'smoke_sim.dart';

const int alarmMs = 900;
const int flightMs = 2900;
const int impactMs = alarmMs + flightMs;
const String appVersion = 'alpha-1.4';

const Map<String, String> stepLabels = {
  'reinforce': 'Reforço',
  'attack': 'Ataque',
  'move': 'Remanejamento',
};

const Map<String, (String, String)> phaseAlerts = {
  'reinforce': ('Reforço', 'Reforce seus territórios'),
  'attack': ('Ataque!', 'Toque num território seu e num vizinho inimigo'),
  'move': ('Remanejamento', 'Mova tropas ou encerre o turno'),
};

const Map<String, String> eventTitles = {
  'storm': 'Tempestade',
  'ceasefire': 'Cessar-fogo',
  'sea': 'Mar revolto',
  'recruit': 'Recrutamento',
  'shortage': 'Escassez',
  'fort': 'Trincheiras',
  'charge': 'Ofensiva',
};

class AppController extends ChangeNotifier {
  AppController({required this.mapData, required this.engine});

  final MapData mapData;
  final GameEngine engine;
  final SmokeSim smoke = SmokeSim();

  AppScreen screen = AppScreen.home;
  String role = 'host'; // 'host' | 'guest'
  bool netP2p = true;
  int me = 0;

  // Lobby & Options (defaults match original app.cfg)
  List<LobbySeat> seats = [];
  int turnSecs = 120;
  bool optEvents = false;
  bool optPacts = false;
  bool optNukes = false;
  bool optHq = true; // Quartel (padrão): medalhas e ordens. Desligado, a partida usa as cartas (o extra)
  bool optSpy = false;
  bool optPublic = true;
  bool? extrasOpen;
  String? lobbyCode;
  bool lobbyOwner = false;

  // Engine Game ID (when host)
  int? _engineId;
  int? get engineId => _engineId;

  // Current filtered view + derived evalView
  Map<String, dynamic>? view;
  EvalViewResult? eval;

  // Online / P2P link state
  OnlineSession? online;
  GameLink? guestLink;
  Map<String, dynamic>? savedSpare;
  bool autoReconnecting = false;
  Timer? _autoTimer;
  Timer? _onlineRetryTimer;
  Timer? _roomsTimer;
  Timer? _heartbeatTimer;
  int _hostLastHeardMs = 0;
  bool hostLag = false;
  bool p2pCertReady = false;
  bool netOnline = WebEnv.isOnline;

  // Interaction state
  int? sel;
  int? target;
  int? infoTerr;
  int? hoverInfoTerr;
  int stepValue = 1;
  String _stepKey = '';
  bool nukeMode = false;
  int? lastTapTerr;
  int lastTapMs = 0;
  int? confirmEndKind; // 0 = endAttack, 1 = endTurn
  int confirmOpenedMs = 0;
  int? pendingNukeTerr;
  int? passDevicePlayer;
  int? _lastViewerTurn;
  String? _activeOfferKey;
  ({int sel, int? target, int n})? peekState;
  Map<int, bool> onlMap = {};
  int? watchersCount;

  // Timers & Turn clock
  int? turnLimitMs;
  int turnDeadlineMs = 0;
  int _warnTurnN = -1;
  int _lastTickSec = -1;
  Timer? _clockTimer;
  Timer? _botTimer;
  Timer? _fxCleanupTimer;

  // FX / Cinema / Banners
  int _evN = -1;
  bool _hasEvN = false;
  int _lastRollN = 0;
  int _roundSeen = 0;
  int? _fogKey;
  int? incomingTerr;
  int cinemaUntilMs = 0;
  List<int>? prevArmies;
  Set<int>? spotlightSet;
  int spotlightUntilMs = 0;
  final List<MapPulse> pulses = [];
  final List<MapStrike> strikes = [];
  final List<MapArrow> arrows = [];
  final List<MapFloatText> floats = [];
  MissileCinema? missile;
  NukeImpactFx? impactFx;
  void Function(double x0, double y0, double x1, double y1, int ms)? onPanTo;
  void Function(bool conquer)? onShake;
  void Function(Map<String, dynamic> view)? onOfferForMe;
  double Function(int a, int b)? getScreenMidY;
  double mapViewportHeight = 600;

  DiceBannerState? diceBanner;
  final List<FlashBannerState> _flashQueue = [];
  FlashBannerState? flashBanner;
  String? toastMessage;
  int toastUntilMs = 0;

  // Victory dismissal (allows inspecting board after game ends)
  bool victoryDismissed = false;
  bool inTutorial = false;

  // Settings & Saved state availability
  bool forceLand = true;
  bool hasSavedLocal = false;
  bool hasSavedGuest = false;
  Map<String, dynamic>? savedOnlineMeta;
  String? pendingJoinSalaCode;
  String? pendingJoinQrCode;

  // Rooms browser state
  bool roomsLoading = false;
  String? roomsError;
  String roomsTab = 'lobby'; // 'lobby' | 'play'
  String roomsQuery = '';
  bool roomsOnlyOpen = false;
  List<Map<String, dynamic>> publicLobbyRooms = [];
  List<Map<String, dynamic>> publicPlayRooms = [];
  int maxWatchers = 0;
  int? pingMs;
  int? _pingSentMs;

  void Function()? _unsubConn;
  void Function()? _unsubVis;

  Future<void> init() async {
    smoke.setReducedMotion(WebEnv.reducedMotion);
    SoundPlayer.enabled = AppStorage.instance.getString('estandarte.sound') != '0';
    forceLand = AppStorage.instance.getString('estandarte.land') != '0';

    final savedCfg = _readJsonStorage('estandarte.cfg');
    if (savedCfg != null) {
      turnSecs = (savedCfg['secs'] as num?)?.toInt() ?? 120;
      optEvents = savedCfg['events'] == true;
      optPacts = savedCfg['pacts'] == true;
      optNukes = savedCfg['nukes'] == true;
      optHq = savedCfg['hq'] != false;
      optSpy = savedCfg['spy'] == true;
    }

    _unsubConn = WebEnv.listenConnectivity((on) {
      netOnline = on;
      notifyListeners();
    });
    _unsubVis = WebEnv.listenVisibility((hidden) {
      if (!hidden) {
        if (role == 'guest' && guestLink != null) {
          guestLink!.send({'t': 'sync'});
        }
        if (online != null && guestLink == null && !online!.gone) {
          _reconnectOnline();
        } else if (role == 'guest' && (guestLink == null || hostLag) && online == null) {
          _tryAutoSpare();
        }
      }
    });

    unawaited(
      P2P.initCert().then((ok) {
        p2pCertReady = ok;
        notifyListeners();
      }),
    );

    _refreshSavedFlags();

    // Check URL params / hash
    final sala = roomCode(WebEnv.getQueryParam('sala'));
    final hash = WebEnv.getHash();
    if (sala != null) {
      pendingJoinSalaCode = sala;
      WebEnv.replaceCleanUrl(sala);
    } else if (hash.startsWith('#j=')) {
      final raw = Uri.decodeComponent(hash.substring(3));
      pendingJoinQrCode = raw;
      WebEnv.replaceCleanUrl();
    } else if (savedOnlineMeta != null) {
      // Auto-rejoin previous online game if token is stored (< 6h)
      final at = (savedOnlineMeta!['at'] as num?)?.toInt() ?? 0;
      if (at == 0 || DateTime.now().millisecondsSinceEpoch - at < 6 * 3600 * 1000) {
        _resumeSavedOnline();
      } else {
        AppStorage.instance.remove('estandarte.online');
        savedOnlineMeta = null;
      }
    }

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) => _tickHeartbeat());

    _fxCleanupTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      var changed = false;
      pulses.removeWhere((p) {
        final rm = now - p.startMs > p.durMs;
        if (rm) changed = true;
        return rm;
      });
      strikes.removeWhere((s) {
        final rm = now - s.startMs > s.durMs;
        if (rm) changed = true;
        return rm;
      });
      arrows.removeWhere((a) {
        final rm = now - a.startMs > a.durMs;
        if (rm) changed = true;
        return rm;
      });
      floats.removeWhere((f) {
        final rm = now - f.startMs > f.durMs;
        if (rm) changed = true;
        return rm;
      });
      if (missile != null && now - missile!.startMs > missile!.alarmMs + missile!.flightMs + 100) {
        missile = null;
        changed = true;
      }
      if (impactFx != null && now - impactFx!.startMs > 2500) {
        impactFx = null;
        changed = true;
      }
      if (incomingTerr != null && now >= cinemaUntilMs - 2600) {
        incomingTerr = null;
        changed = true;
      }
      if (spotlightSet != null && now > spotlightUntilMs) {
        spotlightSet = null;
        changed = true;
      }
      if (diceBanner != null && now > diceBanner!.untilMs) {
        diceBanner = null;
        changed = true;
      }
      if (flashBanner != null && now >= flashBanner!.untilMs) {
        _advanceFlashQueue();
        changed = true;
      }
      if (toastMessage != null && now > toastUntilMs) {
        toastMessage = null;
        changed = true;
      }
      if (changed) notifyListeners();
    });

    notifyListeners();
  }

  void _refreshSavedFlags() {
    hasSavedLocal = AppStorage.instance.getString('estandarte.save3') != null;
    hasSavedGuest = AppStorage.instance.getString('estandarte.guest') != null &&
        AppStorage.instance.getString('estandarte.spare') != null;
    final onlRaw = AppStorage.instance.getString('estandarte.online');
    if (onlRaw != null) {
      try {
        savedOnlineMeta = jsonDecode(onlRaw) as Map<String, dynamic>;
      } catch (_) {
        savedOnlineMeta = null;
      }
    } else {
      savedOnlineMeta = null;
    }
  }

  Map<String, dynamic>? _readJsonStorage(String key) {
    final raw = AppStorage.instance.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String get savedName => AppStorage.instance.getString('estandarte.name') ?? '';

  void savePlayerName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) {
      AppStorage.instance.remove('estandarte.name');
    } else {
      AppStorage.instance.setString(
        'estandarte.name',
        clean.length > 14 ? clean.substring(0, 14) : clean,
      );
    }
  }

  void setHoverInfoTerr(int? t) {
    if (hoverInfoTerr == t) return;
    hoverInfoTerr = t;
    notifyListeners();
  }

  void toggleSound() {
    SoundPlayer.unlock();
    SoundPlayer.enabled = !SoundPlayer.enabled;
    AppStorage.instance.setString('estandarte.sound', SoundPlayer.enabled ? '1' : '0');
    notifyListeners();
  }

  void goHome() {
    _roomsTimer?.cancel();
    _roomsTimer = null;
    screen = AppScreen.home;
    notifyListeners();
  }

  void dismissVictory() {
    victoryDismissed = true;
    notifyListeners();
  }

  void toggleForceLand() {
    forceLand = !forceLand;
    AppStorage.instance.setString('estandarte.land', forceLand ? '1' : '0');
    notifyListeners();
  }

  void showToast(String msg, [int ms = 2600]) {
    toastMessage = msg;
    toastUntilMs = DateTime.now().millisecondsSinceEpoch + ms;
    notifyListeners();
  }

  void showFlash(
    String title,
    Color color, {
    String sub = '',
    int ms = 1000,
    bool big = false,
    bool top = false,
    bool urgent = false,
  }) {
    final isUrgent = urgent || big;
    final item = FlashBannerState(
      title: title,
      color: color,
      sub: sub,
      big: !top,
      top: top,
      durMs: ms,
      urgent: isUrgent,
      untilMs: 0,
    );
    if (isUrgent) {
      _flashQueue.removeWhere((q) => !q.urgent);
    } else {
      final idx = _flashQueue.indexWhere((q) => !q.urgent);
      if (idx >= 0) _flashQueue.removeAt(idx);
    }
    _flashQueue.add(item);
    if (_flashQueue.length > 3) _flashQueue.removeAt(0);
    if (flashBanner == null || (isUrgent && !flashBanner!.urgent)) {
      _advanceFlashQueue();
    }
  }

  void _advanceFlashQueue() {
    if (_flashQueue.isEmpty) {
      flashBanner = null;
      return;
    }
    final next = _flashQueue.removeAt(0);
    final now = DateTime.now().millisecondsSinceEpoch;
    flashBanner = FlashBannerState(
      title: next.title,
      color: next.color,
      sub: next.sub,
      big: next.big,
      top: next.top,
      durMs: next.durMs,
      urgent: next.urgent,
      untilMs: now + next.durMs,
    );
    notifyListeners();
  }

  // ---------------- Local & Host Lobby Setup ----------------

  void startLocalSetup({bool withP2p = true, String? hostName}) {
    SoundPlayer.unlock();
    _resetSessionState();
    role = 'host';
    netP2p = withP2p;
    me = 0;

    final rawName = hostName != null ? cleanName(hostName) : cleanName(savedName);
    if (hostName != null) savePlayerName(hostName);
    final name = rawName.isNotEmpty ? rawName : 'Jogador';
    seats = [
      LobbySeat(name: name, color: 0, ctrl: 'local'),
    ];
    screen = AppScreen.lobby;
    notifyListeners();
  }

  void startTutorial({String? playerName}) {
    SoundPlayer.unlock();
    _resetSessionState();
    inTutorial = true;
    role = 'host';
    netP2p = false;
    me = 0;
    turnSecs = 0;
    optEvents = false;
    optPacts = false;
    optNukes = true;
    optHq = true;
    optSpy = true;

    final rawName = playerName != null ? cleanName(playerName) : cleanName(savedName);
    if (playerName != null && rawName.isNotEmpty) savePlayerName(playerName);
    final name = rawName.isNotEmpty ? rawName : 'Você';
    seats = [
      LobbySeat(name: name, color: 0, ctrl: 'local'),
      LobbySeat(name: 'Instrutor', color: 1, ctrl: 'bot'),
    ];

    final tmpId = engine.newGame(
      seats: seats.map((s) => s.toEngineSeat()).toList(),
      opts: {'events': false, 'pacts': false, 'nukes': true, 'hq': true, 'spy': true},
      seed: 42,
    );
    final st = engine.exportGame(tmpId);
    engine.dropGame(tmpId);

    st['players'] = [
      {
        'name': name,
        'color': 0,
        'ctrl': 'local',
        'seat': 0,
        'alive': true,
        'cards': <int>[],
        'obj': 6, // Dominar 32 territórios (2 jogadores)
        'killedBy': null,
        'conquered': false,
        'lastTrade': 'normal',
        'medals': 1,
      },
      {
        'name': 'Instrutor',
        'color': 1,
        'ctrl': 'bot',
        'seat': 1,
        'alive': true,
        'cards': <int>[],
        'obj': 7,
        'killedBy': null,
        'conquered': false,
        'lastTrade': 'normal',
        'medals': 0,
      },
    ];
    // Jogador 0 começa com 30 territórios; faltam Argentina (12) e África Ocidental (22) para chegar a 32.
    const foeTerrs = <int>{12, 22, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41};
    const strongBorders = <int>{0, 20, 23, 28, 29, 30, 31};
    st['terr'] = [
      for (var t = 0; t < 42; t++)
        {
          'o': foeTerrs.contains(t) ? 1 : 0,
          'a': t == 11
              ? 12 // Brasil
              : t == 10
                  ? 6 // Peru e Chile
                  : strongBorders.contains(t)
                      ? 15
                      : t == 12
                          ? 1 // Argentina
                          : t == 22
                              ? 2 // África Ocidental (entrincheirada no 1º turno)
                              : 1,
        },
    ];
    st['turn'] = 0;
    st['round'] = 1;
    st['step'] = 'reinforce';
    st['pool'] = {'free': 3, 'cont': <String, int>{}};
    st['orders'] = ['airlift', 'trench', 'spy'];
    st['trenches'] = [
      {'t': 22, 'by': 1},
    ];
    st['log'] = [
      'Tutorial: conquiste a Argentina para juntar 3 medalhas, use o Quartel e domine 32 territórios!',
    ];
    st['ev'] = <Map<String, dynamic>>[];

    _engineId = engine.loadGame(st);
    screen = AppScreen.game;
    WebEnv.setWakeLock(true);
    _syncHost();
    sel = 11; // Pré-seleciona o Brasil
    _reeval();
  }

  ({int step, int total, String title, String body})? get tutorialGuide {
    if (!inTutorial) return null;
    final v = view;
    if (v == null) return null;
    if (v['phase'] == 'over') {
      return (
        step: 5,
        total: 5,
        title: 'Tutorial concluído!',
        body: 'Você dominou os 32 territórios, usou o Quartel e cumpriu seu objetivo secreto!',
      );
    }
    final turnIdx = (v['turn'] as num).toInt();
    if (turnIdx != 0) {
      return (
        step: 3,
        total: 5,
        title: 'Vez do Instrutor…',
        body: 'Aguarde o turno do adversário terminar. A Trincheira na África Ocidental vai se desfazer.',
      );
    }
    final terrs = v['terr'] as List<dynamic>;
    var owned = 0;
    for (final t in terrs) {
      if (((t as Map<String, dynamic>)['o'] as num).toInt() == 0) owned++;
    }
    final medals = medalsOf(0);
    final step = v['step'] as String? ?? 'reinforce';
    final round = (v['round'] as num).toInt();

    if (round == 1 && step == 'reinforce') {
      return (
        step: 1,
        total: 5,
        title: 'Reforço (30 de 32 territórios)',
        body: 'Seu objetivo é dominar 32 territórios. O Brasil já está selecionado: toque no botão dourado "Colocar" para posicionar seus 3 exércitos.',
      );
    }
    if (round == 1 && step == 'attack' && owned < 31) {
      return (
        step: 2,
        total: 5,
        title: 'Ataque e Medalhas',
        body: 'Toque no Brasil e depois na Argentina (1 exército) para atacar! A 1ª conquista do turno dá +1 medalha e fechar a América do Sul dá mais +1 medalha.',
      );
    }
    if (round == 1 && owned >= 31) {
      return (
        step: 3,
        total: 5,
        title: '3 Medalhas conquistadas!',
        body: 'A África Ocidental está protegida por Trincheira neste turno. Toque em "Passar" e depois em "Finalizar turno" para usar o Quartel no próximo turno.',
      );
    }
    if (round >= 2 && step == 'reinforce' && medals >= 2 && _poolTotalOf(v) <= 17) {
      return (
        step: 4,
        total: 5,
        title: 'O Quartel (Medalhas e Ordens)',
        body: 'Abra o botão "Quartel" no painel! Com $medals medalhas você pode clicar em "Mobilizar +${eval?.hq?.effort ?? 5}" (ou usar uma Ordem Tática) e depois reforçar o Brasil.',
      );
    }
    return (
      step: 5,
      total: 5,
      title: 'Golpe Final (Rota Marítima)',
      body: 'Coloque seus reforços no Brasil e ataque a África Ocidental (pela linha tracejada no mar) para conquistar o 32º território e vencer!',
    );
  }

  static int _poolTotalOf(Map<String, dynamic> v) {
    final pool = v['pool'] as Map<String, dynamic>? ?? const {};
    var t = (pool['free'] as num?)?.toInt() ?? 0;
    final cont = pool['cont'] as Map<String, dynamic>? ?? const {};
    for (final val in cont.values) {
      if (val is num) t += val.toInt();
    }
    return t;
  }

  void addLobbyPlayer({bool isBot = false, String? localName}) {
    if (online != null) {
      if (lobbyOwner && guestLink != null && isBot) {
        guestLink!.send({'t': 'addBot'});
      }
      return;
    }
    if (seats.length >= 6) return;
    final used = seats.map((s) => s.color).toSet();
    var c = 0;
    while (used.contains(c) && c < engine.constants.colors.length) {
      c++;
    }
    if (isBot) {
      var n = seats.where((s) => s.ctrl == 'bot').length + 1;
      while (uniqueName('Bot $n', seats, (s) => s.name, isBot: true) != 'Bot $n') {
        n++;
      }
      seats.add(
        LobbySeat(
          name: 'Bot $n',
          color: c,
          ctrl: 'bot',
        ),
      );
    } else {
      final raw = localName != null ? cleanName(localName) : '';
      final base = raw.isNotEmpty ? raw : 'Jogador ${seats.length + 1}';
      seats.add(
        LobbySeat(
          name: uniqueName(base, seats, (s) => s.name),
          color: c,
          ctrl: 'local',
        ),
      );
    }
    _broadcastLobby();
    notifyListeners();
  }

  void updateSeatName(int index, String raw) {
    if (online != null) return;
    if (index < 0 || index >= seats.length) return;
    final clean = cleanName(raw);
    if (clean.isEmpty) return;
    final s = seats[index];
    s.name = uniqueName(clean, seats, (x) => x.name, self: s, isBot: s.ctrl == 'bot');
    if (index == 0) savePlayerName(s.name);
    _broadcastLobby();
    notifyListeners();
  }

  void cycleSeatColor(int index) {
    if (online != null) {
      if ((lobbyOwner || index == me) && guestLink != null) {
        guestLink!.send({'t': 'color', 'i': index});
      }
      return;
    }
    if (index < 0 || index >= seats.length) return;
    final total = engine.constants.colors.length;
    final used = {
      for (var i = 0; i < seats.length; i++)
        if (i != index) seats[i].color,
    };
    var next = (seats[index].color + 1) % total;
    for (var k = 0; k < total; k++) {
      if (!used.contains(next)) {
        seats[index].color = next;
        break;
      }
      next = (next + 1) % total;
    }
    _broadcastLobby();
    notifyListeners();
  }

  void removeSeat(int index) {
    if (online != null) {
      if (lobbyOwner && guestLink != null) {
        guestLink!.send({'t': 'kick', 'i': index});
      }
      return;
    }
    if (index <= 0 || index >= seats.length) return;
    final s = seats.removeAt(index);
    s.link?.close();
    if (s.spare != null && s.spare!['cancel'] is void Function()) {
      (s.spare!['cancel'] as void Function())();
    }
    _broadcastLobby();
    notifyListeners();
  }

  void updateLobbyConfig({
    int? secs,
    bool? events,
    bool? pacts,
    bool? nukes,
    bool? hq,
    bool? spy,
    bool? isPublic,
  }) {
    if (online != null) {
      if (lobbyOwner && guestLink != null) {
        guestLink!.send({
          't': 'cfg',
          'secs': ?secs,
          'events': ?events,
          'pacts': ?pacts,
          'nukes': ?nukes,
          'hq': ?hq,
          'spy': ?spy,
          'public': ?isPublic,
        });
      }
      return;
    }
    if (secs != null) turnSecs = secs;
    if (events != null) optEvents = events;
    if (pacts != null) optPacts = pacts;
    if (nukes != null) optNukes = nukes;
    if (hq != null) optHq = hq;
    if (spy != null) optSpy = spy;
    AppStorage.instance.setString(
      'estandarte.cfg',
      jsonEncode({
        'secs': turnSecs,
        'events': optEvents,
        'pacts': optPacts,
        'nukes': optNukes,
        'hq': optHq,
        'spy': optSpy,
      }),
    );
    _broadcastLobby();
    notifyListeners();
  }

  void beginGame() {
    SoundPlayer.unlock();
    if (online != null) {
      if (lobbyOwner && guestLink != null) {
        guestLink!.send({'t': 'begin'});
      }
      return;
    }
    if (seats.length < 2) {
      showToast('Precisa de pelo menos 2 jogadores.');
      return;
    }
    _dropEngineGame();
    _engineId = engine.newGame(
      seats: seats.map((s) => s.toEngineSeat()).toList(),
      opts: {
        'events': optEvents,
        'pacts': optPacts,
        'nukes': optNukes,
        'hq': optHq,
        'spy': optHq && optSpy,
      },
    );
    _hasEvN = false;
    _lastRollN = 0;
    _lastViewerTurn = null;
    _activeOfferKey = null;
    _roundSeen = 0;
    _fogKey = null;
    victoryDismissed = false;
    sel = null;
    target = null;
    infoTerr = null;
    hoverInfoTerr = null;
    nukeMode = false;
    confirmEndKind = null;
    screen = AppScreen.game;
    WebEnv.setWakeLock(true);
    _armTurnClock();
    _syncHost();
  }

  void _broadcastLobby() {
    if (role != 'host') return;
    for (var i = 0; i < seats.length; i++) {
      final link = seats[i].link;
      if (link != null && link.isOpen) {
        link.send({
          't': 'lobby',
          'seats': seats.map((s) => s.toLobbyJson()).toList(),
          'you': i,
          'secs': turnSecs,
          'events': optEvents,
          'pacts': optPacts,
          'nukes': optNukes,
          'hq': optHq,
          'spy': optHq && optSpy,
        });
      }
    }
  }

  // ---------------- Host P2P QR Invite / Reconnect ----------------

  Future<P2PInvite> createP2PInviteForSeat({int? reconnectSeat}) async {
    SoundPlayer.unlock();
    if (role != 'host' && role != 'local') {
      throw StateError('Apenas o anfitrião cria convites QR.');
    }
    final invite = await P2P.createInvite(
      onOpen: (link) {
        if (reconnectSeat != null) {
          _attachRemoteSeat(reconnectSeat, link);
          return;
        }
        // New guest seat
        if (seats.length >= 6) {
          link.send({'t': 'gone', 'm': 'Sala cheia (máximo 6).'});
          link.close();
          return;
        }
        final used = seats.map((s) => s.color).toSet();
        var col = 0;
        while (used.contains(col) && col < engine.constants.colors.length) {
          col++;
        }
        final idx = seats.length;
        seats.add(
          LobbySeat(
            name: uniqueName('Convidado $idx', seats, (s) => s.name),
            color: col,
            ctrl: 'remote',
            online: true,
            link: link,
          ),
        );
        _armSpareForSeat(idx, link);
        _broadcastLobby();
        notifyListeners();
      },
      onMessage: (msg, link) => _handleHostMessage(msg, link),
      onClose: (link) => _handleHostLinkClosed(link),
    );
    if (reconnectSeat != null && reconnectSeat >= 0 && reconnectSeat < seats.length) {
      seats[reconnectSeat].link?.close();
    }
    return invite;
  }

  void _attachRemoteSeat(int seatIdx, GameLink link) {
    if (seatIdx < 0 || seatIdx >= seats.length) return;
    final seat = seats[seatIdx];
    seat.link?.close();
    seat.link = link;
    seat.ctrl = 'remote';
    seat.online = true;
    // Update active game controller if game started
    if (_engineId != null && view != null) {
      final players = (view!['players'] as List<dynamic>);
      for (var p = 0; p < players.length; p++) {
        if ((players[p]['seat'] as num).toInt() == seatIdx) {
          engine.setPlayerCtrl(_engineId!, p, 'remote');
        }
      }
    }
    _armSpareForSeat(seatIdx, link);
    if (_engineId != null) {
      _syncHost();
    } else {
      _broadcastLobby();
      notifyListeners();
    }
  }

  Future<void> _armSpareForSeat(int seatIdx, GameLink link) async {
    final fp = link.peerFp;
    if (fp == null || !p2pCertReady || seatIdx < 0 || seatIdx >= seats.length) return;
    final seat = seats[seatIdx];
    _dropSeatSpare(seat);
    try {
      final spare = await P2P.armSpare(
        fp,
        onOpen: (spareLink) {
          if (seat.link != null && seat.link != spareLink) {
            seat.link!.close();
          }
          seat.link = spareLink;
          seat.spare = null;
          _attachRemoteSeat(seatIdx, spareLink);
        },
        onMessage: (msg, l) => _handleHostMessage(msg, l),
        onClose: (l) => _handleHostLinkClosed(l),
      );
      seat.spare = {'cancel': spare.cancel};
      link.send({
        't': 'spare',
        'code': spare.code,
        'gu': spare.gu,
        'gp': spare.gp,
      });
    } catch (_) {}
  }

  void _dropSeatSpare(LobbySeat s) {
    final sp = s.spare;
    if (sp != null && sp['cancel'] is void Function()) {
      (sp['cancel'] as void Function())();
    }
    s.spare = null;
  }

  void _handleHostMessage(Map<String, dynamic> msg, GameLink link) {
    final idx = seats.indexWhere((s) => s.link == link);
    if (idx >= 0) {
      final st = seats[idx];
      st.seenMs = DateTime.now().millisecondsSinceEpoch;
      if (st.lag) {
        st.lag = false;
        notifyListeners();
      }
    }
    final t = msg['t'] as String?;
    if (t == 'pong') return;
    if (t == 'sync') {
      if (_engineId != null) _syncHost();
      return;
    }
    if (t == 'hello') {
      if (idx < 0) return;
      final nm = cleanName(msg['name'] as String?);
      if (nm.isNotEmpty && _engineId == null) {
        seats[idx].name = uniqueName(nm, seats, (s) => s.name, self: seats[idx]);
        _broadcastLobby();
        notifyListeners();
      } else if (_engineId != null) {
        _syncHost();
      }
      return;
    }
    if (idx < 0) return;
    if (t == 'color' && _engineId == null) {
      cycleSeatColor(idx);
      return;
    }
    if (t == 'leave') {
      if (_engineId == null) {
        removeSeat(idx);
      } else {
        seats[idx].ctrl = 'bot';
        seats[idx].link = null;
        if (view != null) {
          final players = view!['players'] as List<dynamic>;
          for (var p = 0; p < players.length; p++) {
            if ((players[p]['seat'] as num).toInt() == idx) {
              engine.setPlayerCtrl(_engineId!, p, 'bot');
            }
          }
        }
        _syncHost();
      }
      return;
    }
    if (t == 'peek' && _engineId != null) {
      final n = msg['n'];
      final sVal = msg['sel'];
      final tgtVal = msg['target'];
      peekState = (
        n: (n as num).toInt(),
        sel: (sVal as num).toInt(),
        target: tgtVal is num ? tgtVal.toInt() : null,
      );
      for (final s in seats) {
        if (s.link != null && s.link!.isOpen && s.link != link) {
          s.link!.send(msg);
        }
      }
      notifyListeners();
      return;
    }
    if (t == 'act' && _engineId != null && view != null) {
      final pIdx = (view!['players'] as List<dynamic>).indexWhere(
        (p) => (p['seat'] as num).toInt() == idx,
      );
      if (pIdx < 0) return;
      final a = msg['a'] as Map<String, dynamic>?;
      if (a == null) return;
      final err = engine.apply(_engineId!, pIdx, a);
      if (err.isNotEmpty) {
        link.send({'t': 'err', 'm': err});
      } else {
        _syncHost();
      }
    }
  }

  void _tickHeartbeat() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (role == 'host') {
      var changed = false;
      for (final s in seats) {
        if (s.link == null || !s.link!.isOpen) continue;
        s.link!.send({'t': 'ping', 'n': view?['n']});
        if (!s.lag && s.seenMs > 0 && now - s.seenMs > 9000) {
          s.lag = true;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } else if (role == 'guest' &&
        guestLink != null &&
        _hostLastHeardMs > 0 &&
        !hostLag &&
        now - _hostLastHeardMs > 9000) {
      hostLag = true;
      if (online != null && !online!.gone) {
        final l = guestLink;
        guestLink = null;
        l?.close();
        _reconnectOnline();
      } else {
        _tryAutoSpare();
      }
      notifyListeners();
    }
  }

  void _handleHostLinkClosed(GameLink link) {
    final idx = seats.indexWhere((s) => s.link == link);
    if (idx < 0) return;
    seats[idx].link = null;
    seats[idx].online = false;
    if (_engineId != null) {
      _syncHost();
    } else {
      notifyListeners();
    }
  }

  void convertSeatToBot(int seatIdx) {
    if (role != 'host' && role != 'local') return;
    if (seatIdx < 0 || seatIdx >= seats.length) return;
    seats[seatIdx].ctrl = 'bot';
    seats[seatIdx].link?.close();
    seats[seatIdx].link = null;
    _dropSeatSpare(seats[seatIdx]);
    if (_engineId != null && view != null) {
      final players = view!['players'] as List<dynamic>;
      for (var p = 0; p < players.length; p++) {
        if ((players[p]['seat'] as num).toInt() == seatIdx) {
          engine.setPlayerCtrl(_engineId!, p, 'bot');
        }
      }
      _syncHost();
    } else {
      _broadcastLobby();
      notifyListeners();
    }
  }

  // ---------------- Guest P2P QR Join / Auto-Spare ----------------

  Future<P2PJoinResult> joinViaQrCode(String offerCode, String playerName) async {
    SoundPlayer.unlock();
    savePlayerName(playerName);
    _resetSessionState();
    role = 'guest';
    netP2p = true;

    late P2PJoinResult res;
    res = await P2P.joinInvite(
      offerCode,
      onOpen: (link) {
        guestLink = link;
        final nm = cleanName(playerName);
        link.send({'t': 'hello', 'name': nm.isNotEmpty ? nm : 'Convidado'});
        AppStorage.instance.setString(
          'estandarte.guest',
          jsonEncode({'name': nm, 'savedAt': DateTime.now().millisecondsSinceEpoch}),
        );
        _refreshSavedFlags();
        screen = AppScreen.lobby;
        WebEnv.setWakeLock(true);
        notifyListeners();
      },
      onMessage: (msg, link) => _handleRemoteMessage(msg, link),
      onClose: (link) {
        if (guestLink == link) {
          guestLink = null;
          _tryAutoSpare();
          notifyListeners();
        }
      },
    );
    return res;
  }

  Future<void> _tryAutoSpare() async {
    if (autoReconnecting || role != 'guest' || online != null) return;
    final raw = savedSpare ?? _readJsonStorage('estandarte.spare');
    if (raw == null) return;
    savedSpare = raw;
    autoReconnecting = true;
    notifyListeners();
    try {
      final attempt = await P2P.useSpare(
        raw,
        onOpen: (link) {
          guestLink = link;
          autoReconnecting = false;
          savedSpare = null;
          AppStorage.instance.remove('estandarte.spare');
          showToast('Reconectado!', 1800);
          notifyListeners();
        },
        onMessage: (msg, l) => _handleRemoteMessage(msg, l),
        onClose: (l) {
          if (guestLink == l) {
            guestLink = null;
            notifyListeners();
          }
        },
      );
      final ok = await attempt.opened(const Duration(seconds: 10));
      if (!ok) {
        attempt.cancel();
        autoReconnecting = false;
        notifyListeners();
      }
    } catch (_) {
      autoReconnecting = false;
      notifyListeners();
    }
  }

  // ---------------- Online Client & Rooms Browser ----------------

  void setRoomsTab(String tab) {
    if (roomsTab == tab) return;
    roomsTab = tab;
    notifyListeners();
  }

  void setRoomsQuery(String q) {
    roomsQuery = q;
    notifyListeners();
  }

  void toggleRoomsOnlyOpen() {
    roomsOnlyOpen = !roomsOnlyOpen;
    notifyListeners();
  }

  Future<void> refreshRooms({bool silent = false}) async {
    if (!silent) {
      roomsLoading = true;
      roomsError = null;
      notifyListeners();
    }
    try {
      final res = await listRooms(serverUrl());
      publicLobbyRooms = ((res['lobby'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();
      publicPlayRooms = ((res['play'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();
      maxWatchers = (res['maxWatchers'] as num?)?.toInt() ?? 5;
      roomsError = null;
    } catch (_) {
      if (!silent || (publicLobbyRooms.isEmpty && publicPlayRooms.isEmpty)) {
        roomsError = 'O servidor não respondeu. Tentando de novo…';
      }
    } finally {
      roomsLoading = false;
      notifyListeners();
    }
  }

  void openRoomsBrowser() {
    SoundPlayer.unlock();
    screen = AppScreen.rooms;
    roomsError = null;
    notifyListeners();
    unawaited(refreshRooms());
    _roomsTimer?.cancel();
    _roomsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (screen == AppScreen.rooms) {
        unawaited(refreshRooms(silent: true));
      } else {
        _roomsTimer?.cancel();
      }
    });
  }

  void createOnlineRoom(String playerName, {bool isPublic = true}) {
    final nm = cleanName(playerName);
    final finalName = nm.isNotEmpty ? nm : 'Jogador';
    savePlayerName(finalName);
    _connectOnlineQuery(
      'create=1',
      host: true,
      fromRooms: screen == AppScreen.rooms,
      name: finalName,
      isPublic: isPublic,
    );
  }

  void joinOnlineRoom(
    String code,
    String playerName, {
    bool watchOnly = false,
    bool fromRooms = false,
    String? token,
  }) {
    final cleanCode = roomCode(code);
    if (cleanCode == null) {
      showToast('Digite o código de 5 letras ou cole o link da sala.');
      return;
    }
    final nm = cleanName(playerName);
    final finalName = nm.isNotEmpty ? nm : 'Convidado';
    if (!watchOnly) savePlayerName(finalName);
    final srv = serverUrl();
    final tok = token ?? _loadRoomToken(srv, cleanCode);
    final q = StringBuffer('room=${Uri.encodeQueryComponent(cleanCode)}');
    if (watchOnly) q.write('&watch=1');
    _connectOnlineQuery(
      q.toString(),
      host: false,
      fromRooms: fromRooms || screen == AppScreen.rooms,
      name: finalName,
      code: cleanCode,
      token: tok,
      watchOnly: watchOnly,
    );
  }

  void _connectOnlineQuery(
    String query, {
    required bool host,
    required bool fromRooms,
    required String name,
    String? code,
    String? token,
    bool isPublic = true,
    bool watchOnly = false,
  }) {
    SoundPlayer.unlock();
    if (!netOnline) {
      showToast('Sem internet: jogar online precisa de conexão.', 4000);
      return;
    }
    final wasFromRooms = fromRooms;
    _resetSessionState();
    role = 'guest';
    netP2p = false;
    final srv = serverUrl();
    final ses = OnlineSession(
      server: srv,
      code: code,
      host: host,
      fromRooms: wasFromRooms,
      name: name,
      token: token,
      owner: host,
      isPublic: isPublic,
    )..waitMsg = 'Conectando ao servidor…';
    online = ses;
    screen = AppScreen.lobby;
    lobbyCode = code;
    lobbyOwner = host;
    optPublic = isPublic;
    WebEnv.setWakeLock(true);
    notifyListeners();

    guestLink = connectOnline(
      srv,
      query,
      onOpen: (link) {
        ses.waitMsg = '';
        guestLink = link;
        hostLag = false;
        _hostLastHeardMs = DateTime.now().millisecondsSinceEpoch;
        if (!watchOnly) {
          link.send({
            't': 'hello',
            'name': name,
            if (ses.token != null) 'token': ses.token,
          });
        } else {
          link.send({'t': 'hello', 'name': name});
        }
        if (ses.code != null) {
          _saveOnlineSession(watch: watchOnly);
        }
        notifyListeners();
      },
      onMessage: (msg, link) => _handleRemoteMessage(msg, link),
      onClose: (link) {
        if (guestLink == link) {
          guestLink = null;
          if (online == ses && !ses.gone) {
            ses.waitMsg = 'Conexão perdida. Reconectando…';
            _onlineRetryTimer?.cancel();
            _onlineRetryTimer = Timer(const Duration(milliseconds: 1200), _reconnectOnline);
          }
          notifyListeners();
        }
      },
      onWait: (secs, _) {
        if (online == ses) {
          ses.waitMsg = secs < 6
              ? 'Conectando ao servidor…'
              : 'Acordando o servidor (${secs}s)… aguarde até 1 min.';
          notifyListeners();
        }
      },
      onFail: () {
        if (online == ses) {
          ses.waitMsg = 'Não foi possível falar com o servidor.';
          notifyListeners();
        }
      },
    );
  }

  void _reconnectOnline() {
    final ses = online;
    if (ses == null || ses.gone || ses.code == null || guestLink != null) return;
    final tok = ses.token ?? _loadRoomToken(ses.server, ses.code!);
    final q = 'room=${Uri.encodeQueryComponent(ses.code!)}';
    guestLink = connectOnline(
      ses.server,
      q,
      onOpen: (link) {
        ses.waitMsg = '';
        guestLink = link;
        hostLag = false;
        _hostLastHeardMs = DateTime.now().millisecondsSinceEpoch;
        link.send({
          't': 'hello',
          'name': ses.name,
          'token': ?tok,
        });
        notifyListeners();
      },
      onMessage: (msg, link) => _handleRemoteMessage(msg, link),
      onClose: (link) {
        if (guestLink == link) {
          guestLink = null;
          if (online == ses && !ses.gone) {
            _onlineRetryTimer?.cancel();
            _onlineRetryTimer = Timer(const Duration(seconds: 3), _reconnectOnline);
          }
          notifyListeners();
        }
      },
      onWait: (secs, _) {
        if (online == ses) {
          ses.waitMsg = 'Reconectando (${secs}s)…';
          notifyListeners();
        }
      },
      onFail: () {
        if (online == ses) {
          ses.waitMsg = 'Desconectado do servidor.';
          notifyListeners();
        }
      },
    );
  }

  String? _loadRoomToken(String srv, String code) {
    final all = _readJsonStorage('estandarte.tokens');
    if (all == null) return null;
    final entry = all['$srv|$code'];
    return entry is Map ? entry['token'] as String? : null;
  }

  void _saveRoomToken(String srv, String code, String token) {
    final all = _readJsonStorage('estandarte.tokens') ?? <String, dynamic>{};
    all['$srv|$code'] = {'token': token, 'at': DateTime.now().millisecondsSinceEpoch};
    final entries = all.entries.toList()
      ..sort((a, b) {
        final atA = (a.value is Map ? a.value['at'] as num? : null) ?? 0;
        final atB = (b.value is Map ? b.value['at'] as num? : null) ?? 0;
        return atB.compareTo(atA);
      });
    final trimmed = Map<String, dynamic>.fromEntries(entries.take(20));
    AppStorage.instance.setString('estandarte.tokens', jsonEncode(trimmed));
  }

  void _saveOnlineSession({bool watch = false}) {
    final ses = online;
    if (ses == null || ses.code == null) return;
    if (ses.token != null) {
      _saveRoomToken(ses.server, ses.code!, ses.token!);
    }
    AppStorage.instance.setString(
      'estandarte.online',
      jsonEncode({
        'server': ses.server,
        'code': ses.code,
        if (ses.token != null) 'token': ses.token,
        'name': ses.name,
        'host': ses.host,
        'owner': ses.owner,
        'fromRooms': ses.fromRooms,
        'watch': watch,
        'at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    _refreshSavedFlags();
  }

  void _resumeSavedOnline() {
    final m = savedOnlineMeta;
    if (m == null) return;
    final code = m['code'] as String?;
    final tok = m['token'] as String?;
    final nm = m['name'] as String? ?? 'Jogador';
    if (code == null) return;
    joinOnlineRoom(
      code,
      nm,
      watchOnly: m['watch'] == true,
      fromRooms: m['fromRooms'] == true,
      token: tok,
    );
  }

  void _handleRemoteMessage(Map<String, dynamic> msg, GameLink link) {
    final t = msg['t'] as String?;
    if (t == 'seat') {
      final tok = msg['token'] as String?;
      if (online != null && tok != null) {
        online!.token = tok;
        _saveOnlineSession();
      }
      return;
    }
    if (t == 'spare') {
      savedSpare = msg;
      AppStorage.instance.setString('estandarte.spare', jsonEncode(msg));
      _refreshSavedFlags();
      return;
    }
    if (t == 'ping') {
      _hostLastHeardMs = DateTime.now().millisecondsSinceEpoch;
      hostLag = false;
      link.send({'t': 'pong', 'n': msg['n']});
      if (_pingSentMs != null) {
        pingMs = DateTime.now().millisecondsSinceEpoch - _pingSentMs!;
        _pingSentMs = null;
      }
      return;
    }
    if (t == 'err') {
      showToast(msg['m'] as String? ?? 'Ação inválida.');
      return;
    }
    if (t == 'gone') {
      final m = msg['m'] as String? ?? 'Sala encerrada.';
      if (online != null) {
        online!.gone = true;
        AppStorage.instance.remove('estandarte.online');
      } else {
        AppStorage.instance.remove('estandarte.guest');
        AppStorage.instance.remove('estandarte.spare');
      }
      leaveGame(showReason: m);
      return;
    }
    if (t == 'lobby') {
      _hostLastHeardMs = DateTime.now().millisecondsSinceEpoch;
      hostLag = false;
      screen = AppScreen.lobby;
      final rawSeats = (msg['seats'] as List<dynamic>? ?? const []);
      seats = rawSeats
          .map((e) {
            final s = e as Map<String, dynamic>;
            return LobbySeat(
              name: s['name'] as String? ?? '',
              color: (s['color'] as num?)?.toInt() ?? 0,
              ctrl: s['ctrl'] as String? ?? 'remote',
              online: s['on'] == true,
            );
          })
          .toList();
      me = (msg['you'] as num?)?.toInt() ?? -1;
      turnSecs = (msg['secs'] as num?)?.toInt() ?? 0;
      optEvents = msg['events'] == true;
      optPacts = msg['pacts'] == true;
      optNukes = msg['nukes'] == true;
      optHq = msg['hq'] == true;
      optSpy = msg['spy'] == true;
      optPublic = msg['public'] == true;
      lobbyCode = msg['code'] as String?;
      lobbyOwner = msg['owner'] == true;
      if (online != null) {
        online!.code = lobbyCode ?? online!.code;
        online!.owner = lobbyOwner;
        online!.isPublic = optPublic;
        _saveOnlineSession();
      }
      notifyListeners();
      return;
    }
    if (t == 'state') {
      _hostLastHeardMs = DateTime.now().millisecondsSinceEpoch;
      hostLag = false;
      screen = AppScreen.game;
      final sView = msg['s'] as Map<String, dynamic>;
      me = (msg['you'] as num?)?.toInt() ?? -1;
      turnLimitMs = msg['limit'] is num ? (msg['limit'] as num).toInt() : null;
      final leftMs = msg['left'] is num ? (msg['left'] as num).toInt() : null;
      if (leftMs != null) {
        turnDeadlineMs = DateTime.now().millisecondsSinceEpoch + leftMs;
        _ensureClockRunning();
      } else {
        turnDeadlineMs = 0;
      }
      lobbyCode = msg['code'] as String? ?? lobbyCode;
      lobbyOwner = msg['owner'] == true;
      watchersCount = msg['watchers'] is num ? (msg['watchers'] as num).toInt() : null;
      onlMap = {};
      final onRaw = msg['on'];
      if (onRaw is Map<String, dynamic>) {
        for (final e in onRaw.entries) {
          onlMap[int.parse(e.key)] = e.value == true;
        }
      } else if (onRaw is List<dynamic>) {
        for (var i = 0; i < onRaw.length; i++) {
          onlMap[i] = onRaw[i] == true;
        }
      }
      _applyIncomingView(sView);
      return;
    }
    if (t == 'peek') {
      final v = view;
      if (v != null && (msg['n'] as num?)?.toInt() == v['n']) {
        peekState = (
          n: (msg['n'] as num).toInt(),
          sel: (msg['sel'] as num).toInt(),
          target: msg['target'] is num ? (msg['target'] as num).toInt() : null,
        );
        notifyListeners();
      }
    }
  }

  void requestPlayAgainOnline() {
    if (online != null && lobbyOwner && guestLink != null) {
      guestLink!.send({'t': 'again'});
    } else if (role != 'guest') {
      beginGame();
    }
  }

  // ---------------- Host State Sync + Bot + Turn Clock ----------------

  void _syncHost() {
    final id = _engineId;
    if (id == null) return;
    final v = engine.viewFor(id, 0);
    final players = v['players'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    int viewerIdx = 0;
    if (players[turnIdx]['ctrl'] == 'local') {
      viewerIdx = turnIdx;
    } else if (_lastViewerTurn != null &&
        _lastViewerTurn! >= 0 &&
        _lastViewerTurn! < players.length &&
        players[_lastViewerTurn!]['ctrl'] == 'local') {
      viewerIdx = _lastViewerTurn!;
    } else {
      final aliveLocal = players.indexWhere((p) => p['ctrl'] == 'local' && p['alive'] == true);
      final anyLocal = players.indexWhere((p) => p['ctrl'] == 'local');
      viewerIdx = aliveLocal >= 0 ? aliveLocal : (anyLocal >= 0 ? anyLocal : 0);
    }
    final hostView = engine.viewFor(id, viewerIdx);
    me = viewerIdx;

    // Arm turn deadline if turn changed
    final turnKey = '${hostView['round']}:${hostView['turn']}';
    final leftMs = turnSecs > 0 && hostView['phase'] == 'play'
        ? max(0, turnDeadlineMs - DateTime.now().millisecondsSinceEpoch)
        : null;

    // Broadcast personalized views to remote guests
    final onlineByTurn = <int, bool>{};
    for (var p = 0; p < players.length; p++) {
      final seatIdx = (players[p]['seat'] as num).toInt();
      onlineByTurn[p] = seats[seatIdx].ctrl != 'remote' ||
          (seats[seatIdx].link != null && seats[seatIdx].link!.isOpen && !seats[seatIdx].lag);
    }
    onlMap = onlineByTurn;
    for (var p = 0; p < players.length; p++) {
      final seatIdx = (players[p]['seat'] as num).toInt();
      final link = seats[seatIdx].link;
      if (link != null && link.isOpen) {
        final pv = engine.viewFor(id, p);
        link.send({
          't': 'state',
          's': pv,
          'you': p,
          'left': ?leftMs,
          if (turnSecs > 0) 'limit': turnSecs * 1000,
          'on': {for (final e in onlineByTurn.entries) '${e.key}': e.value},
        });
      }
    }

    // Save host/local game (`save3`)
    if (!inTutorial) {
      final stateJson = engine.exportGame(id);
      if (hostView['phase'] == 'play') {
        AppStorage.instance.setString(
          'estandarte.save3',
          jsonEncode({
            'game': stateJson,
            'seats': seats.map((s) => {'name': s.name, 'color': s.color, 'ctrl': s.ctrl}).toList(),
            'secs': turnSecs,
            'role': role,
            'savedAt': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      } else {
        AppStorage.instance.remove('estandarte.save3');
      }
      _refreshSavedFlags();
    }

    _applyIncomingView(hostView, turnKeyForClock: turnKey);
    _scheduleHostBot(hostView);
  }

  String _lastClockTurnKey = '';

  void _armTurnClock() {
    _clockTimer?.cancel();
    _lastClockTurnKey = '';
    _warnTurnN = -1;
    _lastTickSec = -1;
  }

  void _ensureClockRunning() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final v = view;
      if (v == null || v['phase'] != 'play' || turnDeadlineMs <= 0) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final leftMs = turnDeadlineMs - now;
      final sec = (leftMs / 1000).ceil();
      final canIPlay = canPlayNow();
      if (canIPlay && leftMs <= 10500 && leftMs > 0) {
        if (_warnTurnN != v['n'] && sec <= 10) {
          _warnTurnN = (v['n'] as num).toInt();
          SoundPlayer.play('warn');
        } else if (sec != _lastTickSec && sec <= 5 && sec > 0) {
          SoundPlayer.play('tick');
        }
        _lastTickSec = sec;
      }
      if (role != 'guest' && _engineId != null && leftMs <= 0) {
        engine.forceEnd(_engineId!);
        _syncHost();
        return;
      }
      notifyListeners();
    });
  }

  void _scheduleHostBot(Map<String, dynamic> v) {
    _botTimer?.cancel();
    if (role == 'guest' || _engineId == null || v['phase'] != 'play') return;

    final offer = v['offer'] as Map<String, dynamic>?;
    final players = v['players'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final offerTargetBot = offer != null && players[(offer['to'] as num).toInt()]['ctrl'] == 'bot';
    final turnIsBot = players[turnIdx]['ctrl'] == 'bot';
    if (!offerTargetBot && !turnIsBot) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    var delayMs = v['roll'] != null ? 580 : 420;
    if (cinemaUntilMs > now) {
      delayMs = max(delayMs, cinemaUntilMs - now + 200);
    }

    _botTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_engineId == null) return;
      final curView = engine.viewFor(_engineId!, 0);
      if (curView['phase'] != 'play') return;
      final curOffer = curView['offer'] as Map<String, dynamic>?;
      final curPlayers = curView['players'] as List<dynamic>;
      if (curOffer != null) {
        final toIdx = (curOffer['to'] as num).toInt();
        if (curPlayers[toIdx]['ctrl'] == 'bot') {
          final act = engine.botPactReply(_engineId!);
          if (act != null) {
            engine.apply(_engineId!, toIdx, act);
            _syncHost();
            return;
          }
        }
      }
      final tIdx = (curView['turn'] as num).toInt();
      if (curPlayers[tIdx]['ctrl'] == 'bot') {
        final act = engine.botAction(_engineId!);
        if (act != null) {
          engine.apply(_engineId!, tIdx, act);
          _syncHost();
        }
      }
    });
  }

  void _applyIncomingView(Map<String, dynamic> v, {String? turnKeyForClock}) {
    final prevTurnKey = view == null ? '' : '${view!['round']}:${view!['turn']}';
    view = v;
    if (turnKeyForClock != null) {
      if (turnKeyForClock != _lastClockTurnKey) {
        _lastClockTurnKey = turnKeyForClock;
        turnLimitMs = turnSecs > 0 ? turnSecs * 1000 : null;
        turnDeadlineMs = turnSecs > 0 && v['phase'] == 'play'
            ? DateTime.now().millisecondsSinceEpoch + turnSecs * 1000
            : 0;
        if (turnDeadlineMs > 0) _ensureClockRunning();
      }
    }

    // Clear stale confirmations or peek if turn/state changed
    if (confirmEndKind != null && (prevTurnKey != '${v['round']}:${v['turn']}' || v['step'] == 'reinforce')) {
      confirmEndKind = null;
    }
    if (peekState != null && peekState!.n != v['n']) {
      peekState = null;
    }

    // Reset selection when phase/turn step changes
    final turnIdx = (v['turn'] as num).toInt();
    final terrs = v['terr'] as List<dynamic>;
    final stepKey = '${v['round']}:${v['turn']}:${v['step']}';
    final can = canPlayNow();
    if (!can) {
      sel = null;
      target = null;
      nukeMode = false;
    } else {
      if (v['occupy'] != null) {
        final occ = v['occupy'] as Map<String, dynamic>;
        sel = (occ['from'] as num).toInt();
        target = (occ['to'] as num).toInt();
      } else if (sel != null) {
        if ((terrs[sel!]['o'] as num).toInt() != turnIdx) {
          sel = null;
          target = null;
        } else if (v['step'] == 'attack' && target != null && (terrs[target!]['o'] as num).toInt() == turnIdx) {
          target = null;
        } else if (v['step'] == 'move' && target != null && (terrs[target!]['o'] as num).toInt() != turnIdx) {
          target = null;
        }
      }
    }
    if (stepKey != _lastTurnStepKey) {
      _lastTurnStepKey = stepKey;
      if (v['occupy'] == null) {
        sel = null;
        target = null;
      }
    }

    // Track prev armies for badges & pop animation
    prevArmies = terrs.map((t) => (t['a'] as num).toInt()).toList();

    // Update eval from Go engine
    eval = engine.evalView(view: v, viewer: me, sel: sel, nuke: nukeMode);

    // Sync default stepper value cleanly
    _updateStepDefault();

    // Check pass-device screen in local pass-and-play
    _checkPassDevice(v);

    // Handle dice banner
    _handleRollBanner(v);

    // Process new events (FX, flash, sound, nuke cinema)
    _processEvents(v);

    // Sync smoke fog
    _syncFog(v);

    // Victory check
    if (v['phase'] != 'over') {
      victoryDismissed = false;
    }

    notifyListeners();
  }

  void _reeval() {
    final v = view;
    if (v == null) return;
    eval = engine.evalView(view: v, viewer: me, sel: sel, nuke: nukeMode);
    _updateStepDefault();
    notifyListeners();
  }

  String _lastTurnStepKey = '';

  void _checkPassDevice(Map<String, dynamic> v) {
    if (role == 'guest' || v['phase'] != 'play') {
      passDevicePlayer = null;
      return;
    }
    final players = v['players'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final cur = players[turnIdx] as Map<String, dynamic>;
    if (cur['ctrl'] == 'local' && _lastViewerTurn != turnIdx) {
      final locals = players.where((p) => p['ctrl'] == 'local').length;
      final first = _lastViewerTurn == null;
      _lastViewerTurn = turnIdx;
      if (locals > 1 && !first) {
        passDevicePlayer = turnIdx;
      }
    }
    // Notify UI when an incoming pact offer is addressed to a local player on this device
    final of = v['offer'] as Map<String, dynamic>?;
    final ofKey = of != null ? '${v['round']}:${v['turn']}:${of['from']}:${of['to']}' : null;
    if (ofKey != _activeOfferKey) {
      _activeOfferKey = ofKey;
      if (of != null) {
        final toIdx = (of['to'] as num).toInt();
        final isMine = role == 'guest' ? toIdx == me : players[toIdx]['ctrl'] == 'local';
        if (isMine) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onOfferForMe?.call(v);
          });
        }
      }
    }
  }

  void dismissPassDevice() {
    passDevicePlayer = null;
    notifyListeners();
  }

  void _handleRollBanner(Map<String, dynamic> v) {
    final r = v['roll'] as Map<String, dynamic>?;
    if (r == null) return;
    final rn = (r['n'] as num?)?.toInt() ?? 0;
    if (rn == _lastRollN) return;
    _lastRollN = rn;

    final att = (r['att'] as List<dynamic>).map((e) => (e as num).toInt()).toList();
    final def = (r['def'] as List<dynamic>).map((e) => (e as num).toInt()).toList();
    final players = v['players'] as List<dynamic>;
    final cur = players[(v['turn'] as num).toInt()] as Map<String, dynamic>;
    final from = (r['from'] as num?)?.toInt();
    final to = (r['to'] as num?)?.toInt();
    final evs = (v['ev'] as List<dynamic>? ?? const []);
    final atk = evs.cast<Map<String, dynamic>>().lastWhere(
          (e) => e['t'] == 'attack',
          orElse: () => const <String, dynamic>{},
        );
    final defPlayerIdx = (atk['def'] as num?)?.toInt();
    final defP = defPlayerIdx != null && defPlayerIdx >= 0 && defPlayerIdx < players.length
        ? players[defPlayerIdx] as Map<String, dynamic>
        : null;

    var low = false;
    if (from != null && to != null && getScreenMidY != null) {
      low = getScreenMidY!(from, to) < mapViewportHeight * 0.45;
    }

    diceBanner = DiceBannerState(
      att: att,
      def: def,
      attName: cur['name'] as String? ?? '',
      attColor: _playerColor((cur['color'] as num).toInt()),
      defName: defP?['name'] as String? ?? 'Defesa',
      defColor: defP != null ? _playerColor((defP['color'] as num).toInt()) : const Color(0xFF9DB0C8),
      low: low,
      untilMs: DateTime.now().millisecondsSinceEpoch + 2900,
    );
  }

  void _processEvents(Map<String, dynamic> v) {
    final nVal = (v['n'] as num).toInt();
    if (_hasEvN && _evN == nVal) return;
    final first = !_hasEvN;
    if (first) _roundSeen = (v['round'] as num).toInt();
    _hasEvN = true;
    _evN = nVal;

    final players = v['players'] as List<dynamic>;
    Color col(int p) => _playerColor((players[p]['color'] as num).toInt());
    String nm(int p) => players[p]['name'] as String? ?? '';
    bool mine(int p) => role == 'guest' ? p == me : players[p]['ctrl'] == 'local';
    final now = DateTime.now().millisecondsSinceEpoch;

    final evList = (v['ev'] as List<dynamic>? ?? const []);
    for (final raw in evList) {
      final e = raw as Map<String, dynamic>;
      final type = e['t'] as String?;
      if (first && type != 'turn') continue;
      switch (type) {
        case 'turn':
          if (v['phase'] != 'play') break;
          final r = (v['round'] as num).toInt();
          if (r == 1 && _roundSeen == 0) {
            showFlash('Rodada 2', const Color(0xFFE2B04A),
                sub: 'A partir de agora os ataques estão liberados', ms: 1400, big: true);
          }
          _roundSeen = r;
          final p = (e['p'] as num).toInt();
          if (mine(p)) {
            showFlash(
              'Sua vez!',
              col(p),
              sub: r == 0 ? 'Distribua seus exércitos' : phaseAlerts['reinforce']!.$2,
              ms: 1000,
              big: true,
            );
            WebEnv.vibrate(120);
            SoundPlayer.play('turn');
          } else {
            showFlash('Vez de ${nm(p)}', col(p), ms: 900, top: true);
            SoundPlayer.play('other');
          }
        case 'phase':
          final p = (e['p'] as num).toInt();
          final step = e['step'] as String? ?? '';
          if (mine(p) && phaseAlerts.containsKey(step)) {
            final al = phaseAlerts[step]!;
            showFlash(al.$1, col(p), sub: al.$2, ms: 1000, big: true);
            WebEnv.vibrate(40);
            SoundPlayer.play('phase');
          }
        case 'place':
          final p = (e['p'] as num).toInt();
          final to = (e['to'] as num).toInt();
          final k = (e['k'] as num).toInt();
          pulses.add(MapPulse(terr: to, color: col(p), startMs: now));
          floats.add(MapFloatText(terr: to, text: '+$k', color: Colors.white, startMs: now));
          SoundPlayer.play('place');
          if (!mine(p)) _spotlight({to});
        case 'trade':
          final p = (e['p'] as num).toInt();
          final val = (e['v'] as num).toInt();
          final bonus = (e['bonus'] as List<dynamic>? ?? const []).map((x) => (x as num).toInt()).toList();
          if (mine(p)) {
            showFlash(
              '+$val exércitos',
              col(p),
              sub: e['auto'] == true ? 'Troca automática de cartas' : 'Troca de cartas',
              ms: 1000,
              big: true,
            );
          } else {
            showFlash('${nm(p)} trocou cartas: +$val', col(p), ms: 1000, top: true);
            if (bonus.isNotEmpty) _spotlight(bonus.toSet());
          }
          for (final t in bonus) {
            pulses.add(MapPulse(terr: t, color: col(p), startMs: now));
            floats.add(MapFloatText(terr: t, text: '+2', color: Colors.white, startMs: now));
          }
          SoundPlayer.play('trade');
        case 'medal':
          final p = (e['p'] as num).toInt();
          final k = (e['k'] as num).toInt();
          const why = {
            'conquest': 'primeira conquista do turno',
            'continent': 'continente fechado',
            'kill': 'adversário eliminado',
          };
          if (mine(p)) {
            showFlash(
              k > 0 ? '+$k medalha${k == 1 ? '' : 's'}' : 'Limite de medalhas',
              const Color(0xFFE2B04A),
              sub: k > 0 ? (why[e['why']] ?? '') : 'Gaste no Quartel no início do seu turno',
              ms: 1000,
              top: true,
            );
            if (k > 0) SoundPlayer.play('card');
          }
        case 'mobilize':
          final p = (e['p'] as num).toInt();
          final val = (e['v'] as num).toInt();
          if (mine(p)) {
            showFlash('+$val exércitos', col(p), sub: 'Mobilização', ms: 1000, big: true);
          } else {
            showFlash('${nm(p)} mobilizou: +$val', col(p), ms: 1000, top: true);
          }
          SoundPlayer.play('trade');
        case 'airlift':
          final p = (e['p'] as num).toInt();
          final from = (e['from'] as num).toInt();
          final to = (e['to'] as num).toInt();
          final k = (e['k'] as num).toInt();
          pulses.add(MapPulse(terr: to, color: col(p), startMs: now));
          floats.add(MapFloatText(terr: to, text: '+$k', color: Colors.white, startMs: now));
          showFlash(
            mine(p) ? 'Ponte aérea' : '${nm(p)}: ponte aérea',
            col(p),
            sub: '$k de ${mapData.territories[from].name} para ${mapData.territories[to].name}',
            ms: 1300,
            top: true,
          );
          if (!mine(p)) _spotlight({from, to});
          SoundPlayer.play('move');
        case 'trench':
          final p = (e['p'] as num).toInt();
          final to = (e['to'] as num).toInt();
          pulses.add(MapPulse(terr: to, color: col(p), startMs: now));
          showFlash(
            mine(p) ? 'Trincheira' : '${nm(p)}: trincheira',
            col(p),
            sub: '${mapData.territories[to].name} não pode ser atacado até a próxima vez de ${nm(p)}',
            ms: 1500,
            top: true,
          );
          if (!mine(p)) _spotlight({to});
          SoundPlayer.play('place');
        case 'spy':
          final p = (e['p'] as num).toInt();
          final q = (e['q'] as num).toInt();
          showFlash(
            mine(p)
                ? 'Espionagem'
                : mine(q)
                    ? '${nm(p)} espionou você!'
                    : '${nm(p)} espionou ${nm(q)}',
            col(p),
            sub: mine(p)
                ? 'Relatório sobre ${nm(q)} salvo no Quartel · +1 no maior dado contra ele neste turno'
                : mine(q)
                    ? 'Ele ganha +1 no maior dado contra você neste turno'
                    : '',
            ms: 1500,
            big: mine(p) || mine(q),
            top: !mine(p) && !mine(q),
          );
          if (mine(q) && !mine(p)) WebEnv.vibrate(120);
          SoundPlayer.play('phase');
        case 'sabotage':
          final p = (e['p'] as num).toInt();
          final q = (e['q'] as num).toInt();
          showFlash(
            mine(q) && !mine(p) ? '${nm(p)} sabotou você!' : '${nm(p)} sabotou ${nm(q)}',
            col(p),
            sub: 'Sem bônus de continente no próximo turno',
            ms: 1500,
            big: mine(q) && !mine(p),
            top: !(mine(q) && !mine(p)),
          );
          if (mine(q) && !mine(p)) WebEnv.vibrate(160);
          SoundPlayer.play('lost');
        case 'move':
          final p = (e['p'] as num).toInt();
          final from = (e['from'] as num).toInt();
          final to = (e['to'] as num).toInt();
          final k = (e['k'] as num).toInt();
          arrows.add(MapArrow(from: from, to: to, color: col(p), startMs: now));
          floats.add(MapFloatText(terr: to, text: '+$k', color: Colors.white, startMs: now));
          SoundPlayer.play('move');
          if (!mine(p)) _spotlight({from, to});
        case 'attack':
          final p = (e['p'] as num).toInt();
          final def = (e['def'] as num).toInt();
          final from = (e['from'] as num).toInt();
          final to = (e['to'] as num).toInt();
          final won = e['won'] == true;
          final la = (e['la'] as num?)?.toInt() ?? 0;
          final ld = (e['ld'] as num?)?.toInt() ?? 0;
          strikes.add(MapStrike(from: from, to: to, color: col(p), won: won, startMs: now));
          if (la > 0) floats.add(MapFloatText(terr: from, text: '−$la', color: const Color(0xFFFF8A7A), startMs: now));
          if (ld > 0) floats.add(MapFloatText(terr: to, text: '−$ld', color: const Color(0xFFFF8A7A), startMs: now));
          onShake?.call(won);
          if (!mine(p)) _spotlight({from, to}, 1200);
          final involved = mine(p) || mine(def);
          SoundPlayer.play('dice');
          SoundPlayer.play(!won ? 'attack' : (mine(def) && !mine(p) ? 'lost' : 'conquer'));
          if (won) {
            if (involved) WebEnv.vibrate(140);
            if (mine(p)) {
              showFlash('Conquistou!', col(p), sub: mapData.territories[to].name, ms: 1000, big: true);
            } else if (mine(def)) {
              showFlash('${nm(p)} tomou ${mapData.territories[to].name}', col(p), ms: 1200, top: true);
            }
          } else if (involved) {
            WebEnv.vibrate(70);
          }
        case 'card':
          final p = (e['p'] as num).toInt();
          if (mine(p)) {
            showFlash('Carta recebida', col(p), sub: 'Toque no ícone de cartas para ver');
            SoundPlayer.play('card');
          }
        case 'dead':
          final p = (e['p'] as num).toInt();
          final by = (e['by'] as num).toInt();
          showFlash('${nm(p)} eliminado', col(by), sub: 'por ${nm(by)}');
          if (mine(p)) WebEnv.vibrate(200);
          SoundPlayer.play('dead');
        case 'timeout':
          final p = (e['p'] as num).toInt();
          showFlash(
            mine(p) ? 'Tempo esgotado!' : 'Tempo de ${nm(p)} esgotou',
            const Color(0xFFE06A5A),
            ms: 1000,
            big: mine(p),
            top: !mine(p),
          );
          SoundPlayer.play('timeout');
        case 'win':
          SoundPlayer.play('win');
          WebEnv.vibrate(300);
        case 'nuke':
          final p = (e['p'] as num).toInt();
          final def = (e['def'] as num).toInt();
          final to = (e['to'] as num).toInt();
          final lost = (e['lost'] as num).toInt();
          _startNukeCinema(to, p);
          _spotlight({to}, impactMs + 2600);
          showFlash(
            'Alerta nuclear!',
            const Color(0xFFFF4A3A),
            sub: '${nm(p)} lançou uma ogiva contra ${mapData.territories[to].name} (${nm(def)})',
            ms: impactMs,
            big: true,
            top: true,
          );
          Timer(const Duration(milliseconds: impactMs + 400), () {
            if (view == null) return;
            showFlash(
              '${mapData.territories[to].name} atingido',
              const Color(0xFF7DFF4A),
              sub: '−$lost exércitos · radioativo até a vez de ${nm(p)} voltar',
              ms: 2600,
              big: true,
              top: true,
            );
          });
        case 'fogEnd':
          final to = (e['to'] as num).toInt();
          showFlash('A névoa sobre ${mapData.territories[to].name} se dissipou', const Color(0xFF7DFF4A), ms: 1100, top: true);
        case 'pactVoid':
          final a = (e['a'] as num).toInt();
          final b = (e['b'] as num).toInt();
          if (mine(a) || mine(b)) {
            showFlash('Pacto encerrado', const Color(0xFFE2B04A),
                sub: '${nm(a)} e ${nm(b)} · acabou com a ogiva', ms: 1500, top: true);
          }
        case 'eventEnd':
          final k = e['k'] as String? ?? '';
          showFlash('${eventTitles[k] ?? k} terminou', const Color(0xFFE2B04A), ms: 1000, top: true);
        case 'event':
          final k = e['k'] as String? ?? '';
          showFlash(eventTitles[k] ?? k, const Color(0xFFE2B04A), sub: eval?.eventText ?? '', ms: 2400, big: true);
          SoundPlayer.play('phase');
        case 'pactAsk':
          final a = (e['a'] as num).toInt();
          final b = (e['b'] as num).toInt();
          if (!mine(b)) {
            showFlash(
              mine(a) ? 'Proposta enviada a ${nm(b)}' : '${nm(a)} propôs um pacto a ${nm(b)}',
              col(a),
              ms: 1100,
              top: true,
            );
          }
        case 'pact':
          final a = (e['a'] as num).toInt();
          final b = (e['b'] as num).toInt();
          final until = (e['until'] as num).toInt();
          final inv = mine(a) || mine(b);
          showFlash(
            inv ? 'Pacto firmado' : 'Pacto: ${nm(a)} e ${nm(b)}',
            col(a),
            sub: inv ? '${nm(a)} e ${nm(b)} · até o fim da rodada ${until + 1}' : '',
            ms: inv ? 1500 : 1300,
            big: inv,
            top: !inv,
          );
          if (inv) WebEnv.vibrate(60);
          SoundPlayer.play('trade');
        case 'pactNo':
          final a = (e['a'] as num).toInt();
          final b = (e['b'] as num).toInt();
          if (mine(a)) {
            showFlash('Pacto recusado', col(b), sub: '${nm(b)} não aceitou', ms: 1200, big: true);
          } else if (!mine(b)) {
            showFlash('${nm(b)} recusou o pacto de ${nm(a)}', col(b), ms: 1100, top: true);
          }
        case 'pactBreak':
          final a = (e['a'] as num).toInt();
          final b = (e['b'] as num).toInt();
          final lost = (e['lost'] as num).toInt();
          final inv = mine(a) || mine(b);
          showFlash(
            mine(b) && !mine(a)
                ? '${nm(a)} rompeu o pacto com você!'
                : inv
                    ? 'Pacto rompido'
                    : '${nm(a)} rompeu o pacto com ${nm(b)}',
            col(a),
            sub: inv ? '${nm(a)} perdeu $lost exército${lost == 1 ? '' : 's'} do reforço' : '',
            ms: 1600,
            big: inv,
            top: !inv,
          );
          if (mine(b) && !mine(a)) WebEnv.vibrate(160);
          SoundPlayer.play('lost');
        case 'pactEnd':
          final a = (e['a'] as num).toInt();
          final b = (e['b'] as num).toInt();
          if (mine(a) || mine(b)) {
            showFlash('Pacto encerrado', const Color(0xFFE2B04A),
                sub: '${nm(a)} e ${nm(b)} podem se atacar de novo', ms: 1500, top: true);
          }
      }
    }
  }

  void _spotlight(Set<int> ids, [int ms = 1000]) {
    spotlightSet = ids;
    spotlightUntilMs = DateTime.now().millisecondsSinceEpoch + ms;
  }

  void _startNukeCinema(int t, int by) {
    final targetGeo = mapData.territories[t];
    final terrs = view?['terr'] as List<dynamic>? ?? const [];
    final own = <int>[];
    for (var i = 0; i < terrs.length; i++) {
      if ((terrs[i]['o'] as num).toInt() == by &&
          (mapData.territories[i].x - targetGeo.x).abs() < mapData.width / 2) {
        own.add(i);
      }
    }
    own.sort((a, b) {
      final ta = mapData.territories[a];
      final tb = mapData.territories[b];
      final da = hypot(ta.x - targetGeo.x, ta.y - targetGeo.y);
      final db = hypot(tb.x - targetGeo.x, tb.y - targetGeo.y);
      return da.compareTo(db);
    });
    final fromX = own.isNotEmpty ? mapData.territories[own.first].x : targetGeo.x - 220;
    final fromY = own.isNotEmpty ? mapData.territories[own.first].y : targetGeo.y - 160;
    final now = DateTime.now().millisecondsSinceEpoch;
    incomingTerr = t;
    cinemaUntilMs = now + impactMs + 2600;
    missile = MissileCinema(
      fromX: fromX,
      fromY: fromY,
      toX: targetGeo.x,
      toY: targetGeo.y,
      targetTerr: t,
      startMs: now,
      alarmMs: alarmMs,
      flightMs: flightMs,
    );
    SoundPlayer.play('siren');
    WebEnv.vibrate(300);
    onPanTo?.call(fromX, fromY, targetGeo.x, targetGeo.y, alarmMs);

    Timer(const Duration(milliseconds: alarmMs), () {
      if (view == null) return;
      SoundPlayer.play('launch');
    });
    Timer(const Duration(milliseconds: impactMs), () {
      if (view == null) return;
      incomingTerr = null;
      impactFx = NukeImpactFx(terr: t, x: targetGeo.x, y: targetGeo.y, startMs: DateTime.now().millisecondsSinceEpoch);
      onShake?.call(true);
      SoundPlayer.play('boom');
      WebEnv.vibrate(350);
      if (_fogKey == t) {
        _startSmokeFor(t, detonate: true);
      }
      Timer(const Duration(milliseconds: 3000), () {
        if (_fogKey == t) SoundPlayer.play('geiger');
      });
      notifyListeners();
    });
  }

  void _syncFog(Map<String, dynamic> v) {
    final fog = v['fog'] as Map<String, dynamic>?;
    final key = (fog != null && v['phase'] == 'play') ? (fog['t'] as num).toInt() : null;
    if (key == _fogKey) return;
    _fogKey = key;
    if (key == null) {
      smoke.stop(false);
      return;
    }
    if (incomingTerr == key) return; // starts on impact
    _startSmokeFor(key, detonate: false);
  }

  void _startSmokeFor(int t, {required bool detonate}) {
    final geo = mapData.territories[t];
    unawaited(
      smoke.start(
        terrIndex: t,
        path: geo.path,
        bbox: geo.bounds,
        cx: geo.x,
        cy: geo.y,
        detonate: detonate,
      ),
    );
  }

  // ---------------- Gameplay Queries & Actions ----------------

  bool canPlayNow() {
    final v = view;
    if (v == null || v['phase'] != 'play') return false;
    final players = v['players'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final cur = players[turnIdx] as Map<String, dynamic>;
    if (role == 'guest') {
      return turnIdx == me && cur['ctrl'] != 'bot' && guestLink != null;
    }
    return cur['ctrl'] == 'local';
  }

  int activePlayerIndex() {
    final v = view;
    if (v == null) return 0;
    return role == 'guest' ? me : (v['turn'] as num).toInt();
  }

  Set<int> validTargets() {
    final v = view;
    final ev = eval;
    if (v == null || ev == null || sel == null) return const {};
    final terrs = v['terr'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final step = v['step'] as String;
    final out = <int>{};
    for (final j in mapData.territories[sel!].adj) {
      final owner = (terrs[j]['o'] as num).toInt();
      if (step == 'attack' && owner != turnIdx && !ev.attackBlocks.containsKey(j)) {
        out.add(j);
      } else if (step == 'move' && owner == turnIdx && !ev.moveBlocks.containsKey(j)) {
        out.add(j);
      }
    }
    return out;
  }

  (int, int)? stepRange() {
    final v = view;
    if (v == null || !canPlayNow()) return null;
    final terrs = v['terr'] as List<dynamic>;
    final occ = v['occupy'] as Map<String, dynamic>?;
    if (occ != null) {
      final lo = (occ['min'] as num?)?.toInt() ?? 0;
      final hi = (occ['max'] as num).toInt();
      return hi > lo ? (lo, hi) : null;
    }
    final s = sel;
    if (s == null) return null;
    final step = v['step'] as String;
    if (step == 'reinforce') {
      final pool = v['pool'] as Map<String, dynamic>;
      final free = (pool['free'] as num).toInt();
      final contMap = pool['cont'] as Map<String, dynamic>? ?? const {};
      final contBonus = (contMap['${mapData.territories[s].continent}'] as num?)?.toInt() ?? 0;
      final maxPut = free + contBonus;
      if (maxPut <= 0) return null;
      return (1, maxPut);
    }
    final armies = (terrs[s]['a'] as num).toInt();
    if (step == 'attack' && target != null) {
      final evt = v['event'] as Map<String, dynamic>?;
      final storm = evt != null &&
          evt['k'] == 'storm' &&
          mapData.territories[target!].continent == (evt['c'] as num?)?.toInt();
      final cap = storm ? 2 : 3;
      final maxDice = min(cap, armies - 1);
      return maxDice >= 1 ? (1, maxDice) : null;
    }
    if (step == 'move' && target != null) {
      final movableMap = v['movable'] as Map<String, dynamic>? ?? const {};
      final movable = (movableMap['$s'] as num?)?.toInt() ?? 0;
      final maxMove = min(armies - 1, movable);
      return maxMove >= 1 ? (1, maxMove) : null;
    }
    return null;
  }

  void _updateStepDefault() {
    final v = view;
    if (v == null) return;
    final rng = canPlayNow() ? stepRange() : null;
    final occ = v['occupy'] as Map<String, dynamic>?;
    final key = '${v['step']}:${occ != null ? 'o${occ['to']}' : ''}:$sel:$target';
    if (occ != null && rng == null) {
      stepValue = (occ['min'] as num?)?.toInt() ?? 0;
    } else if (rng != null) {
      if (key != _stepKey) {
        stepValue = occ != null ? rng.$1 : (v['step'] == 'attack' ? rng.$2 : 1);
      }
      stepValue = stepValue.clamp(rng.$1, rng.$2);
    }
    _stepKey = key;
  }

  void changeStep(int delta) {
    final rng = stepRange();
    if (rng == null) return;
    final next = (stepValue + delta).clamp(rng.$1, rng.$2);
    if (next != stepValue) {
      stepValue = next;
      notifyListeners();
    }
  }

  void setMaxReinforce() {
    final rng = stepRange();
    if (rng == null) return;
    stepValue = rng.$2;
    placeReinforce();
  }

  void _sendAction(Map<String, dynamic> action) {
    if (role == 'guest') {
      guestLink?.send({'t': 'act', 'a': action});
      return;
    }
    if (_engineId == null || view == null) return;
    final pIdx = action['t'] == 'pactReply'
        ? ((view!['offer']?['to'] as num?)?.toInt() ?? activePlayerIndex())
        : activePlayerIndex();
    final err = engine.apply(_engineId!, pIdx, action);
    if (err.isNotEmpty) {
      showToast(err);
    } else {
      _syncHost();
    }
  }

  void _sendPeek() {
    final v = view;
    if (v == null || role == 'local' || sel == null || !canPlayNow()) return;
    final msg = {'t': 'peek', 'n': v['n'], 'sel': sel, 'target': target};
    if (role == 'guest') {
      guestLink?.send(msg);
    } else {
      for (final s in seats) {
        if (s.link != null && s.link!.isOpen) s.link!.send(msg);
      }
    }
  }

  void tapTerritory(int t) {
    SoundPlayer.unlock();
    final v = view;
    final ev = eval;
    if (v == null || ev == null) return;
    infoTerr = t;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!canPlayNow() || v['occupy'] != null) {
      notifyListeners();
      return;
    }
    final terrs = v['terr'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final owner = (terrs[t]['o'] as num).toInt();
    final armies = (terrs[t]['a'] as num).toInt();
    final step = v['step'] as String;

    // Nuke targeting mode
    if (nukeMode) {
      final blk = ev.nukeTargetBlocks[t];
      if (blk != null && blk.isNotEmpty) {
        showToast(blk, 3800);
        notifyListeners();
        return;
      }
      pendingNukeTerr = t;
      notifyListeners();
      return;
    }

    if (step == 'reinforce') {
      if (owner != turnIdx) {
        sel = null;
        target = null;
        _reeval();
        return;
      }
      if (ev.mustTrade) {
        showToast('Com 5 cartas é obrigatório trocar antes.');
        notifyListeners();
        return;
      }
      final pool = v['pool'] as Map<String, dynamic>;
      final free = (pool['free'] as num).toInt();
      final contMap = pool['cont'] as Map<String, dynamic>? ?? const {};
      final contBonus = (contMap['${mapData.territories[t].continent}'] as num?)?.toInt() ?? 0;
      if (free + contBonus < 1) {
        sel = null;
        showToast('Os exércitos restantes são bônus de outro continente.');
        _reeval();
        return;
      }
      final doubleTap = lastTapTerr == t && now - lastTapMs < 450;
      lastTapTerr = t;
      lastTapMs = doubleTap ? 0 : now;
      if (doubleTap) {
        sel = t;
        stepValue = 1;
        _sendAction({'t': 'place', 't0': t, 'n': 1});
        return;
      }
      if (sel == t && stepRange() != null) {
        stepValue = min(stepRange()!.$2, stepValue + 1);
      } else {
        sel = t;
        target = null;
        _reeval();
      }
      _sendPeek();
      notifyListeners();
      return;
    }

    if (step == 'attack') {
      if (owner != turnIdx) {
        if (sel != null && validTargets().contains(t)) {
          if (target == t) {
            attack();
          } else {
            target = t;
            _updateStepDefault();
            _sendPeek();
            notifyListeners();
          }
          return;
        }
        if (sel != null && mapData.territories[sel!].adj.contains(t)) {
          final blk = ev.attackBlocks[t];
          if (blk != null && blk.isNotEmpty) {
            target = null;
            showToast(blk, 4200);
            notifyListeners();
            return;
          }
        }
        final from = ev.directAttackFrom[t];
        if (from != null) {
          sel = from;
          target = t;
          _reeval();
          _sendPeek();
          notifyListeners();
          return;
        }
        final blk = ev.directAttackBlock[t];
        target = null;
        if (blk != null) {
          showToast(blk, 4200);
        } else {
          showToast('Nenhum território seu com 2 ou mais exércitos faz fronteira com esse.');
        }
        notifyListeners();
        return;
      }
      if (armies < 2) {
        sel = null;
        target = null;
        showToast('É preciso 2 ou mais exércitos para atacar daqui.');
        _reeval();
        return;
      }
      if (target != null && mapData.territories[t].adj.contains(target)) {
        sel = t;
      } else {
        sel = t;
        target = null;
      }
      _reeval();
      _sendPeek();
      notifyListeners();
      return;
    }

    if (step == 'move') {
      if (owner == turnIdx && sel != null && t != sel && mapData.territories[sel!].adj.contains(t)) {
        final blk = ev.moveBlocks[t];
        if (blk != null && blk.isNotEmpty) {
          target = null;
          showToast(blk, 3600);
          notifyListeners();
          return;
        }
      }
      if (owner == turnIdx && sel != null && t == target) {
        final rng = stepRange();
        if (rng != null) {
          stepValue = min(rng.$2, stepValue + 1);
          notifyListeners();
        }
        return;
      }
      if (owner == turnIdx && sel != null && t != sel && validTargets().contains(t)) {
        target = t;
        _updateStepDefault();
        _sendPeek();
        notifyListeners();
        return;
      }
      if (owner == turnIdx && t == sel && target != null) {
        stepValue = max(1, stepValue - 1);
        notifyListeners();
        return;
      }
      if (owner != turnIdx || t == sel) {
        sel = null;
        target = null;
        _reeval();
        return;
      }
      final movableMap = v['movable'] as Map<String, dynamic>? ?? const {};
      final mov = (movableMap['$t'] as num?)?.toInt() ?? 0;
      if (mov <= 0) {
        sel = null;
        target = null;
        showToast('Nenhum exército disponível para mover daqui.');
        _reeval();
        return;
      }
      sel = t;
      target = null;
      _reeval();
      _sendPeek();
      notifyListeners();
    }
  }

  void clearSelection() {
    if (nukeMode) {
      nukeMode = false;
      pendingNukeTerr = null;
      _reeval();
      return;
    }
    if (target != null) {
      target = null;
      _updateStepDefault();
      notifyListeners();
      return;
    }
    if (sel != null) {
      sel = null;
      _reeval();
      return;
    }
    if (infoTerr != null) {
      infoTerr = null;
      notifyListeners();
    }
  }

  void placeReinforce() {
    if (sel == null) return;
    final n = stepValue;
    stepValue = 1;
    _sendAction({'t': 'place', 't0': sel, 'n': n});
  }

  void autoTrade() {
    final tr = eval?.bestTrade;
    if (tr == null) return;
    _sendAction({'t': 'trade', 'cards': tr});
  }

  void tradeCards(List<int> cards) {
    _sendAction({'t': 'trade', 'cards': cards});
  }

  void toggleNukeMode(bool on) {
    nukeMode = on;
    pendingNukeTerr = null;
    if (on) {
      sel = null;
      target = null;
    }
    _reeval();
  }

  /// Partida com Quartel: medalhas e ordens no lugar das cartas.
  bool get hqOn => (view?['opts'] as Map<String, dynamic>?)?['hq'] == true;

  /// Medalhas do jogador [p] (0 em partidas sem Quartel).
  int medalsOf(int p) {
    final players = view?['players'] as List<dynamic>?;
    if (players == null || p < 0 || p >= players.length) return 0;
    return ((players[p] as Map<String, dynamic>)['medals'] as num?)?.toInt() ?? 0;
  }

  /// Quem entrincheirou o território [t] (null se ninguém).
  int? trenchOwner(int t) {
    for (final x in view?['trenches'] as List<dynamic>? ?? const []) {
      final m = x as Map<String, dynamic>;
      if ((m['t'] as num).toInt() == t) return (m['by'] as num).toInt();
    }
    return null;
  }

  void mobilize() => _sendAction({'t': 'mobilize'});

  void orderAirlift(int from, int to, int n) =>
      _sendAction({'t': 'order', 'k': 'airlift', 'from': from, 'to': to, 'n': n});

  void orderTrench(int t) => _sendAction({'t': 'order', 'k': 'trench', 'to': t});

  void orderSpy(int q) => _sendAction({'t': 'order', 'k': 'spy', 'with': q});

  void orderSabotage(int q) => _sendAction({'t': 'order', 'k': 'sabotage', 'with': q});

  void confirmNukeLaunch(int t) {
    if (hqOn) {
      // no Quartel a ogiva é uma ordem: custa medalhas, não cartas
      pendingNukeTerr = null;
      nukeMode = false;
      _sendAction({'t': 'nuke', 'to': t});
      return;
    }
    final tr = eval?.nukeTrade;
    pendingNukeTerr = null;
    nukeMode = false;
    if (tr == null) {
      _reeval();
      return;
    }
    _sendAction({'t': 'nuke', 'cards': tr, 'to': t});
  }

  void cancelPendingNuke() {
    pendingNukeTerr = null;
    notifyListeners();
  }

  void confirmOccupy() {
    _sendAction({'t': 'occupy', 'n': stepValue});
  }

  void attack() {
    if (sel == null || target == null) return;
    _sendAction({'t': 'attack', 'from': sel, 'to': target, 'dice': stepValue});
  }

  void blitz() {
    if (sel == null || target == null) return;
    _sendAction({'t': 'attack', 'from': sel, 'to': target, 'blitz': true});
  }

  void requestEndAttack() {
    final v = view;
    if (v == null || !canPlayNow()) return;
    confirmEndKind = 0;
    confirmOpenedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  void confirmEndPhase() {
    if (DateTime.now().millisecondsSinceEpoch - confirmOpenedMs < 400) return;
    final kind = confirmEndKind;
    confirmEndKind = null;
    sel = null;
    target = null;
    if (kind == 0) {
      _sendAction({'t': 'endAttack'});
    } else if (kind == 1) {
      _sendAction({'t': 'endTurn'});
    }
    notifyListeners();
  }

  void cancelConfirmEnd() {
    if (DateTime.now().millisecondsSinceEpoch - confirmOpenedMs < 400) return;
    confirmEndKind = null;
    notifyListeners();
  }

  void moveTroops() {
    if (sel == null || target == null) return;
    _stepKey = '';
    _sendAction({'t': 'move', 'from': sel, 'to': target, 'n': stepValue});
  }

  void requestEndTurn() {
    final v = view;
    if (v == null || !canPlayNow()) return;
    confirmEndKind = 1;
    confirmOpenedMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  void proposePact(int toPlayer) {
    _sendAction({'t': 'pactOffer', 'to': toPlayer});
  }

  void replyPact(bool accept) {
    _sendAction({'t': 'pactReply', 'accept': accept});
  }

  void breakPact(int targetPlayer) {
    _sendAction({'t': 'pactBreak', 'with': targetPlayer});
  }

  // ---------------- Resume Saved Game & Leave ----------------

  void resumeSavedLocal() {
    final raw = AppStorage.instance.getString('estandarte.save3');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _resetSessionState();
      role = 'host';
      netP2p = true;
      turnSecs = (data['secs'] as num?)?.toInt() ?? 120;
      seats = (data['seats'] as List<dynamic>? ?? [])
          .map((e) => LobbySeat(
                name: e['name'] as String? ?? '',
                color: (e['color'] as num?)?.toInt() ?? 0,
                ctrl: e['ctrl'] as String? ?? 'local',
              ))
          .toList();
      final gameJson = data['game'] as Map<String, dynamic>;
      _engineId = engine.loadGame(gameJson);
      _hasEvN = false;
      _evN = -1;
      _lastRollN = 0;
      _lastViewerTurn = null;
      _fogKey = null;
      screen = AppScreen.game;
      WebEnv.setWakeLock(true);
      _armTurnClock();
      _syncHost();
      if (seats.any((s) => s.ctrl == 'remote')) {
        showToast('Reconecte os convidados pelo menu ☰ (botão QR).', 5000);
      }
    } catch (_) {
      showToast('Não foi possível carregar a partida salva.');
    }
  }

  void resumeSavedGuest() {
    _resetSessionState();
    role = 'guest';
    netP2p = true;
    screen = AppScreen.game;
    unawaited(_tryAutoSpare());
  }

  void leaveGame({String? showReason}) {
    final backToRooms = online != null && online!.fromRooms && !online!.gone;
    _botTimer?.cancel();
    _clockTimer?.cancel();
    _autoTimer?.cancel();
    _onlineRetryTimer?.cancel();
    _roomsTimer?.cancel();

    if (online != null) {
      final link = guestLink;
      if (link != null && !online!.gone) {
        link.send({'t': 'leave'});
      }
      AppStorage.instance.remove('estandarte.online');
    } else if (role == 'guest') {
      AppStorage.instance.remove('estandarte.guest');
      AppStorage.instance.remove('estandarte.spare');
      savedSpare = null;
    }

    _resetSessionState();
    WebEnv.setWakeLock(false);
    if (backToRooms) {
      openRoomsBrowser();
    } else {
      screen = AppScreen.home;
    }
    if (showReason != null && showReason.isNotEmpty) {
      showToast(showReason, 4000);
    }
    _refreshSavedFlags();
    notifyListeners();
  }

  void _dropEngineGame() {
    if (_engineId != null) {
      try {
        engine.dropGame(_engineId!);
      } catch (_) {}
      _engineId = null;
    }
  }

  void _resetSessionState() {
    inTutorial = false;
    _botTimer?.cancel();
    _clockTimer?.cancel();
    _autoTimer?.cancel();
    _onlineRetryTimer?.cancel();
    _roomsTimer?.cancel();
    for (final s in seats) {
      _dropSeatSpare(s);
      s.link?.close();
    }
    guestLink?.close();
    guestLink = null;
    online = null;
    _dropEngineGame();
    smoke.stop(true);
    _fogKey = null;
    _hasEvN = false;
    _evN = -1;
    _lastRollN = 0;
    _lastViewerTurn = null;
    _lastTurnStepKey = '';
    _activeOfferKey = null;
    hostLag = false;
    _hostLastHeardMs = 0;
    view = null;
    eval = null;
    sel = null;
    target = null;
    infoTerr = null;
    hoverInfoTerr = null;
    nukeMode = false;
    pendingNukeTerr = null;
    confirmEndKind = null;
    passDevicePlayer = null;
    peekState = null;
    diceBanner = null;
    flashBanner = null;
    _flashQueue.clear();
    missile = null;
    impactFx = null;
    pulses.clear();
    strikes.clear();
    arrows.clear();
    floats.clear();
    onlMap = {};
    watchersCount = null;
    lobbyCode = null;
    lobbyOwner = false;
    turnDeadlineMs = 0;
  }

  Color _playerColor(int idx) {
    final cols = engine.constants.colors;
    if (idx < 0 || idx >= cols.length) return const Color(0xFF999999);
    return parseHexColor(cols[idx].hex);
  }

  double hypot(double dx, double dy) => sqrt(dx * dx + dy * dy);

  @override
  void dispose() {
    _unsubConn?.call();
    _unsubVis?.call();
    _fxCleanupTimer?.cancel();
    _heartbeatTimer?.cancel();
    _roomsTimer?.cancel();
    _resetSessionState();
    smoke.dispose();
    super.dispose();
  }
}
