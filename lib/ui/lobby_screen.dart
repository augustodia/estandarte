import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
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
    final canConfig = isOnline ? c.lobbyOwner : c.role != 'guest';
    final code = c.lobbyCode ?? c.online?.code;
    final title = isOnline ? (code != null ? 'Sala $code' : 'Sala online') : 'Sala';
    final sub = 'Jogadores · ${c.seats.length} de 6';
    final extrasOpen = c.extrasOpen ?? layout.big;

    Widget seatsWidget() {
      final colors = c.engine.constants.colors;
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
        ],
      );
    }

    Widget actionsWidget() {
      final full = c.seats.length >= 6;
      final n = c.seats.length;
      final activeExtras = _extrasMeta.where((e) => _getExtra(e.$1)).map((e) => e.$2).toList();
      final extrasSummary = activeExtras.isNotEmpty ? activeExtras.join(', ') : 'nenhuma ligada';
      final waitMsg = c.online?.waitMsg ?? '';
      final connBanner = isOnline && (c.guestLink == null || waitMsg.isNotEmpty)
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
        final timeStr = c.turnSecs > 0 ? '${c.turnSecs ~/ 60} min' : 'livre';
        final extraTxt = activeExtras.isNotEmpty
            ? ' Regras extras: ${activeExtras.map((e) => e.toLowerCase()).join(', ')}.'
            : '';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?connBanner,
            Text(
              isOnline
                  ? 'Tempo por turno: $timeStr.$extraTxt Aguardando quem criou a sala iniciar… Toque na sua bolinha para trocar de cor.'
                  : 'Tempo por turno: $timeStr.$extraTxt Aguardando o anfitrião iniciar…',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.mute),
            ),
            if (isOnline && code != null) ...[
              const SizedBox(height: 10),
              EstButton(
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
          // Tempo por turno
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tempo por turno',
                style: TextStyle(fontSize: 14, color: AppColors.mute),
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
              color: AppColors.deep,
              borderRadius: BorderRadius.circular(10),
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
                          style: TextStyle(fontSize: 14, color: AppColors.ink),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            extrasSummary,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.mute),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (extrasOpen)
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
            ),
          ),

          if (isOnline) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0x660B1626),
                borderRadius: BorderRadius.circular(10),
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
            EstButton(
              label: 'Convidar por QR',
              onPressed: full
                  ? null
                  : (P2P.supported
                      ? () => showP2pInviteModal(context, c)
                      : () => c.showToast(
                          'Convite QR requer navegador WebRTC (ou use "Jogar online").')),
            ),
            const SizedBox(height: 8),
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
            label: 'Iniciar partida ($n ${n == 1 ? 'jogador' : 'jogadores'})',
            variant: EstButtonVariant.primary,
            onPressed: n < 2 ? null : c.beginGame,
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
                        Text(title, style: AppText.serif(size: 34)),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    sub.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      letterSpacing: 1.3,
                                      color: AppColors.mute,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  seatsWidget(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 32),
                            Expanded(
                              child: EstGlassCard(
                                padding: const EdgeInsets.all(20),
                                borderRadius: 18,
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
                        Text(title, style: AppText.serif(size: 26)),
                        const SizedBox(height: 10),
                        seatsWidget(),
                        const SizedBox(height: 10),
                        actionsWidget(),
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
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppColors.glassGradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.edgeShadows,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: canCycle ? () => ctrl.cycleSeatColor(index) : null,
            child: MouseRegion(
              cursor: canCycle ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: col,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x88000000), width: 2),
                  boxShadow: [
                    const BoxShadow(color: Color(0x66000000), spreadRadius: 3),
                    BoxShadow(color: col, blurRadius: 12),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: canRename ? () => _renameSeat(context) : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 15, color: AppColors.ink),
                      children: [
                        TextSpan(
                          text: seat.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (isMe)
                          const TextSpan(
                            text: ' (você)',
                            style: TextStyle(fontWeight: FontWeight.w400),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 12, color: AppColors.mute),
                      children: [
                        TextSpan(text: '${color.name} · '),
                        TextSpan(
                          text: kindLabel,
                          style: TextStyle(color: offline ? AppColors.bad : AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canKick)
            SizedBox(
              width: 38,
              child: EstButton(
                small: true,
                label: '✕',
                variant: EstButtonVariant.ghost,
                padding: EdgeInsets.zero,
                onPressed: () => ctrl.removeSeat(index),
              ),
            ),
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
