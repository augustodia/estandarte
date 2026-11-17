import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../game/daily_challenge.dart';
import '../game/fx_models.dart';
import 'account_sheet.dart';
import 'map_view.dart';
import 'modals.dart';
import 'quartel_modal.dart';
import 'theme.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  VoidCallback? _fitZoom;
  void Function(double factor)? _zoomBy;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _stageKey = GlobalKey();

  BuildContext get _stageCtx => _stageKey.currentContext ?? context;

  @override
  void initState() {
    super.initState();
    widget.ctrl.onOfferForMe = _handleIncomingOffer;
  }

  @override
  void dispose() {
    if (widget.ctrl.onOfferForMe == _handleIncomingOffer) {
      widget.ctrl.onOfferForMe = null;
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _handleIncomingOffer(Map<String, dynamic> v) {
    if (!mounted) return;
    showOfferModal(_stageCtx, widget.ctrl);
  }

  void _triggerPrimaryAction() {
    final c = widget.ctrl;
    final v = c.view;
    if (v == null) return;
    if (c.passDevicePlayer != null) {
      c.dismissPassDevice();
      return;
    }
    if (c.confirmEndKind != null) {
      c.confirmEndPhase();
      return;
    }
    if (c.pendingNukeTerr != null) {
      c.confirmNukeLaunch(c.pendingNukeTerr!);
      return;
    }
    if (!c.canPlayNow()) return;
    if (v['occupy'] != null) {
      c.confirmOccupy();
      return;
    }
    final step = v['step'] as String;
    if (step == 'reinforce') {
      if (c.trenchMode) {
        if (c.pendingTrenchTerr != null) c.confirmTrench();
      } else if (c.airliftMode) {
        if (c.airliftFrom != null && c.airliftTo != null) c.confirmAirlift();
      } else if (c.sel != null) {
        c.placeReinforce();
      } else if (c.eval?.bestTrade != null) {
        c.autoTrade();
      }
    } else if (step == 'attack') {
      if (c.sel != null && c.target != null) {
        c.attack();
      } else {
        c.requestEndAttack();
      }
    } else if (step == 'move') {
      if (c.sel != null && c.target != null) {
        c.moveTroops();
      } else {
        c.requestEndTurn();
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final c = widget.ctrl;

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _triggerPrimaryAction();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowRight) {
      c.changeStep(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft) {
      c.changeStep(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (c.confirmEndKind != null) {
        c.cancelConfirmEnd();
      } else if (c.pendingNukeTerr != null) {
        c.cancelPendingNuke();
      } else {
        c.clearSelection();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _fitZoom?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyO) {
      showObjectiveModal(_stageCtx, c);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      showCardsModal(_stageCtx, c);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      showMenuModal(_stageCtx, c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final layout = EstLayout.of(context, inGame: true, forceLand: c.forceLand);
    final v = c.view;

    Widget mapArea() {
      final evt = v?['event'] as Map<String, dynamic>?;
      final showEvt = evt != null && v?['phase'] == 'play';
      final ringLeft = layout.wide ? 20.0 : 16.0;
      final ringBottom = layout.wide ? 18.0 : (layout.land ? 12.0 : 10.0);
      final ringSize = layout.wide ? 76.0 : (layout.land ? 54.0 : 60.0);
      final fitLeft = layout.wide ? 42.0 : (layout.land ? 27.0 : 30.0);
      final fitBottom = layout.wide ? 104.0 : (layout.land ? 72.0 : 78.0);
      final evLeft = layout.wide ? 16.0 : (layout.land ? 10.0 : 84.0);
      final evBottom = layout.land ? 12.0 : 16.0;

      String evtLabel = '';
      if (showEvt) {
        final k = evt['k'] as String? ?? '';
        final base = eventTitles[k] ?? k;
        final contIdx = (evt['c'] as num?)?.toInt();
        evtLabel = contIdx != null && contIdx < c.mapData.continents.length
            ? '$base · ${c.mapData.continents[contIdx].name}'
            : base;
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          WorldMapView(
            ctrl: c,
            bottomReserve: layout.wide ? 96.0 : (layout.land ? 60.0 : 0.0),
            onControllerReady: (fitFn) => _fitZoom = fitFn,
            onZoomControllerReady: (zoomFn) => _zoomBy = zoomFn,
          ),

          // #ring: Floating bottom-left turn order + countdown timer button (tap -> menu)
          if (v != null && v['phase'] == 'play')
            Positioned(
              left: ringLeft,
              bottom: ringBottom,
              child: _TurnRingButton(
                ctrl: c,
                size: ringSize,
                onTap: () => showMenuModal(_stageCtx, c),
              ),
            ),

          // #fit / zoom strip above #ring
          Positioned(
            left: fitLeft,
            bottom: fitBottom,
            child: layout.land
                ? EstIconButton(
                    icon: EstIconKind.fit,
                    size: 32,
                    iconSize: 15,
                    color: AppColors.ink,
                    tooltip: 'Ajustar zoom (F)',
                    onPressed: () => _fitZoom?.call(),
                  )
                : _MapLensBar(
                    onZoomIn: () => _zoomBy?.call(1.28),
                    onFit: () => _fitZoom?.call(),
                    onZoomOut: () => _zoomBy?.call(1 / 1.28),
                  ),
          ),

          // #evchip: Floating active event pill
          if (showEvt)
            Positioned(
              left: evLeft,
              top: layout.wide
                  ? ((c.tutorialGuide != null || c.activeChallenge != null) ? 96.0 : 14.0)
                  : (layout.land ? 8.0 : null),
              bottom: layout.wide || layout.land ? null : evBottom,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: max(120, layout.size.width * 0.42),
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => showExtrasModal(context, c),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.only(left: 8, right: 11),
                      decoration: BoxDecoration(
                        color: AppColors.obsidian.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF9AA4B2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const EstIcon(EstIconKind.extras, size: 13, color: AppColors.gold),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              evtLabel,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.gold,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // celular deitado: o painel de ação flutua sobre o mapa, à direita do relógio
          if (layout.land && !layout.wide && v != null)
            Positioned(
              left: ringLeft + ringSize + 10,
              right: 10,
              bottom: 8,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 660),
                  child: _BottomActionBar(ctrl: c, layout: layout),
                ),
              ),
            ),

          // Floating Command Dock in desktop wide mode (keeps action right below the map)
          if (layout.wide && v != null)
            Positioned(
              left: 118,
              right: 16,
              bottom: 14,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: _BottomActionBar(ctrl: c, layout: layout, floatingDock: true),
                ),
              ),
            ),

          // #dice: 3D pips dice tray
          if (c.diceBanner != null)
            Positioned(
              left: 12,
              right: 12,
              top: c.diceBanner!.low
                  ? null
                  : ((c.tutorialGuide != null || c.activeChallenge != null) ? 98 : 12),
              bottom: c.diceBanner!.low ? (layout.wide ? 112 : 12) : null,
              child: Center(child: _DiceTray(banner: c.diceBanner!)),
            ),

          if (c.tutorialGuide != null)
            Positioned(
              left: layout.land ? 10 : 12,
              right: layout.land ? null : 12,
              top: layout.land ? 8 : 10,
              child: Align(
                alignment: layout.land ? Alignment.topLeft : Alignment.topCenter,
                child: _TutorialCoachBanner(
                  guide: c.tutorialGuide!,
                  onExit: c.leaveGame,
                ),
              ),
            )
          else if (c.activeChallenge != null)
            Positioned(
              left: layout.land ? 10 : 12,
              right: layout.land ? null : 12,
              top: layout.land ? 8 : 10,
              child: Align(
                alignment: layout.land ? Alignment.topLeft : Alignment.topCenter,
                child: _ChallengeHudBanner(
                  spec: c.activeChallenge!,
                  status: c.challengeStatus,
                  difficulty: c.challengeDifficulty,
                  onExit: c.leaveGame,
                ),
              ),
            ),
        ],
      );
    }

    Widget gameBody() {
      if (layout.wide) {
        final sideW = (layout.size.width * 0.25).clamp(320.0, 390.0);
        return Row(
          children: [
            Expanded(child: mapArea()),
            Container(
              width: sideW,
              decoration: const BoxDecoration(
                gradient: AppColors.wideHudGradient,
                border: Border(left: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HudPanel(ctrl: c, layout: layout),
                  Expanded(child: _SidePanel(ctrl: c, wide: true)),
                  _SidebarTelemetryFooter(ctrl: c),
                ],
              ),
            ),
          ],
        );
      }

      if (layout.tall) {
        return Column(
          children: [
            _HudPanel(ctrl: c, layout: layout),
            Expanded(flex: 62, child: mapArea()),
            SizedBox(
              height: min(210.0, layout.size.height * 0.24),
              child: _SidePanel(ctrl: c, wide: false),
            ),
            _BottomActionBar(ctrl: c, layout: layout),
          ],
        );
      }

      if (layout.land) {
        return Column(
          children: [
            _TopBar(ctrl: c),
            Expanded(child: mapArea()),
          ],
        );
      }

      // Mobile portrait when forceLand == false
      return Column(
        children: [
          _HudPanel(ctrl: c, layout: layout),
          Expanded(child: mapArea()),
          _BottomActionBar(ctrl: c, layout: layout),
        ],
      );
    }

    Widget stage = Scaffold(
      key: _stageKey,
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              gameBody(),

              // #flash banner
              if (c.flashBanner != null) _FlashOverlay(banner: c.flashBanner!, land: layout.land),

              // #toast at top
              if (c.toastMessage != null)
                Positioned(
                  top: layout.land ? 10 : (layout.big ? 18 : 62),
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.obsidian.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.brass),
                          boxShadow: AppColors.edgeShadows,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const EstIcon(EstIconKind.compass, size: 14, color: AppColors.gold),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                c.toastMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Local pass-device curtain
              if (c.passDevicePlayer != null && v != null)
                _PassDeviceOverlay(ctrl: c, playerIdx: c.passDevicePlayer!),

              // Pending nuke confirmation modal
              if (c.pendingNukeTerr != null)
                _ConfirmNukeOverlay(ctrl: c, terrIdx: c.pendingNukeTerr!),

              // Confirm end attack / end turn modal
              if (c.confirmEndKind != null)
                _ConfirmEndOverlay(ctrl: c, kind: c.confirmEndKind!),

              // Victory / Challenge outcome overlay (#win)
              if (v != null &&
                  (v['phase'] == 'over' || c.challengeWon || c.challengeLost) &&
                  !c.victoryDismissed)
                _VictoryOverlay(ctrl: c, land: layout.land),
            ],
          ),
        ),
      ),
    );

    return EstRotatedStage(
      rotated: layout.rot,
      watch: c,
      resolveRotated: (rootCtx) {
        final raw = MediaQuery.sizeOf(rootCtx);
        final rawMin = min(raw.width, raw.height);
        return raw.height > raw.width && rawMin < 600 && c.forceLand;
      },
      child: stage,
    );
  }
}

// ---------- HUD (#hud) ----------

class _HudPanel extends StatelessWidget {
  const _HudPanel({required this.ctrl, required this.layout});

  final AppController ctrl;
  final EstLayout layout;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view;
    if (v == null) return const SizedBox(height: 52);
    final players = v['players'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final cur = players[turnIdx] as Map<String, dynamic>;
    final colors = ctrl.engine.constants.colors;
    final curCol = parseHexColor(colors[(cur['color'] as num).toInt()].hex);
    final round = (v['round'] as num).toInt();
    final step = v['step'] as String? ?? 'reinforce';
    final meP = (ctrl.me >= 0 && ctrl.me < players.length)
        ? players[ctrl.me] as Map<String, dynamic>
        : null;
    final opts = v['opts'] as Map<String, dynamic>? ?? const {};
    final extras = opts['events'] == true || opts['pacts'] == true || opts['nukes'] == true || (opts['hq'] == true && opts['spy'] == true);
    final pactsCount = opts['pacts'] == true ? (v['pacts'] as List<dynamic>? ?? const []).length : 0;
    final offer = v['offer'] as Map<String, dynamic>?;
    final offerIsMine = offer != null &&
        (ctrl.role == 'guest'
            ? (offer['to'] as num).toInt() == ctrl.me
            : players[(offer['to'] as num).toInt()]['ctrl'] == 'local');
    final rawCards = meP?['cards'];
    final hqOn = opts['hq'] == true;
    final handSize = hqOn
        ? ((meP?['medals'] as num?)?.toInt() ?? 0)
        : rawCards is List
            ? rawCards.length
            : (rawCards is num ? rawCards.toInt() : 0);
    final handLabel = hqOn ? 'Quartel' : 'Cartas';
    final phaseLabel = v['phase'] == 'over' ? 'Fim de jogo' : '${stepLabels[step] ?? step} · rodada ${round + 1}';

    Widget dot(double sz) => EstFactionSeal(color: curCol, size: sz - 5, highlighted: true);

    Widget iconBtn({
      required EstIconKind kind,
      required String label,
      required String tooltip,
      required VoidCallback onTap,
      String? badge,
      bool callPulse = false,
      bool expanded = false,
    }) {
      final btn = Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Ink(
              height: layout.wide ? 50 : (layout.land ? 36 : 38),
              padding: EdgeInsets.symmetric(horizontal: layout.wide ? 6 : (layout.land ? 6 : 8)),
              decoration: BoxDecoration(
                color: callPulse ? AppColors.panel2 : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: callPulse ? AppColors.gold : const Color(0xFF3A4452)),
              ),
              child: layout.wide
                  ? Stack(
                      children: [
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                EstIcon(
                                  kind,
                                  size: 17,
                                  color: callPulse ? AppColors.gold : AppColors.ink,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.mute,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (badge != null)
                          Positioned(
                            top: 4,
                            right: 6,
                            child: Text(
                              badge,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold,
                                height: 1.0,
                              ),
                            ),
                          ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EstIcon(
                          kind,
                          size: 18,
                          color: callPulse ? AppColors.gold : AppColors.ink,
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            badge,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      );
      return expanded ? Expanded(child: btn) : btn;
    }

    if (layout.wide) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: const BoxDecoration(
          gradient: AppColors.wideHudGradient,
          border: Border(bottom: BorderSide(color: Color(0x337D8796))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                dot(22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cur['name'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: AppText.serif(size: 20, letterSpacing: 0.03),
                      ),
                      Text(
                        phaseLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.mute),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (meP != null) ...[
                  iconBtn(
                    kind: EstIconKind.goal,
                    label: 'Objetivo',
                    tooltip: 'Objetivo (O)',
                    expanded: true,
                    onTap: () => showObjectiveModal(context, ctrl),
                  ),
                  const SizedBox(width: 8),
                  iconBtn(
                    kind: hqOn ? EstIconKind.medal : EstIconKind.cards,
                    label: handLabel,
                    tooltip: '$handLabel (C)',
                    badge: '$handSize',
                    expanded: true,
                    onTap: () => showCardsModal(context, ctrl),
                  ),
                ] else
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2029),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF7D8796)),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.visibility_outlined, size: 15, color: Color(0xFFE8ECF1)),
                          SizedBox(width: 6),
                          Text(
                            'Assistindo',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE8ECF1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (extras) ...[
                  const SizedBox(width: 8),
                  iconBtn(
                    kind: EstIconKind.extras,
                    label: 'Extras',
                    tooltip: 'Regras extras',
                    badge: pactsCount > 0 ? '$pactsCount' : null,
                    callPulse: offerIsMine,
                    expanded: true,
                    onTap: () => showExtrasModal(context, ctrl),
                  ),
                ],
                const SizedBox(width: 8),
                iconBtn(
                  kind: EstIconKind.menu,
                  label: 'Menu',
                  tooltip: 'Menu (M)',
                  expanded: true,
                  onTap: () => showMenuModal(context, ctrl),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: layout.land
          ? const EdgeInsets.fromLTRB(12, 6, 8, 8)
          : EdgeInsets.symmetric(horizontal: layout.big ? 16 : 10, vertical: layout.big ? 12 : 6),
      decoration: BoxDecoration(
        gradient: layout.land ? null : AppColors.hudGradient,
        border: layout.land
            ? const Border(right: BorderSide(color: Color(0xFF7D8796)))
            : const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        mainAxisSize: layout.land ? MainAxisSize.min : MainAxisSize.max,
        children: [
          dot(18),
          const SizedBox(width: 8),
          if (layout.land)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${cur['name'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  Text(
                    phaseLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.2),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${cur['name'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  Text(
                    phaseLabel,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.mute, height: 1.2),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 6),
          if (meP != null) ...[
            iconBtn(
              kind: EstIconKind.goal,
              label: 'Objetivo',
              tooltip: 'Objetivo (O)',
              onTap: () => showObjectiveModal(context, ctrl),
            ),
            const SizedBox(width: 6),
            iconBtn(
              kind: hqOn ? EstIconKind.medal : EstIconKind.cards,
              label: handLabel,
              tooltip: '$handLabel (C)',
              badge: '$handSize',
              onTap: () => showCardsModal(context, ctrl),
            ),
          ] else
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2029),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF7D8796)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.visibility_outlined, size: 14, color: Color(0xFFE8ECF1)),
                  SizedBox(width: 5),
                  Text(
                    'Assistindo',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFE8ECF1)),
                  ),
                ],
              ),
            ),
          if (extras) ...[
            const SizedBox(width: 6),
            iconBtn(
              kind: EstIconKind.extras,
              label: 'Extras',
              tooltip: 'Regras extras',
              badge: pactsCount > 0 ? '$pactsCount' : null,
              callPulse: offerIsMine,
              onTap: () => showExtrasModal(context, ctrl),
            ),
          ],
          const SizedBox(width: 6),
          iconBtn(
            kind: EstIconKind.menu,
            label: 'Menu',
            tooltip: 'Menu (M)',
            onTap: () => showMenuModal(context, ctrl),
          ),
        ],
      ),
    );
  }
}

// ---------- Barra superior (celular deitado) ----------

/// Rodada e de quem é a vez à esquerda, etapas do turno no centro, atalhos à direita. Altura fixa de 40.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.ctrl});

  final AppController ctrl;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view;
    if (v == null) return const SizedBox(height: 40);
    final players = v['players'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final cur = players[turnIdx] as Map<String, dynamic>;
    final colors = ctrl.engine.constants.colors;
    final curCol = parseHexColor(colors[(cur['color'] as num).toInt()].hex);
    final round = (v['round'] as num).toInt();
    final step = v['step'] as String? ?? 'reinforce';
    final playing = v['phase'] == 'play';
    final mine = ctrl.canPlayNow();
    final meP = (ctrl.me >= 0 && ctrl.me < players.length) ? players[ctrl.me] as Map<String, dynamic> : null;
    final opts = v['opts'] as Map<String, dynamic>? ?? const {};
    final hqOn = opts['hq'] == true;
    final extras = opts['events'] == true ||
        opts['pacts'] == true ||
        opts['nukes'] == true ||
        (hqOn && opts['spy'] == true);
    final pactsCount = opts['pacts'] == true ? (v['pacts'] as List<dynamic>? ?? const []).length : 0;
    final offer = v['offer'] as Map<String, dynamic>?;
    final offerIsMine = offer != null &&
        (ctrl.role == 'guest'
            ? (offer['to'] as num).toInt() == ctrl.me
            : players[(offer['to'] as num).toInt()]['ctrl'] == 'local');
    final rawCards = meP?['cards'];
    final hand = hqOn
        ? ((meP?['medals'] as num?)?.toInt() ?? 0)
        : rawCards is List
            ? rawCards.length
            : (rawCards is num ? rawCards.toInt() : 0);

    Widget btn(EstIconKind icon, String tip, VoidCallback onTap, {String? badge, bool call = false}) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: tip,
            child: Material(
              color: call ? AppColors.panel2 : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Container(
                  height: 30,
                  constraints: const BoxConstraints(minWidth: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: call ? AppColors.ink : AppColors.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      EstIcon(icon, size: 16, color: call ? AppColors.ink : AppColors.mute),
                      if (badge != null) ...[
                        const SizedBox(width: 4),
                        Text(badge, style: AppText.number(size: 15, weight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    final who = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('R${round + 1}', style: AppText.label(size: 13, color: AppColors.faint)),
        Container(width: 1, height: 14, margin: const EdgeInsets.symmetric(horizontal: 9), color: AppColors.glassBorder),
        EstFactionSeal(color: curCol, size: 12),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            !playing ? 'FIM DE JOGO' : (mine ? 'SUA VEZ' : '${cur['name'] ?? ''}'.toUpperCase()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label(size: 15, color: AppColors.ink, weight: FontWeight.w700),
          ),
        ),
      ],
    );

    Widget steps() {
      String? special;
      if (ctrl.nukeMode) special = 'OGIVA · ESCOLHA O ALVO';
      if (ctrl.trenchMode) special = 'TRINCHEIRA · ESCOLHA O TERRITÓRIO';
      if (ctrl.airliftMode) special = 'PONTE AÉREA';
      if (v['occupy'] != null) special = 'AVANÇO DE TROPAS';
      if (special != null) {
        return Text(
          special,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.label(size: 13, color: ctrl.nukeMode ? AppColors.rad : AppColors.ink, weight: FontWeight.w700),
        );
      }
      const order = ['reinforce', 'attack', 'move'];
      const names = ['Reforço', 'Ataque', 'Manobra'];
      final at = order.indexOf(step);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < order.length; i++)
            Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: i == at ? AppColors.action : Colors.transparent, width: 2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i < at) ...[
                    const Icon(Icons.check_rounded, size: 13, color: AppColors.faint),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    names[i].toUpperCase(),
                    style: AppText.label(size: 13, color: i == at ? AppColors.ink : AppColors.faint),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.deep,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: who)),
          if (playing) steps(),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (meP != null) ...[
                  btn(EstIconKind.goal, 'Objetivo (O)', () => showObjectiveModal(context, ctrl)),
                  btn(
                    hqOn ? EstIconKind.medal : EstIconKind.cards,
                    hqOn ? 'Quartel (C)' : 'Cartas (C)',
                    () => showCardsModal(context, ctrl),
                    badge: '$hand',
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('ASSISTINDO', style: AppText.label(size: 12, color: AppColors.mute)),
                  ),
                if (extras)
                  btn(
                    EstIconKind.extras,
                    'Regras extras',
                    () => showExtrasModal(context, ctrl),
                    badge: pactsCount > 0 ? '$pactsCount' : null,
                    call: offerIsMine,
                  ),
                btn(EstIconKind.menu, 'Menu (M)', () => showMenuModal(context, ctrl)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Side Panel (#side) for Wide & Tall ----------

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.ctrl, required this.wide});

  final AppController ctrl;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view;
    if (v == null) return const SizedBox.shrink();
    final players = v['players'] as List<dynamic>;
    final terrs = v['terr'] as List<dynamic>;
    final colors = ctrl.engine.constants.colors;
    final turnIdx = (v['turn'] as num).toInt();
    final pacts = (v['opts']?['pacts'] == true) ? (v['pacts'] as List<dynamic>? ?? const []) : const [];
    final localHumans = players.where((p) => p['ctrl'] == 'local').length;
    final log = (v['log'] as List<dynamic>? ?? const []).reversed.take(40).toList();
    final totalTerr = max(1, ctrl.mapData.territories.length);

    Widget sectionHeader(String left, [String? right]) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
          child: EstSectionTag(
            left,
            trailing: right != null
                ? Text(
                    right.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.mute,
                    ),
                  )
                : null,
          ),
        );

    Widget playerRow(int i) {
      final p = players[i] as Map<String, dynamic>;
      final col = parseHexColor(colors[(p['color'] as num).toInt()].hex);
      var owned = 0;
      for (final t in terrs) {
        if ((t['o'] as num).toInt() == i) owned++;
      }
      final pct = (owned / totalTerr).clamp(0.0, 1.0);
      final cards = p['cards'] is List ? (p['cards'] as List).length : (p['cards'] as num? ?? 0).toInt();
      final seatIdx = (p['seat'] as num?)?.toInt() ?? i;
      final seat = ctrl.role != 'guest' && seatIdx < ctrl.seats.length ? ctrl.seats[seatIdx] : null;
      final off = p['alive'] == true &&
          p['ctrl'] == 'remote' &&
          (ctrl.role != 'guest'
              ? (seat == null || seat.link == null || seat.lag)
              : (ctrl.onlMap.isNotEmpty && ctrl.onlMap[i] != true));
      Map<String, dynamic>? pact;
      for (final x in pacts) {
        final xm = x as Map<String, dynamic>;
        if ((xm['a'] as num).toInt() == i || (xm['b'] as num).toInt() == i) {
          pact = xm;
          break;
        }
      }
      final pactOtherName = pact != null
          ? '${players[(pact['a'] as num).toInt() == i ? (pact['b'] as num).toInt() : (pact['a'] as num).toInt()]['name']}'
          : null;
      final isMe = ctrl.role == 'guest'
          ? i == ctrl.me
          : (p['ctrl'] == 'local' && localHumans == 1);
      final isNow = i == turnIdx && v['phase'] == 'play';
      final isWon = v['phase'] == 'over' && i == (v['winner'] as num?)?.toInt();
      final dead = p['alive'] != true;

      final tags = [
        if (dead) 'eliminado',
        if (!dead && p['ctrl'] == 'bot') 'bot',
        if (!dead) '$owned terr.',
        if (!dead && !ctrl.hqOn) '$cards carta${cards == 1 ? '' : 's'}',
        if (p['sabotaged'] == true) 'sabotado',
        if (pactOtherName != null) 'pacto: $pactOtherName',
      ].join(' · ');

      return Opacity(
        opacity: dead ? 0.42 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 5),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isNow ? AppColors.panel2 : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isWon
                  ? AppColors.gold
                  : (isNow ? AppColors.glassBorder : AppColors.line),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(
                      height: 2,
                      color: col,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(10, wide ? 8 : 7, 11, wide ? 10 : 9),
                child: Row(
                  children: [
                    EstFactionSeal(color: col, size: 12, highlighted: isNow),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${p['name'] ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    decoration: dead ? TextDecoration.lineThrough : null,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0x28F2EEE6),
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(color: AppColors.brassDim),
                                  ),
                                  child: const Text(
                                    'VOCÊ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color: AppColors.gold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(fontSize: 11, color: AppColors.mute),
                              children: [
                                TextSpan(text: tags),
                                if (off)
                                  const TextSpan(
                                    text: ' · offline',
                                    style: TextStyle(color: AppColors.bad),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (!dead && ctrl.hqOn) ...[
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EstMedalBadge(earned: ctrl.medalsOf(i) > 0, size: 15),
                          const SizedBox(width: 2),
                          Text(
                            '${ctrl.medalsOf(i)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: ctrl.medalsOf(i) > 0 ? AppColors.gold : AppColors.mute,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${(100 * owned / totalTerr).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget logList() => ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.82, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 10),
            itemCount: log.length,
            itemBuilder: (_, k) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: k == 0 ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5) : EdgeInsets.zero,
              decoration: k == 0
                  ? BoxDecoration(
                      color: AppColors.obsidian.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF3A4452)),
                    )
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (k == 0) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 7),
                      child: Transform.rotate(
                        angle: pi / 4,
                        child: Container(width: 4.5, height: 4.5, color: AppColors.brass),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      '${log[k]}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.38,
                        fontWeight: k == 0 ? FontWeight.w600 : FontWeight.w400,
                        color: k == 0 ? AppColors.ink : AppColors.mute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    final playersHeader =
        'Forças em campo${(ctrl.watchersCount ?? 0) > 0 ? ' · ${ctrl.watchersCount} assistindo' : ''}';

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionHeader(playersHeader, 'domínio'),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: EstLayout.of(context).size.height * 0.44),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: players.length,
                itemBuilder: (_, i) => playerRow(i),
              ),
            ),
            sectionHeader('Crônica'),
            Expanded(child: logList()),
          ],
        ),
      );
    }

    // Tall (tablet portrait): 2 columns below map
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.wideHudGradient,
        border: Border(top: BorderSide(color: Color(0xFF7D8796))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 115,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                sectionHeader(playersHeader, 'domínio'),
                Expanded(
                  child: ListView.builder(
                    itemCount: players.length,
                    itemBuilder: (_, i) => playerRow(i),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                sectionHeader('Registro'),
                Expanded(child: logList()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Floating Turn Order + Clock Ring (#ring) ----------

class _TurnRingButton extends StatelessWidget {
  const _TurnRingButton({
    required this.ctrl,
    required this.size,
    required this.onTap,
  });

  final AppController ctrl;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view!;
    final players = v['players'] as List<dynamic>;
    final terrs = v['terr'] as List<dynamic>;
    final turnIdx = (v['turn'] as num).toInt();
    final colors = ctrl.engine.constants.colors;
    final totalTerr = max(1, ctrl.mapData.territories.length);

    final slices = <(Color, int)>[];
    for (var k = 0; k < players.length; k++) {
      final i = (turnIdx + k) % players.length;
      if (players[i]['alive'] == true) {
        var owned = 0;
        for (final t in terrs) {
          if ((t['o'] as num).toInt() == i) owned++;
        }
        slices.add((parseHexColor(colors[(players[i]['color'] as num).toInt()].hex), owned));
      }
    }

    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: ctrl.clockTick,
        builder: (context, _, _) {
          final hasClock = ctrl.turnDeadlineMs > 0 && (ctrl.turnLimitMs ?? 0) > 0;
          double clockFrac = 0;
          int secsLeft = 0;
          bool low = false;
          String topText;
          String subText;

          if (hasClock) {
            final left = ctrl.turnDeadlineMs - DateTime.now().millisecondsSinceEpoch;
            secsLeft = max(0, (left / 1000).ceil());
            clockFrac = (left / ctrl.turnLimitMs!).clamp(0.0, 1.0);
            low = secsLeft <= 10;
            topText = secsLeft >= 60
                ? '${secsLeft ~/ 60}:${(secsLeft % 60).toString().padLeft(2, '0')}'
                : '$secsLeft';
            subText = secsLeft >= 60 ? '' : 'seg';
          } else {
            topText = '${slices.isNotEmpty ? slices.first.$2 : 0}';
            subText = 'terr';
          }

          return Tooltip(
            message: 'Ordem dos turnos e relógio · Abrir mesa (M)',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: CustomPaint(
                    painter: _TurnRingPainter(
                      slices: slices,
                      totalTerr: totalTerr,
                      clockFrac: clockFrac,
                      low: low,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            topText,
                            style: AppText.number(
                              size: (size * 0.27).clamp(13.0, 21.0),
                              weight: FontWeight.w700,
                              color: low ? AppColors.bad : AppColors.ink,
                            ).copyWith(height: 1.0),
                          ),
                          if (subText.isNotEmpty)
                            Text(
                              subText.toUpperCase(),
                              style: AppText.label(size: (size * 0.15).clamp(8.0, 10.0), color: AppColors.faint)
                                  .copyWith(height: 1.0, letterSpacing: 0.4),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TurnRingPainter extends CustomPainter {
  const _TurnRingPainter({
    required this.slices,
    required this.totalTerr,
    required this.clockFrac,
    required this.low,
  });

  final List<(Color, int)> slices;
  final int totalTerr;
  final double clockFrac;
  final bool low;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100.0;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s, s);

    // Disc
    canvas.drawCircle(Offset.zero, 50, Paint()..color = AppColors.panel);
    canvas.drawCircle(
      Offset.zero,
      49.5,
      Paint()
        ..color = AppColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Outer clock track (r=45, width=4)
    canvas.drawCircle(
      Offset.zero,
      45,
      Paint()
        ..color = AppColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    if (clockFrac > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: 45),
        -pi / 2,
        2 * pi * clockFrac,
        false,
        Paint()
          ..color = low ? AppColors.bad : AppColors.action
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..strokeWidth = 4,
      );
    }

    // Inner player order slices (r=31, width=10)
    if (slices.isNotEmpty) {
      const c = 2 * pi * 31;
      final gap = slices.length > 1 ? 2.5 : 0.0;
      final lens = slices.map((e) => max(8.0, (e.$2 / totalTerr) * c)).toList();
      final sum = lens.fold<double>(0, (a, b) => a + b);
      final norm = lens.map((l) => (l * c) / sum).toList();
      double off = -pi / 2;
      for (var k = 0; k < slices.length; k++) {
        final sweepAll = (norm[k] / c) * 2 * pi;
        final sweepDraw = max(0.02, ((norm[k] - gap) / c) * 2 * pi);
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: 31),
          off,
          sweepDraw,
          false,
          Paint()
            ..color = slices[k].$1
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6,
        );
        off += sweepAll;
      }

      // Pointer triangle at midpoint of current player's slice
      final midDeg = (((norm[0] - gap) / 2 / c) * 360.0);
      canvas.save();
      canvas.rotate(midDeg * pi / 180.0);
      canvas.drawPath(
        Path()
          ..moveTo(-4, -42)
          ..lineTo(4, -42)
          ..lineTo(0, -36)
          ..close(),
        Paint()..color = AppColors.ink,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TurnRingPainter old) {
    if (old.clockFrac != clockFrac ||
        old.low != low ||
        old.totalTerr != totalTerr ||
        old.slices.length != slices.length) {
      return true;
    }
    for (var i = 0; i < slices.length; i++) {
      if (old.slices[i] != slices[i]) return true;
    }
    return false;
  }
}

// ---------- Dice Roll Banner (#dice) ----------

class _DiceTray extends StatelessWidget {
  const _DiceTray({required this.banner});

  final DiceBannerState banner;

  @override
  Widget build(BuildContext context) {
    final att = banner.att;
    final def = banner.def;
    final pairs = min(att.length, def.length);
    var attLost = 0;
    var defLost = 0;
    for (var i = 0; i < pairs; i++) {
      if (att[i] > def[i]) {
        defLost++;
      } else {
        attLost++;
      }
    }

    Widget sideRow(
      List<int> vals,
      String name,
      Color color,
      int lost,
      bool Function(int i) isLost,
    ) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 101,
            child: Row(
              children: [
                for (var i = 0; i < vals.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  DieFace(
                    value: vals[i],
                    color: color,
                    size: 30,
                    lost: i < pairs && isLost(i),
                    won: i < pairs && !isLost(i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text(
              lost > 0 ? '−$lost' : '✓',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: lost > 0 ? const Color(0xFFFF6B5E) : const Color(0xFFE8ECF1),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppColors.glassGradient,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppColors.edgeShadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          sideRow(att, banner.attName, banner.attColor, attLost, (i) => att[i] <= def[i]),
          const SizedBox(height: 5),
          sideRow(def, banner.defName, banner.defColor, defLost, (i) => att[i] > def[i]),
        ],
      ),
    );
  }
}

// ---------- Flash Overlay (#flash & #flash.mini) ----------

class _FlashOverlay extends StatelessWidget {
  const _FlashOverlay({required this.banner, required this.land});

  final FlashBannerState banner;
  final bool land;

  @override
  Widget build(BuildContext context) {
    final isMini = banner.top;
    return IgnorePointer(
      child: Align(
        alignment: isMini
            ? Alignment.topCenter
            : (land ? const Alignment(0, -0.16) : const Alignment(0, -0.20)),
        child: Padding(
          padding: EdgeInsets.only(top: isMini ? (land ? 58.0 : 104.0) : 0, left: 20, right: 20),
          // aviso neutro com uma faixa na cor de quem age: a cor informa, o painel não grita
          child: Container(
            constraints: BoxConstraints(maxWidth: isMini ? 420 : 340),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: AppColors.edgeShadows,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 3, color: banner.color),
                Padding(
                  padding: isMini
                      ? const EdgeInsets.fromLTRB(14, 5, 14, 6)
                      : EdgeInsets.fromLTRB(20, land ? 8 : 10, 20, land ? 10 : 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isMini ? banner.title : banner.title.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: isMini
                            ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)
                            : AppText.label(size: land ? 20 : 24, color: AppColors.ink, weight: FontWeight.w700),
                      ),
                      if (banner.sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          banner.sub,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, height: 1.3, color: AppColors.mute),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarTelemetryFooter extends StatelessWidget {
  const _SidebarTelemetryFooter({required this.ctrl});
  final AppController ctrl;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view;
    final ev = ctrl.eval;
    if (v == null || ev == null) return const SizedBox.shrink();

    final players = v['players'] as List<dynamic>;
    final terrs = v['terr'] as List<dynamic>;
    final colors = ctrl.engine.constants.colors;
    final meP = (ctrl.me >= 0 && ctrl.me < players.length)
        ? players[ctrl.me] as Map<String, dynamic>
        : null;
    final meColor = meP != null
        ? parseHexColor(colors[(meP['color'] as num).toInt()].hex)
        : AppColors.mute;

    final activeInfoTerr = ctrl.hoverInfoTerr ?? ctrl.infoTerr;
    final infoSpans = <InlineSpan>[];
    if (activeInfoTerr != null) {
      final t = activeInfoTerr;
      final tr = ctrl.mapData.territories[t];
      final cont = ctrl.mapData.continents[tr.continent];
      final ownerIdx = (terrs[t]['o'] as num).toInt();
      final ownerName = '${players[ownerIdx]['name'] ?? ''}';
      final armies = (terrs[t]['a'] as num).toInt();
      final isFog = v['fog'] != null && (v['fog']['t'] as num).toInt() == t;
      infoSpans.add(TextSpan(
        text: tr.name,
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
      ));
      infoSpans.add(TextSpan(text: ' · ${cont.name} · $ownerName · $armies exérc.'));
      if (isFog) {
        infoSpans.add(const TextSpan(
          text: ' · radioativo',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.rad),
        ));
      }
      if (ctrl.trenchOwner(t) != null) {
        infoSpans.add(const TextSpan(
          text: ' · entrincheirado',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
        ));
      }
    } else if (v['event'] != null && v['phase'] == 'play') {
      final k = v['event']['k'];
      infoSpans.add(TextSpan(
        text: '${eventTitles[k] ?? k}',
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
      ));
      infoSpans.add(TextSpan(text: ' · ${ev.eventText}'));
    } else {
      infoSpans.add(const TextSpan(text: 'Passe o cursor sobre um território para ver detalhes.'));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.obsidian,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, height: 1.3, color: AppColors.mute),
              children: infoSpans,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          _YouChip(meP: meP, meColor: meColor, watchers: ctrl.watchersCount ?? 0),
        ],
      ),
    );
  }
}

class _PhaseTrack extends StatelessWidget {
  const _PhaseTrack({
    required this.step,
    required this.occupy,
    required this.nukeMode,
    required this.trenchMode,
    required this.airliftMode,
    required this.accent,
  });

  final String step;
  final bool occupy;
  final bool nukeMode;
  final bool trenchMode;
  final bool airliftMode;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (nukeMode || trenchMode || airliftMode) {
      final (icon, title, col) = nukeMode
          ? (EstIconKind.nuke, 'ORDEM TÁTICA · OGIVA NUCLEAR', AppColors.rad)
          : trenchMode
              ? (EstIconKind.shield, 'ORDEM TÁTICA · TRINCHEIRA', AppColors.gold)
              : (EstIconKind.airlift, 'ORDEM TÁTICA · PONTE AÉREA', AppColors.gold);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EstIcon(icon, size: 13, color: col),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: col,
            ),
          ),
        ],
      );
    }

    if (occupy) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          EstIcon(EstIconKind.sword, size: 13, color: AppColors.gold),
          SizedBox(width: 6),
          Text(
            'TERRITÓRIO CONQUISTADO · AVANÇO DE TROPAS',
            textHeightBehavior: TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              height: 1.15,
              color: AppColors.gold,
            ),
          ),
        ],
      );
    }

    const stages = [
      ('reinforce', '1. Reforço', EstIconKind.troop),
      ('attack', '2. Ataque', EstIconKind.sword),
      ('move', '3. Remanejar', EstIconKind.move),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < stages.length; i++) ...[
              if (i > 0) Container(width: 1, color: AppColors.line),
              Builder(
                builder: (_) {
                  final active = step == stages[i].$1;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? accent.withValues(alpha: 0.24) : Colors.transparent,
                      border: active
                          ? Border(bottom: BorderSide(color: accent, width: 1.8))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EstIcon(
                          stages[i].$3,
                          size: 11,
                          color: active ? AppColors.ink : AppColors.mute.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          stages[i].$2.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                            letterSpacing: 0.8,
                            color: active ? AppColors.ink : AppColors.mute.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------- Bottom Bar / Floating Command Dock (#bar) ----------

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.ctrl,
    required this.layout,
    this.floatingDock = false,
  });

  final AppController ctrl;
  final EstLayout layout;
  final bool floatingDock;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view;
    final ev = ctrl.eval;
    if (v == null || ev == null) return const SizedBox.shrink();

    final players = v['players'] as List<dynamic>;
    final terrs = v['terr'] as List<dynamic>;
    final colors = ctrl.engine.constants.colors;
    final turnIdx = (v['turn'] as num).toInt();
    final cur = players[turnIdx] as Map<String, dynamic>;
    final curCol = parseHexColor(colors[(cur['color'] as num).toInt()].hex);
    final can = ctrl.canPlayNow();
    final rng = ctrl.stepRange();
    final meP = (ctrl.me >= 0 && ctrl.me < players.length)
        ? players[ctrl.me] as Map<String, dynamic>
        : null;
    final opts = v['opts'] as Map<String, dynamic>? ?? const {};

    // Footer .info line (hover territory > tapped info territory > event > last log)
    final activeInfoTerr = ctrl.hoverInfoTerr ?? ctrl.infoTerr;
    final infoSpans = <InlineSpan>[];
    if (activeInfoTerr != null) {
      final t = activeInfoTerr;
      final tr = ctrl.mapData.territories[t];
      final cont = ctrl.mapData.continents[tr.continent];
      final ownerIdx = (terrs[t]['o'] as num).toInt();
      final ownerName = '${players[ownerIdx]['name'] ?? ''}';
      final armies = (terrs[t]['a'] as num).toInt();
      final isFog = v['fog'] != null && (v['fog']['t'] as num).toInt() == t;
      infoSpans.add(TextSpan(text: '${tr.name} · ${cont.name} · $ownerName · $armies exérc.'));
      if (isFog) {
        infoSpans.add(
          const TextSpan(
            text: ' · radioativo: não pode ser atacado',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.rad),
          ),
        );
      }
      if (ctrl.trenchOwner(t) != null) {
        infoSpans.add(
          const TextSpan(
            text: ' · entrincheirado: não pode ser atacado',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
          ),
        );
      }
    } else if (v['event'] != null && v['phase'] == 'play') {
      final k = v['event']['k'];
      infoSpans.add(
        TextSpan(
          text: '${eventTitles[k] ?? k}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
        ),
      );
      infoSpans.add(TextSpan(text: ' · ${ev.eventText}'));
    } else {
      final log = v['log'] as List<dynamic>? ?? const [];
      if (log.isNotEmpty) infoSpans.add(TextSpan(text: '${log.last}'));
    }

    final msgSpans = <InlineSpan>[];
    final btns = <Widget>[];
    final btnHeight = layout.wide ? 44.0 : 40.0;

    Widget actionBtn(
      String label,
      VoidCallback onTap, {
      EstButtonVariant variant = EstButtonVariant.normal,
      bool expand = true,
    }) {
      final b = EstButton(
        small: true,
        height: btnHeight,
        label: label,
        variant: variant,
        onPressed: onTap,
      );
      return expand && !layout.land ? Expanded(child: b) : b;
    }

    if (v['phase'] == 'over') {
      final wIdx = (v['winner'] as num).toInt();
      final w = players[wIdx] as Map<String, dynamic>;
      final wCol = parseHexColor(colors[(w['color'] as num).toInt()].hex);
      final objTxt = ev.objectiveTexts[wIdx] ?? '';
      msgSpans.add(TextSpan(text: '${w['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: wCol)));
      msgSpans.add(TextSpan(text: ' venceu! $objTxt'));
      if (ctrl.role != 'guest' || ctrl.lobbyOwner) {
        btns.add(actionBtn('Nova partida', ctrl.requestPlayAgainOnline, variant: EstButtonVariant.primary));
      }
    } else if (!can) {
      if (ctrl.role == 'guest' && ctrl.guestLink == null) {
        msgSpans.add(
          const TextSpan(
            text: 'Sem conexão. ',
            style: TextStyle(color: AppColors.bad, fontWeight: FontWeight.w700),
          ),
        );
        msgSpans.add(
          TextSpan(
            text: ctrl.online != null
                ? 'Reconectando ao servidor…'
                : (ctrl.autoReconnecting ? 'Tentando voltar sozinho…' : 'Peça um novo QR ao anfitrião.'),
          ),
        );
        if (ctrl.online == null) {
          btns.add(
            actionBtn(
              'Reconectar (ler QR)',
              () => showP2pJoinModal(context, ctrl),
              variant: EstButtonVariant.primary,
            ),
          );
        }
      } else {
        final pk = ctrl.peekState;
        final selIdx = pk?.sel;
        final tgtIdx = pk?.target;
        final step = v['step'] as String;
        final poolFree = (v['pool']?['free'] as num?)?.toInt() ?? 0;
        final poolCont = (v['pool']?['cont'] as Map<String, dynamic>?) ?? const {};
        final poolTot = poolFree + poolCont.values.fold<int>(0, (a, b) => a + (b as num).toInt());
        final doing = step == 'reinforce'
            ? 'está reforçando${selIdx != null ? ' ${ctrl.mapData.territories[selIdx].name}' : ''} ($poolTot a colocar)'
            : step == 'move'
                ? (selIdx != null
                    ? 'vai mover tropas de ${ctrl.mapData.territories[selIdx].name}'
                    : 'está remanejando tropas')
                : (selIdx != null && tgtIdx != null)
                    ? 'mira ${ctrl.mapData.territories[tgtIdx].name} a partir de ${ctrl.mapData.territories[selIdx].name}'
                    : (selIdx != null
                        ? 'prepara um ataque de ${ctrl.mapData.territories[selIdx].name}'
                        : 'está na fase de ataque');
        msgSpans.add(
          TextSpan(
            text: '${cur['name']}',
            style: TextStyle(fontWeight: FontWeight.w700, color: curCol),
          ),
        );
        msgSpans.add(TextSpan(text: ' $doing'));
        if (cur['ctrl'] == 'bot') {
          msgSpans.add(const TextSpan(text: ' (bot)'));
        } else if (ctrl.onlMap.isNotEmpty && cur['ctrl'] == 'remote' && ctrl.onlMap[turnIdx] != true) {
          msgSpans.add(
            const TextSpan(
              text: ' (desconectado)',
              style: TextStyle(color: AppColors.bad),
            ),
          );
        }
      }
    } else if (v['step'] == 'reinforce') {
      final pool = v['pool'] as Map<String, dynamic>;
      final free = (pool['free'] as num).toInt();
      final contMap = pool['cont'] as Map<String, dynamic>? ?? const {};
      final extra = contMap.entries
          .map((e) => '+${e.value} em ${ctrl.mapData.continents[int.parse(e.key)].name}')
          .join(', ');
      final canNuke = !ctrl.nukeMode && ev.nukeTrade != null && ev.nukeBlock.isEmpty;

      final inOrderMode = ctrl.nukeMode || ctrl.trenchMode || ctrl.airliftMode;

      if (ctrl.nukeMode) {
        msgSpans.add(
          const TextSpan(
            text: 'Ogiva: ',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.rad),
          ),
        );
        msgSpans.add(
          TextSpan(
            text:
                'toque no território inimigo que será o alvo. Destrói ${ev.nukeDamage} exércitos dele (sempre sobra 1) e ninguém, nem você, poderá atacá-lo nesta rodada. ${ctrl.hqOn ? 'Custa 4 medalhas.' : 'Você recebe ${ev.nukeRefund} em vez dos ${ev.tradeValue} da troca.'}',
          ),
        );
        btns.add(actionBtn('Cancelar', () => ctrl.toggleNukeMode(false)));
      } else if (ctrl.trenchMode) {
        msgSpans.add(
          const TextSpan(
            text: 'Trincheira: ',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
          ),
        );
        if (ctrl.pendingTrenchTerr == null) {
          msgSpans.add(
            const TextSpan(
              text:
                  'toque em um território seu no mapa para protegê-lo contra ataques até seu próximo turno (2 medalhas).',
            ),
          );
        } else {
          final tName = ctrl.mapData.territories[ctrl.pendingTrenchTerr!].name;
          msgSpans.add(const TextSpan(text: 'proteger '));
          msgSpans.add(
            TextSpan(
              text: tName,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          );
          msgSpans.add(const TextSpan(text: '? Toque de novo no mapa ou confirme abaixo.'));
          btns.add(
            actionBtn(
              'Proteger $tName',
              ctrl.confirmTrench,
              variant: EstButtonVariant.primary,
            ),
          );
        }
        btns.add(actionBtn('Cancelar', () => ctrl.toggleTrenchMode(false), variant: EstButtonVariant.ghost));
      } else if (ctrl.airliftMode) {
        msgSpans.add(
          const TextSpan(
            text: 'Ponte aérea: ',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
          ),
        );
        if (ctrl.airliftFrom == null) {
          msgSpans.add(
            const TextSpan(
              text: 'toque no território seu de onde sairão os exércitos (2+ exércitos · 2 medalhas).',
            ),
          );
        } else if (ctrl.airliftTo == null) {
          final fromName = ctrl.mapData.territories[ctrl.airliftFrom!].name;
          final fromArmies = (terrs[ctrl.airliftFrom!]['a'] as num).toInt();
          msgSpans.add(const TextSpan(text: 'saindo de '));
          msgSpans.add(
            TextSpan(
              text: '$fromName ($fromArmies)',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          );
          msgSpans.add(const TextSpan(text: ' · toque em qualquer outro território seu de destino.'));
          btns.add(actionBtn('Trocar origem', ctrl.clearAirliftFrom));
        } else {
          final fromName = ctrl.mapData.territories[ctrl.airliftFrom!].name;
          final toName = ctrl.mapData.territories[ctrl.airliftTo!].name;
          msgSpans.add(
            TextSpan(
              text: '$fromName → $toName',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
          );
          msgSpans.add(const TextSpan(text: ' · toque no destino para somar, na origem para tirar'));
          if (rng != null) {
            btns.add(_StepperWidget(ctrl: ctrl, range: rng, height: btnHeight));
            btns.add(actionBtn('Máx', () {
              ctrl.stepValue = rng.$2;
              ctrl.confirmAirlift();
            }));
            btns.add(
              actionBtn(
                'Enviar ${ctrl.stepValue}',
                ctrl.confirmAirlift,
                variant: EstButtonVariant.primary,
              ),
            );
          }
          btns.add(actionBtn('Trocar origem', ctrl.clearAirliftFrom));
        }
        btns.add(actionBtn('Cancelar', () => ctrl.toggleAirliftMode(false), variant: EstButtonVariant.ghost));
      } else if (ev.mustTrade) {
        msgSpans.add(
          TextSpan(
            text: canNuke
                ? 'Você tem 5 ou mais cartas: troque ou lance a ogiva antes de reforçar.'
                : 'Você tem 5 ou mais cartas: troque antes de reforçar.',
          ),
        );
      } else if (rng != null) {
        final selCont = ctrl.mapData.territories[ctrl.sel!].continent;
        final contBonusHere = (contMap['$selCont'] as num?)?.toInt() ?? 0;
        msgSpans.add(const TextSpan(text: 'Reforçar '));
        msgSpans.add(
          TextSpan(
            text: ctrl.mapData.territories[ctrl.sel!].name,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
        );
        if (free == 0 && contBonusHere > 0) {
          msgSpans.add(
            TextSpan(
              text:
                  ' · Bônus obrigatório de ${ctrl.mapData.continents[selCont].name} (+$contBonusHere ${contBonusHere == 1 ? 'exército' : 'exércitos'})',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
            ),
          );
        } else {
          msgSpans.add(
            TextSpan(
              text: ' · $free livre${free == 1 ? '' : 's'}${extra.isNotEmpty ? ' ($extra)' : ''}',
            ),
          );
        }
      } else if (free == 0 && contMap.isNotEmpty) {
        final obList = contMap.entries
            .where((e) => (e.value as num).toInt() > 0)
            .map((e) => '+${e.value} na ${ctrl.mapData.continents[int.parse(e.key)].name}')
            .join(' e ');
        msgSpans.add(
          const TextSpan(
            text: 'Bônus de continente obrigatório: ',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
          ),
        );
        msgSpans.add(
          TextSpan(
            text: 'coloque $obList (toque num território iluminado desse continente).',
          ),
        );
      } else {
        msgSpans.add(
          TextSpan(
            text:
                'Toque num território seu para reforçar (toque duplo coloca 1) · $free livre${free == 1 ? '' : 's'}${extra.isNotEmpty ? ' ($extra)' : ''}',
          ),
        );
      }

      if (!inOrderMode) {
        if (rng != null) {
          btns.add(_StepperWidget(ctrl: ctrl, range: rng, height: btnHeight));
          btns.add(actionBtn('Máx', ctrl.setMaxReinforce));
          btns.add(actionBtn('Colocar', ctrl.placeReinforce, variant: EstButtonVariant.primary));
        }
        if (ev.bestTrade != null) {
          btns.add(
            actionBtn(
              'Trocar +${ev.tradeValue}',
              ctrl.autoTrade,
              variant: rng == null ? EstButtonVariant.primary : EstButtonVariant.normal,
            ),
          );
        }
        final hq = ev.hq;
        if (hq != null && hq.mobilizeBlock.isEmpty) {
          btns.add(
            actionBtn(
              'Mobilizar +${hq.effort}',
              ctrl.mobilize,
              variant: rng == null ? EstButtonVariant.primary : EstButtonVariant.normal,
            ),
          );
        }
        if (hq != null && hq.orders.any((o) => o.block.isEmpty)) {
          btns.add(actionBtn('Quartel', () => showQuartelModal(context, ctrl)));
        }
        if (canNuke) {
          btns.add(
            actionBtn(
              'Ogiva',
              () => ctrl.toggleNukeMode(true),
              variant: EstButtonVariant.rad,
            ),
          );
        }
      }
    } else if (v['occupy'] != null) {
      final from = (v['occupy']['from'] as num).toInt();
      final to = (v['occupy']['to'] as num).toInt();
      msgSpans.add(
        const TextSpan(
          text: 'Conquistou ',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
        ),
      );
      msgSpans.add(
        TextSpan(
          text: ctrl.mapData.territories[to].name,
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
      );
      msgSpans.add(
        TextSpan(
          text:
              '! 1 exército já avançou de ${ctrl.mapData.territories[from].name} · levar mais quantos?',
        ),
      );
      if (rng != null) btns.add(_StepperWidget(ctrl: ctrl, range: rng, height: btnHeight));
      btns.add(
        actionBtn(
          ctrl.stepValue == 0 ? 'Manter 1' : 'Levar +${ctrl.stepValue}',
          ctrl.confirmOccupy,
          variant: EstButtonVariant.primary,
        ),
      );
    } else if (v['step'] == 'attack') {
      if (rng != null) {
        final s = ctrl.sel!;
        final t = ctrl.target!;
        msgSpans.add(
          TextSpan(
            text:
                '${ctrl.mapData.territories[s].name} (${terrs[s]['a']}) contra ${ctrl.mapData.territories[t].name} (${terrs[t]['a']}) · toque de novo no alvo para atacar',
          ),
        );
        btns.add(
          _StepperWidget(
            ctrl: ctrl,
            range: rng,
            height: btnHeight,
            unit: ctrl.stepValue == 1 ? 'dado' : 'dados',
          ),
        );
        btns.add(actionBtn('Atacar', ctrl.attack, variant: EstButtonVariant.primary));
        btns.add(actionBtn('Auto', ctrl.blitz));
        btns.add(actionBtn('Encerrar', ctrl.requestEndAttack, variant: EstButtonVariant.ghost));
      } else {
        msgSpans.add(
          TextSpan(
            text: ctrl.sel != null
                ? 'Toque num inimigo ligado pelas linhas.'
                : 'Toque no inimigo que quer atacar (ou num território seu para escolher a origem).',
          ),
        );
        btns.add(actionBtn('Encerrar ataques', ctrl.requestEndAttack));
      }
    } else {
      // step == 'move'
      if (rng != null) {
        final s = ctrl.sel!;
        final t = ctrl.target!;
        msgSpans.add(const TextSpan(text: 'Mover de '));
        msgSpans.add(
          TextSpan(
            text: ctrl.mapData.territories[s].name,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
        );
        msgSpans.add(const TextSpan(text: ' para '));
        msgSpans.add(
          TextSpan(
            text: ctrl.mapData.territories[t].name,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
        );
        msgSpans.add(const TextSpan(text: ' · toque no destino para somar, na origem para tirar'));
        btns.add(_StepperWidget(ctrl: ctrl, range: rng, height: btnHeight));
        btns.add(actionBtn('Máx', () {
          ctrl.stepValue = rng.$2;
          ctrl.moveTroops();
        }));
        btns.add(actionBtn('Mover', ctrl.moveTroops, variant: EstButtonVariant.primary));
        btns.add(actionBtn('Encerrar', ctrl.requestEndTurn, variant: EstButtonVariant.ghost));
      } else {
        final movable = v['movable'] as Map<String, dynamic>? ?? const {};
        final leftMove = ctrl.sel != null ? ((movable['${ctrl.sel}'] as num?)?.toInt() ?? 0) : 0;
        msgSpans.add(
          TextSpan(
            text: ctrl.sel != null
                ? 'Mover de ${ctrl.mapData.territories[ctrl.sel!].name} (até $leftMove): toque no destino ligado pelas linhas.'
                : 'Remaneje: toque na origem e depois num vizinho seu.',
          ),
        );
        btns.add(actionBtn('Encerrar turno', ctrl.requestEndTurn, variant: EstButtonVariant.primary));
      }
    }

    // Pact quick button in bar when active on your turn
    final alivePlayers = players.where((p) => p['alive'] == true).length;
    if (can &&
        v['phase'] == 'play' &&
        opts['pacts'] == true &&
        !ctrl.nukeMode &&
        !ctrl.trenchMode &&
        !ctrl.airliftMode &&
        v['occupy'] == null &&
        v['step'] != 'move' &&
        alivePlayers > 2 &&
        rng == null) {
      final pactsList = (v['pacts'] as List<dynamic>? ?? const []);
      final busy = pactsList.any(
        (x) => (x['a'] as num).toInt() == turnIdx || (x['b'] as num).toInt() == turnIdx,
      );
      btns.add(
        EstButton(
          small: true,
          height: btnHeight,
          variant: EstButtonVariant.pact,
          onPressed: () => showPactsModal(context, ctrl),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EstIcon(EstIconKind.pact, size: 16, color: Color(0xFFF2EEE6)),
              const SizedBox(width: 6),
              Text(
                busy ? 'Pacto ativo' : 'Propor pacto',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF2EEE6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Host warning button when remote players are offline/lagging
    Widget? warnRow;
    if (ctrl.role != 'guest' && v['phase'] == 'play') {
      final offSeats = ctrl.seats.where((s) => s.ctrl == 'remote' && (s.link == null || s.lag)).toList();
      if (offSeats.isNotEmpty) {
        final txt = offSeats.length == 1 ? offSeats[0].name : '${offSeats.length} jogadores';
        final label =
            'Reconectar $txt (${offSeats.any((s) => s.link == null) ? 'offline' : 'sem resposta'})';
        warnRow = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: EstButton(
            small: true,
            variant: EstButtonVariant.warn,
            label: label,
            onPressed: () => showP2pInviteModal(context, ctrl),
          ),
        );
      }
    } else if (ctrl.role == 'guest' && ctrl.guestLink != null && ctrl.hostLag && ctrl.online == null) {
      warnRow = Padding(
        padding: const EdgeInsets.only(top: 6),
        child: EstButton(
          small: true,
          variant: EstButtonVariant.warn,
          label: 'Anfitrião sem resposta · reconectar',
          onPressed: () => showP2pJoinModal(context, ctrl),
        ),
      );
    }

    // Celular deitado: painel flutuante sobre o mapa. Sem botões, vira uma etiqueta curta do tamanho do texto.
    if (layout.land) {
      final quiet = btns.isEmpty && warnRow == null;
      return Container(
        constraints: BoxConstraints(minHeight: quiet ? 32 : 48),
        padding: EdgeInsets.fromLTRB(12, quiet ? 6 : 6, quiet ? 12 : 6, quiet ? 6 : 6),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.line),
          boxShadow: AppColors.edgeShadows,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: quiet ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisSize: quiet ? MainAxisSize.min : MainAxisSize.max,
              children: [
                EstFactionSeal(color: curCol, size: 10, highlighted: can),
                const SizedBox(width: 8),
                if (quiet)
                  Flexible(
                    child: Text.rich(
                      TextSpan(style: const TextStyle(fontSize: 13, height: 1.25, color: AppColors.ink), children: msgSpans),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Expanded(
                    child: Text.rich(
                      TextSpan(style: const TextStyle(fontSize: 13, height: 1.25, color: AppColors.ink), children: msgSpans),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (btns.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final b in btns)
                        if (b is Expanded) b.child else b,
                    ],
                  ),
                ],
              ],
            ),
            ?warnRow,
          ],
        ),
      );
    }

    final meColor = meP != null
        ? parseHexColor(colors[(meP['color'] as num).toInt()].hex)
        : AppColors.mute;

    if (floatingDock) {
      // Quando não é a sua vez (e partida está ativa sem aviso crítico): barra tática compacta
      if (!can && v['phase'] == 'play' && warnRow == null && btns.isEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.obsidian.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: curCol.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EstFactionSeal(color: curCol, size: 9, highlighted: true),
              const SizedBox(width: 9),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13, color: AppColors.ink),
                    children: msgSpans,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }

      return EstGlassCard(
        ornate: true,
        highlight: can,
        borderRadius: 6,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (can && v['phase'] == 'play') ...[
              _PhaseTrack(
                step: v['step'] as String? ?? 'reinforce',
                occupy: v['occupy'] != null,
                nukeMode: ctrl.nukeMode,
                trenchMode: ctrl.trenchMode,
                airliftMode: ctrl.airliftMode,
                accent: curCol,
              ),
              const SizedBox(height: 6),
            ],
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.3, color: AppColors.ink),
                children: msgSpans,
              ),
              textAlign: TextAlign.center,
            ),
            if (btns.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final b in btns)
                    if (b is Expanded) b.child else b,
                ],
              ),
            ],
            ?warnRow,
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        layout.wide ? 16 : 12,
        layout.wide ? 12 : 8,
        layout.wide ? 16 : 12,
        layout.wide ? 12 : 10,
      ),
      decoration: BoxDecoration(
        gradient: layout.wide ? AppColors.wideHudGradient : AppColors.hudGradient,
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (can && v['phase'] == 'play') ...[
            Center(
              child: _PhaseTrack(
                step: v['step'] as String? ?? 'reinforce',
                occupy: v['occupy'] != null,
                nukeMode: ctrl.nukeMode,
                trenchMode: ctrl.trenchMode,
                airliftMode: ctrl.airliftMode,
                accent: curCol,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: layout.wide ? 14.5 : 13.5,
                height: 1.3,
                color: AppColors.ink,
              ),
              children: msgSpans,
            ),
          ),
          if (btns.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < btns.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  btns[i],
                ],
              ],
            ),
          ],
          ?warnRow,
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                    children: infoSpans,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: layout.size.width * 0.5),
                child: _YouChip(meP: meP, meColor: meColor, watchers: ctrl.watchersCount ?? 0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YouChip extends StatelessWidget {
  const _YouChip({
    required this.meP,
    required this.meColor,
    required this.watchers,
  });

  final Map<String, dynamic>? meP;
  final Color meColor;
  final int watchers;

  @override
  Widget build(BuildContext context) {
    if (meP == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_outlined, size: 13, color: AppColors.mute),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Assistindo${watchers > 1 ? ' (+${watchers - 1})' : ''}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: meColor,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x88000000)),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Você: ${meP!['name'] ?? ''}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.mute),
          ),
        ),
        if (watchers > 0) ...[
          const SizedBox(width: 6),
          const Icon(Icons.visibility_outlined, size: 12, color: AppColors.mute),
          const SizedBox(width: 3),
          Text('$watchers', style: const TextStyle(fontSize: 12, color: AppColors.mute)),
        ],
      ],
    );
  }
}

class _StepperWidget extends StatelessWidget {
  const _StepperWidget({
    required this.ctrl,
    required this.range,
    this.unit,
    this.height = 40,
  });

  final AppController ctrl;
  final (int, int) range;
  final String? unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final canMinus = ctrl.stepValue > range.$1;
    final canPlus = ctrl.stepValue < range.$2;
    final cellSize = height - 2;

    Widget stepBtn({
      required EstIconKind icon,
      required bool enabled,
      required VoidCallback onTap,
    }) =>
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.30,
              child: SizedBox(
                width: cellSize,
                height: cellSize,
                child: Center(
                  child: EstIcon(icon, size: 16, color: AppColors.ink),
                ),
              ),
            ),
          ),
        );

    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.deep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stepBtn(
            icon: EstIconKind.minus,
            enabled: canMinus,
            onTap: () => ctrl.changeStep(-1),
          ),
          Container(width: 1, height: cellSize, color: AppColors.line),
          Container(
            constraints: BoxConstraints(minWidth: unit != null ? 42 : 38),
            height: cellSize,
            color: AppColors.obsidian.withValues(alpha: 0.72),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${ctrl.stepValue}',
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    color: AppColors.ink,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit != null)
                  Text(
                    unit!,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: AppColors.mute,
                    ),
                  ),
              ],
            ),
          ),
          Container(width: 1, height: cellSize, color: AppColors.line),
          stepBtn(
            icon: EstIconKind.plus,
            enabled: canPlus,
            onTap: () => ctrl.changeStep(1),
          ),
        ],
      ),
    );
  }
}

// ---------- Inline Game Overlays (styled matching #modal .sheet) ----------

class _SheetBackdrop extends StatelessWidget {
  const _SheetBackdrop({required this.child, this.onTapOutside, this.maxWidth = 460});

  final Widget child;
  final VoidCallback? onTapOutside;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final layout = EstLayout.of(context);
    final centered = layout.big || layout.land;
    final compactLand = layout.land && !layout.big;
    return GestureDetector(
      onTap: onTapOutside,
      child: Container(
        color: const Color(0xCC0B0F14),
        alignment: centered ? Alignment.center : Alignment.bottomCenter,
        padding: centered
            ? EdgeInsets.symmetric(horizontal: compactLand ? 16 : 20, vertical: compactLand ? 10 : 20)
            : EdgeInsets.zero,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: centered ? maxWidth : 500,
              maxHeight: layout.size.height * (compactLand ? 0.92 : 0.90),
            ),
            child: EstGlassCard(
              highlight: true,
              ornate: true,
              borderRadius: centered ? 6 : 8,
              padding: EdgeInsets.all(compactLand ? 16 : 20),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _PassDeviceOverlay extends StatelessWidget {
  const _PassDeviceOverlay({required this.ctrl, required this.playerIdx});

  final AppController ctrl;
  final int playerIdx;

  @override
  Widget build(BuildContext context) {
    final players = ctrl.view!['players'] as List<dynamic>;
    final p = players[playerIdx] as Map<String, dynamic>;
    final col = parseHexColor(
      ctrl.engine.constants.colors[(p['color'] as num).toInt()].hex,
    );
    return _SheetBackdrop(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Passe o aparelho', style: AppText.serif(size: 21, color: const Color(0xFFE8ECF1))),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 15, color: AppColors.mute),
              children: [
                const TextSpan(text: 'Agora é a vez de '),
                TextSpan(
                  text: '${p['name'] ?? ''}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: col),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          EstButton(
            label: 'Estou com o aparelho',
            variant: EstButtonVariant.primary,
            onPressed: ctrl.dismissPassDevice,
          ),
        ],
      ),
    );
  }
}

class _ConfirmNukeOverlay extends StatelessWidget {
  const _ConfirmNukeOverlay({required this.ctrl, required this.terrIdx});

  final AppController ctrl;
  final int terrIdx;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view!;
    final ev = ctrl.eval!;
    final players = v['players'] as List<dynamic>;
    final d = v['terr'][terrIdx] as Map<String, dynamic>;
    final own = players[(d['o'] as num).toInt()] as Map<String, dynamic>;
    final ownCol = parseHexColor(ctrl.engine.constants.colors[(own['color'] as num).toInt()].hex);
    final name = ctrl.mapData.territories[terrIdx].name;
    final lost = ev.nukeTargetDamages[terrIdx] ?? ev.nukeDamage;
    final armies = (d['a'] as num).toInt();
    final hasPact = (v['pacts'] as List<dynamic>? ?? const []).any(
      (x) => (x['a'] as num).toInt() == ctrl.me || (x['b'] as num).toInt() == ctrl.me,
    );

    return _SheetBackdrop(
      onTapOutside: ctrl.cancelPendingNuke,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Lançar a ogiva?', style: AppText.serif(size: 21, color: AppColors.rad)),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 15, color: AppColors.ink),
              children: [
                const TextSpan(text: 'Alvo: '),
                TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ', de '),
                TextSpan(
                  text: '${own['name'] ?? ''}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ownCol),
                ),
                const TextSpan(text: '. Perde '),
                TextSpan(text: '$lost', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' de $armies exércitos.'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final b in [
            if (ctrl.hqOn)
              'Custa 4 medalhas e conta como a sua ordem tática deste turno.'
            else
              'Você entrega 3 cartas e recebe ${ev.nukeRefund} exércitos em vez dos ${ev.tradeValue} da troca.',
            '$name fica radioativo: ninguém pode atacá-lo até a sua vez voltar, nem você. O dono joga normalmente.',
            'O resto do seu turno segue normal: você reforça, ataca em outros lugares e remaneja.',
            if (hasPact) 'Seu pacto acaba.',
            if (ctrl.hqOn)
              'Antes de outra ogiva você terá de fazer uma Mobilização.'
            else
              'Sua próxima troca terá de ser normal.',
          ])
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 3),
              child: Text('• $b', style: const TextStyle(fontSize: 13, color: AppColors.ink)),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: EstButton(
                  label: 'Lançar',
                  variant: EstButtonVariant.rad,
                  onPressed: () => ctrl.confirmNukeLaunch(terrIdx),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: EstButton(label: 'Cancelar', onPressed: ctrl.cancelPendingNuke)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmEndOverlay extends StatelessWidget {
  const _ConfirmEndOverlay({required this.ctrl, required this.kind});

  final AppController ctrl;
  final int kind;

  @override
  Widget build(BuildContext context) {
    final atk = kind == 0;
    return _SheetBackdrop(
      onTapOutside: ctrl.cancelConfirmEnd,
      maxWidth: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            atk ? 'Encerrar os ataques?' : 'Encerrar o turno?',
            style: AppText.serif(size: 21, color: const Color(0xFFE8ECF1)),
          ),
          const SizedBox(height: 8),
          Text(
            atk
                ? 'Você passa para o remanejamento e não ataca mais neste turno.'
                : 'A vez passa para o próximo jogador.',
            style: const TextStyle(fontSize: 13, color: AppColors.mute),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: EstButton(
                  label: atk ? 'Encerrar ataques' : 'Encerrar turno',
                  variant: EstButtonVariant.primary,
                  onPressed: ctrl.confirmEndPhase,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EstButton(
                  label: 'Continuar jogando',
                  onPressed: ctrl.cancelConfirmEnd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- Victory Screen (#win & .wincard) ----------

class _VictoryOverlay extends StatefulWidget {
  const _VictoryOverlay({required this.ctrl, required this.land});

  final AppController ctrl;
  final bool land;

  @override
  State<_VictoryOverlay> createState() => _VictoryOverlayState();
}

class _VictoryOverlayState extends State<_VictoryOverlay> {
  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final v = c.view!;
    final players = v['players'] as List<dynamic>;
    final terrs = v['terr'] as List<dynamic>;
    final colors = c.engine.constants.colors;
    final layout = EstLayout.of(context);

    if (c.activeChallenge != null) {
      return _ChallengeOutcomeOverlay(ctrl: c, land: widget.land);
    }

    final wIdx = (v['winner'] as num).toInt();
    final w = players[wIdx] as Map<String, dynamic>;
    final wCol = parseHexColor(colors[(w['color'] as num).toInt()].hex);
    final mine = c.role == 'guest' ? wIdx == c.me : w['ctrl'] == 'local';
    final hasSeat = c.me >= 0 && c.me < players.length;
    final verdict = mine ? 'VITÓRIA' : (hasSeat ? 'DERROTA' : 'FIM DE PARTIDA');
    final objTxt = (c.eval?.objectiveTexts[wIdx] ?? '').replaceFirst(RegExp(r' Se for o seu.*$'), '');
    final round = (v['round'] as num?)?.toInt() ?? 0;

    int owned(int idx) {
      var n = 0;
      for (final t in terrs) {
        if ((t['o'] as num).toInt() == idx) n++;
      }
      return n;
    }

    final rank = List.generate(players.length, (i) => i)
      ..sort((a, b) {
        final wCmp = (b == wIdx ? 1 : 0) - (a == wIdx ? 1 : 0);
        if (wCmp != 0) return wCmp;
        return owned(b) - owned(a);
      });

    final twoCol = widget.land && !layout.big;

    final hero = Column(
      crossAxisAlignment: twoCol ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          verdict,
          style: AppText.label(
            size: 13,
            color: mine ? AppColors.action : (hasSeat ? AppColors.bad : AppColors.mute),
            weight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EstFactionSeal(color: wCol, size: twoCol ? 26 : 30),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${w['name'] ?? ''}'.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: twoCol ? 30 : 36, color: AppColors.ink, weight: FontWeight.w700)
                    .copyWith(letterSpacing: 1.0, height: 1.0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Rodada ${round + 1}',
          style: AppText.number(size: 15, color: AppColors.mute, weight: FontWeight.w600),
        ),
        if (objTxt.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            v['winBy'] == 'last' ? 'ÚLTIMO EXÉRCITO EM JOGO · O OBJETIVO ERA' : 'OBJETIVO CUMPRIDO',
            style: AppText.label(size: 11),
          ),
          const SizedBox(height: 4),
          Text(
            objTxt,
            textAlign: twoCol ? TextAlign.start : TextAlign.center,
            style: const TextStyle(fontSize: 15, height: 1.35, color: AppColors.ink),
          ),
        ],
      ],
    );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: Text('COMANDANTE', style: AppText.label(size: 11))),
            Text('TERRITÓRIOS', style: AppText.label(size: 11)),
          ],
        ),
        const SizedBox(height: 6),
        for (var k = 0; k < rank.length; k++)
          Builder(
            builder: (_) {
              final i = rank[k];
              final p = players[i] as Map<String, dynamic>;
              final col = parseHexColor(colors[(p['color'] as num).toInt()].hex);
              final isFirst = i == wIdx;
              final alive = p['alive'] == true;
              return Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isFirst ? AppColors.panel2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border(
                    top: k == 0 ? BorderSide.none : const BorderSide(color: AppColors.line),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text('${k + 1}', style: AppText.number(size: 15, color: AppColors.faint)),
                    ),
                    EstFactionSeal(color: col, size: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p['name'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isFirst ? FontWeight.w700 : FontWeight.w500,
                          color: alive || isFirst ? AppColors.ink : AppColors.faint,
                        ),
                      ),
                    ),
                    Text(
                      alive ? '${owned(i)}' : 'ELIMINADO',
                      style: alive
                          ? AppText.number(size: 17, weight: FontWeight.w700, color: isFirst ? AppColors.ink : AppColors.mute)
                          : AppText.label(size: 11),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: EstButton(label: 'Ver o mapa', onPressed: c.dismissVictory)),
            if (c.role != 'guest' || c.lobbyOwner) ...[
              const SizedBox(width: 8),
              Expanded(
                child: EstButton(
                  label: 'Nova partida',
                  variant: EstButtonVariant.primary,
                  onPressed: c.requestPlayAgainOnline,
                ),
              ),
            ],
          ],
        ),
      ],
    );

    return Container(
      color: const Color(0xF20B0F14),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(maxWidth: twoCol ? 760 : (layout.big ? 520 : 400)),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: AppColors.line),
                boxShadow: AppColors.edgeShadows,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: 4, color: wCol),
                  Padding(
                    padding: EdgeInsets.all(twoCol ? 18 : (layout.big ? 24 : 18)),
                    child: twoCol
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: hero),
                              const SizedBox(width: 24),
                              Expanded(flex: 6, child: table),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [hero, const SizedBox(height: 18), table],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Passo do tutorial. Compacto e recolhível para não cobrir o mapa; abre sozinho quando o passo muda.
class _TutorialCoachBanner extends StatefulWidget {
  const _TutorialCoachBanner({
    required this.guide,
    required this.onExit,
  });

  final ({int step, int total, String title, String body}) guide;
  final VoidCallback onExit;

  @override
  State<_TutorialCoachBanner> createState() => _TutorialCoachBannerState();
}

class _TutorialCoachBannerState extends State<_TutorialCoachBanner> {
  var _open = true;

  @override
  void didUpdateWidget(_TutorialCoachBanner old) {
    super.didUpdateWidget(old);
    if (old.guide.step != widget.guide.step) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guide;
    final compact = estCompact(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 380 : 480),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppColors.edgeShadows,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(Radii.md),
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    // progresso do tutorial em traços
                    for (var i = 1; i <= g.total; i++)
                      Container(
                        width: 10,
                        height: 3,
                        margin: const EdgeInsets.only(right: 3),
                        color: i <= g.step ? AppColors.action : AppColors.glassBorder,
                      ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        g.title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label(size: 13, color: AppColors.ink, weight: FontWeight.w700),
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.mute,
                    ),
                    TextButton(
                      onPressed: widget.onExit,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: AppColors.mute,
                      ),
                      child: Text('SAIR', style: AppText.label(size: 12, color: AppColors.mute)),
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                child: Text(
                  g.body,
                  style: TextStyle(fontSize: compact ? 13 : 15, height: 1.35, color: AppColors.ink),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChallengeHudBanner extends StatelessWidget {
  const _ChallengeHudBanner({
    required this.spec,
    required this.status,
    required this.difficulty,
    required this.onExit,
  });

  final DailyChallengeSpec spec;
  final ChallengeLiveStatus? status;
  final String difficulty;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final star2 = status?.star2Active ?? true;
    final star3 = status?.star3Active ?? true;
    final progress = status?.progressText ?? spec.goal.title;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: estCompact(context) ? 420 : 620),
      child: EstGlassCard(
        highlight: spec.isHistorical,
        ornate: false,
        borderRadius: 6,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
              decoration: const BoxDecoration(
                color: Color(0x880B0F14),
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  EstIcon(
                    spec.isHistorical ? EstIconKind.book : EstIconKind.medal,
                    size: 13,
                    color: AppColors.medal,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    spec.isHistorical ? 'QUINTA HISTÓRICA' : 'DESAFIO DO DIA',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.medal,
                    ),
                  ),
                  if (difficulty == 'marechal') ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.bad.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: AppColors.bad.withValues(alpha: 0.6)),
                      ),
                      child: const Text(
                        'MARECHAL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE8ECF1),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      spec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onExit,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'Sair',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mute),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      progress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE8ECF1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _MiniStarChip(label: '2★ ≤R${spec.goal.star2MaxRound}', ok: star2),
                  const SizedBox(width: 6),
                  _MiniStarChip(label: '3★ ${status?.star3Reason ?? 'Extra'}', ok: star3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStarChip extends StatelessWidget {
  const _MiniStarChip({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final col = ok ? AppColors.medal : const Color(0xFF7D8796);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: ok ? AppColors.medal.withValues(alpha: 0.14) : AppColors.obsidian,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ok ? const Color(0x66C9A45C) : AppColors.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: col,
          decoration: ok ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }
}

class _ChallengeOutcomeOverlay extends StatelessWidget {
  const _ChallengeOutcomeOverlay({required this.ctrl, required this.land});

  final AppController ctrl;
  final bool land;

  @override
  Widget build(BuildContext context) {
    final spec = ctrl.activeChallenge!;
    final won = ctrl.challengeWon;
    final stars = ctrl.challengeStarsEarned;
    final v = ctrl.view;
    final round = (v?['round'] as num?)?.toInt() ?? 1;
    final layout = EstLayout.of(context);
    final accent = won ? AppColors.gold : AppColors.bad;
    final rank = ctrl.challengeServerRank;
    final st = ctrl.challengeStatus;

    return Container(
      color: const Color(0xEE0B0F14),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxWidth: layout.big ? 500 : (land ? 600 : 400)),
            padding: EdgeInsets.all(layout.big ? 24 : 18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent, width: 2),
              boxShadow: AppColors.edgeShadows,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EstIcon(
                  won ? (spec.isHistorical ? EstIconKind.cup : EstIconKind.medal) : EstIconKind.shield,
                  size: 54,
                  color: accent,
                ),
                const SizedBox(height: 8),
                Text(
                  won
                      ? (spec.isHistorical ? 'CRÔNICA CONCLUÍDA' : 'DESAFIO CONCLUÍDO')
                      : 'DERROTA TÁTICA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  spec.title,
                  textAlign: TextAlign.center,
                  style: AppText.serif(size: layout.big ? 30 : 24),
                ),
                const SizedBox(height: 8),
                if (won)
                  Text(
                    '★' * stars + '☆' * (3 - stars),
                    style: const TextStyle(fontSize: 28, color: AppColors.gold, letterSpacing: 4),
                  )
                else
                  Text(
                    ctrl.challengeEndReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFE8ECF1)),
                  ),
                if (won && rank != null && rank > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.brass),
                    ),
                    child: Text(
                      '#$rank no ranking de hoje!',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                ],
                if (ctrl.challengeNeedsAccount && !ctrl.signedIn) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'O ranking é das contas: entre para o próximo resultado contar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.mute),
                  ),
                  const SizedBox(height: 6),
                  EstButton(small: true, label: 'Entrar ou criar conta', onPressed: () => showAccountSheet(context, ctrl)),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.obsidian,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Rodada $round · Baixas: ${ctrl.challengeArmiesLost} · Ordens do Quartel: ${ctrl.challengeOrdersUsed}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (won) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: AppColors.line),
                        const SizedBox(height: 6),
                        Text(
                          '1★ ${spec.goal.star1Desc}',
                          style: const TextStyle(fontSize: 12, color: AppColors.gold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '2★ ${spec.goal.star2Desc}',
                          style: TextStyle(
                            fontSize: 12,
                            color: (st?.star2Active ?? false) ? AppColors.gold : AppColors.mute,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '3★ ${spec.goal.star3Desc}',
                          style: TextStyle(
                            fontSize: 12,
                            color: (st?.star3Active ?? false) ? AppColors.gold : AppColors.mute,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (won) ...[
                  EstButton(
                    icon: EstIconKind.qr,
                    label: 'Copiar relatório tático',
                    variant: EstButtonVariant.pact,
                    onPressed: () {
                      final report = buildChallengeShareReport(
                        spec: spec,
                        stars: stars,
                        rounds: round,
                        armiesLost: ctrl.challengeArmiesLost,
                        ordersUsed: ctrl.challengeOrdersUsed,
                        difficulty: ctrl.challengeDifficulty,
                        serverRank: rank,
                      );
                      Clipboard.setData(ClipboardData(text: report));
                      ctrl.showToast('Relatório tático copiado!');
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: EstButton(label: 'Ver o mapa', onPressed: ctrl.dismissVictory),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EstButton(
                        label: won ? 'Tentar 3★' : 'Tentar de novo',
                        variant: EstButtonVariant.primary,
                        onPressed: ctrl.requestPlayAgainOnline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                EstButton(
                  label: 'Ver Ranking & Códice',
                  variant: EstButtonVariant.ghost,
                  onPressed: ctrl.leaveGame,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLensBar extends StatelessWidget {
  const _MapLensBar({
    required this.onZoomIn,
    required this.onFit,
    required this.onZoomOut,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onFit;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    Widget cell(EstIconKind kind, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 30,
              height: 29,
              child: Center(
                child: EstIcon(kind, size: 14, color: AppColors.ink),
              ),
            ),
          ),
        );

    return Material(
      color: AppColors.obsidian.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            cell(EstIconKind.plus, 'Aproximar mapa', onZoomIn),
            Container(width: 30, height: 1, color: AppColors.line),
            cell(EstIconKind.fit, 'Ajustar enquadramento (F)', onFit),
            Container(width: 30, height: 1, color: AppColors.line),
            cell(EstIconKind.minus, 'Afastar mapa', onZoomOut),
          ],
        ),
      ),
    );
  }
}
