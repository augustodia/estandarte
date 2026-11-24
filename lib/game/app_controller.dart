import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../core/names.dart';
import '../engine/game_engine.dart';
import '../net/account_api.dart' as acc;
import '../net/online_client.dart';
import '../net/telemetry.dart';
import '../platform/lan_host.dart';
import '../platform/p2p.dart';
import '../platform/sound.dart';
import '../platform/storage.dart';
import '../platform/web_env.dart';
import 'crests.dart';
import 'daily_challenge.dart';
import 'fx_models.dart';
import 'smoke_sim.dart';

const int alarmMs = 900;
const int flightMs = 2900;
const int impactMs = alarmMs + flightMs;
const String appVersion = 'alpha-1.4';
const int corrTurnMs = 24 * 3600 * 1000; // correspondência: prazo de cada jogada

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
  bool lobbyQuick = false;
  int lobbyQuickDeadlineMs = 0;
  int lobbyRankedStartBy = 0; // duelo ranqueado: até quando o adversário pode chegar (ms)
  String lobbyPass = '';
  bool lobbyHasPass = false;
  ({String code, bool wrong, bool isLan})? passPrompt;
  String? _pendingRoomPass;

  // Native LAN WebSocket host (Windows / mobile / desktop)
  LanServerHandle? _lanServer;
  final Set<GameLink> _pendingGuestLinks = {};
  bool lanStarting = false;
  String? get lanHostAddr => _lanServer?.primaryAddress;
  List<String> get lanAllAddrs => _lanServer?.addresses ?? const [];

  // Host Relay WebSocket (5-letter shareable room code over Internet)
  OnlineLink? _relayLink;
  Timer? _relayRetryTimer;
  String? relayCode;
  String? _relaySecret;
  bool relayStarting = false;
  String relayWaitMsg = '';
  final Map<int, _RelayPeerLink> _relayPeers = {};
  final Set<_RelayPeerLink> _relayWatchers = {};
  bool get isRelayConnected => _relayLink != null && _relayLink!.isOpen;

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
  bool trenchMode = false;
  int? pendingTrenchTerr;
  bool airliftMode = false;
  int? airliftFrom;
  int? airliftTo;
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
  final ValueNotifier<int> clockTick = ValueNotifier<int>(0);

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

  // Victory dismissal & Tutorial / Daily Challenge state
  bool victoryDismissed = false;
  bool inTutorial = false;
  bool _tutorialCompletedSent = false;
  bool _matchEndSent = false;
  int _matchStartedMs = 0;

  DailySnapshot? dailySnapshot;
  bool dailyLoading = false;
  String? dailyError;
  String challengeDifficulty = 'standard'; // 'standard' | 'marechal'
  DailyChallengeSpec? activeChallenge;
  ChallengeLiveStatus? challengeStatus;
  bool challengeWon = false;
  bool challengeLost = false;
  String challengeEndReason = '';
  int challengeStarsEarned = 0;
  int get challengeArmiesLost => _challengeArmiesLost;
  int get challengeOrdersUsed => _challengeOrdersUsed;
  int? challengeServerRank;
  /// Venceu o desafio sem conta: o resultado não entra no ranking (a tela convida a entrar).
  bool challengeNeedsAccount = false;
  List<DailyRankEntry> challengeSubmitRanking = [];
  bool challengeResultSubmitted = false;

  /// Replay da melhor partida conferida da conta no desafio de hoje (o servidor devolve no envio).
  String? challengeReplayId;

  /// Ranking de ontem (com os replays para assistir); null enquanto não buscou.
  List<DailyRankEntry>? yesterdayRanking;
  String yesterdayTitle = '';
  bool yesterdayLoading = false;

  Future<void> loadYesterdayRanking() async {
    final today = dailySnapshot?.date;
    if (today == null || yesterdayLoading || !netOnline) return;
    final d = DateTime.tryParse(today);
    if (d == null) return;
    final y = d.subtract(const Duration(days: 1));
    final date = '${y.year.toString().padLeft(4, '0')}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
    yesterdayLoading = true;
    notifyListeners();
    try {
      final res = await fetchDailyRanking(serverUrl(), date: date);
      yesterdayRanking = [
        for (final e in (res['entries'] as List<dynamic>? ?? const []))
          DailyRankEntry.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      yesterdayTitle = res['title'] as String? ?? '';
    } catch (_) {
      showToast('Não deu para buscar o ranking de ontem.');
    } finally {
      yesterdayLoading = false;
      notifyListeners();
    }
  }

  /// O replay da melhor partida de hoje deste aparelho/conta (guardado com o progresso do dia).
  String? get todayReplayId {
    final d = dailySnapshot?.date;
    final rec = d == null ? null : dailyProgress[d];
    final id = rec is Map ? rec['replay'] as String? : null;
    return (id != null && id.length == 8) ? id : null;
  }
  String? _challengeRunId;
  int _challengeStartedMs = 0;
  bool _challengeRecorded = false; // jogando com a semente do servidor: a partida vai gravada no envio

  // placar do desafio: quem conta é o motor (o mesmo que o servidor usa para conferir)
  Map<String, dynamic>? get _challengeState => view?['challenge'] as Map<String, dynamic>?;
  int _challengeInt(String k) => (_challengeState?[k] as num?)?.toInt() ?? 0;
  int get _challengeArmiesLost => _challengeInt('armiesLost');
  int get _challengeNukesUsed => _challengeInt('nukesUsed');
  int get _challengeOrdersUsed => _challengeInt('ordersUsed');
  bool get _challengeLostKeyEver => _challengeState?['lostKey'] == true;
  Map<String, dynamic> dailyProgress = {};
  Map<String, dynamic> codexProgress = {};

  // Settings & Saved state availability
  bool forceLand = true;
  bool hasSavedLocal = false;
  bool hasSavedGuest = false;
  Map<String, dynamic>? savedOnlineMeta;
  String? pendingJoinSalaCode;
  String? pendingJoinQrCode;
  String? pendingJoinCorrCode;

  String? pendingReplayCode;

  // ---------------- Replay e dados verificáveis ----------------

  /// Compromisso dos dados da partida online em andamento (SHA-256 da semente do servidor).
  String? matchCommit;

  /// Replay da partida online que acabou de terminar.
  String? matchReplayId;

  /// Contribuição deste aparelho para os dados das partidas online (vai no "hello"; aparece no replay).
  final String clientSeed = _newClientSeed();

  static String _newClientSeed() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // Chave Ed25519 deste aparelho (a semente fica guardada; a chave nunca sai do motor): assina as jogadas online.
  String? _devicePub;
  String? get devicePub {
    if (_devicePub != null) return _devicePub;
    try {
      final r = engine.callJson('deviceKey', {'seed': AppStorage.instance.getString(_kDeviceKey) ?? ''});
      AppStorage.instance.setString(_kDeviceKey, r['seed'] as String);
      _devicePub = r['pub'] as String;
    } catch (_) {}
    return _devicePub;
  }

  String? _csSentFor;
  String? _keySentFor;
  int _lastQ = 0;

  /// Na sala de espera online: manda a contribuição para os dados e a chave do aparelho depois de ver o compromisso
  /// (assim o servidor não tem como escolher a semente sabendo a contribuição).
  void _contribute(String? commit, GameLink link) {
    final ses = online;
    if (ses == null || ses.lan || commit == null || commit.length != 64 || commit == _csSentFor) return;
    _csSentFor = commit;
    _keySentFor = commit;
    link.send({'t': 'cs', 'c': commit, 'v': clientSeed, 'k': ?devicePub});
    final log = (_readJsonList(_kContrib) ?? const []).map((e) => '$e').toList()
      ..remove(commit)
      ..add(commit);
    AppStorage.instance.setString(_kContrib, jsonEncode(log.length > 200 ? log.sublist(log.length - 200) : log));
  }

  /// Na partida online: avisa a chave deste aparelho (troca de aparelho no meio da partida, como na correspondência).
  void _announceKey(GameLink link) {
    final ses = online;
    final commit = matchCommit;
    if (ses == null || ses.lan || commit == null || me < 0 || commit == _keySentFor) return;
    _keySentFor = commit;
    final k = devicePub;
    if (k != null) link.send({'t': 'key', 'k': k});
  }

  /// Este aparelho contribuiu para a partida deste compromisso depois de vê-lo.
  bool contributedTo(String commit) =>
      (_readJsonList(_kContrib) ?? const []).map((e) => '$e').contains(commit);

  List<dynamic>? _readJsonList(String key) {
    final raw = AppStorage.instance.getString(key);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is List ? v : null;
    } catch (_) {
      return null;
    }
  }

  ReplaySession? replay;

  // Emotes táticos: recados prontos (sem texto livre). O servidor e o anfitrião só repassam o número.
  static const List<String> emoteTexts = [
    'Bom jogo',
    'Bem jogado!',
    'Obrigado',
    'Ops…',
    'Trégua?',
    'Todos contra o líder!',
    'Vou me vingar',
    'Foi por pouco',
  ];
  static const int emoteGapMs = 3000; // o servidor recusa mais de um a cada 3 s
  static const String _kEmotesMuted = 'estandarte.emotesMuted';
  final List<EmoteBubble> emotes = [];
  bool emotesMuted = false;
  int _emoteSeq = 0;
  int _emoteSentMs = 0;
  final Map<int, int> _seatEmoteMs = {}; // anfitrião: último recado de cada lugar
  bool replayLoading = false;
  Timer? _replayTimer;
  AppScreen _replayBack = AppScreen.home;

  /// Abre o replay pelo código ou link: busca no servidor, confere a semente e refaz a partida no motor.
  Future<void> openReplay(String raw) async {
    final code = acc.replayCode(raw);
    if (code == null) {
      showToast('O código do replay tem 8 letras.');
      return;
    }
    if (replayLoading) return;
    if (!netOnline) {
      showToast('Sem internet: o replay vem do servidor.', 4000);
      return;
    }
    replayLoading = true;
    notifyListeners();
    try {
      final r = await acc.fetchReplay(serverUrl(), code);
      _startReplay(code, r.meta, r.replay);
    } on acc.AccountError catch (e) {
      showToast(e.message, 4500);
    } on StateError catch (e) {
      showToast('Este replay não confere: ${e.message.replaceFirst(RegExp(r'^Engine error in \w+: '), '')}', 5000);
    } finally {
      replayLoading = false;
      notifyListeners();
    }
  }

  void _startReplay(String code, Map<String, dynamic> meta, Map<String, dynamic> rep) {
    final res = engine.callJson('replayLoad', rep); // confere o compromisso e refaz a partida (erro se adulterado)
    if (online != null || _engineId != null || replay != null) leaveGame(keepSeat: true);
    _replayBack = screen == AppScreen.game ? AppScreen.home : screen;
    _resetSessionState();
    final id = (res['id'] as num).toInt();
    replay = ReplaySession(
      code: code,
      engineId: id,
      steps: (res['steps'] as num?)?.toInt() ?? 0,
      turns: [
        for (final t in (res['turns'] as List<dynamic>? ?? const []))
          ReplayTurn(((t as Map)['step'] as num).toInt(), (t['round'] as num).toInt(), (t['turn'] as num).toInt()),
      ],
      meta: meta,
      rep: rep,
      proof: [for (final p in (res['players'] as List<dynamic>? ?? const [])) Map<String, dynamic>.from(p as Map)],
    );
    role = 'guest';
    me = -1;
    _applyIncomingView(engine.viewFor(id, -1));
    screen = AppScreen.game;
    Telemetry.track('replay_opened', mode: meta['mode'] as String?);
    notifyListeners();
  }

  /// Vai para o passo [step]. Sem [animate], pula sem dados nem avisos (salto de turno, barra de progresso).
  void replayGoTo(int step, {bool animate = false}) {
    final r = replay;
    if (r == null) return;
    final res = engine.callJson('replayGoto', {'id': r.engineId, 'step': step});
    r.pos = (res['pos'] as num?)?.toInt() ?? step;
    final v = engine.viewFor(r.engineId, -1);
    if (!animate) {
      v['ev'] = <Map<String, dynamic>>[];
      _lastRollN = ((v['roll'] as Map?)?['n'] as num?)?.toInt() ?? _lastRollN;
      diceBanner = null;
    }
    _applyIncomingView(v);
    if (r.pos >= r.steps) {
      r.playing = false;
      _replayTimer?.cancel();
    }
    notifyListeners();
  }

  void replayToggle() {
    final r = replay;
    if (r == null) return;
    if (r.pos >= r.steps) replayGoTo(0);
    r.playing = !r.playing;
    _replayTimer?.cancel();
    if (r.playing) _replayTick();
    notifyListeners();
  }

  void _replayTick() {
    final r = replay;
    if (r == null || !r.playing) return;
    if (r.pos >= r.steps) {
      r.playing = false;
      notifyListeners();
      return;
    }
    final steps = r.rep['steps'] as List<dynamic>? ?? const [];
    final a = r.pos < steps.length ? (steps[r.pos] as Map)['a'] : null;
    final t = a is Map ? a['t'] : null;
    final ms = switch (t) {
      'attack' => 1300,
      'nuke' || 'order' => 1500,
      'place' || 'mobilize' => 260,
      _ => 520,
    };
    replayGoTo(r.pos + 1, animate: true);
    _replayTimer = Timer(Duration(milliseconds: ms ~/ r.speed), _replayTick);
  }

  void replayStep(int delta) {
    final r = replay;
    if (r == null) return;
    r.playing = false;
    _replayTimer?.cancel();
    replayGoTo((r.pos + delta).clamp(0, r.steps), animate: delta > 0);
  }

  /// Pula para o começo do turno anterior (-1) ou do próximo (+1).
  void replayTurn(int delta) {
    final r = replay;
    if (r == null || r.turns.isEmpty) return;
    var i = r.turnIndex;
    if (delta < 0 && r.pos > r.turns[i].step) {
      // no meio do turno: volta para o começo dele
    } else {
      i = (i + delta).clamp(0, r.turns.length - 1);
    }
    final target = delta > 0 && r.turnIndex == r.turns.length - 1 ? r.steps : r.turns[i].step;
    replayGoTo(target);
  }

  void replaySeekTurn(int i) {
    final r = replay;
    if (r == null || r.turns.isEmpty) return;
    replayGoTo(r.turns[i.clamp(0, r.turns.length - 1)].step);
  }

  void replaySpeed() {
    final r = replay;
    if (r == null) return;
    r.speed = r.speed >= 4 ? 1 : r.speed * 2;
    if (r.playing) {
      _replayTimer?.cancel();
      _replayTimer = Timer(Duration(milliseconds: 300 ~/ r.speed), _replayTick);
    }
    notifyListeners();
  }

  void _leaveReplay() {
    _resetSessionState();
    screen = _replayBack;
    notifyListeners();
    if (screen == AppScreen.corr) unawaited(refreshCorr(silent: true));
  }

  /// Só para as fotos de tela: abre um replay sem servidor.
  @visibleForTesting
  void debugOpenReplay(String code, Map<String, dynamic> meta, Map<String, dynamic> rep) => _startReplay(code, meta, rep);

  /// Código que chegou por link: a tela da correspondência já abre com ele no campo.
  String corrPrefill = '';

  // Correspondência (24 h por jogada): as partidas da conta, de quem é a vez e o prazo
  List<acc.AsyncGameInfo> corrGames = const [];
  List<acc.AsyncInviteInfo> corrInvites = const [];
  bool corrLoading = false;
  bool corrLoaded = false;
  String? corrError;
  Timer? _corrTimer;

  /// Partidas em que é a sua vez (o número que aparece no início).
  int get corrYourTurn => corrGames.where((g) => g.playing && g.yourTurn).length;

  /// A partida aberta agora é por correspondência.
  bool get inCorr => online?.corr == true;

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
    emotesMuted = AppStorage.instance.getString(_kEmotesMuted) == '1';

    final savedCfg = _readJsonStorage('estandarte.cfg');
    if (savedCfg != null) {
      turnSecs = (savedCfg['secs'] as num?)?.toInt() ?? 120;
      optEvents = savedCfg['events'] == true;
      optPacts = savedCfg['pacts'] == true;
      optNukes = savedCfg['nukes'] == true;
      optHq = savedCfg['hq'] != false;
      optSpy = savedCfg['spy'] == true;
    }

    _loadAccount();
    _unsubConn = WebEnv.listenConnectivity((on) {
      netOnline = on;
      if (on) unawaited(refreshAccount());
      notifyListeners();
    });
    _unsubVis = WebEnv.listenVisibility((hidden) {
      if (!hidden) {
        if (role == 'guest' && guestLink != null) {
          guestLink!.send({'t': 'sync'});
        }
        if (online != null && guestLink == null && !online!.gone) {
          _reconnectOnline();
        } else if (role == 'guest' && (guestLink == null || hostLag) && online == null && replay == null) {
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
    _loadDailyLocalProgress();
    Telemetry.appVersion = appVersion;
    Telemetry.track('app_opened');
    unawaited(refreshDailyChallenge(quiet: true));

    // Check URL params / hash
    final sala = roomCode(WebEnv.getQueryParam('sala'));
    final partida = acc.asyncCode(WebEnv.getQueryParam('partida'));
    final replayLink = acc.replayCode(WebEnv.getQueryParam('replay'));
    final hash = WebEnv.getHash();
    if (replayLink != null) {
      pendingReplayCode = replayLink;
      WebEnv.replaceCleanUrl();
    } else if (partida != null) {
      pendingJoinCorrCode = partida;
      WebEnv.replaceCleanUrl();
    } else if (sala != null) {
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

  // ── Conta ────────────────────────────────────────────────────────────────────
  // Opcional: sem conta, tudo funciona igual (convidado, mesa local, rede de casa).
  // Com conta: o nome de usuário (único) é o nome no jogo e o desafio do dia vale em qualquer aparelho.
  static const _kAccToken = 'ultimato.account.token';
  static const _kPlayed = 'ultimato.played';
  static const _kDeviceKey = 'ultimato.devicekey';
  static const _kContrib = 'ultimato.contrib';
  static const _kAccUser = 'ultimato.account.user';
  // De quem é o progresso guardado no aparelho (id da conta; vazio = convidado).
  static const _kProgressOwner = 'ultimato.progress.owner';
  bool _syncingProgress = false;
  bool _syncAgain = false;

  acc.AccountUser? account;

  /// Brasão de cada jogador da partida online (índice do jogador; vazio sem brasão).
  List<String> playerCrests = const [];

  String crestOfPlayer(int p) => p >= 0 && p < playerCrests.length ? playerCrests[p] : '';

  /// Escolhe o brasão em destaque da conta ('' tira). Devolve a mensagem de erro, ou null se deu certo.
  Future<String?> setCrest(String crest) async {
    final tok = _accountToken;
    if (tok == null) return 'Entre na sua conta para exibir um brasão.';
    if (crest.isNotEmpty && !crestEarned(codexProgress, crest)) return 'Esse brasão ainda não foi conquistado.';
    try {
      final u = await acc.accountSetCrest(serverUrl(), tok, crest);
      if (_accountToken != tok) return null;
      _storeAccount(tok, u);
      Telemetry.track('crest_set', props: {'crest': crest.isEmpty ? 'none' : crest.split(':').first});
      notifyListeners();
      return null;
    } on acc.AccountError catch (e) {
      if (e.unauthorized && _accountToken == tok) {
        _clearAccount();
        notifyListeners();
      }
      return e.message;
    } catch (_) {
      return 'Sem conexão com o servidor. Tente de novo.';
    }
  }

  /// O brasão em destaque sobe de metal sozinho quando a campanha da crônica melhora.
  void _upgradeCrest() {
    final cur = account?.crest ?? '';
    final p = parseCrest(cur);
    if (p == null || p.chronicle == null) return;
    final best = bestChronicleCrest(codexProgress, p.chronicle!.id);
    if (best.isNotEmpty && best != cur && (parseCrest(best)?.tier ?? 0) > p.tier) unawaited(setCrest(best));
  }
  String? _accountToken;
  bool accountBusy = false;

  /// E-mail novo esperando o código (troca de e-mail de conta já confirmada).
  String? accountPendingEmail;

  /// Quando dá para pedir outro código.
  DateTime? accountResendAt;

  bool get signedIn => account != null && _accountToken != null;

  /// Pedido para a tela abrir a janela da conta (com o motivo). A tela limpa depois de abrir.
  String? accountPrompt;

  /// Online só com conta: sem ela, pede para entrar e não segue.
  bool _onlineGate() {
    if (signedIn) return true;
    accountPrompt = 'Para jogar online, entre ou crie uma conta. É grátis e o seu nome fica só seu.';
    notifyListeners();
    return false;
  }

  /// Nome online: sempre o da conta.
  String get onlineName => account?.username ?? 'Jogador';

  /// Falta confirmar o e-mail do cadastro ou o de uma troca.
  bool get accountNeedsConfirm => signedIn && (!account!.emailVerified || accountPendingEmail != null);

  /// Para onde foi o último código.
  String get accountCodeEmail => accountPendingEmail ?? account?.email ?? '';

  int get accountResendIn {
    final at = accountResendAt;
    if (at == null) return 0;
    final s = at.difference(DateTime.now()).inMilliseconds;
    return s <= 0 ? 0 : (s / 1000).ceil();
  }

  void _loadAccount() {
    _accountToken = AppStorage.instance.getString(_kAccToken);
    final u = _readJsonStorage(_kAccUser);
    account = _accountToken != null && u != null ? acc.AccountUser.fromJson(u) : null;
    if (account == null) _accountToken = null;
    if (account != null) {
      final saved = acc.Entitlements.fromToken(AppStorage.instance.getString(_kEnt) ?? '');
      if (saved.valid) ent = saved; // offline e LAN: o que a conta comprou continua valendo por 30 dias
    }
    if (netOnline) unawaited(refreshAccount());
  }

  void _storeAccount(String token, acc.AccountUser u) {
    _accountToken = token;
    account = u;
    AppStorage.instance.setString(_kAccToken, token);
    AppStorage.instance.setString(_kAccUser, jsonEncode(u.toJson()));
    savePlayerName(u.username);
  }

  void _applyState(acc.AccountState st) {
    final tok = _accountToken;
    if (tok != null) _storeAccount(tok, st.user);
    accountPendingEmail = st.pendingEmail;
    if (st.resendIn > 0) accountResendAt = DateTime.now().add(Duration(seconds: st.resendIn));
  }

  void _clearAccount() {
    corrGames = const [];
    corrInvites = const [];
    friends = const acc.FriendLists();
    friendsLoaded = false;
    corrLoaded = false;
    _accountToken = null;
    account = null;
    accountPendingEmail = null;
    accountResendAt = null;
    ent = acc.Entitlements.none;
    pixOrder = null;
    _pixTimer?.cancel();
    AppStorage.instance.remove(_kAccToken);
    AppStorage.instance.remove(_kAccUser);
    AppStorage.instance.remove(_kEnt);
  }

  /// Confere a sessão guardada. Sem internet, mantém a conta como estava.
  Future<void> refreshAccount() async {
    final tok = _accountToken;
    if (tok == null) return;
    try {
      final st = await acc.accountMe(serverUrl(), tok);
      if (_accountToken != tok) return;
      _applyState(st);
      unawaited(syncProgress());
      unawaited(refreshCorr(silent: true));
      unawaited(refreshFriends(silent: true));
      unawaited(refreshRankedMe()); // duelo em andamento e patente aparecem no início
      unawaited(refreshEntitlements());
    } on acc.AccountError catch (e) {
      if (e.unauthorized && _accountToken == tok) _clearAccount();
    }
    notifyListeners();
  }

  /// Progresso do desafio (estrelas por dia, meta semanal, Códice) na conta: manda o do aparelho, recebe o da
  /// conta juntado (fica o melhor de cada item) e guarda aqui. Na primeira vez numa conta, o que foi jogado como
  /// convidado vai junto. Se o aparelho guardava o progresso de outra conta, não manda: só baixa o desta.
  Future<void> syncProgress() async {
    final tok = _accountToken;
    final me = account;
    if (tok == null || me == null || !netOnline) return;
    if (_syncingProgress) {
      _syncAgain = true; // chegou progresso novo durante o envio: manda de novo no fim
      return;
    }
    _syncingProgress = true;
    try {
      final owner = AppStorage.instance.getString(_kProgressOwner);
      final mine = owner == null || owner.isEmpty || owner == '${me.id}';
      final res = await acc.accountSyncProgress(
          serverUrl(), tok, mine ? dailyProgress : const {}, mine ? codexProgress : const {});
      if (_accountToken != tok) return;
      dailyProgress = res.daily;
      codexProgress = res.codex;
      AppStorage.instance.setString('estandarte.daily.done', jsonEncode(dailyProgress));
      AppStorage.instance.setString('estandarte.codex', jsonEncode(codexProgress));
      AppStorage.instance.setString(_kProgressOwner, '${me.id}');
      _upgradeCrest();
      notifyListeners();
    } on acc.AccountError catch (e) {
      if (e.unauthorized && _accountToken == tok) {
        _clearAccount();
        notifyListeners();
      }
    } finally {
      _syncingProgress = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncProgress());
      }
    }
  }

  /// Roda um pedido de conta: marca ocupado, devolve o erro (ou null) e sai da conta se o token caiu.
  Future<acc.AccountError?> _accountRun(Future<void> Function() run) async {
    if (accountBusy) return null;
    accountBusy = true;
    notifyListeners();
    try {
      await run();
      return null;
    } on acc.AccountError catch (e) {
      if (e.unauthorized && _accountToken != null) _clearAccount();
      return e;
    } finally {
      accountBusy = false;
      notifyListeners();
    }
  }

  /// Cria a conta e entra; o código de confirmação vai para o e-mail.
  Future<acc.AccountError?> accountSignUp(String email, String username, String password) =>
      _accountRun(() async {
        final s = await acc.accountRegister(serverUrl(), email.trim(), username.trim(), password);
        _storeAccount(s.token, s.user);
        accountPendingEmail = null;
        accountResendAt = s.codeSent ? DateTime.now().add(const Duration(seconds: 60)) : null;
        unawaited(syncProgress()); // o que foi jogado como convidado vai para a conta nova
      });

  /// Entra com e-mail ou nome de usuário.
  Future<acc.AccountError?> accountSignIn(String login, String password) => _accountRun(() async {
        final s = await acc.accountLogin(serverUrl(), login.trim(), password);
        _storeAccount(s.token, s.user);
        accountPendingEmail = null;
        accountResendAt = null;
        unawaited(refreshAccount()); // traz troca de e-mail pendente e o tempo do reenvio (e as partidas)
      });

  Future<acc.AccountError?> accountVerify(String code) => _accountRun(() async {
        final u = await acc.accountVerify(serverUrl(), _accountToken!, code.trim());
        _storeAccount(_accountToken!, u);
        accountPendingEmail = null;
        accountResendAt = null;
      });

  Future<acc.AccountError?> accountResendCode() => _accountRun(() async {
        final secs = await acc.accountResendCode(serverUrl(), _accountToken!);
        accountResendAt = DateTime.now().add(Duration(seconds: secs));
      });

  /// Troca o e-mail: com e-mail confirmado o novo fica pendente até o código; sem, troca na hora.
  Future<acc.AccountError?> accountChangeEmail(String email) => _accountRun(() async {
        final st = await acc.accountChangeEmail(serverUrl(), _accountToken!, email.trim());
        _applyState(st);
        if (st.codeSent) accountResendAt = DateTime.now().add(const Duration(seconds: 60));
      });

  /// Esqueci a senha: manda o código para o e-mail da conta.
  Future<acc.AccountError?> accountForgotPassword(String login) =>
      _accountRun(() => acc.accountForgotPassword(serverUrl(), login.trim()));

  /// Troca a senha com o código e entra (neste aparelho; os outros saem).
  Future<acc.AccountError?> accountResetPassword(String login, String code, String password) =>
      _accountRun(() async {
        final s = await acc.accountResetPassword(serverUrl(), login.trim(), code.trim(), password);
        _storeAccount(s.token, s.user);
        accountPendingEmail = null;
        accountResendAt = null;
        unawaited(refreshAccount());
      });

  /// Troca o nome de usuário (continua único).
  Future<acc.AccountError?> accountRename(String username) => _accountRun(() async {
        final u = await acc.accountRename(serverUrl(), _accountToken!, username.trim());
        _storeAccount(_accountToken!, u);
      });

  /// null = nome livre. Sem internet devolve null (o cadastro confere de novo).
  Future<String?> accountCheckUsername(String username) async {
    try {
      return await acc.accountCheckUsername(serverUrl(), username.trim());
    } on acc.AccountError {
      return null;
    }
  }

  /// Sai da conta neste aparelho (o nome fica, para continuar jogando como convidado).
  Future<void> accountSignOut() async {
    final tok = _accountToken;
    _clearAccount();
    notifyListeners();
    if (tok != null) {
      try {
        await acc.accountLogout(serverUrl(), tok);
      } catch (_) {} // sem internet: o token vence sozinho no servidor
    }
  }

  /// Só para as fotos de tela: entra numa conta sem servidor.
  @visibleForTesting
  void debugSetAccount(acc.AccountUser? u, {String? pendingEmail}) {
    account = u;
    _accountToken = u == null ? null : 'teste';
    accountPendingEmail = pendingEmail;
    accountResendAt = u == null ? null : DateTime.now().add(const Duration(seconds: 42));
    notifyListeners();
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
    _corrTimer?.cancel();
    _friendsTimer?.cancel();
    screen = AppScreen.home;
    notifyListeners();
    if (signedIn) {
      unawaited(refreshCorr(silent: true));
      unawaited(refreshFriends(silent: true));
      unawaited(refreshRankedMe());
    }
  }

  // ---------------- Correspondência ----------------

  /// Busca as partidas por correspondência da conta. [silent] não mostra erro se já há uma lista na tela.
  Future<void> refreshCorr({bool silent = false}) async {
    final tok = _accountToken;
    if (tok == null || !netOnline || corrLoading) return;
    corrLoading = true;
    if (!silent) notifyListeners();
    try {
      final res = await acc.asyncMine(serverUrl(), tok);
      if (_accountToken != tok) return;
      corrGames = res.games;
      corrInvites = res.invites;
      corrLoaded = true;
      corrError = null;
    } on acc.AccountError catch (e) {
      if (e.unauthorized && _accountToken == tok) _clearAccount();
      if (!silent || corrGames.isEmpty) corrError = e.message;
    } finally {
      corrLoading = false;
      notifyListeners();
    }
  }

  void openCorrScreen() {
    SoundPlayer.unlock();
    if (!_onlineGate()) return;
    _roomsTimer?.cancel();
    screen = AppScreen.corr;
    corrError = null;
    notifyListeners();
    unawaited(refreshCorr());
    _corrTimer?.cancel();
    _corrTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (screen == AppScreen.corr) {
        unawaited(refreshCorr(silent: true));
      } else {
        _corrTimer?.cancel();
      }
    });
  }

  bool corrCreating = false;

  /// Cria a sala de espera no servidor e entra nela (as regras se acertam na sala, como numa mesa online).
  /// [invite]: amigos chamados já na criação (recebem o convite e um e-mail).
  Future<void> createCorrGame({List<String> invite = const []}) async {
    if (!_onlineGate() || corrCreating) return;
    if (!netOnline) {
      showToast('Sem internet: a correspondência precisa de conexão.', 4000);
      return;
    }
    corrCreating = true;
    notifyListeners();
    try {
      final id = await acc.asyncCreate(serverUrl(), _accountToken!, invite: invite);
      if (id.isNotEmpty) {
        if (invite.isNotEmpty) showToast('Convite enviado para ${invite.join(', ')}.');
        openCorrGame(id);
      }
    } on acc.AccountError catch (e) {
      if (e.unauthorized) {
        _clearAccount();
        _onlineGate();
      } else {
        showToast(e.message, 4500);
      }
    } finally {
      corrCreating = false;
      notifyListeners();
    }
  }

  /// Abre uma partida por correspondência (pelo código de 6 letras ou o link).
  void openCorrGame(String raw) {
    final code = acc.asyncCode(raw);
    if (code == null) {
      showToast('O código da correspondência tem 6 letras (ex.: K7M2QA).');
      return;
    }
    if (!_onlineGate()) return;
    _corrTimer?.cancel();
    _connectOnlineQuery(
      'async=$code',
      host: false,
      fromRooms: false,
      name: onlineName,
      code: code,
      isPublic: false,
      corr: true,
    );
  }

  /// Recusa o convite de um amigo (some da lista).
  Future<void> declineCorrInvite(String id) async {
    final tok = _accountToken;
    if (tok == null) return;
    corrInvites = corrInvites.where((i) => i.id != id).toList();
    notifyListeners();
    try {
      await acc.asyncDeclineInvite(serverUrl(), tok, id);
    } on acc.AccountError catch (e) {
      showToast(e.message);
      unawaited(refreshCorr(silent: true));
    }
  }

  /// Chama um amigo para a sala de espera da correspondência aberta agora.
  Future<bool> inviteToCorr(String name) async {
    final tok = _accountToken;
    final id = lobbyCode ?? online?.code;
    if (tok == null || id == null || !inCorr) return false;
    try {
      await acc.asyncInvite(serverUrl(), tok, id, name);
      showToast('Convite enviado para $name.');
      return true;
    } on acc.AccountError catch (e) {
      showToast(e.message, 4000);
      return false;
    }
  }

  // ---------------- Amigos ----------------

  acc.FriendLists friends = const acc.FriendLists();
  bool friendsLoading = false;
  bool friendsLoaded = false;
  String? friendsError;
  Timer? _friendsTimer;

  /// Amigos com o jogo aberto agora (o número no início).
  int get friendsOnline => friends.friends.where((f) => f.online).length;

  Future<void> refreshFriends({bool silent = false}) async {
    final tok = _accountToken;
    if (tok == null || !netOnline || friendsLoading) return;
    friendsLoading = true;
    if (!silent) notifyListeners();
    try {
      final l = await acc.friendsList(serverUrl(), tok);
      if (_accountToken != tok) return;
      friends = l;
      friendsLoaded = true;
      friendsError = null;
    } on acc.AccountError catch (e) {
      if (e.unauthorized && _accountToken == tok) _clearAccount();
      if (!silent || !friendsLoaded) friendsError = e.message;
    } finally {
      friendsLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- loja (Comandante)

  static const _kEnt = 'ultimato.ent';
  acc.Entitlements ent = acc.Entitlements.none; // o que a conta comprou
  acc.StoreCatalog? storeCatalog;
  bool storeLoading = false;
  String? storeError;
  acc.PixOrder? pixOrder; // Pix em andamento (pelo site)
  bool pixBusy = false;
  Timer? _pixTimer;

  bool lobbyPremium = false; // quem manda na sala é Comandante: o conteúdo dele vale para a mesa toda
  bool lobbyExtrasLocked = false; // servidor: regras extras travadas (quem manda na sala não é Comandante)
  static const _kStoreOpen = 'ultimato.store.open';

  /// A loja já abriu alguma vez (até lá nada fica travado, porque não haveria como comprar).
  bool get storeOpen => AppStorage.instance.getString(_kStoreOpen) == '1';

  /// Regras extras travadas nesta sala: online quem decide é o servidor; na mesa local e na LAN, quem abre a mesa
  /// precisa ser Comandante (vale offline pelo token guardado).
  bool get extrasLocked => online != null ? lobbyExtrasLocked : (storeOpen && !isComandante);

  bool get isComandante => signedIn && ent.comandante;

  void _setEnt(acc.Entitlements e) {
    ent = e;
    if (e.token.isNotEmpty) AppStorage.instance.setString(_kEnt, e.token);
    notifyListeners();
  }

  Future<void> refreshEntitlements() async {
    final tok = _accountToken;
    if (tok == null || !netOnline) return;
    try {
      final e = await acc.storeMe(serverUrl(), tok);
      if (_accountToken == tok) _setEnt(e);
    } catch (_) {} // loja fechada ou sem internet: fica o que estava guardado
  }

  void openStoreScreen() {
    SoundPlayer.unlock();
    _corrTimer?.cancel();
    _roomsTimer?.cancel();
    _friendsTimer?.cancel();
    screen = AppScreen.store;
    storeError = null;
    notifyListeners();
    Telemetry.track('store_view');
    unawaited(refreshStore());
  }

  Future<void> refreshStore() async {
    if (storeLoading) return;
    storeLoading = true;
    notifyListeners();
    try {
      storeCatalog = await acc.storeCatalog(serverUrl());
      if (storeCatalog!.items.any((i) => i.available)) AppStorage.instance.setString(_kStoreOpen, '1');
      await refreshEntitlements();
    } on acc.AccountError catch (e) {
      storeError = e.message;
    } catch (_) {
      storeError = 'O servidor não respondeu. Tente de novo.';
    } finally {
      storeLoading = false;
      notifyListeners();
    }
  }

  /// Gera um Pix para o item e confere a cada 3 s até ser pago (ou vencer).
  Future<void> buyWithPix(String sku) async {
    final tok = _accountToken;
    if (tok == null || pixBusy) return;
    pixBusy = true;
    storeError = null;
    notifyListeners();
    try {
      pixOrder = await acc.storePixOrder(serverUrl(), tok, sku);
      Telemetry.track('store_pix_order', props: {'sku': sku});
      _pixTimer?.cancel();
      _pixTimer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_pollPix()));
    } on acc.AccountError catch (e) {
      storeError = e.message;
    } catch (_) {
      storeError = 'Não deu para gerar o Pix. Confira a internet e tente de novo.';
    } finally {
      pixBusy = false;
      notifyListeners();
    }
  }

  Future<void> _pollPix() async {
    final tok = _accountToken, o = pixOrder;
    if (tok == null || o == null || screen != AppScreen.store) {
      _pixTimer?.cancel();
      return;
    }
    try {
      final r = await acc.storePixStatus(serverUrl(), tok, o.id);
      pixOrder = r.order;
      if (r.order.status != 'pending') _pixTimer?.cancel();
      if (r.ent != null) {
        _setEnt(r.ent!);
        Telemetry.track('store_purchase', props: {'channel': 'pix'});
      }
      notifyListeners();
    } catch (_) {} // tenta de novo no próximo ciclo
  }

  Future<({List<acc.MyReplay> list, bool archive, bool more, int keepDays})> loadMyReplays() {
    final tok = _accountToken;
    if (tok == null) throw const acc.AccountError('Entre na sua conta para ver suas partidas.');
    return acc.replaysMine(serverUrl(), tok);
  }

  void cancelPix() {
    _pixTimer?.cancel();
    pixOrder = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- fila ranqueada (Duelo)

  Map<String, dynamic>? rankedInfo; // /ranked/me: nota, posição, castigo, duelo em andamento
  List<Map<String, dynamic>> rankedTopList = const [];
  int rankedQueueSize = 0;
  bool rankedLoading = false;
  String? rankedError;
  String? _rankedTicket;
  String rankedStatus = 'idle'; // idle | joining | waiting | matched
  int _rankedJoinedMs = 0;
  Timer? _rankedTimer;
  String? rankedMode; // a partida atual é um duelo ranqueado ('duel')
  Map<String, dynamic>? rankedResult; // resultado da nota no fim do duelo
  bool _rankedSession = false; // entrou pela fila: ao sair, volta para a tela da ranqueada

  int get rankedWaitSecs =>
      _rankedJoinedMs == 0 ? 0 : (DateTime.now().millisecondsSinceEpoch - _rankedJoinedMs) ~/ 1000;

  void openRankedScreen() {
    SoundPlayer.unlock();
    if (!_onlineGate()) return;
    _corrTimer?.cancel();
    _roomsTimer?.cancel();
    _friendsTimer?.cancel();
    screen = AppScreen.ranked;
    rankedError = null;
    notifyListeners();
    unawaited(refreshRanked());
  }

  Future<void> refreshRanked() async {
    if (rankedLoading) return;
    rankedLoading = true;
    notifyListeners();
    final tok = _accountToken;
    try {
      final top = await acc.rankedTop(serverUrl());
      rankedTopList = [for (final e in (top['entries'] as List<dynamic>? ?? const [])) Map<String, dynamic>.from(e as Map)];
      rankedQueueSize = (top['queue'] as num?)?.toInt() ?? 0;
      if (tok != null) {
        rankedInfo = await acc.rankedMe(serverUrl(), tok);
      }
    } on acc.AccountError catch (e) {
      if (e.unauthorized && _accountToken == tok) {
        _clearAccount();
      } else {
        rankedError = e.message;
      }
    } catch (_) {
      rankedError = 'O servidor não respondeu. Tente de novo.';
    } finally {
      rankedLoading = false;
      notifyListeners();
    }
  }

  /// Só a nota da conta (para o início: patente e duelo em andamento), sem mexer na tela.
  Future<void> refreshRankedMe() async {
    final tok = _accountToken;
    if (tok == null || !netOnline) return;
    try {
      rankedInfo = await acc.rankedMe(serverUrl(), tok);
      notifyListeners();
    } catch (_) {}
  }

  /// Entra na fila do Duelo e pergunta a cada 2 s até achar um adversário.
  Future<void> joinRankedQueue() async {
    final tok = _accountToken;
    if (tok == null || rankedStatus != 'idle') return;
    rankedStatus = 'joining';
    rankedError = null;
    notifyListeners();
    try {
      final r = await acc.rankedJoin(serverUrl(), tok);
      _rankedJoinedMs = DateTime.now().millisecondsSinceEpoch - ((r['secs'] as num?)?.toInt() ?? 0) * 1000;
      Telemetry.track('ranked_queue_join');
      _onRankedPoll(r);
    } on acc.AccountError catch (e) {
      rankedStatus = 'idle';
      rankedError = e.message;
      notifyListeners();
    } catch (_) {
      rankedStatus = 'idle';
      rankedError = 'Não deu para entrar na fila. Confira a internet e tente de novo.';
      notifyListeners();
    }
  }

  void _onRankedPoll(Map<String, dynamic> r) {
    final st = r['status'] as String? ?? '';
    _rankedTicket = r['ticket'] as String? ?? _rankedTicket;
    rankedQueueSize = (r['queue'] as num?)?.toInt() ?? rankedQueueSize;
    if (st == 'matched' && r['room'] is String) {
      _rankedTimer?.cancel();
      rankedStatus = 'matched';
      notifyListeners();
      Telemetry.track('ranked_matched', props: {'wait': rankedWaitSecs});
      _enterRankedRoom(r['room'] as String);
      return;
    }
    if (st != 'waiting') {
      _stopRankedQueue();
      notifyListeners();
      return;
    }
    rankedStatus = 'waiting';
    _rankedTimer?.cancel();
    _rankedTimer = Timer(const Duration(seconds: 2), () async {
      final t = _rankedTicket;
      if (t == null || rankedStatus != 'waiting') return;
      try {
        _onRankedPoll(await acc.rankedPoll(serverUrl(), t));
      } catch (_) {
        if (rankedStatus == 'waiting') _onRankedPoll({'status': 'waiting', 'ticket': t}); // tenta de novo
      }
    });
    notifyListeners();
  }

  Future<void> leaveRankedQueue() async {
    final t = _rankedTicket;
    _stopRankedQueue();
    notifyListeners();
    if (t != null) {
      try {
        await acc.rankedLeave(serverUrl(), t);
      } catch (_) {}
    }
  }

  void _stopRankedQueue() {
    _rankedTimer?.cancel();
    _rankedTicket = null;
    rankedStatus = 'idle';
    _rankedJoinedMs = 0;
  }

  /// Volta para o duelo em andamento (caiu, fechou o app) ou entra no que acabou de ser pareado.
  void _enterRankedRoom(String code) {
    _stopRankedQueue();
    _rankedSession = true;
    joinOnlineRoom(code, onlineName);
    _rankedSession = true; // joinOnlineRoom limpa o estado da sessão anterior
  }

  void rejoinRankedDuel() {
    final code = rankedInfo?['room'] as String?;
    if (code != null) _enterRankedRoom(code);
  }

  /// Desistir do duelo em andamento (a vitória vai para o adversário; não é abandono).
  void resignRanked() {
    final v = view;
    if (rankedMode == null || v == null || v['phase'] != 'play' || me < 0) return;
    _sendAction({'t': 'resign'});
    Telemetry.track('ranked_resign');
  }

  void openFriendsScreen() {
    SoundPlayer.unlock();
    if (!_onlineGate()) return;
    _corrTimer?.cancel();
    _roomsTimer?.cancel();
    screen = AppScreen.friends;
    friendsError = null;
    notifyListeners();
    unawaited(refreshFriends());
    _friendsTimer?.cancel();
    _friendsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (screen == AppScreen.friends) {
        unawaited(refreshFriends(silent: true));
      } else {
        _friendsTimer?.cancel();
      }
    });
  }

  /// Pede amizade; devolve a mensagem de erro (null se deu certo).
  Future<String?> addFriend(String name) async {
    final tok = _accountToken;
    if (tok == null) return 'Entre na sua conta.';
    final clean = name.trim();
    if (clean.isEmpty) return 'Digite o nome de usuário.';
    try {
      final r = await acc.friendRequest(serverUrl(), tok, clean);
      showToast(r.accepted ? 'Agora você e ${r.name} são amigos.' : 'Pedido enviado para ${r.name}.');
      unawaited(refreshFriends(silent: true));
      return null;
    } on acc.AccountError catch (e) {
      return e.message;
    }
  }

  Future<void> acceptFriend(String name) => _friendAction(
        name,
        () => acc.friendAccept(serverUrl(), _accountToken!, name),
        'Agora você e $name são amigos.',
      );

  /// Desfaz a amizade, recusa ou cancela o pedido.
  Future<void> removeFriend(String name) => _friendAction(
        name,
        () => acc.friendRemove(serverUrl(), _accountToken!, name),
        null,
      );

  Future<void> _friendAction(String name, Future<void> Function() run, String? done) async {
    if (_accountToken == null) return;
    try {
      await run();
      if (done != null) showToast(done);
    } on acc.AccountError catch (e) {
      showToast(e.message);
    }
    await refreshFriends(silent: true);
  }

  /// Desafia um amigo: cria uma partida por correspondência já com o convite e abre a sala de espera.
  void challengeFriend(String name) => unawaited(createCorrGame(invite: [name]));

  /// Só para as fotos de tela.
  @visibleForTesting
  void debugSetFriends(acc.FriendLists l) {
    friends = l;
    friendsLoaded = true;
    friendsError = null;
    notifyListeners();
  }

  /// Só para as fotos de tela.
  @visibleForTesting
  void debugSetCorr(List<acc.AsyncGameInfo> games, {List<acc.AsyncInviteInfo> invites = const []}) {
    corrInvites = invites;
    corrGames = games;
    corrLoaded = true;
    corrError = null;
    notifyListeners();
  }

  void _loadDailyLocalProgress() {
    dailyProgress = _readJsonStorage('estandarte.daily.done') ?? {};
    codexProgress = _readJsonStorage('estandarte.codex') ?? {};
    final cached = _readJsonStorage('estandarte.daily.cache');
    if (cached != null && dailySnapshot == null) {
      try {
        final snap = DailySnapshot.fromServerJson(cached);
        dailySnapshot = DailySnapshot(
          date: snap.date,
          resetInSecs: snap.resetInSecs,
          weekday: snap.weekday,
          challenge: snap.challenge,
          ranking: snap.ranking,
          totalRanked: snap.totalRanked,
          fromServer: false,
          rankingNote: snap.rankingNote,
        );
      } catch (_) {}
    }
  }

  int get weeklyChallengeDaysCount {
    final now = DateTime.now();
    var count = 0;
    for (var i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (dailyProgress.containsKey(key)) count++;
    }
    return count;
  }

  int get todayChallengeStars {
    final date = dailySnapshot?.date;
    if (date == null) return 0;
    final rec = dailyProgress[date];
    if (rec is Map) {
      return (rec['stars'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<void> refreshDailyChallenge({bool quiet = false}) async {
    if (dailyLoading) return;
    dailyLoading = true;
    if (!quiet) dailyError = null;
    notifyListeners();
    try {
      final res = await fetchDailyChallenge(serverUrl());
      final snap = DailySnapshot.fromServerJson(res);
      dailySnapshot = snap;
      dailyError = null;
      AppStorage.instance.setString('estandarte.daily.cache', jsonEncode(res));
    } catch (_) {
      if (!quiet) {
        dailyError = 'Não foi possível sincronizar o desafio com o servidor.';
      }
    } finally {
      dailyLoading = false;
      notifyListeners();
    }
  }

  Future<void> openDailyScreen() async {
    _roomsTimer?.cancel();
    _roomsTimer = null;
    screen = AppScreen.daily;
    Telemetry.track(
      'challenge_viewed',
      date: dailySnapshot?.date,
      challengeId: dailySnapshot?.challenge.id,
      mode: dailySnapshot?.challenge.kind,
    );
    notifyListeners();
    await refreshDailyChallenge(quiet: dailySnapshot != null);
  }

  void setChallengeDifficulty(String diff) {
    final next = diff == 'marechal' ? 'marechal' : 'standard';
    if (next == challengeDifficulty) return;
    challengeDifficulty = next;
    notifyListeners();
  }

  Future<void> startDailyChallenge({DailyChallengeSpec? overrideSpec}) async {
    SoundPlayer.unlock();
    var spec = overrideSpec ?? dailySnapshot?.challenge;
    if (spec == null) {
      await refreshDailyChallenge();
      spec = dailySnapshot?.challenge;
    }
    if (spec == null) {
      showToast('Sem conexão para carregar o desafio de hoje.');
      return;
    }

    _resetSessionState();
    activeChallenge = spec;
    role = 'host';
    netP2p = false;
    me = 0;
    turnSecs = 0;
    challengeWon = false;
    challengeLost = false;
    challengeEndReason = '';
    challengeStarsEarned = 0;
    challengeServerRank = null;
    challengeNeedsAccount = false;
    challengeSubmitRanking = List<DailyRankEntry>.from(dailySnapshot?.ranking ?? const []);
    challengeResultSubmitted = false;
    challengeReplayId = null;
    _challengeStartedMs = DateTime.now().millisecondsSinceEpoch;

    String? srvRunId;
    String? srvSeed; // dados da corrida: com ela a partida é gravada e o servidor confere o resultado
    if (netOnline) {
      try {
        final startRes = await startDailyRun(
          serverUrl(),
          clientId: Telemetry.clientId,
          difficulty: challengeDifficulty,
          platform: Telemetry.platformLabel,
          appVersion: appVersion,
        );
        srvRunId = startRes['runId'] as String?;
        srvSeed = startRes['seed'] as String?;
      } catch (_) {}
    }
    _challengeRunId = srvRunId ?? 'off_${DateTime.now().millisecondsSinceEpoch}';

    // O motor monta a partida do desafio (mutações, dificuldade, regras e estrelas) e, com a semente do servidor, grava
    // as jogadas para o servidor refazer e conferir o resultado.
    final cleanPlayer = cleanName(savedName);
    _dropEngineGame();
    final started = engine.callJson('challengeStart', {
      'setup': spec.setup,
      'spec': challengeSpecJson(spec),
      'difficulty': challengeDifficulty,
      'name': cleanPlayer.isNotEmpty ? cleanPlayer : 'Você',
      'seed': ?srvSeed,
    });
    _engineId = (started['id'] as num).toInt();
    _challengeRecorded = started['recorded'] == true;
    final st = engine.exportGame(_engineId!);
    final players = (st['players'] as List<dynamic>).cast<Map<String, dynamic>>();
    final opts = Map<String, dynamic>.from(st['opts'] as Map<String, dynamic>? ?? const {});
    optEvents = opts['events'] == true;
    optPacts = opts['pacts'] == true;
    optNukes = opts['nukes'] == true;
    optHq = opts['hq'] != false;
    optSpy = opts['spy'] == true;
    seats = [
      for (final p in players)
        LobbySeat(
          name: p['name'] as String? ?? 'Jogador',
          color: (p['color'] as num?)?.toInt() ?? 0,
          ctrl: p['ctrl'] as String? ?? 'bot',
        ),
    ];
    screen = AppScreen.game;
    WebEnv.setWakeLock(true);
    Telemetry.track(
      'challenge_started',
      date: spec.date,
      challengeId: spec.id,
      mode: spec.kind,
      difficulty: challengeDifficulty,
      doctrine: spec.doctrines.isNotEmpty ? spec.doctrines.first.key : null,
      mutation: spec.mutations.isNotEmpty ? spec.mutations.first.key : null,
      // Servidor já grava challenge_started autoritativo em POST /daily/start quando online
      localOnly: srvRunId != null,
    );
    _syncHost();
  }

  String _activeTelemetryMode() {
    if (inTutorial) return 'tutorial';
    if (activeChallenge != null) return activeChallenge!.kind;
    if (lobbyQuick) return 'quick';
    if (online != null) return online!.lan ? 'lan' : 'online';
    if (relayCode != null) return 'relay';
    if (_lanServer != null) return 'lan';
    return 'local';
  }

  void _evaluateActiveChallenge(Map<String, dynamic> hostView) {
    final spec = activeChallenge;
    if (spec == null || challengeWon || challengeLost) return;
    var status = evaluateChallengeState(
      spec: spec,
      mapData: mapData,
      view: hostView,
      nukesUsed: _challengeNukesUsed,
      armiesLost: _challengeArmiesLost,
      ordersUsed: _challengeOrdersUsed,
      lostKeyEver: _challengeLostKeyEver,
    );
    // Quem decide vitória, derrota e estrelas é o motor (o servidor refaz a partida com ele); daqui fica o texto.
    var round = (hostView['round'] as num?)?.toInt() ?? 1;
    final eng = _challengeState;
    if (eng != null) {
      final res = eng['result'] as Map<String, dynamic>?;
      if (res == null) {
        status = ChallengeLiveStatus(
          progressText: status.progressText,
          star2Active: eng['star2'] == true,
          star3Active: eng['star3'] == true,
          star3Reason: status.star3Reason,
          won: false,
          lost: false,
        );
      } else {
        final won = res['won'] == true;
        round = (res['round'] as num?)?.toInt() ?? round;
        status = ChallengeLiveStatus(
          progressText: status.progressText,
          star2Active: won && eng['star2'] == true,
          star3Active: won && eng['star3'] == true,
          star3Reason: status.star3Reason,
          won: won,
          lost: !won,
          endReason: (status.won || status.lost) && status.won == won ? status.endReason : _challengeEndText(res),
          earnedStars: won ? (res['stars'] as num?)?.toInt() ?? 1 : 0,
        );
      }
    }
    challengeStatus = status;
    if (status.won || status.lost) {
      challengeWon = status.won;
      challengeLost = status.lost;
      challengeEndReason = status.endReason;
      challengeStarsEarned = status.earnedStars;
      _botTimer?.cancel();
      _clockTimer?.cancel();
      SoundPlayer.play(status.won ? 'win' : 'lost');
      WebEnv.vibrate(status.won ? 280 : 180);
      _finalizeChallengeOutcome(spec, status, round);
      notifyListeners();
    }
  }

  /// A partida gravada do desafio (vai no envio para o servidor conferir); null sem gravação.
  Map<String, dynamic>? _challengeReplay() {
    final id = _engineId;
    if (!_challengeRecorded || id == null) return null;
    try {
      return engine.callJson('challengeReplay', {'id': id});
    } catch (_) {
      return null;
    }
  }

  String _challengeEndText(Map<String, dynamic> res) {
    final g = activeChallenge?.goal;
    switch (res['reason']) {
      case 'won':
        return 'Missão cumprida!';
      case 'eliminated':
        return 'Suas forças foram eliminadas do mapa.';
      case 'key_lost':
        final t = (res['lost'] as num?)?.toInt() ?? -1;
        final name = t >= 0 && t < mapData.territories.length ? mapData.territories[t].name : 'um território-chave';
        return 'Você perdeu $name (território vital da missão).';
      case 'beaten':
        return 'Um adversário cumpriu o objetivo primeiro.';
      default:
        return 'O prazo máximo de ${g?.maxRounds ?? 0} rodadas terminou.';
    }
  }

  void _finalizeChallengeOutcome(
    DailyChallengeSpec spec,
    ChallengeLiveStatus status,
    int round,
  ) {
    final durSec = _challengeStartedMs > 0
        ? max(1, (DateTime.now().millisecondsSinceEpoch - _challengeStartedMs) ~/ 1000)
        : 1;

    if (status.won) {
      final prevDay = dailyProgress[spec.date];
      final prevStars = prevDay is Map ? (prevDay['stars'] as num?)?.toInt() ?? 0 : 0;
      final prevRounds = prevDay is Map ? (prevDay['rounds'] as num?)?.toInt() ?? 99 : 99;
      if (status.earnedStars > prevStars ||
          (status.earnedStars == prevStars && round < prevRounds)) {
        dailyProgress[spec.date] = {
          'id': spec.id,
          'stars': status.earnedStars,
          'rounds': round,
          'difficulty': challengeDifficulty,
          'at': DateTime.now().millisecondsSinceEpoch,
        };
        AppStorage.instance.setString('estandarte.daily.done', jsonEncode(dailyProgress));
      }

      if (spec.isHistorical) {
        final prevCodex = codexProgress[spec.id];
        final prevCStars = prevCodex is Map ? (prevCodex['bestStars'] as num?)?.toInt() ?? 0 : 0;
        final prevCRounds = prevCodex is Map ? (prevCodex['bestRounds'] as num?)?.toInt() ?? 99 : 99;
        if (status.earnedStars > prevCStars ||
            (status.earnedStars == prevCStars && round < prevCRounds)) {
          codexProgress[spec.id] = {
            'id': spec.id,
            'title': spec.title,
            'era': spec.era,
            'lore': spec.codexLore,
            'bestStars': status.earnedStars,
            'bestRounds': round,
            'difficulty': challengeDifficulty,
            'date': spec.date,
          };
          AppStorage.instance.setString('estandarte.codex', jsonEncode(codexProgress));
        }
      }
      unawaited(syncProgress()); // com conta, o resultado vale em qualquer aparelho
    }

    Telemetry.track(
      'challenge_finished',
      date: spec.date,
      challengeId: spec.id,
      mode: spec.kind,
      difficulty: challengeDifficulty,
      doctrine: spec.doctrines.isNotEmpty ? spec.doctrines.first.key : null,
      mutation: spec.mutations.isNotEmpty ? spec.mutations.first.key : null,
      outcome: status.won ? 'win' : 'loss',
      stars: status.earnedStars,
      rounds: round,
      durationSec: durSec,
      props: {
        'armiesLost': _challengeArmiesLost,
        'ordersUsed': _challengeOrdersUsed,
        'nukesUsed': _challengeNukesUsed,
      },
      // Servidor já grava challenge_finished autoritativo em POST /daily/submit quando online
      localOnly: netOnline,
      immediate: !netOnline,
    );

    challengeNeedsAccount = netOnline && !signedIn && status.won;
    if (netOnline && signedIn && !challengeResultSubmitted) {
      challengeResultSubmitted = true;
      final name = cleanName(savedName).isNotEmpty ? cleanName(savedName) : 'Comandante';
      unawaited(
        submitDailyRun(serverUrl(), {
          'runId': _challengeRunId ?? 'off_${DateTime.now().millisecondsSinceEpoch}',
          'date': spec.date,
          'clientId': Telemetry.clientId,
          'playerName': name,
          'difficulty': challengeDifficulty,
          'won': status.won,
          'stars': status.earnedStars,
          'rounds': round,
          'armiesLost': _challengeArmiesLost,
          'ordersUsed': _challengeOrdersUsed,
          'durationSec': durSec,
          'replay': ?_challengeReplay(),
        }, accountToken: _accountToken).then((res) {
          final ver = res['verified'] as Map<String, dynamic>?;
          if (ver != null) {
            // o que o servidor apurou refazendo a partida (deve bater com o que o motor daqui calculou)
            challengeStarsEarned = (ver['stars'] as num?)?.toInt() ?? challengeStarsEarned;
            final rid = ver['replay'] as String?;
            if (rid != null && rid.length == 8) {
              challengeReplayId = rid;
              final rec = dailyProgress[spec.date];
              if (rec is Map) {
                dailyProgress[spec.date] = {...Map<String, dynamic>.from(rec), 'replay': rid};
                AppStorage.instance.setString('estandarte.daily.done', jsonEncode(dailyProgress));
              }
            }
          }
          unawaited(syncProgress()); // traz a crônica conferida (libera o brasão)
          final rank = (res['rank'] as num?)?.toInt();
          final rawEntries = (res['entries'] as List<dynamic>? ?? const []);
          final parsed = [for (final e in rawEntries) DailyRankEntry.fromJson(e as Map<String, dynamic>)];
          challengeServerRank = rank != null && rank > 0 ? rank : null;
          challengeSubmitRanking = parsed;
          if (dailySnapshot != null && dailySnapshot!.date == spec.date) {
            dailySnapshot = DailySnapshot(
              date: dailySnapshot!.date,
              resetInSecs: dailySnapshot!.resetInSecs,
              weekday: dailySnapshot!.weekday,
              challenge: dailySnapshot!.challenge,
              ranking: parsed,
              totalRanked: (res['totalRanked'] as num?)?.toInt() ?? parsed.length,
              fromServer: true,
              rankingNote: dailySnapshot!.rankingNote,
            );
          }
          notifyListeners();
        }).catchError((Object e) {
          final msg = e is DailySubmitError ? e.message : '';
          if (msg.isNotEmpty) showToast(msg, 4200); // ex.: partida não conferida, app desatualizado
        }),
      );
    }
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

  /// Primeira visita: nunca jogou o tutorial, uma partida ou o desafio, nem entrou numa conta.
  bool get isNewcomer =>
      AppStorage.instance.getString(_kPlayed) == null && dailyProgress.isEmpty && !signedIn && !hasSavedLocal;

  void _markPlayed() {
    if (AppStorage.instance.getString(_kPlayed) == null) AppStorage.instance.setString(_kPlayed, '1');
  }

  void startTutorial({String? playerName}) {
    SoundPlayer.unlock();
    _markPlayed();
    _resetSessionState();
    inTutorial = true;
    _tutorialCompletedSent = false;
    Telemetry.track('tutorial_started', mode: 'tutorial');
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
        body: 'Seu objetivo é dominar 32 territórios. O Brasil já está selecionado: toque no botão claro "Colocar" para posicionar seus 3 exércitos.',
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
      if (v['occupy'] != null) {
        return (
          step: 3,
          total: 5,
          title: 'Território Conquistado! (Avance tropas)',
          body: 'Você tomou a Argentina e ganhou 2 medalhas! Escolha quantas tropas extras quer levar do Brasil e toque no botão claro para confirmar a ocupação.',
        );
      }
      return (
        step: 3,
        total: 5,
        title: '3 Medalhas conquistadas!',
        body: 'A África Ocidental está protegida por Trincheira neste turno. Toque em "Encerrar ataques" e depois em "Encerrar turno" para usar o Quartel no próximo turno.',
      );
    }
    if (round >= 2 && step == 'reinforce' && medals >= 2 && _poolTotalOf(v) <= 17) {
      return (
        step: 4,
        total: 5,
        title: 'O Quartel (Medalhas e Ordens)',
        body: 'Clique no botão "Mobilizar +${eval?.hq?.effort ?? 5}" (ou abra o "Quartel") para converter suas medalhas em exércitos antes de reforçar!',
      );
    }
    if (round >= 2 && step == 'reinforce') {
      final free = (v['pool']?['free'] as num?)?.toInt() ?? 0;
      if (free == 0 && _poolTotalOf(v) > 0) {
        return (
          step: 5,
          total: 5,
          title: 'Bônus de Continente Obrigatório',
          body: 'Como você domina continentes inteiros, esses exércitos extras devem ser colocados nos continentes destacados no mapa!',
        );
      }
    }
    return (
      step: 5,
      total: 5,
      title: 'Golpe Final (Rota Marítima)',
      body: 'Coloque seus reforços livres no Brasil e ataque a África Ocidental (pela linha tracejada no mar) para conquistar o 32º território e vencer!',
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
    if (index == 0 && (relayCode != null || relayStarting) && signedIn) return; // na mesa pela internet, o seu nome é o da conta
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
    s.link?.send({'t': 'gone', 'm': 'Você foi removido da mesa.'});
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
    String? pass,
  }) {
    final cleanPass = pass != null ? _cleanRoomPass(pass) : null;
    if (online != null) {
      if (lobbyOwner && guestLink != null) {
        if (cleanPass != null && !lobbyQuick) {
          lobbyPass = cleanPass;
          lobbyHasPass = cleanPass.isNotEmpty;
        }
        guestLink!.send({
          't': 'cfg',
          'secs': ?secs,
          'events': ?events,
          'pacts': ?pacts,
          'nukes': ?nukes,
          'hq': ?hq,
          'spy': ?spy,
          'public': ?isPublic,
          if (cleanPass != null && !lobbyQuick) 'pass': cleanPass,
        });
        if (cleanPass != null) notifyListeners();
      }
      return;
    }
    if (extrasLocked && (events == true || pacts == true || nukes == true || spy == true || hq == false)) {
      showToast('Regras extras são do Comandante.');
      return;
    }
    if (secs != null) turnSecs = secs;
    if (events != null) optEvents = events;
    if (pacts != null) optPacts = pacts;
    if (nukes != null) optNukes = nukes;
    if (hq != null) optHq = hq;
    if (spy != null) optSpy = spy;
    if (isPublic != null) optPublic = isPublic;
    if (cleanPass != null) {
      lobbyPass = cleanPass;
      lobbyHasPass = cleanPass.isNotEmpty;
    }
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
    _markPlayed();
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
    if (extrasLocked) {
      optEvents = optPacts = optNukes = optSpy = false; // mesa de quem não é Comandante: regras padrão
      optHq = true;
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
    _matchStartedMs = DateTime.now().millisecondsSinceEpoch;
    _matchEndSent = false;
    Telemetry.track('match_started', mode: _activeTelemetryMode(), props: {'players': seats.length});
    _armTurnClock();
    _syncHost();
  }

  String _cleanRoomPass(String raw) {
    final s = raw.trim();
    return s.length > 24 ? s.substring(0, 24) : s;
  }

  String _randomToken() {
    final r = Random.secure();
    const hex = '0123456789abcdef';
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buf.write(hex[r.nextInt(16)]);
    }
    return buf.toString();
  }

  Future<void> startLanHost() async {
    if (!LanHost.supported ||
        _lanServer != null ||
        lanStarting ||
        relayCode != null ||
        relayStarting ||
        online != null) {
      return;
    }
    SoundPlayer.unlock();
    lanStarting = true;
    notifyListeners();
    try {
      final srv = await LanHost.start(
        onOpen: (link) {
          _pendingGuestLinks.add(link);
        },
        onMessage: (msg, link) => _handleHostMessage(msg, link),
        onClose: (link) => _handleHostLinkClosed(link),
      );
      _lanServer = srv;
      role = 'host';
      lobbyCode = srv.primaryAddress;
      _broadcastLobby();
    } catch (e) {
      showToast('Não foi possível abrir a rede local ($e).');
    } finally {
      lanStarting = false;
      notifyListeners();
    }
  }

  Future<void> stopLanHost() async {
    final srv = _lanServer;
    if (srv == null) return;
    _lanServer = null;
    for (final l in _pendingGuestLinks.toList()) {
      if (l is! _RelayPeerLink) {
        _pendingGuestLinks.remove(l);
        l.close();
      }
    }
    for (var i = seats.length - 1; i >= 0; i--) {
      if (seats[i].ctrl == 'remote' && seats[i].link is! _RelayPeerLink) {
        seats[i].link?.send({'t': 'gone', 'm': 'O anfitrião encerrou a rede local.'});
        seats[i].link?.close();
        seats.removeAt(i);
      }
    }
    lobbyCode = relayCode;
    await srv.close();
    _broadcastLobby();
    notifyListeners();
  }

  void startRelayHost() {
    if (relayCode != null ||
        relayStarting ||
        _lanServer != null ||
        lanStarting ||
        online != null) {
      return;
    }
    if (!netOnline) {
      showToast('Sem internet: abrir sala por código precisa de conexão.', 4000);
      return;
    }
    if (!_onlineGate()) return; // mesa pela internet: quem abre também joga com o nome da conta
    if (seats.isNotEmpty && seats[0].ctrl == 'local') {
      seats[0].name = uniqueName(onlineName, seats, (x) => x.name, self: seats[0]);
      _broadcastLobby();
    }
    SoundPlayer.unlock();
    _relayRetryTimer?.cancel();
    relayStarting = true;
    relayWaitMsg = 'Conectando ao servidor…';
    role = 'host';
    notifyListeners();
    _connectRelaySocket('relay=1');
  }

  void _connectRelaySocket(String query) {
    final srv = serverUrl();
    _relayLink = connectOnline(
      srv,
      query,
      onOpen: (link) {
        relayWaitMsg = '';
        notifyListeners();
      },
      onMessage: (msg, link) => _handleRelayControlMessage(msg, link),
      onClose: (link) {
        if (_relayLink != link) return;
        _relayLink = null;
        if (relayCode != null && _relaySecret != null && role == 'host') {
          relayWaitMsg = 'Conexão perdida. Reconectando…';
          _relayRetryTimer?.cancel();
          _relayRetryTimer = Timer(const Duration(milliseconds: 1200), _reconnectRelayHost);
        } else {
          relayStarting = false;
          relayWaitMsg = '';
        }
        notifyListeners();
      },
      onWait: (secs, _) {
        if (relayStarting || relayCode != null) {
          relayWaitMsg = secs < 6
              ? 'Conectando ao servidor…'
              : 'Acordando o servidor (${secs}s)… aguarde até 1 min.';
          notifyListeners();
        }
      },
      onFail: () {
        relayStarting = false;
        if (relayCode == null) {
          relayWaitMsg = '';
          showToast('Não foi possível abrir a sala no servidor.');
        } else {
          relayWaitMsg = 'Sem conexão com o servidor.';
        }
        notifyListeners();
      },
    );
  }

  void _reconnectRelayHost() {
    if (relayCode == null || _relaySecret == null || _relayLink != null || role != 'host') return;
    final q =
        'relayHost=${Uri.encodeQueryComponent(relayCode!)}&secret=${Uri.encodeQueryComponent(_relaySecret!)}';
    _connectRelaySocket(q);
  }

  void stopRelayHost({bool silent = false}) {
    _teardownRelayHost(
      reason: 'O anfitrião fechou a sala online.',
      sendEnd: true,
      showReason: !silent,
    );
  }

  void _teardownRelayHost({
    required String reason,
    required bool sendEnd,
    bool showReason = true,
  }) {
    _relayRetryTimer?.cancel();
    _relayRetryTimer = null;
    final rl = _relayLink;
    _relayLink = null;
    if (rl != null) {
      if (sendEnd && rl.isOpen) {
        rl.send({'t': 'rEnd', 'm_reason': reason});
      }
      rl.close();
    }
    relayStarting = false;
    relayWaitMsg = '';
    relayCode = null;
    _relaySecret = null;
    lobbyCode = lanHostAddr;
    for (final w in _relayWatchers.toList()) {
      w.markClosed();
    }
    _relayWatchers.clear();
    for (final p in _relayPeers.values) {
      p.markClosed();
      _pendingGuestLinks.remove(p);
    }
    _relayPeers.clear();
    if (_engineId == null) {
      seats.removeWhere((s) => s.ctrl == 'remote' && s.link is _RelayPeerLink);
      for (final s in seats) {
        if (s.link is _RelayPeerLink) {
          s.link = null;
          s.online = false;
        }
      }
      watchersCount = null;
      _broadcastLobby();
    } else {
      for (final s in seats) {
        if (s.link is _RelayPeerLink) {
          s.link = null;
          s.online = false;
        }
      }
      watchersCount = null;
      _syncHost();
    }
    if (showReason) {
      showToast(reason);
    }
    notifyListeners();
  }

  void _handleRelayControlMessage(Map<String, dynamic> msg, GameLink link) {
    final t = msg['t'] as String?;
    if (t == 'relayReady') {
      final code = msg['code'] as String?;
      final secret = msg['secret'] as String?;
      if (code == null || secret == null) return;
      final isReconnect = relayCode == code;
      relayStarting = false;
      relayWaitMsg = '';
      relayCode = code;
      _relaySecret = secret;
      lobbyCode = code;
      role = 'host';
      if (isReconnect) {
        final aliveIds = <int>{
          for (final p in (msg['peers'] as List<dynamic>? ?? const []))
            if (p is num) p.toInt(),
        };
        final dropped = _relayPeers.keys.where((id) => !aliveIds.contains(id)).toList();
        for (final id in dropped) {
          final pl = _relayPeers.remove(id);
          if (pl != null) {
            pl.markClosed();
            _relayWatchers.remove(pl);
            _handleHostLinkClosed(pl);
          }
        }
      }
      _publishRelayRoomInfo();
      _broadcastLobby();
      if (_engineId != null) _syncHost();
      notifyListeners();
      return;
    }
    if (t == 'rPing') {
      link.send({'t': 'rPong'});
      return;
    }
    if (t == 'rOpen') {
      final pid = (msg['id'] as num?)?.toInt();
      if (pid == null) return;
      final watch = msg['watch'] == true;
      final old = _relayPeers.remove(pid);
      if (old != null) {
        old.markClosed();
        _relayWatchers.remove(old);
        _handleHostLinkClosed(old);
      }
      final peer = _RelayPeerLink(pid, watch, this);
      _relayPeers[pid] = peer;
      _pendingGuestLinks.add(peer);
      return;
    }
    if (t == 'rIn') {
      final pid = (msg['id'] as num?)?.toInt();
      final inner = msg['m'];
      if (pid == null || inner is! Map<String, dynamic>) return;
      final peer = _relayPeers[pid];
      if (peer == null) return;
      _handleHostMessage(inner, peer);
      return;
    }
    if (t == 'rClose') {
      final pid = (msg['id'] as num?)?.toInt();
      if (pid == null) return;
      final peer = _relayPeers.remove(pid);
      if (peer == null) return;
      peer.markClosed();
      final wasWatcher = _relayWatchers.remove(peer);
      _handleHostLinkClosed(peer);
      if (wasWatcher) {
        _publishRelayRoomInfo();
        if (_engineId != null) _syncHost();
      }
      return;
    }
    if (t == 'err') {
      showToast(msg['m'] as String? ?? 'Erro no servidor.');
      return;
    }
    if (t == 'gone') {
      final m = msg['m'] as String? ?? 'Sala encerrada no servidor.';
      _teardownRelayHost(reason: m, sendEnd: false);
      return;
    }
  }

  void _sendRelayOut(int peerId, Map<String, dynamic> msg) {
    final rl = _relayLink;
    if (rl == null || !rl.isOpen) return;
    rl.send({'t': 'rOut', 'id': peerId, 'm': msg});
  }

  void _closeRelayPeer(int peerId) {
    final peer = _relayPeers.remove(peerId);
    if (peer != null) {
      peer.markClosed();
      _pendingGuestLinks.remove(peer);
      _relayWatchers.remove(peer);
    }
    final rl = _relayLink;
    if (rl != null && rl.isOpen) {
      rl.send({
        't': 'rOut',
        'id': peerId,
        'm': {'t': 'gone', 'm': 'Conexão encerrada.'},
        'close': true,
      });
    }
  }

  void _publishRelayRoomInfo() {
    final rl = _relayLink;
    if (role != 'host' || relayCode == null || rl == null || !rl.isOpen) return;
    final id = _engineId;
    final curView = id != null ? view : null;
    final status = id == null
        ? 'lobby'
        : (curView != null && curView['phase'] == 'over' ? 'over' : 'play');
    final hostName = seats.isNotEmpty
        ? seats.first.name
        : (savedName.isNotEmpty ? savedName : 'Anfitrião');
    final List<Map<String, dynamic>> playersInfo;
    if (id != null && curView != null) {
      final vPlayers = curView['players'] as List<dynamic>? ?? const [];
      playersInfo = [
        for (var p = 0; p < vPlayers.length; p++)
          () {
            final vp = vPlayers[p] as Map<String, dynamic>;
            final ctrl = vp['ctrl'] as String? ?? 'local';
            final seatIdx = (vp['seat'] as num?)?.toInt() ?? p;
            final isOn = ctrl == 'bot'
                ? false
                : (ctrl != 'remote' ||
                    (seatIdx >= 0 &&
                        seatIdx < seats.length &&
                        seats[seatIdx].link != null &&
                        seats[seatIdx].link!.isOpen &&
                        !seats[seatIdx].lag));
            return {
              'name': vp['name'] ?? '',
              'color': vp['color'] ?? p,
              'ctrl': ctrl,
              'on': isOn,
            };
          }(),
      ];
    } else {
      playersInfo = [
        for (final s in seats)
          {
            'name': s.name,
            'color': s.color,
            'ctrl': s.ctrl,
            'on': s.ctrl == 'bot'
                ? false
                : (s.ctrl != 'remote' || (s.link != null && s.link!.isOpen)),
          },
      ];
    }
    final watcherLimit = maxWatchers > 0 ? maxWatchers : 5;
    final isFull = status == 'lobby' ? seats.length >= 6 : _relayWatchers.length >= watcherLimit;
    rl.send({
      't': 'rCfg',
      'host': hostName,
      'status': status,
      'players': playersInfo,
      'round': id != null && curView != null ? (curView['round'] as num?)?.toInt() ?? 0 : 0,
      'secs': turnSecs,
      'events': optEvents,
      'pacts': optPacts,
      'nukes': optNukes,
      'hq': optHq,
      'spy': optHq && optSpy,
      'watchers': _relayWatchers.length,
      'full': isFull,
      'public': optPublic,
      'hasPass': lobbyPass.isNotEmpty,
    });
  }

  void _broadcastLobby() {
    if (role != 'host') return;
    final roomCode = relayCode ?? lanHostAddr;
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
          'public': optPublic,
          'hasPass': lobbyPass.isNotEmpty,
          'code': ?roomCode,
        });
      }
    }
    for (final w in _relayWatchers) {
      if (w.isOpen) {
        w.send({
          't': 'lobby',
          'seats': seats.map((s) => s.toLobbyJson()).toList(),
          'you': -1,
          'secs': turnSecs,
          'events': optEvents,
          'pacts': optPacts,
          'nukes': optNukes,
          'hq': optHq,
          'spy': optHq && optSpy,
          'public': optPublic,
          'hasPass': lobbyPass.isNotEmpty,
          'code': ?roomCode,
        });
      }
    }
    _publishRelayRoomInfo();
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
    if (t == 'emote') {
      // só de quem tem lugar na partida, no máximo um a cada 3 s; quem assiste não manda
      final e = (msg['e'] is num) ? (msg['e'] as num).toInt() : -1;
      final p = idx >= 0 ? _playerOfSeat(idx) : -1;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_engineId == null || p < 0 || e < 0 || e >= emoteTexts.length) return;
      if (now - (_seatEmoteMs[idx] ?? 0) < emoteGapMs) return;
      _seatEmoteMs[idx] = now;
      _relayEmote({'t': 'emote', 'p': p, 'e': e}, link);
      _pushEmote(p, e);
      return;
    }
    if (t == 'hello') {
      if (idx < 0) {
        if (!_pendingGuestLinks.contains(link)) return;
        final tok = msg['token'] as String?;
        if (tok != null && tok.isNotEmpty) {
          final reIdx = seats.indexWhere((s) => s.token == tok);
          if (reIdx >= 0) {
            _pendingGuestLinks.remove(link);
            _attachRemoteSeat(reIdx, link);
            link.send({'t': 'seat', 'token': tok});
            return;
          }
        }
        if (link is _RelayPeerLink && link.watch) {
          final watcherLimit = maxWatchers > 0 ? maxWatchers : 5;
          if (_relayWatchers.length >= watcherLimit) {
            _pendingGuestLinks.remove(link);
            link.send({
              't': 'gone',
              'm': 'Esta partida já tem $watcherLimit espectadores, o máximo.',
            });
            link.close();
            return;
          }
          if (lobbyPass.isNotEmpty) {
            final supplied = _cleanRoomPass((msg['pass'] as String?) ?? '');
            if (supplied != lobbyPass) {
              link.send({
                't': 'needPass',
                'wrong': supplied.isNotEmpty,
                'code': relayCode ?? lanHostAddr ?? 'Sala',
              });
              return;
            }
          }
          _pendingGuestLinks.remove(link);
          _relayWatchers.add(link);
          if (_engineId != null) {
            _syncHost();
          } else {
            _broadcastLobby();
          }
          notifyListeners();
          return;
        }
        if (_engineId != null) {
          _pendingGuestLinks.remove(link);
          link.send({
            't': 'gone',
            'm': link is _RelayPeerLink
                ? 'A partida já começou.'
                : 'A partida na rede local já começou.',
          });
          link.close();
          return;
        }
        if (seats.length >= 6) {
          _pendingGuestLinks.remove(link);
          link.send({'t': 'gone', 'm': 'Mesa cheia (máximo 6).'});
          link.close();
          return;
        }
        if (lobbyPass.isNotEmpty) {
          final supplied = _cleanRoomPass((msg['pass'] as String?) ?? '');
          if (supplied != lobbyPass) {
            link.send({
              't': 'needPass',
              'wrong': supplied.isNotEmpty,
              'code': relayCode ?? lanHostAddr ?? 'Rede Local',
            });
            return;
          }
        }
        _pendingGuestLinks.remove(link);
        final used = seats.map((s) => s.color).toSet();
        var col = 0;
        while (used.contains(col) && col < engine.constants.colors.length) {
          col++;
        }
        final rawNm = cleanName(msg['name'] as String?);
        final seatName = uniqueName(
          rawNm.isNotEmpty ? rawNm : 'Convidado ${seats.length}',
          seats,
          (s) => s.name,
        );
        final seatTok = _randomToken();
        seats.add(
          LobbySeat(
            name: seatName,
            color: col,
            ctrl: 'remote',
            online: true,
            seenMs: DateTime.now().millisecondsSinceEpoch,
            token: seatTok,
            link: link,
          ),
        );
        link.send({'t': 'seat', 'token': seatTok});
        _broadcastLobby();
        notifyListeners();
        return;
      }
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
    if (idx < 0) {
      if (t == 'leave' && link is _RelayPeerLink && _relayWatchers.remove(link)) {
        _publishRelayRoomInfo();
        if (_engineId != null) _syncHost();
      }
      return;
    }
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
      for (final w in _relayWatchers) {
        if (w.isOpen) w.send(msg);
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
    _pendingGuestLinks.remove(link);
    final wasWatcher = link is _RelayPeerLink && _relayWatchers.remove(link);
    final idx = seats.indexWhere((s) => s.link == link);
    if (idx < 0) {
      if (wasWatcher) {
        _publishRelayRoomInfo();
        if (_engineId != null) _syncHost();
      }
      return;
    }
    seats[idx].link = null;
    seats[idx].online = false;
    if (_engineId != null) {
      _syncHost();
    } else {
      _broadcastLobby();
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
    if (!_onlineGate()) return;
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

  void createOnlineRoom(String playerName, {bool isPublic = true, String? pass}) {
    if (!_onlineGate()) return;
    final finalName = onlineName;
    final cleanP = pass != null ? _cleanRoomPass(pass) : '';
    _connectOnlineQuery(
      'create=1',
      host: true,
      fromRooms: screen == AppScreen.rooms,
      name: finalName,
      isPublic: isPublic,
      pass: cleanP.isNotEmpty ? cleanP : null,
    );
  }

  void startQuickMatch(String playerName) {
    if (!_onlineGate()) return;
    final finalName = onlineName;
    _connectOnlineQuery(
      'quick=1',
      host: true,
      fromRooms: screen == AppScreen.rooms,
      name: finalName,
      isPublic: true,
    );
  }

  void joinOnlineRoom(
    String code,
    String playerName, {
    bool watchOnly = false,
    bool fromRooms = false,
    String? token,
    String? pass,
  }) {
    final cleanCode = roomCode(code);
    if (cleanCode == null) {
      showToast('Digite o código de 5 letras ou cole o link da sala.');
      return;
    }
    if (!_onlineGate()) return;
    final finalName = onlineName;
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
      pass: pass,
    );
  }

  void joinLanHost(String rawAddress, String playerName, {String? pass}) {
    final wsUrl = parseLanWsUrl(rawAddress);
    if (wsUrl == null) {
      showToast('Endereço inválido (ex.: 192.168.1.15 ou 192.168.1.15:7788).');
      return;
    }
    final nm = cleanName(playerName);
    final finalName = nm.isNotEmpty ? nm : 'Convidado';
    savePlayerName(finalName);
    final tok = _loadRoomToken(wsUrl, 'lan');
    _connectOnlineQuery(
      'room=lan',
      serverOverride: wsUrl,
      host: false,
      fromRooms: false,
      name: finalName,
      code: rawAddress.trim(),
      token: tok,
      isLan: true,
      pass: pass,
    );
  }

  void _connectOnlineQuery(
    String query, {
    String? serverOverride,
    required bool host,
    required bool fromRooms,
    required String name,
    String? code,
    String? token,
    bool isPublic = true,
    bool watchOnly = false,
    bool isLan = false,
    bool corr = false,
    String? pass,
  }) {
    SoundPlayer.unlock();
    if (!isLan && !netOnline) {
      showToast('Sem internet: jogar online precisa de conexão.', 4000);
      return;
    }
    final wasFromRooms = fromRooms;
    _resetSessionState();
    role = 'guest';
    netP2p = false;
    _pendingRoomPass = pass != null ? _cleanRoomPass(pass) : null;
    final srv = serverOverride ?? serverUrl();
    final ses = OnlineSession(
      server: srv,
      code: code,
      host: host,
      fromRooms: wasFromRooms,
      name: name,
      token: token,
      owner: host,
      isPublic: !isLan && isPublic,
      lan: isLan,
      corr: corr,
    )..waitMsg = isLan ? 'Conectando ao anfitrião ($code)…' : 'Conectando ao servidor…';
    online = ses;
    screen = AppScreen.lobby;
    lobbyCode = code;
    lobbyOwner = host;
    optPublic = !isLan && isPublic;
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
            if (_pendingRoomPass != null && _pendingRoomPass!.isNotEmpty) 'pass': _pendingRoomPass,
            if (!isLan && _accountToken != null) 'acc': _accountToken,
          });
          _csSentFor = _keySentFor = null; // conexão nova: a contribuição e a chave vão de novo
        } else {
          link.send({
            't': 'hello',
            'name': name,
            if (_pendingRoomPass != null && _pendingRoomPass!.isNotEmpty) 'pass': _pendingRoomPass,
            if (!isLan && _accountToken != null) 'acc': _accountToken,
          });
        }
        if (ses.code != null && !ses.lan && !ses.corr) {
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
          ses.waitMsg = isLan
              ? 'Procurando anfitrião ($secs s)… confira IP, porta e firewall.'
              : (secs < 6
                  ? 'Conectando ao servidor…'
                  : 'Acordando o servidor (${secs}s)… aguarde até 1 min.');
          notifyListeners();
        }
      },
      onFail: () {
        if (online == ses) {
          ses.waitMsg = isLan
              ? 'Não foi possível conectar ao anfitrião ($code).'
              : 'Não foi possível falar com o servidor.';
          notifyListeners();
        }
      },
    );
  }

  void _reconnectOnline() {
    final ses = online;
    if (ses == null || ses.gone || ses.code == null || guestLink != null) return;
    final tok = ses.token ?? _loadRoomToken(ses.server, ses.lan ? 'lan' : ses.code!);
    final q = ses.lan
        ? 'room=lan'
        : (ses.corr ? 'async=${Uri.encodeQueryComponent(ses.code!)}' : 'room=${Uri.encodeQueryComponent(ses.code!)}');
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
          if (_pendingRoomPass != null && _pendingRoomPass!.isNotEmpty) 'pass': _pendingRoomPass,
          if (!ses.lan && _accountToken != null) 'acc': _accountToken,
        });
        _csSentFor = _keySentFor = null;
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
    if (ses == null || ses.code == null || ses.corr) return; // a correspondência volta pela lista, não pela retomada
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

  void submitRoomPassword(String rawPass) {
    final link = guestLink;
    final ses = online;
    final clean = _cleanRoomPass(rawPass);
    _pendingRoomPass = clean;
    passPrompt = null;
    if (ses != null) {
      ses.waitMsg = 'Verificando senha…';
    }
    notifyListeners();
    link?.send({
      't': 'hello',
      'name': ses?.name ?? (savedName.isNotEmpty ? savedName : 'Convidado'),
      if (ses?.token != null) 'token': ses!.token,
      'pass': clean,
      if (ses != null && !ses.lan && _accountToken != null) 'acc': _accountToken,
    });
  }

  void cancelPasswordPrompt() {
    passPrompt = null;
    leaveGame();
  }

  void _handleRemoteMessage(Map<String, dynamic> msg, GameLink link) {
    final t = msg['t'] as String?;
    if (t == 'needPass') {
      passPrompt = (
        code: (msg['code'] as String?) ?? lobbyCode ?? 'Sala',
        wrong: msg['wrong'] == true,
        isLan: online?.lan ?? false,
      );
      if (online != null) online!.waitMsg = '';
      notifyListeners();
      return;
    }
    if (t == 'seat') {
      passPrompt = null;
      final tok = msg['token'] as String?;
      if (online != null && tok != null) {
        online!.token = tok;
        if (online!.lan) {
          _saveRoomToken(online!.server, 'lan', tok);
        } else {
          _saveOnlineSession();
        }
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
      if (msg['auth'] == true) {
        // o servidor não aceitou a conta (sessão vencida ou sem conta): confere e pede para entrar
        unawaited(refreshAccount());
        accountPrompt = m;
      }
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
      passPrompt = null;
      _contribute(msg['commit'] as String?, link);
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
              crest: s['crest'] as String? ?? '',
              rank: s['rank'] as String? ?? '',
              cmd: s['cmd'] == true,
              fnd: (s['fnd'] as num?)?.toInt() ?? 0,
            );
          })
          .toList();
      rankedMode = msg['ranked'] as String?;
      lobbyPremium = msg['premium'] == true;
      lobbyExtrasLocked = msg['extrasLocked'] == true;
      lobbyRankedStartBy = (msg['startBy'] as num?)?.toInt() ?? 0;
      me = (msg['you'] as num?)?.toInt() ?? -1;
      turnSecs = (msg['secs'] as num?)?.toInt() ?? 0;
      optEvents = msg['events'] == true;
      optPacts = msg['pacts'] == true;
      optNukes = msg['nukes'] == true;
      optHq = msg['hq'] == true;
      optSpy = msg['spy'] == true;
      optPublic = msg['public'] == true;
      lobbyHasPass = msg['hasPass'] == true;
      if (msg['pass'] is String) {
        lobbyPass = msg['pass'] as String;
      } else if (!lobbyHasPass) {
        lobbyPass = '';
      }
      lobbyCode = msg['code'] as String?;
      lobbyOwner = msg['owner'] == true;
      lobbyQuick = msg['quick'] == true;
      final qLeft = (msg['quickLeft'] as num?)?.toInt();
      lobbyQuickDeadlineMs = (lobbyQuick && qLeft != null)
          ? DateTime.now().millisecondsSinceEpoch + qLeft
          : 0;
      if (online != null) {
        online!.code = lobbyCode ?? online!.code;
        online!.owner = lobbyOwner;
        online!.isPublic = optPublic;
        if (!online!.lan) {
          _saveOnlineSession();
        }
      }
      notifyListeners();
      return;
    }
    if (t == 'ranked') { // resultado do duelo ranqueado: a nota antes e depois
      rankedResult = msg;
      Telemetry.track('ranked_result', props: {'place': msg['place'], 'delta': msg['delta']});
      notifyListeners();
      if (_accountToken != null) unawaited(refreshRanked());
      return;
    }
    if (t == 'state') {
      passPrompt = null;
      rankedMode = msg['ranked'] as String?;
      _markPlayed();
      _hostLastHeardMs = DateTime.now().millisecondsSinceEpoch;
      hostLag = false;
      screen = AppScreen.game;
      final sView = msg['s'] as Map<String, dynamic>;
      me = (msg['you'] as num?)?.toInt() ?? -1;
      turnLimitMs = msg['limit'] is num ? (msg['limit'] as num).toInt() : null;
      var leftMs = msg['left'] is num ? (msg['left'] as num).toInt() : null;
      final cm = msg['commit'] as String? ?? '';
      matchCommit = cm.isEmpty ? null : cm;
      _announceKey(link);
      final rp = msg['replay'] as String? ?? '';
      matchReplayId = rp.isEmpty ? null : rp;
      if (msg['async'] == true && msg['deadline'] is num) {
        // correspondência: 24 h por jogada, contadas no servidor
        turnLimitMs = corrTurnMs;
        leftMs = max(0, (msg['deadline'] as num).toInt() - DateTime.now().millisecondsSinceEpoch);
      }
      if (leftMs != null) {
        turnDeadlineMs = DateTime.now().millisecondsSinceEpoch + leftMs;
        _ensureClockRunning();
      } else {
        turnDeadlineMs = 0;
      }
      lobbyCode = msg['code'] as String? ?? lobbyCode;
      lobbyOwner = msg['owner'] == true;
      watchersCount = msg['watchers'] is num ? (msg['watchers'] as num).toInt() : null;
      playerCrests = [for (final x in (msg['crests'] as List<dynamic>? ?? const [])) x is String ? x : ''];
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
    if (t == 'emote') {
      final p = msg['p'], e = msg['e'];
      if (p is num && e is num && p.toInt() != me) _pushEmote(p.toInt(), e.toInt());
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
    if (activeChallenge != null) {
      unawaited(startDailyChallenge(overrideSpec: activeChallenge));
      return;
    }
    if (online != null && lobbyOwner && guestLink != null) {
      guestLink!.send({'t': 'again'});
    } else if (role != 'guest') {
      beginGame();
    }
  }

  // ---------------- Host State Sync + Bot + Turn Clock ----------------

  void _syncHost() {
    if (_engineId == null) return;
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
    final roomCode = relayCode ?? lanHostAddr;
    final onlineMapMsg = {for (final e in onlineByTurn.entries) '${e.key}': e.value};
    watchersCount = relayCode != null ? _relayWatchers.length : null;
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
          'on': onlineMapMsg,
          'code': ?roomCode,
          if (relayCode != null) 'watchers': _relayWatchers.length,
        });
      }
    }
    for (final w in _relayWatchers) {
      if (w.isOpen) {
        final wv = engine.viewFor(id, -1);
        w.send({
          't': 'state',
          's': wv,
          'you': -1,
          'watch': true,
          'left': ?leftMs,
          if (turnSecs > 0) 'limit': turnSecs * 1000,
          'on': onlineMapMsg,
          'code': ?relayCode,
          'watchers': _relayWatchers.length,
        });
      }
    }

    // Save host/local game (`save3`)
    if (!inTutorial && activeChallenge == null) {
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
    _evaluateActiveChallenge(hostView);
    _publishRelayRoomInfo();
    if (!challengeWon && !challengeLost) {
      _scheduleHostBot(hostView);
    }
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
      clockTick.value++;
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
      trenchMode = false;
      pendingTrenchTerr = null;
      airliftMode = false;
      airliftFrom = null;
      airliftTo = null;
    } else {
      if (v['step'] != 'reinforce') {
        nukeMode = false;
        trenchMode = false;
        pendingTrenchTerr = null;
        airliftMode = false;
        airliftFrom = null;
        airliftTo = null;
      }
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
      defColor: defP != null ? _playerColor((defP['color'] as num).toInt()) : const Color(0xFFE8ECF1),
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
            showFlash('Rodada 2', const Color(0xFFF2EEE6),
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
              const Color(0xFFF2EEE6),
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
          if (la > 0) floats.add(MapFloatText(terr: from, text: '−$la', color: const Color(0xFFFF6B5E), startMs: now));
          if (ld > 0) floats.add(MapFloatText(terr: to, text: '−$ld', color: const Color(0xFFFF6B5E), startMs: now));
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
            const Color(0xFFFF6B5E),
            ms: 1000,
            big: mine(p),
            top: !mine(p),
          );
          SoundPlayer.play('timeout');
        case 'win':
          SoundPlayer.play('win');
          WebEnv.vibrate(300);
          if (inTutorial && !_tutorialCompletedSent) {
            _tutorialCompletedSent = true;
            Telemetry.track('tutorial_completed', mode: 'tutorial', immediate: true);
          } else if (!inTutorial && activeChallenge == null && !_matchEndSent) {
            _matchEndSent = true;
            final dur = _matchStartedMs > 0
                ? max(1, (DateTime.now().millisecondsSinceEpoch - _matchStartedMs) ~/ 1000)
                : 0;
            Telemetry.track(
              'match_ended',
              mode: _activeTelemetryMode(),
              rounds: (v['round'] as num?)?.toInt(),
              durationSec: dur,
              outcome: 'finished',
              immediate: true,
            );
          }
        case 'nuke':
          final p = (e['p'] as num).toInt();
          final def = (e['def'] as num).toInt();
          final to = (e['to'] as num).toInt();
          final lost = (e['lost'] as num).toInt();
          _startNukeCinema(to, p);
          _spotlight({to}, impactMs + 2600);
          showFlash(
            'Alerta nuclear!',
            const Color(0xFFFF6B5E),
            sub: '${nm(p)} lançou uma ogiva contra ${mapData.territories[to].name} (${nm(def)})',
            ms: impactMs,
            big: true,
            top: true,
          );
          Timer(const Duration(milliseconds: impactMs + 400), () {
            if (view == null) return;
            showFlash(
              '${mapData.territories[to].name} atingido',
              const Color(0xFFC8FF3E),
              sub: '−$lost exércitos · radioativo até a vez de ${nm(p)} voltar',
              ms: 2600,
              big: true,
              top: true,
            );
          });
        case 'challenge': // regra do desafio que o motor aplicou (doutrina, evento fixo)
          final k = e['k'] as String? ?? '';
          final spec = activeChallenge;
          if (k == 'blitz_medals') {
            showFlash('Doutrina de Choque · +1 medalha', const Color(0xFFF2EEE6),
                sub: 'Conquista com ataque máximo (3 dados)', ms: 1300, top: true);
          } else if (k == 'continental_fervor') {
            showFlash('Logística de Fronteira', const Color(0xFFF2EEE6),
                sub: '+${(e['bonus'] as num?)?.toInt() ?? 2} exércitos bônus por novo continente dominado', ms: 1700, top: true);
          }
          if (spec != null && k.isNotEmpty) {
            Telemetry.track('mechanic_triggered', date: spec.date, challengeId: spec.id, mode: spec.kind, props: {
              'key': k.startsWith('event:') ? k : 'doctrine:$k',
              if (e['bonus'] != null) 'bonus': e['bonus'],
              if (e['round'] != null) 'round': e['round'],
            });
          }
        case 'fogEnd':
          final to = (e['to'] as num).toInt();
          showFlash('A névoa sobre ${mapData.territories[to].name} se dissipou', const Color(0xFFC8FF3E), ms: 1100, top: true);
        case 'pactVoid':
          final a = (e['a'] as num).toInt();
          final b = (e['b'] as num).toInt();
          if (mine(a) || mine(b)) {
            showFlash('Pacto encerrado', const Color(0xFFF2EEE6),
                sub: '${nm(a)} e ${nm(b)} · acabou com a ogiva', ms: 1500, top: true);
          }
        case 'eventEnd':
          final k = e['k'] as String? ?? '';
          showFlash('${eventTitles[k] ?? k} terminou', const Color(0xFFF2EEE6), ms: 1000, top: true);
        case 'event':
          final k = e['k'] as String? ?? '';
          showFlash(eventTitles[k] ?? k, const Color(0xFFF2EEE6), sub: eval?.eventText ?? '', ms: 2400, big: true);
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
            showFlash('Pacto encerrado', const Color(0xFFF2EEE6),
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
    if (airliftMode) {
      if (airliftFrom != null && airliftTo != null) {
        final armies = (terrs[airliftFrom!]['a'] as num).toInt();
        final maxSend = armies - 1;
        return maxSend >= 1 ? (1, maxSend) : null;
      }
      return null;
    }
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
    final key = airliftMode
        ? 'airlift:$airliftFrom:$airliftTo'
        : '${v['step']}:${occ != null ? 'o${occ['to']}' : ''}:$sel:$target';
    if (occ != null && rng == null) {
      stepValue = (occ['min'] as num?)?.toInt() ?? 0;
    } else if (rng != null) {
      if (key != _stepKey) {
        stepValue = occ != null
            ? rng.$1
            : (airliftMode || v['step'] == 'attack' ? rng.$2 : 1);
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
      final commit = matchCommit;
      final key = devicePub;
      if (online != null && !online!.lan && commit != null && key != null) {
        // jogada assinada pela chave deste aparelho, com um contador que só cresce (sobrevive a recarregar a página)
        final q = max(_lastQ + 1, DateTime.now().microsecondsSinceEpoch);
        _lastQ = q;
        try {
          final sig = engine.callJson('signAction', {'commit': commit, 'n': q, 'a': jsonEncode(action)})['sig'] as String;
          guestLink?.send({'t': 'act', 'a': action, 'q': q, 'g': sig});
          return;
        } catch (_) {}
      }
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
      final actT = action['t'] as String?;
      if (actT == 'order') {
        final k = action['k'] as String? ?? '';
        Telemetry.track(
          'hq_order_used',
          date: activeChallenge?.date,
          challengeId: activeChallenge?.id,
          mode: _activeTelemetryMode(),
          props: {'order': k},
        );
      } else if (actT == 'mobilize') {
        Telemetry.track(
          'hq_order_used',
          date: activeChallenge?.date,
          challengeId: activeChallenge?.id,
          mode: _activeTelemetryMode(),
          props: {'order': 'mobilize'},
        );
      } else if (actT == 'nuke') {
        Telemetry.track(
          'hq_order_used',
          date: activeChallenge?.date,
          challengeId: activeChallenge?.id,
          mode: _activeTelemetryMode(),
          props: {'order': 'nuke'},
        );
      }
      _syncHost();
    }
  }

  /// Dá para mandar recado: partida com outra pessoa do outro lado (online, correspondência, rede de casa ou relay).
  @visibleForTesting
  bool debugCanEmote = false; // telas de teste: mostra o botão sem precisar de outra pessoa conectada

  @visibleForTesting
  void debugPushEmote(int p, int e, {bool mine = false}) => _pushEmote(p, e, mine: mine);

  bool get canEmote {
    final v = view;
    if (debugCanEmote && v != null) return true;
    if (v == null || replay != null || activeChallenge != null || tutorialGuide != null) return false;
    if (role == 'guest') return me >= 0 && guestLink != null && guestLink!.isOpen;
    return _engineId != null &&
        (seats.any((s) => s.link != null && s.link!.isOpen) || _relayWatchers.any((w) => w.isOpen));
  }

  /// Quanto falta (ms) para poder mandar outro recado.
  int get emoteWaitMs => max(0, _emoteSentMs + emoteGapMs - DateTime.now().millisecondsSinceEpoch);

  int _playerOfSeat(int seat) {
    final players = view?['players'] as List<dynamic>? ?? const [];
    for (var p = 0; p < players.length; p++) {
      if ((players[p]['seat'] as num?)?.toInt() == seat) return p;
    }
    return -1;
  }

  void sendEmote(int e) {
    if (e < 0 || e >= emoteTexts.length || !canEmote || emoteWaitMs > 0) return;
    _emoteSentMs = DateTime.now().millisecondsSinceEpoch;
    if (role == 'guest') {
      guestLink?.send({'t': 'emote', 'e': e});
      _pushEmote(me, e, mine: true);
    } else {
      final p = _playerOfSeat(0);
      if (p < 0) return;
      _relayEmote({'t': 'emote', 'p': p, 'e': e}, null);
      _pushEmote(p, e, mine: true);
    }
    Timer(const Duration(milliseconds: emoteGapMs), notifyListeners); // libera os recados de novo no painel
    Telemetry.track('emote_sent', mode: _activeTelemetryMode(), props: {'e': e});
  }

  void setEmotesMuted(bool on) {
    emotesMuted = on;
    AppStorage.instance.setString(_kEmotesMuted, on ? '1' : '0');
    if (on) emotes.removeWhere((b) => !b.mine);
    notifyListeners();
  }

  void _relayEmote(Map<String, dynamic> msg, GameLink? from) {
    for (final s in seats) {
      if (s.link != null && s.link!.isOpen && s.link != from) s.link!.send(msg);
    }
    for (final w in _relayWatchers) {
      if (w.isOpen) w.send(msg);
    }
  }

  void _pushEmote(int p, int e, {bool mine = false}) {
    final players = view?['players'] as List<dynamic>? ?? const [];
    if (p < 0 || p >= players.length || e < 0 || e >= emoteTexts.length) return;
    if (emotesMuted && !mine) return;
    final b = EmoteBubble(++_emoteSeq, p, e, mine);
    emotes.removeWhere((x) => x.player == p); // um balão por jogador: o novo substitui o anterior
    emotes.add(b);
    while (emotes.length > 3) {
      emotes.removeAt(0);
    }
    Timer(const Duration(milliseconds: 4200), () {
      if (emotes.remove(b)) notifyListeners();
    });
    notifyListeners();
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
      for (final w in _relayWatchers) {
        if (w.isOpen) w.send(msg);
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

    // Trench targeting mode
    if (trenchMode) {
      final hq = ev.hq;
      final blk = hq?.trenchBlocks[t];
      if (owner != turnIdx) {
        showToast('Escolha um território seu para proteger com a Trincheira.');
        notifyListeners();
        return;
      }
      if (blk != null && blk.isNotEmpty) {
        showToast(blk, 3600);
        notifyListeners();
        return;
      }
      if (pendingTrenchTerr == t) {
        confirmTrench();
      } else {
        pendingTrenchTerr = t;
        notifyListeners();
      }
      return;
    }

    // Airlift targeting mode
    if (airliftMode) {
      final hq = ev.hq;
      if (airliftFrom == null) {
        if (owner != turnIdx) {
          showToast('Escolha um território seu de origem (2 ou mais exércitos).');
          notifyListeners();
          return;
        }
        final blk = hq?.airliftBlocks[t];
        if (blk != null && blk.isNotEmpty) {
          showToast(blk, 3600);
          notifyListeners();
          return;
        }
        if (armies < 2) {
          showToast('É preciso 2 ou mais exércitos para enviar pela Ponte aérea.');
          notifyListeners();
          return;
        }
        airliftFrom = t;
        airliftTo = null;
        _reeval();
        return;
      }

      if (t == airliftFrom) {
        if (airliftTo != null) {
          changeStep(-1);
        } else {
          airliftFrom = null;
          _reeval();
        }
        return;
      }
      if (owner != turnIdx) {
        showToast('Escolha um território seu como destino (ou toque em "Trocar origem").');
        notifyListeners();
        return;
      }
      if (t == airliftTo) {
        changeStep(1);
        return;
      }
      airliftTo = t;
      _reeval();
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
    if (trenchMode) {
      if (pendingTrenchTerr != null) {
        pendingTrenchTerr = null;
        notifyListeners();
      } else {
        trenchMode = false;
        _reeval();
      }
      return;
    }
    if (airliftMode) {
      if (airliftTo != null) {
        airliftTo = null;
        _reeval();
      } else if (airliftFrom != null) {
        airliftFrom = null;
        _reeval();
      } else {
        airliftMode = false;
        _reeval();
      }
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
      trenchMode = false;
      pendingTrenchTerr = null;
      airliftMode = false;
      airliftFrom = null;
      airliftTo = null;
      sel = null;
      target = null;
    }
    _reeval();
  }

  void toggleTrenchMode(bool on) {
    trenchMode = on;
    pendingTrenchTerr = null;
    if (on) {
      nukeMode = false;
      pendingNukeTerr = null;
      airliftMode = false;
      airliftFrom = null;
      airliftTo = null;
      sel = null;
      target = null;
    }
    _reeval();
  }

  void confirmTrench() {
    final t = pendingTrenchTerr;
    if (t == null) return;
    trenchMode = false;
    pendingTrenchTerr = null;
    orderTrench(t);
  }

  void toggleAirliftMode(bool on) {
    airliftMode = on;
    airliftFrom = null;
    airliftTo = null;
    if (on) {
      nukeMode = false;
      pendingNukeTerr = null;
      trenchMode = false;
      pendingTrenchTerr = null;
      sel = null;
      target = null;
    }
    _reeval();
  }

  void clearAirliftFrom() {
    airliftFrom = null;
    airliftTo = null;
    _reeval();
  }

  void confirmAirlift() {
    final from = airliftFrom;
    final to = airliftTo;
    if (from == null || to == null) return;
    final n = stepValue;
    airliftMode = false;
    airliftFrom = null;
    airliftTo = null;
    orderAirlift(from, to, n);
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

  /// Sai da partida. Na correspondência, [keepSeat] só fecha neste aparelho (o lugar continua seu).
  void leaveGame({String? showReason, bool keepSeat = false}) {
    emotes.clear();
    _seatEmoteMs.clear();
    playerCrests = const [];
    if (replay != null) {
      _leaveReplay();
      return;
    }
    final backToRooms = online != null && online!.fromRooms && !online!.gone;
    final backToCorr = online != null && online!.corr;
    final backToDaily = activeChallenge != null;
    final backToRanked = _rankedSession || rankedMode != null;
    if (activeChallenge != null && !challengeWon && !challengeLost && _challengeStartedMs > 0) {
      final dur = max(1, (DateTime.now().millisecondsSinceEpoch - _challengeStartedMs) ~/ 1000);
      Telemetry.track(
        'challenge_finished',
        date: activeChallenge!.date,
        challengeId: activeChallenge!.id,
        mode: activeChallenge!.kind,
        difficulty: challengeDifficulty,
        outcome: 'quit',
        rounds: (view?['round'] as num?)?.toInt() ?? 1,
        durationSec: dur,
        immediate: true,
      );
    }
    _botTimer?.cancel();
    _clockTimer?.cancel();
    _autoTimer?.cancel();
    _onlineRetryTimer?.cancel();
    _roomsTimer?.cancel();

    if (online != null) {
      final link = guestLink;
      if (link != null && !online!.gone && !(keepSeat && online!.corr)) {
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
    if (backToDaily) {
      unawaited(openDailyScreen());
    } else if (backToRanked && signedIn) {
      openRankedScreen();
    } else if (backToCorr && signedIn) {
      openCorrScreen();
    } else if (backToRooms) {
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
    _replayTimer?.cancel();
    rankedMode = null;
    rankedResult = null;
    _rankedSession = false;
    final rp = replay;
    if (rp != null) {
      try {
        engine.dropGame(rp.engineId);
      } catch (_) {}
      replay = null;
    }
    matchCommit = null;
    matchReplayId = null;
    inTutorial = false;
    _tutorialCompletedSent = false;
    _matchEndSent = false;
    _matchStartedMs = 0;
    activeChallenge = null;
    challengeStatus = null;
    challengeWon = false;
    challengeLost = false;
    challengeEndReason = '';
    challengeStarsEarned = 0;
    challengeServerRank = null;
    challengeNeedsAccount = false;
    challengeSubmitRanking = [];
    challengeResultSubmitted = false;
    _challengeRunId = null;
    _challengeStartedMs = 0;
    _challengeRecorded = false;
    _botTimer?.cancel();
    _clockTimer?.cancel();
    _autoTimer?.cancel();
    _onlineRetryTimer?.cancel();
    _roomsTimer?.cancel();
    for (final l in _pendingGuestLinks.toList()) {
      l.close();
    }
    _pendingGuestLinks.clear();
    _relayRetryTimer?.cancel();
    _relayRetryTimer = null;
    final rl = _relayLink;
    _relayLink = null;
    if (rl != null) {
      if (rl.isOpen) {
        rl.send({'t': 'rEnd', 'm_reason': 'O anfitrião encerrou a sala.'});
      }
      rl.close();
    }
    relayStarting = false;
    relayWaitMsg = '';
    relayCode = null;
    _relaySecret = null;
    for (final w in _relayWatchers.toList()) {
      w.markClosed();
    }
    _relayWatchers.clear();
    for (final p in _relayPeers.values) {
      p.markClosed();
    }
    _relayPeers.clear();
    final srv = _lanServer;
    _lanServer = null;
    if (srv != null) {
      unawaited(srv.close());
    }
    lanStarting = false;
    for (final s in seats) {
      _dropSeatSpare(s);
      s.link?.close();
    }
    guestLink?.close();
    guestLink = null;
    online = null;
    passPrompt = null;
    _pendingRoomPass = null;
    lobbyPass = '';
    lobbyHasPass = false;
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
    trenchMode = false;
    pendingTrenchTerr = null;
    airliftMode = false;
    airliftFrom = null;
    airliftTo = null;
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
    lobbyQuick = false;
    lobbyQuickDeadlineMs = 0;
    turnDeadlineMs = 0;
  }

  Color _playerColor(int idx) {
    final cols = engine.constants.colors;
    if (idx < 0 || idx >= cols.length) return const Color(0xFF9AA4B2);
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
    _corrTimer?.cancel();
    _friendsTimer?.cancel();
    _resetSessionState();
    clockTick.dispose();
    smoke.dispose();
    super.dispose();
  }
}

class _RelayPeerLink extends GameLink {
  _RelayPeerLink(this.id, this.watch, this._owner);

  final int id;
  final bool watch;
  final AppController _owner;
  bool _open = true;

  @override
  bool get isOpen => _open && _owner.isRelayConnected;

  @override
  void send(Map<String, dynamic> msg) {
    if (!isOpen) return;
    _owner._sendRelayOut(id, msg);
  }

  @override
  void close() {
    if (!_open) return;
    _open = false;
    _owner._closeRelayPeer(id);
  }

  void markClosed() {
    _open = false;
  }
}
