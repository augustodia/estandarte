import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../platform/lan_host.dart';
import '../platform/p2p.dart';
import 'modals.dart';
import 'theme.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  Timer? _quickTick;
  final _passCtrl = TextEditingController();
  bool _editingPass = false;
  bool _showPass = false;

  @override
  void initState() {
    super.initState();
    _passCtrl.text = widget.ctrl.lobbyPass;
    _quickTick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && widget.ctrl.lobbyQuick && widget.ctrl.lobbyQuickDeadlineMs > 0) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _quickTick?.cancel();
    _passCtrl.dispose();
    super.dispose();
  }

  static const _extrasMeta = [
    (
      'cards',
      'Cartas no lugar do Quartel',
      'A partida troca o Quartel (medalhas e ordens táticas) pelas cartas de território: junte três e troque por exércitos.',
    ),
    (
      'spy',
      'Espionagem',
      'Ordem do Quartel (2 medalhas): a 1ª revela 2 objetivos possíveis do alvo; a 2ª confirma o verdadeiro. Dá +1 no maior dado de ataque contra ele no turno.',
    ),
    (
      'events',
      'Eventos de rodada',
      'De vez em quando, um evento surpresa muda as regras para todos por uma rodada.',
    ),
    (
      'pacts',
      'Pactos',
      'Dois jogadores combinam não se atacar por 2 rodadas. Romper antes custa metade do reforço.',
    ),
    (
      'nukes',
      'Ogiva nuclear',
      'Vira uma das ordens do Quartel (ou, com cartas, entra no lugar de uma troca): arrasa um território inimigo, que fica radioativo por uma rodada.',
    ),
  ];

  bool _getExtra(String k) => switch (k) {
        'events' => widget.ctrl.optEvents,
        'pacts' => widget.ctrl.optPacts,
        'nukes' => widget.ctrl.optNukes,
        'cards' => !widget.ctrl.optHq,
        'spy' => widget.ctrl.optHq && widget.ctrl.optSpy,
        _ => false,
      };

  void _toggleExtra(String k) {
    final c = widget.ctrl;
    switch (k) {
      case 'events':
        c.updateLobbyConfig(events: !c.optEvents);
      case 'pacts':
        c.updateLobbyConfig(pacts: !c.optPacts);
      case 'nukes':
        c.updateLobbyConfig(nukes: !c.optNukes);
      case 'cards':
        c.updateLobbyConfig(hq: !c.optHq);
      case 'spy':
        c.updateLobbyConfig(spy: !c.optSpy);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final layout = EstLayout.of(context);
    final isOnline = c.online != null;
    final isLanGuest = c.online?.lan == true;
    final isLanHostActive = !isOnline && c.lanHostAddr != null;
    final isRelayHostActive = !isOnline && c.relayCode != null;
    final isQuick = c.lobbyQuick;
    final canConfig = isOnline ? c.lobbyOwner : c.role != 'guest';
    final code = c.relayCode ?? c.lobbyCode ?? c.online?.code;
    final maxSeats = isQuick ? 4 : 6;
    final sub = 'Forças na mesa · ${c.seats.length} de $maxSeats';
    final extrasOpen = c.extrasOpen ?? layout.big;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final quickRemMs = isQuick && c.lobbyQuickDeadlineMs > 0
        ? (c.lobbyQuickDeadlineMs - nowMs).clamp(0, 45000)
        : 0;
    final quickSec = (quickRemMs / 1000).ceil();

    final showJoinLocal = canConfig &&
        !isOnline &&
        !isLanHostActive &&
        !isRelayHostActive &&
        (LanHost.canJoinByIp || P2P.supported);

    Widget joinLocalBar({required bool inline}) {
      if (!showJoinLocal) return const SizedBox.shrink();
      final buttons = <Widget>[
        if (LanHost.canJoinByIp)
          EstButton(
            small: true,
            height: 36,
            variant: EstButtonVariant.pact,
            icon: EstIconKind.lan,
            label: P2P.supported ? 'Entrar por IP' : 'Entrar na mesa local (IP)',
            onPressed: () => showLanJoinModal(context, c),
          ),
        if (P2P.supported)
          EstButton(
            small: true,
            height: 36,
            variant: EstButtonVariant.pact,
            icon: EstIconKind.qr,
            label: LanHost.canJoinByIp ? 'Entrar por QR' : 'Entrar por QR Code',
            onPressed: () => showP2pJoinModal(context, c),
          ),
      ];
      if (inline) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              buttons[i],
            ],
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ],
      );
    }

    Widget headerBar({required bool big}) => Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  EstIconButton(
                    icon: EstIconKind.back,
                    size: 34,
                    iconSize: 15,
                    color: AppColors.ink,
                    tooltip: isOnline ? 'Sair da sala' : 'Voltar',
                    onPressed: c.leaveGame,
                  ),
                  const SizedBox(width: 12),
                  EstIcon(
                    isQuick
                        ? EstIconKind.bolt
                        : (isLanGuest || isLanHostActive
                            ? EstIconKind.lan
                            : (isOnline || isRelayHostActive ? EstIconKind.globe : EstIconKind.board)),
                    size: big ? 24 : 20,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      isQuick
                          ? 'Partida Rápida'
                          : (isLanGuest
                              ? 'Rede Local'
                              : (isOnline ? 'Sala Online' : 'Mesa Local')),
                      overflow: TextOverflow.ellipsis,
                      style: AppText.serif(size: big ? 30 : 24),
                    ),
                  ),
                  if ((isOnline || isLanHostActive || isRelayHostActive) && code != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.obsidian,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.brassDim),
                      ),
                      child: Text(
                        isLanGuest || isLanHostActive ? code : '#$code',
                        style: const TextStyle(
                          fontFamily: AppText.cond, fontFeatures: AppText.tabular,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: AppColors.gold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (big && showJoinLocal) ...[
              const SizedBox(width: 16),
              joinLocalBar(inline: true),
            ],
          ],
        );

    Widget? quickBanner() {
      if (!isQuick) return null;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const EstIcon(EstIconKind.bolt, size: 15, color: AppColors.brass),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'FILA RÁPIDA ATIVA',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: AppColors.gold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.obsidian,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.brassDim),
                  ),
                  child: Text(
                    quickSec > 0 ? '${quickSec}s' : 'INICIANDO',
                    style: const TextStyle(
                      fontFamily: AppText.cond, fontFeatures: AppText.tabular,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (quickRemMs / 45000).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColors.obsidian,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aguardando até 4 comandantes. Ao zerar o relógio (ou iniciando agora), bots completam as vagas.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFFE8ECF1)),
            ),
          ],
        ),
      );
    }

    Widget seatsWidget() {
      final colors = c.engine.constants.colors;
      final openCount = isQuick ? max(0, 4 - c.seats.length) : 0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < c.seats.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _SeatTile(
              ctrl: c,
              index: i,
              color: colors[c.seats[i].color % colors.length],
              isOnline: isOnline,
              canConfig: canConfig,
            ),
          ],
          for (var k = 0; k < openCount; k++) ...[
            const SizedBox(height: 6),
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.obsidian.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line.withValues(alpha: 0.65)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.deep,
                      border: Border.all(color: AppColors.line, width: 1.2),
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Text(
                    'Aguardando comandante (ou bot ao iniciar)',
                    style: TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    Widget actionsWidget() {
      final full = c.seats.length >= maxSeats;
      final n = c.seats.length;
      final activeExtras = _extrasMeta.where((e) => _getExtra(e.$1)).map((e) => e.$2).toList();
      final extrasSummary = activeExtras.isNotEmpty ? activeExtras.join(', ') : 'nenhuma ligada';
      final waitMsg = isOnline ? (c.online?.waitMsg ?? '') : c.relayWaitMsg;
      final showOnlineWait = isOnline && (c.guestLink == null || waitMsg.isNotEmpty);
      final showRelayWait =
          isRelayHostActive && (!c.isRelayConnected || waitMsg.isNotEmpty);
      final connBanner = (showOnlineWait || showRelayWait)
          ? Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                waitMsg.isNotEmpty ? waitMsg : 'Sem conexão com o servidor. Reconectando…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.bad),
              ),
            )
          : null;

      if (!canConfig) {
        final timeStr = c.turnSecs > 0 ? '${c.turnSecs ~/ 60} min' : 'Livre';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?connBanner,
            ?quickBanner(),
            const EstSectionTag('BRIEFING DA MESA'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.obsidian.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Tempo de turno:', style: TextStyle(fontSize: 13, color: AppColors.mute)),
                      const Spacer(),
                      Text(
                        timeStr,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('Sistema tático:', style: TextStyle(fontSize: 13, color: AppColors.mute)),
                      const Spacer(),
                      Text(
                        c.optHq ? 'Quartel (medalhas e ordens)' : 'Cartas de território',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold),
                      ),
                    ],
                  ),
                  if (c.lobbyHasPass) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Acesso:', style: TextStyle(fontSize: 13, color: AppColors.mute)),
                        const Spacer(),
                        const EstIcon(EstIconKind.lock, size: 12, color: AppColors.gold),
                        const SizedBox(width: 5),
                        const Text(
                          'Protegida por senha',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold),
                        ),
                      ],
                    ),
                  ],
                  if (activeExtras.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final ex in activeExtras)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.panel,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Text(
                              ex,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isOnline
                  ? 'Aguardando o anfitrião iniciar. Toque no círculo da sua cor para trocar.'
                  : 'Aguardando o anfitrião iniciar…',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.mute),
            ),
            if (isOnline && !isLanGuest && code != null) ...[
              const SizedBox(height: 12),
              EstButton(
                icon: EstIconKind.qr,
                label: 'Convidar (link ou QR)',
                onPressed: () => showOnlineInviteModal(context, c),
              ),
            ],
            const SizedBox(height: 8),
            EstButton(
              label: isOnline ? 'Sair da sala' : 'Sair',
              variant: EstButtonVariant.ghost,
              onPressed: () => c.leaveGame(),
            ),
          ],
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?connBanner,
          ?quickBanner(),
          const EstSectionTag('REGRAS DA BATALHA'),
          const SizedBox(height: 10),
          // Tempo por turno
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tempo por turno',
                style: TextStyle(fontSize: 13, color: AppColors.mute),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final opt in const [
                    (0, 'Livre'),
                    (60, '1 min'),
                    (120, '2 min'),
                    (180, '3 min'),
                  ])
                    EstChip(
                      label: opt.$2,
                      height: 36,
                      fontSize: 13,
                      selected: c.turnSecs == opt.$1,
                      onTap: () => c.updateLobbyConfig(secs: opt.$1),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Collapsible Regras extras
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    c.extrasOpen = !extrasOpen;
                    setState(() {});
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 150),
                          turns: extrasOpen ? 0.25 : 0.0,
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppColors.mute,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Regras extras',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            extrasSummary,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.mute),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: extrasOpen
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final ex in _extrasMeta)
                              if (ex.$1 != 'spy' || c.optHq)
                                EstSwitchOpt(
                                  title: ex.$2,
                                  subtitle: ex.$3,
                                  value: _getExtra(ex.$1),
                                  enabled: true,
                                  onChanged: (_) => _toggleExtra(ex.$1),
                                ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          if (isOnline || isRelayHostActive) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.obsidian.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line),
              ),
              child: EstSwitchOpt(
                topBorder: false,
                title: 'Sala pública',
                subtitle:
                    'Aparece na lista de salas: qualquer um pode entrar e, depois que começar, assistir. Desligada, só entra quem tem o código.',
                value: c.optPublic,
                enabled: true,
                onChanged: (v) => c.updateLobbyConfig(isPublic: v),
              ),
            ),
          ],

          if (!isQuick) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.obsidian.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: c.lobbyHasPass ? const Color(0xFF9AA4B2) : AppColors.line,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      EstIcon(
                        EstIconKind.lock,
                        size: 14,
                        color: c.lobbyHasPass ? AppColors.gold : AppColors.mute,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Senha da sala',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              c.lobbyHasPass
                                  ? 'Ativa · quem entrar sem token digita a senha'
                                  : 'Opcional · entrada livre sem senha',
                              style: const TextStyle(fontSize: 11, color: AppColors.mute),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (c.lobbyHasPass && !_editingPass) ...[
                        EstButton(
                          small: true,
                          height: 32,
                          label: 'Alterar',
                          onPressed: () {
                            _passCtrl.text = c.lobbyPass;
                            setState(() => _editingPass = true);
                          },
                        ),
                        const SizedBox(width: 6),
                        EstButton(
                          small: true,
                          height: 32,
                          variant: EstButtonVariant.ghost,
                          label: 'Remover',
                          onPressed: () {
                            _passCtrl.clear();
                            c.updateLobbyConfig(pass: '');
                            setState(() => _editingPass = false);
                          },
                        ),
                      ] else
                        EstButton(
                          small: true,
                          height: 32,
                          label: _editingPass ? 'Fechar' : 'Definir',
                          onPressed: () {
                            if (!_editingPass) {
                              _passCtrl.text = c.lobbyPass;
                            }
                            setState(() => _editingPass = !_editingPass);
                          },
                        ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: _editingPass
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: EstTextField(
                                    controller: _passCtrl,
                                    height: 38,
                                    obscureText: !_showPass,
                                    maxLength: 24,
                                    hintText: 'Senha (até 24 chars)',
                                    onSubmitted: (val) {
                                      c.updateLobbyConfig(pass: val);
                                      setState(() => _editingPass = false);
                                    },
                                    suffix: IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                                      icon: Icon(
                                        _showPass
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 17,
                                        color: AppColors.mute,
                                      ),
                                      onPressed: () => setState(() => _showPass = !_showPass),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                EstButton(
                                  small: true,
                                  height: 38,
                                  variant: EstButtonVariant.primary,
                                  label: 'Salvar',
                                  onPressed: () {
                                    c.updateLobbyConfig(pass: _passCtrl.text);
                                    setState(() => _editingPass = false);
                                  },
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          if (isOnline)
            Row(
              children: [
                Expanded(
                  child: EstButton(
                    label: 'Convidar',
                    onPressed: (full || code == null) ? null : () => showOnlineInviteModal(context, c),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstButton(
                    label: '+ Bot',
                    onPressed: full ? null : () => c.addLobbyPlayer(isBot: true),
                  ),
                ),
              ],
            )
          else ...[
            if (isRelayHostActive) ...[
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF9AA4B2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const EstIcon(EstIconKind.globe, size: 15, color: AppColors.gold),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            'SALA POR CÓDIGO ATIVA',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                        EstButton(
                          small: true,
                          height: 28,
                          variant: EstButtonVariant.ghost,
                          label: 'Encerrar',
                          onPressed: c.stopRelayHost,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            '#${c.relayCode!}',
                            style: const TextStyle(
                              fontFamily: AppText.cond, fontFeatures: AppText.tabular,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        EstButton(
                          small: true,
                          height: 32,
                          label: 'Copiar',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: c.relayCode!));
                            c.showToast('Código #${c.relayCode} copiado.');
                          },
                        ),
                        const SizedBox(width: 6),
                        EstButton(
                          small: true,
                          height: 32,
                          icon: EstIconKind.qr,
                          label: 'Link / QR',
                          onPressed: () => showOnlineInviteModal(context, c),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Amigos no PC ou navegador entram em Salas Online digitando #${c.relayCode}.',
                      style: const TextStyle(fontSize: 11, color: AppColors.mute),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else if (c.lanHostAddr != null) ...[
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF9AA4B2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const EstIcon(EstIconKind.lan, size: 15, color: AppColors.gold),
                        const SizedBox(width: 7),
                        const Expanded(
                          child: Text(
                            'HOST LAN ATIVO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                        EstButton(
                          small: true,
                          height: 28,
                          variant: EstButtonVariant.ghost,
                          label: 'Fechar rede',
                          onPressed: c.stopLanHost,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            c.lanHostAddr!,
                            style: const TextStyle(
                              fontFamily: AppText.cond, fontFeatures: AppText.tabular,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        EstButton(
                          small: true,
                          height: 32,
                          label: 'Copiar IP',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: c.lanHostAddr!));
                            c.showToast('IP copiado.');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.lanAllAddrs.length > 1
                          ? 'Outros adaptadores: ${c.lanAllAddrs.skip(1).join(' · ')}'
                          : 'Outros aparelhos na mesma rede entram digitando esse endereço.',
                      style: const TextStyle(fontSize: 11, color: AppColors.mute),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              EstButton(
                icon: EstIconKind.globe,
                label: c.relayStarting
                    ? (c.relayWaitMsg.isNotEmpty ? c.relayWaitMsg : 'Abrindo sala por código…')
                    : 'Abrir sala por código (Internet)',
                onPressed: (c.relayStarting || c.lanStarting) ? null : c.startRelayHost,
              ),
              if (LanHost.supported) ...[
                const SizedBox(height: 6),
                EstButton(
                  small: true,
                  icon: EstIconKind.lan,
                  label: c.lanStarting ? 'Abrindo rede local…' : 'Rede local (Wi-Fi / LAN)',
                  onPressed: (c.lanStarting || c.relayStarting) ? null : c.startLanHost,
                ),
              ],
              if (P2P.supported) ...[
                const SizedBox(height: 6),
                EstButton(
                  small: true,
                  icon: EstIconKind.qr,
                  label: 'Convidar por QR (offline)',
                  onPressed: full || c.relayStarting ? null : () => showP2pInviteModal(context, c),
                ),
              ],
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: EstButton(
                    small: true,
                    label: '+ Jogador neste aparelho',
                    onPressed: full ? null : () => _showAddLocalModal(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstButton(
                    small: true,
                    label: '+ Bot',
                    onPressed: full ? null : () => c.addLobbyPlayer(isBot: true),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),
          EstButton(
            icon: EstIconKind.sword,
            label: isQuick && n < 4
                ? 'Iniciar agora (completar com bots)'
                : 'Iniciar Batalha ($n/$maxSeats)',
            variant: EstButtonVariant.primary,
            height: 48,
            onPressed: (n < 2 && !isQuick) ? null : c.beginGame,
          ),
          const SizedBox(height: 4),
          EstButton(
            label: isOnline ? 'Sair da sala' : 'Sair',
            variant: EstButtonVariant.ghost,
            onPressed: () => c.leaveGame(),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(layout.big ? 28 : 16),
            child: layout.big
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        headerBar(big: true),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  EstSectionTag(sub),
                                  const SizedBox(height: 12),
                                  seatsWidget(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              child: EstGlassCard(
                                padding: const EdgeInsets.all(20),
                                borderRadius: 6,
                                child: actionsWidget(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        headerBar(big: false),
                        if (showJoinLocal) ...[
                          const SizedBox(height: 10),
                          joinLocalBar(inline: false),
                        ],
                        const SizedBox(height: 12),
                        EstSectionTag(sub),
                        const SizedBox(height: 8),
                        seatsWidget(),
                        const SizedBox(height: 12),
                        EstGlassCard(
                          ornate: false,
                          padding: const EdgeInsets.all(14),
                          borderRadius: 6,
                          child: actionsWidget(),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _showAddLocalModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    showEstSheet<void>(
      context,
      maxWidth: 440,
      builder: (ctx) => EstSheetBody(
        title: 'Jogador neste aparelho',
        onClose: () => Navigator.pop(ctx),
        children: [
          const Text('Nome', style: TextStyle(fontSize: 13, color: AppColors.mute)),
          const SizedBox(height: 6),
          TextField(
            controller: nameCtrl,
            autofocus: true,
            maxLength: 14,
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (val) {
              widget.ctrl.addLobbyPlayer(isBot: false, localName: val);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: EstButton(
                  label: 'Adicionar',
                  variant: EstButtonVariant.primary,
                  onPressed: () {
                    widget.ctrl.addLobbyPlayer(isBot: false, localName: nameCtrl.text);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EstButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.ctrl,
    required this.index,
    required this.color,
    required this.isOnline,
    required this.canConfig,
  });

  final AppController ctrl;
  final int index;
  final dynamic color;
  final bool isOnline;
  final bool canConfig;

  @override
  Widget build(BuildContext context) {
    final seat = ctrl.seats[index];
    final col = parseHexColor(color.hex as String);
    final isMe = index == ctrl.me && (isOnline || ctrl.role == 'guest');
    final canCycle = isOnline ? (canConfig || index == ctrl.me) : canConfig;
    final canKick = canConfig && (isOnline ? index != ctrl.me : index > 0);
    final canRename = !isOnline && canConfig && seat.ctrl == 'local';

    final String kindLabel;
    bool offline = false;
    if (seat.ctrl == 'bot') {
      kindLabel = 'bot';
    } else if (isOnline) {
      if (seat.online) {
        kindLabel = 'online';
      } else {
        kindLabel = 'desconectado';
        offline = true;
      }
    } else {
      kindLabel = seat.ctrl == 'remote' ? 'outro aparelho' : 'neste aparelho';
    }

    return Container(
      constraints: BoxConstraints(minHeight: estCompact(context) ? 44 : 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isMe ? AppColors.panel2 : AppColors.panel,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isMe ? AppColors.glassBorder : AppColors.line),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: canCycle ? () => ctrl.cycleSeatColor(index) : null,
            child: MouseRegion(
              cursor: canCycle ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: Tooltip(
                message: canCycle ? 'Trocar cor' : color.name,
                child: EstFactionSeal(color: col, size: 17, highlighted: isMe),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: InkWell(
              onTap: canRename ? () => _renameSeat(context) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          seat.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (canRename) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: AppColors.mute.withValues(alpha: 0.7),
                        ),
                      ],
                      if (isMe) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
                              letterSpacing: 0.7,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 11, color: AppColors.mute),
                      children: [
                        TextSpan(text: '${color.name} · '),
                        TextSpan(
                          text: kindLabel,
                          style: TextStyle(color: offline ? AppColors.bad : AppColors.mute),
                        ),
                        if (canCycle && isMe)
                          const TextSpan(
                            text: ' · toque na cor para trocar',
                            style: TextStyle(color: Color(0xFF9AA4B2)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canKick) ...[
            const SizedBox(width: 8),
            EstIconButton(
              icon: EstIconKind.close,
              size: 28,
              iconSize: 12,
              dangerHover: true,
              tooltip: 'Remover da mesa',
              onPressed: () => ctrl.removeSeat(index),
            ),
          ],
        ],
      ),
    );
  }

  void _renameSeat(BuildContext context) {
    final tc = TextEditingController(text: ctrl.seats[index].name);
    showEstSheet<void>(
      context,
      maxWidth: 420,
      builder: (ctx) => EstSheetBody(
        title: 'Nome do jogador',
        onClose: () => Navigator.pop(ctx),
        children: [
          TextField(
            controller: tc,
            autofocus: true,
            maxLength: 14,
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (v) {
              ctrl.updateSeatName(index, v);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: EstButton(
                  label: 'Salvar',
                  variant: EstButtonVariant.primary,
                  onPressed: () {
                    ctrl.updateSeatName(index, tc.text);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EstButton(label: 'Cancelar', onPressed: () => Navigator.pop(ctx)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
