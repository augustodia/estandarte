import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../game/fx_models.dart';
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
  final FocusNode _focusNode = FocusNode();

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
    showOfferModal(context, widget.ctrl);
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
      if (c.sel != null) {
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
      showObjectiveModal(context, c);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      showCardsModal(context, c);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      showMenuModal(context, c);
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
      final ringBottom = layout.wide ? 20.0 : (layout.land ? 12.0 : 10.0);
      final ringSize = layout.wide ? 84.0 : 68.0;
      final fitLeft = layout.wide ? 45.0 : 33.0;
      final fitBottom = layout.wide ? 118.0 : (layout.land ? 90.0 : 88.0);
      final evLeft = layout.wide ? 120.0 : 92.0;
      final evBottom = layout.wide ? 30.0 : (layout.land ? 12.0 : 16.0);

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
            onControllerReady: (fitFn) => _fitZoom = fitFn,
          ),

          // #ring: Floating bottom-left turn order + countdown timer button (tap -> menu)
          if (v != null && v['phase'] == 'play')
            Positioned(
              left: ringLeft,
              bottom: ringBottom,
              child: _TurnRingButton(
                ctrl: c,
                size: ringSize,
                onTap: () => showMenuModal(context, c),
              ),
            ),

          // #fit: Floating fit/zoom toggle button above #ring
          Positioned(
            left: fitLeft,
            bottom: fitBottom,
            child: Tooltip(
              message: 'Ajustar zoom (F)',
              child: GestureDetector(
                onTap: () => _fitZoom?.call(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xD915263D),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: AppColors.line),
                  ),
                  alignment: Alignment.center,
                  child: const EstIcon(EstIconKind.fit, size: 16),
                ),
              ),
            ),
          ),

          // #evchip: Floating active event pill right of #ring
          if (showEvt)
            Positioned(
              left: evLeft,
              bottom: evBottom,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: max(120, layout.size.width * 0.45),
                ),
                child: GestureDetector(
                  onTap: () => showExtrasModal(context, c),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.only(left: 7, right: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xD90A1422),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x99E2B04A)),
                      boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 14)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const EstIcon(EstIconKind.extras, size: 14, color: AppColors.gold),
                        const SizedBox(width: 5),
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

          // #dice: 3D pips dice tray
          if (c.diceBanner != null)
            Positioned(
              left: 12,
              right: 12,
              top: c.diceBanner!.low ? null : 10,
              bottom: c.diceBanner!.low ? 10 : null,
              child: Center(child: _DiceTray(banner: c.diceBanner!)),
            ),
        ],
      );
    }

    Widget gameBody() {
      if (layout.wide) {
        final sideW = (layout.size.width * 0.25).clamp(310.0, 390.0);
        return Row(
          children: [
            Expanded(child: mapArea()),
            Container(
              width: sideW,
              decoration: const BoxDecoration(
                gradient: AppColors.wideHudGradient,
                border: Border(left: BorderSide(color: Color(0xFF2D4A72))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HudPanel(ctrl: c, layout: layout),
                  Expanded(child: _SidePanel(ctrl: c, wide: true)),
                  _BottomActionBar(ctrl: c, layout: layout),
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
            Expanded(child: mapArea()),
            Container(
              decoration: const BoxDecoration(
                gradient: AppColors.hudGradient,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _HudPanel(ctrl: c, layout: layout),
                  Expanded(child: _BottomActionBar(ctrl: c, layout: layout)),
                ],
              ),
            ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xF00A1422),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.glassBorder),
                          boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 24)],
                        ),
                        child: Text(
                          c.toastMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
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

              // Victory overlay (#win)
              if (v != null && v['phase'] == 'over' && !c.victoryDismissed)
                _VictoryOverlay(ctrl: c, land: layout.land),
            ],
          ),
        ),
      ),
    );

    if (layout.rot) {
      stage = RotatedBox(quarterTurns: 1, child: stage);
    }
    return stage;
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
    final extras = opts['events'] == true || opts['pacts'] == true || opts['nukes'] == true;
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

    Widget dot(double sz) => Container(
          width: sz,
          height: sz,
          decoration: BoxDecoration(
            color: curCol,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x88000000), width: 2),
            boxShadow: [
              const BoxShadow(color: Color(0x88000000), spreadRadius: 2),
              BoxShadow(color: curCol.withValues(alpha: 0.7), blurRadius: 10),
            ],
          ),
        );

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
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: layout.wide ? 54 : (layout.land ? 36 : 38),
              padding: EdgeInsets.symmetric(horizontal: layout.wide ? 6 : (layout.land ? 6 : 8)),
              decoration: BoxDecoration(
                gradient: callPulse
                    ? const LinearGradient(
                        colors: [Color(0xFF4A3A14), Color(0xFF2B210B)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF14243B), Color(0xFF0B1626)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: callPulse ? AppColors.gold : AppColors.line),
                boxShadow: const [BoxShadow(color: Color(0x10FFFFFF), blurRadius: 1)],
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
          border: Border(bottom: BorderSide(color: Color(0x332D4A72))),
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
                    kind: EstIconKind.cards,
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
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFF13284A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2F5385)),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '👁 Assistindo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFA9CDFB),
                        ),
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
            ? const Border(right: BorderSide(color: Color(0xFF2D4A72)))
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
              kind: EstIconKind.cards,
              label: handLabel,
              tooltip: '$handLabel (C)',
              badge: '$handSize',
              onTap: () => showCardsModal(context, ctrl),
            ),
          ] else
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF13284A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF2F5385)),
              ),
              alignment: Alignment.center,
              child: const Text(
                '👁 Assistindo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFA9CDFB)),
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
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                left.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: AppColors.mute,
                ),
              ),
              if (right != null)
                Text(
                  right.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: AppColors.mute,
                  ),
                ),
            ],
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
        if (p['ctrl'] == 'bot') 'bot',
        '$owned terr.',
        if (ctrl.hqOn)
          '${ctrl.medalsOf(i)} medalha${ctrl.medalsOf(i) == 1 ? '' : 's'}'
        else
          '$cards carta${cards == 1 ? '' : 's'}',
        if (p['sabotaged'] == true) 'sabotado',
        if (pactOtherName != null) 'pacto com $pactOtherName',
      ].join(' · ');

      return Opacity(
        opacity: dead ? 0.45 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 5),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isNow ? null : const Color(0x800B1626),
            gradient: isNow
                ? LinearGradient(
                    colors: [
                      Color.lerp(const Color(0xFF0B1626), col, 0.24)!,
                      const Color(0xCC0B1626),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isWon
                  ? AppColors.gold
                  : (isNow ? col.withValues(alpha: 0.7) : const Color(0xFF233C5E)),
            ),
          ),
          child: Stack(
            children: [
              if (isNow)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 4, color: col),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: col,
                        boxShadow: [BoxShadow(color: col, blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, wide ? 9 : 7, 12, wide ? 12 : 10),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x88000000), width: 2),
                        boxShadow: [BoxShadow(color: col, blurRadius: 10)],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${dead ? '☠ ' : ''}${p['name'] ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                const Text(
                                  'VOCÊ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.6,
                                    color: AppColors.gold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(fontSize: 12, color: AppColors.mute),
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
                    const SizedBox(width: 8),
                    Text(
                      '${(100 * owned / totalTerr).round()}%',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
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
            stops: [0.0, 0.80, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 10),
            itemCount: log.length,
            itemBuilder: (_, k) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '${log[k]}',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: k == 0 ? AppColors.ink : AppColors.mute,
                ),
              ),
            ),
          ),
        );

    final playersHeader =
        'Jogadores${(ctrl.watchersCount ?? 0) > 0 ? ' · 👁 ${ctrl.watchersCount} assistindo' : ''}';

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionHeader(playersHeader, 'domínio'),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: players.length,
                itemBuilder: (_, i) => playerRow(i),
              ),
            ),
            sectionHeader('Registro'),
            Expanded(child: logList()),
          ],
        ),
      );
    }

    // Tall (tablet portrait): 2 columns below map
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.wideHudGradient,
        border: Border(top: BorderSide(color: Color(0xFF2D4A72))),
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
      subText = 'terr.';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 4))],
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
                  style: TextStyle(
                    fontSize: size >= 80 ? 19 : 16,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: low ? const Color(0xFFFF8A7A) : AppColors.ink,
                  ),
                ),
                if (subText.isNotEmpty)
                  Text(
                    subText,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                      color: AppColors.mute,
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
    canvas.drawCircle(Offset.zero, 50, Paint()..color = const Color(0xE60A1422));

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
          ..color = low ? AppColors.bad : AppColors.gold
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
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
            ..strokeWidth = 10,
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
  bool shouldRepaint(covariant _TurnRingPainter old) => true;
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
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: lost > 0 ? const Color(0xFFFF8A7A) : const Color(0xFF8DFFB0),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF214253E), Color(0xF20A1422)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF37557F)),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, 10))],
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
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: isMini
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 5)
                : const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.glassGradient,
              borderRadius: BorderRadius.circular(isMini ? 999 : 16),
              border: Border.all(color: banner.color, width: isMini ? 1 : 2),
              boxShadow: [
                const BoxShadow(color: Color(0xBB000000), blurRadius: 36, offset: Offset(0, 10)),
                if (!isMini) BoxShadow(color: banner.color.withValues(alpha: 0.30), blurRadius: 30),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  banner.title,
                  textAlign: TextAlign.center,
                  style: isMini
                      ? TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: banner.color)
                      : AppText.serif(size: 24, color: banner.color, letterSpacing: 0.03),
                ),
                if (banner.sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    banner.sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.3, color: AppColors.ink),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Bottom Bar (#bar) ----------

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.ctrl, required this.layout});

  final AppController ctrl;
  final EstLayout layout;

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
      } else if (ev.mustTrade) {
        msgSpans.add(
          TextSpan(
            text: canNuke
                ? 'Você tem 5 ou mais cartas: troque ou lance a ogiva antes de reforçar.'
                : 'Você tem 5 ou mais cartas: troque antes de reforçar.',
          ),
        );
      } else if (rng != null) {
        msgSpans.add(const TextSpan(text: 'Reforçar '));
        msgSpans.add(
          TextSpan(
            text: ctrl.mapData.territories[ctrl.sel!].name,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
        );
        msgSpans.add(
          TextSpan(
            text: ' · $free livre${free == 1 ? '' : 's'}${extra.isNotEmpty ? ' ($extra)' : ''}',
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

      if (!ctrl.nukeMode) {
        if (rng != null) {
          btns.add(_StepperWidget(ctrl: ctrl, range: rng));
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
      final to = (v['occupy']['to'] as num).toInt();
      msgSpans.add(const TextSpan(text: 'Conquistou '));
      msgSpans.add(
        TextSpan(
          text: ctrl.mapData.territories[to].name,
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
      );
      msgSpans.add(const TextSpan(text: '! Um exército já entrou; levar mais quantos?'));
      if (rng != null) btns.add(_StepperWidget(ctrl: ctrl, range: rng));
      btns.add(actionBtn('Mover', ctrl.confirmOccupy, variant: EstButtonVariant.primary));
    } else if (v['step'] == 'attack') {
      if (rng != null) {
        final s = ctrl.sel!;
        final t = ctrl.target!;
        msgSpans.add(
          TextSpan(
            text:
                '${ctrl.mapData.territories[s].name} (${terrs[s]['a']}) ⚔ ${ctrl.mapData.territories[t].name} (${terrs[t]['a']}) · toque de novo no alvo para atacar',
          ),
        );
        btns.add(
          _StepperWidget(
            ctrl: ctrl,
            range: rng,
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
        btns.add(_StepperWidget(ctrl: ctrl, range: rng));
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
              const EstIcon(EstIconKind.pact, size: 16, color: Color(0xFFFFE2A3)),
              const SizedBox(width: 6),
              Text(
                busy ? 'Pacto ativo' : 'Propor pacto',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFE2A3),
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

    // Compact horizontal bar in land/rot mode
    if (layout.land) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 13, height: 1.25, color: AppColors.ink),
                  children: msgSpans,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (btns.isNotEmpty) ...[
              const SizedBox(width: 8),
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: btns),
            ],
          ],
        ),
      );
    }

    final meColor = meP != null
        ? parseHexColor(colors[(meP['color'] as num).toInt()].hex)
        : AppColors.mute;

    return Container(
      padding: EdgeInsets.fromLTRB(
        layout.wide ? 16 : 12,
        layout.wide ? 14 : 8,
        layout.wide ? 16 : 12,
        layout.wide ? 14 : 10,
      ),
      decoration: BoxDecoration(
        gradient: layout.wide ? AppColors.wideHudGradient : AppColors.hudGradient,
        border: const Border(top: BorderSide(color: Color(0xFF2D4A72))),
        boxShadow: layout.wide
            ? const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -10))]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: layout.wide ? 15 : 14,
                height: layout.wide ? 1.4 : 1.3,
                color: AppColors.ink,
              ),
              children: msgSpans,
            ),
          ),
          if (btns.isNotEmpty) ...[
            SizedBox(height: layout.wide ? 10 : 6),
            layout.wide
                ? Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final b in btns)
                        if (b is Expanded) b.child else b,
                    ],
                  )
                : Row(
                    children: [
                      for (var i = 0; i < btns.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        btns[i],
                      ],
                    ],
                  ),
          ],
          ?warnRow,
          SizedBox(height: layout.wide ? 10 : 6),
          if (layout.wide)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                    children: infoSpans,
                  ),
                ),
                const SizedBox(height: 4),
                _YouChip(meP: meP, meColor: meColor, watchers: ctrl.watchersCount ?? 0),
              ],
            )
          else
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
      return Text(
        '👁 Assistindo${watchers > 1 ? ' com mais ${watchers - 1}' : ''}',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.mute),
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
          const SizedBox(width: 4),
          Text('· 👁 $watchers', style: const TextStyle(fontSize: 12, color: AppColors.mute)),
        ],
      ],
    );
  }
}

class _StepperWidget extends StatelessWidget {
  const _StepperWidget({required this.ctrl, required this.range, this.unit});

  final AppController ctrl;
  final (int, int) range;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final canMinus = ctrl.stepValue > range.$1;
    final canPlus = ctrl.stepValue < range.$2;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1626), Color(0xFF0F1E33)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: canMinus ? () => ctrl.changeStep(-1) : null,
            child: Opacity(
              opacity: canMinus ? 1.0 : 0.3,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Text(
                    '−',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${ctrl.stepValue}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: AppColors.ink,
                  ),
                ),
                if (unit != null)
                  Text(
                    unit!,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: AppColors.mute,
                    ),
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: canPlus ? () => ctrl.changeStep(1) : null,
            child: Opacity(
              opacity: canPlus ? 1.0 : 0.3,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Text(
                    '+',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ),
              ),
            ),
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
    return GestureDetector(
      onTap: onTapOutside,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Container(
          color: const Color(0xB302060C),
          alignment: centered ? Alignment.center : Alignment.bottomCenter,
          padding: centered ? const EdgeInsets.all(20) : EdgeInsets.zero,
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: centered ? maxWidth : 500),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.glassGradient,
                  borderRadius: centered
                      ? BorderRadius.circular(18)
                      : const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: AppColors.edgeShadows,
                ),
                child: child,
              ),
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
          Text('Passe o aparelho', style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC))),
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
              style: const TextStyle(fontSize: 16, color: AppColors.ink),
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
              child: Text('• $b', style: const TextStyle(fontSize: 13.5, color: AppColors.ink)),
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
            style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC)),
          ),
          const SizedBox(height: 8),
          Text(
            atk
                ? 'Você passa para o remanejamento e não ataca mais neste turno.'
                : 'A vez passa para o próximo jogador.',
            style: const TextStyle(fontSize: 14, color: AppColors.mute),
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

class _VictoryOverlayState extends State<_VictoryOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final List<_Confetti> _bits;

  @override
  void initState() {
    super.initState();
    final v = widget.ctrl.view!;
    final wIdx = (v['winner'] as num).toInt();
    final wCol = parseHexColor(
      widget.ctrl.engine.constants.colors[(v['players'][wIdx]['color'] as num).toInt()].hex,
    );
    _bits = List.generate(
      70,
      (k) => _Confetti(
        x: ((k * 37) % 100) / 100.0,
        y: -((k * 29) % 40) / 40.0,
        vy: 0.25 + (((k * 13) % 20) / 40.0),
        vx: ((k % 5) - 2) * 0.03,
        size: 6.0 + (k % 4) * 2.0,
        color: [wCol, AppColors.gold, AppColors.ink, wCol][k % 4],
      ),
    );
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final v = c.view!;
    final players = v['players'] as List<dynamic>;
    final terrs = v['terr'] as List<dynamic>;
    final colors = c.engine.constants.colors;
    final wIdx = (v['winner'] as num).toInt();
    final w = players[wIdx] as Map<String, dynamic>;
    final wCol = parseHexColor(colors[(w['color'] as num).toInt()].hex);
    final mine = c.role == 'guest' ? wIdx == c.me : w['ctrl'] == 'local';
    final objTxt = (c.eval?.objectiveTexts[wIdx] ?? '').replaceFirst(RegExp(r' Se for o seu.*$'), '');
    final layout = EstLayout.of(context);

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

    return Container(
      color: const Color(0xEE050A13),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, _) => CustomPaint(painter: _ConfettiPainter(bits: _bits, t: _anim.value)),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: layout.big ? 500 : (widget.land ? 620 : 400)),
                padding: EdgeInsets.all(layout.big ? 24 : 18),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: wCol, width: 2),
                  boxShadow: [
                    BoxShadow(color: wCol.withValues(alpha: 0.22), spreadRadius: 6),
                    const BoxShadow(color: Color(0xCC000000), blurRadius: 60, offset: Offset(0, 20)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _anim,
                      builder: (context, child) {
                        final bob = sin(_anim.value * pi * 4);
                        return Transform.translate(
                          offset: Offset(0, -3 * bob.abs()),
                          child: child,
                        );
                      },
                      child: EstIcon(EstIconKind.cup, size: 72, color: wCol),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mine ? 'Você venceu!' : 'Vitória de',
                      style: const TextStyle(
                        fontSize: 14,
                        letterSpacing: 2.0,
                        color: AppColors.mute,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${w['name'] ?? ''}',
                      textAlign: TextAlign.center,
                      style: AppText.serif(size: layout.big ? 40 : 32, color: wCol, height: 1.05),
                    ),
                    if (objTxt.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        v['winBy'] == 'last' ? 'ÚLTIMO EXÉRCITO EM JOGO · O OBJETIVO ERA' : 'OBJETIVO CUMPRIDO',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: AppColors.mute,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        objTxt,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, height: 1.35, color: AppColors.ink),
                      ),
                    ],
                    const SizedBox(height: 14),
                    for (final i in rank)
                      Builder(
                        builder: (_) {
                          final p = players[i] as Map<String, dynamic>;
                          final col = parseHexColor(colors[(p['color'] as num).toInt()].hex);
                          final isFirst = i == wIdx;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: isFirst ? wCol.withValues(alpha: 0.18) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: col,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0x88000000), width: 2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${p['name'] ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isFirst ? FontWeight.w700 : FontWeight.w400,
                                      color: isFirst ? AppColors.ink : AppColors.mute,
                                    ),
                                  ),
                                ),
                                Text(
                                  p['alive'] == true ? '${owned(i)} territórios' : 'eliminado',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isFirst ? FontWeight.w700 : FontWeight.w400,
                                    color: isFirst ? AppColors.ink : AppColors.mute,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: EstButton(label: 'Ver o mapa', onPressed: c.dismissVictory),
                        ),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Confetti {
  _Confetti({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.bits, required this.t});

  final List<_Confetti> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bits) {
      final py = ((b.y + b.vy * t * 4) % 1.2) * size.height;
      final px = ((b.x + b.vx * t * 4 + sin(t * 14 + b.size) * 0.02) % 1.0) * size.width;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(px, py), width: b.size, height: b.size * 1.6),
        Paint()..color = b.color.withValues(alpha: 0.92),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
