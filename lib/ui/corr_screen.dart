import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../net/account_api.dart';
import 'theme.dart';

/// Correspondência: partidas de dias, com até 24 h para cada jogada.
///
/// Uma lista só, na ordem em que pedem atenção: a sua vez, a vez dos outros, salas de espera e encerradas.
/// Cada linha traz as insígnias de quem joga, de quem é a vez e uma régua fina com o que sobra do prazo.
class CorrScreen extends StatefulWidget {
  const CorrScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<CorrScreen> createState() => _CorrScreenState();
}

class _CorrScreenState extends State<CorrScreen> {
  late final TextEditingController _codeCtrl;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.ctrl.corrPrefill);
    widget.ctrl.corrPrefill = '';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  AppController get c => widget.ctrl;

  void _open() {
    final code = asyncCode(_codeCtrl.text);
    if (code == null) {
      c.showToast('O código da correspondência tem 6 letras (ex.: K7M2QA).');
      return;
    }
    c.openCorrGame(code);
  }

  @override
  Widget build(BuildContext context) {
    final layout = EstLayout.of(context);
    final short = layout.size.height <= 520;
    final pad = layout.big ? 36.0 : (short ? 16.0 : 20.0);
    final games = c.corrGames;

    final groups = <(String, List<AsyncGameInfo>)>[
      ('SUA VEZ', games.where((g) => g.playing && g.yourTurn).toList()),
      ('VEZ DOS OUTROS', games.where((g) => g.playing && !g.yourTurn).toList()),
      ('SALA DE ESPERA', games.where((g) => g.waiting).toList()),
      ('ENCERRADAS', games.where((g) => g.over).toList()),
    ];

    final body = <Widget>[];
    final invites = c.corrInvites;
    if (invites.isNotEmpty) {
      body.add(Row(
        children: [
          Text('CONVITES', style: AppText.label(size: 11.5, color: AppColors.ink)),
          const SizedBox(width: 8),
          Text('${invites.length}', style: AppText.number(size: 12, color: AppColors.faint)),
          const SizedBox(width: 12),
          const Expanded(child: Divider(height: 1, thickness: 1, color: AppColors.line)),
        ],
      ));
      body.add(const SizedBox(height: 10));
      for (var i = 0; i < invites.length; i++) {
        if (i > 0) body.add(const SizedBox(height: 6));
        body.add(_InviteRow(ctrl: c, invite: invites[i]));
      }
    }
    if (!c.corrLoaded && c.corrLoading) {
      body.add(const _Note('Buscando as suas partidas…'));
    } else if (c.corrError != null && games.isEmpty) {
      body.add(_Note(c.corrError!, bad: true));
    } else if (games.isEmpty && invites.isEmpty) {
      body.add(_EmptyState(wide: layout.wide));
    } else {
      for (final (label, list) in groups) {
        if (list.isEmpty) continue;
        if (body.isNotEmpty) body.add(SizedBox(height: short ? 18 : 26));
        body.add(Row(
          children: [
            Text(label, style: AppText.label(size: 11.5, color: label == 'SUA VEZ' ? AppColors.ink : AppColors.faint)),
            const SizedBox(width: 8),
            Text('${list.length}', style: AppText.number(size: 12, color: AppColors.faint)),
            const SizedBox(width: 12),
            const Expanded(child: Divider(height: 1, thickness: 1, color: AppColors.line)),
          ],
        ));
        body.add(const SizedBox(height: 10));
        for (var i = 0; i < list.length; i++) {
          if (i > 0) body.add(const SizedBox(height: 6));
          body.add(_GameRow(ctrl: c, game: list[i], onTap: () => c.openCorrGame(list[i].id)));
        }
      }
    }

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, short ? 12 : 24, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(layout, short),
                  SizedBox(height: short ? 12 : 22),
                  _commandBar(layout),
                  SizedBox(height: short ? 14 : 26),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.ink,
                      backgroundColor: AppColors.panel,
                      onRefresh: c.refreshCorr,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: body,
                      ),
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

  Widget _header(EstLayout layout, bool short) {
    return Row(
      children: [
        EstIconButton(
          icon: EstIconKind.back,
          size: 36,
          iconSize: 16,
          color: AppColors.ink,
          tooltip: 'Voltar',
          onPressed: c.goHome,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Correspondência', style: AppText.serif(size: layout.big ? 28 : (short ? 20 : 24))),
              if (!short) ...[
                const SizedBox(height: 2),
                Text('24 H POR JOGADA · AVISO POR E-MAIL', style: AppText.label(size: 11)),
              ],
            ],
          ),
        ),
        if (c.corrLoading && c.corrLoaded)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.faint),
          ),
      ],
    );
  }

  Widget _commandBar(EstLayout layout) {
    final create = EstButton(
      label: c.corrCreating ? 'Criando…' : 'Nova partida',
      icon: EstIconKind.plus,
      variant: EstButtonVariant.primary,
      height: 42,
      onPressed: c.corrCreating ? null : c.createCorrGame,
    );
    final join = Row(
      children: [
        Expanded(
          child: EstTextField(
            controller: _codeCtrl,
            height: 42,
            maxLength: 80,
            hintText: 'Código de 6 letras',
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _open(),
            style: const TextStyle(
              fontFamily: AppText.cond,
              fontFeatures: AppText.tabular,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        EstButton(label: 'Abrir', height: 42, onPressed: _open),
      ],
    );
    if (layout.size.width >= 640) {
      return Row(
        children: [
          SizedBox(width: 210, child: create),
          const SizedBox(width: 12),
          Container(width: 1, height: 26, color: AppColors.line),
          const SizedBox(width: 12),
          Expanded(child: join),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [create, const SizedBox(height: 8), join],
    );
  }
}

/// "faltam 18 h", "faltam 42 min" ou "passando a vez…" quando o prazo venceu e o servidor ainda não jogou.
String corrTimeLeft(int deadlineMs, {int? nowMs}) {
  final left = deadlineMs - (nowMs ?? DateTime.now().millisecondsSinceEpoch);
  if (deadlineMs <= 0) return '';
  if (left <= 0) return 'passando a vez…';
  final mins = (left / 60000).ceil();
  if (mins >= 60) return 'faltam ${(mins / 60).floor()} h';
  return 'faltam $mins min';
}

String _ago(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inDays >= 2) return 'há ${d.inDays} dias';
  if (d.inDays == 1) return 'ontem';
  if (d.inHours >= 1) return 'há ${d.inHours} h';
  return 'agora há pouco';
}

/// Os nomes como frase: "Você, Beto e Carla".
String _names(List<AsyncSeatInfo> seats) {
  final n = [for (final s in seats) s.you ? 'Você' : s.name];
  if (n.isEmpty) return '';
  if (n.length == 1) return n.first;
  return '${n.sublist(0, n.length - 1).join(', ')} e ${n.last}';
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.ctrl, required this.game, required this.onTap});

  final AppController ctrl;
  final AsyncGameInfo game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final colors = ctrl.engine.constants.colors;
    final mine = g.playing && g.yourTurn;

    final String status;
    final String detail;
    Color statusColor = AppColors.mute;
    if (g.playing) {
      status = g.yourTurn ? 'JOGAR' : 'VEZ DE ${g.turnName.toUpperCase()}';
      detail = corrTimeLeft(g.deadlineMs);
      if (g.yourTurn) statusColor = AppColors.ink;
    } else if (g.waiting) {
      status = 'ESPERANDO';
      detail = '${g.seats.length} de 6 · ${g.owner ? 'você começa' : 'quem criou começa'}';
    } else {
      status = g.youWon ? 'VITÓRIA' : (g.winner.isNotEmpty ? 'VENCEU ${g.winner.toUpperCase()}' : 'ENCERRADA');
      detail = _ago(g.updatedMs);
      if (g.youWon) statusColor = AppColors.medal;
    }
    final sub = [
      '#${g.id}',
      if (g.playing || g.over) 'rodada ${g.round}',
      if (g.seats.any((s) => s.bot)) '${g.seats.where((s) => s.bot).length} bot${g.seats.where((s) => s.bot).length > 1 ? 's' : ''}',
    ].join(' · ');

    // régua do prazo: o que sobra das 24 h
    double frac = 0;
    if (g.playing && g.deadlineMs > 0) {
      frac = ((g.deadlineMs - DateTime.now().millisecondsSinceEpoch) / corrTurnMs).clamp(0.0, 1.0);
    }

    return Opacity(
      opacity: g.over ? 0.72 : 1,
      child: Material(
        color: mine ? AppColors.panel2 : AppColors.panel,
        borderRadius: BorderRadius.circular(Radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: mine ? AppColors.glassBorder : AppColors.line),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 74,
                        child: Wrap(
                          spacing: 1,
                          runSpacing: 1,
                          children: [
                            for (final s in g.seats)
                              Opacity(
                                opacity: s.bot ? 0.5 : 1,
                                child: EstFactionSeal(
                                  color: parseHexColor(colors[s.color % colors.length].hex),
                                  size: 13,
                                  highlighted: s.you,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _names(g.seats),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.number(size: 12.5, color: AppColors.faint, weight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(size: 12.5, color: statusColor, weight: FontWeight.w700),
                            ),
                          ),
                          if (detail.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                          ],
                        ],
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
                    ],
                  ),
                ),
                if (g.playing)
                  SizedBox(
                    height: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: frac,
                        heightFactor: 1,
                        child: ColoredBox(color: mine ? AppColors.ink : AppColors.glassBorder),
                      ),
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

/// Convite de um amigo: quem chamou, quem já está na sala, Entrar ou recusar.
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.ctrl, required this.invite});

  final AppController ctrl;
  final AsyncInviteInfo invite;

  @override
  Widget build(BuildContext context) {
    final colors = ctrl.engine.constants.colors;
    final inv = invite;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Wrap(
              spacing: 1,
              runSpacing: 1,
              children: [
                for (final s in inv.seats)
                  EstFactionSeal(color: parseHexColor(colors[s.color % colors.length].hex), size: 13),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${inv.from} te chamou',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '#${inv.id} · ${inv.seats.length} de 6',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.number(size: 12.5, color: AppColors.faint, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          EstButton(small: true, label: 'Entrar', onPressed: () => ctrl.openCorrGame(inv.id)),
          const SizedBox(width: 6),
          EstIconButton(
            icon: EstIconKind.close,
            size: 32,
            iconSize: 12,
            tooltip: 'Recusar',
            onPressed: () => ctrl.declineCorrInvite(inv.id),
          ),
        ],
      ),
    );
  }
}

/// Primeira vez: como funciona, em três passos curtos.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('1', 'Crie e mande o código', 'Nova partida abre uma sala de espera. Quem tiver o código ou o link entra.'),
      ('2', 'Cada um joga quando puder', 'Até 24 h para cada jogada. Pode fechar o jogo: a partida fica no servidor.'),
      ('3', 'Avisamos quando for a sua vez', 'Chega um e-mail. Três prazos perdidos seguidos e um bot assume o seu lugar.'),
    ];
    final items = [
      for (final (n, t, d) in steps)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(n, style: AppText.number(size: 22, color: AppColors.faint, weight: FontWeight.w700)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Text(d, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute)),
                ],
              ),
            ),
          ],
        ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: AppColors.line),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 28),
                  Expanded(child: items[i]),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  items[i],
                ],
              ],
            ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.bad = false});

  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: bad ? AppColors.bad : AppColors.mute),
        ),
      );
}
