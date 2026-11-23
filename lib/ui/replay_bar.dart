import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../platform/web_env.dart';
import 'theme.dart';

/// Controles do replay, no lugar da barra de ação: voltar/avançar turno e passo, tocar/pausar, velocidade, a régua
/// dos turnos e o selo dos dados verificados.
class ReplayBar extends StatelessWidget {
  const ReplayBar({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  Widget build(BuildContext context) {
    final r = ctrl.replay;
    final v = ctrl.view;
    if (r == null || v == null) return const SizedBox.shrink();
    final players = v['players'] as List<dynamic>;
    final colors = ctrl.engine.constants.colors;
    final over = v['phase'] == 'over';
    final turnIdx = (v['turn'] as num).toInt();
    final cur = players[turnIdx] as Map<String, dynamic>;
    final curCol = parseHexColor(colors[(cur['color'] as num).toInt()].hex);
    final round = (v['round'] as num).toInt() + 1;
    final lastRound = r.turns.isEmpty ? round : r.turns.last.round + 1;

    Widget btn(IconData icon, String tip, VoidCallback onTap, {bool big = false}) => Tooltip(
          message: tip,
          child: Material(
            color: big ? AppColors.action : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(
                width: big ? 44 : 36,
                height: big ? 40 : 36,
                child: Icon(icon, size: big ? 24 : 20, color: big ? AppColors.onAction : AppColors.ink),
              ),
            ),
          ),
        );

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        activeTrackColor: AppColors.ink,
        inactiveTrackColor: AppColors.line,
        thumbColor: AppColors.ink,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      child: Slider(
        value: r.steps == 0 ? 0 : r.pos / r.steps,
        onChanged: r.steps == 0
            ? null
            : (x) {
                if (r.playing) ctrl.replayToggle();
                ctrl.replayGoTo((x * r.steps).round());
              },
      ),
    );

    // celular deitado: uma linha só, para o mapa ficar à vista
    if (MediaQuery.sizeOf(context).height <= 520) {
      return Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppColors.edgeShadows,
        ),
        child: Row(
          children: [
            btn(Icons.skip_previous_rounded, 'Turno anterior', () => ctrl.replayTurn(-1)),
            btn(r.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, r.playing ? 'Pausar' : 'Tocar',
                ctrl.replayToggle,
                big: true),
            btn(Icons.skip_next_rounded, 'Próximo turno', () => ctrl.replayTurn(1)),
            const SizedBox(width: 10),
            Expanded(child: slider),
            const SizedBox(width: 10),
            Text(over ? 'FIM' : 'R$round/$lastRound', style: AppText.number(size: 13, weight: FontWeight.w700)),
            const SizedBox(width: 6),
            TextButton(
              onPressed: ctrl.replaySpeed,
              style: TextButton.styleFrom(minimumSize: const Size(40, 36), padding: EdgeInsets.zero),
              child: Text('${r.speed}×', style: AppText.number(size: 14, weight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Dados verificados',
              onPressed: () => showReplayProofSheet(context, ctrl),
              icon: const Icon(Icons.verified_outlined, size: 18, color: AppColors.ink),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
          Row(
            children: [
              Text('REPLAY', style: AppText.label(size: 11, color: AppColors.faint)),
              const SizedBox(width: 8),
              Text('#${r.code}', style: AppText.number(size: 12, color: AppColors.faint)),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    if (!over) ...[
                      EstFactionSeal(color: curCol, size: 11),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        over ? 'Fim da partida · rodada $round' : 'Rodada $round de $lastRound · ${cur['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
              _VerifiedChip(onTap: () => showReplayProofSheet(context, ctrl)),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Compartilhar o replay',
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  onTap: () async {
                    final url = '${WebEnv.getBaseUrl()}?replay=${r.code}';
                    final shared = await WebEnv.shareOrCopy(title: 'Replay do Ultimato', text: 'Replay da partida', url: url);
                    if (!shared) ctrl.showToast('Link do replay copiado.');
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.ios_share_rounded, size: 17, color: AppColors.ink),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          slider,
          const SizedBox(height: 4),
          Row(
            children: [
              btn(Icons.skip_previous_rounded, 'Turno anterior', () => ctrl.replayTurn(-1)),
              btn(Icons.chevron_left_rounded, 'Passo anterior', () => ctrl.replayStep(-1)),
              const SizedBox(width: 4),
              btn(r.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, r.playing ? 'Pausar' : 'Tocar',
                  ctrl.replayToggle,
                  big: true),
              const SizedBox(width: 4),
              btn(Icons.chevron_right_rounded, 'Próximo passo', () => ctrl.replayStep(1)),
              btn(Icons.skip_next_rounded, 'Próximo turno', () => ctrl.replayTurn(1)),
              const Spacer(),
              Text('${r.pos}/${r.steps}', style: AppText.number(size: 12, color: AppColors.faint)),
              const SizedBox(width: 10),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.sm),
                child: InkWell(
                  onTap: ctrl.replaySpeed,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Text('${r.speed}×', style: AppText.number(size: 14, weight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_outlined, size: 15, color: AppColors.ink),
              const SizedBox(width: 5),
              Text('DADOS VERIFICADOS', style: AppText.label(size: 11, color: AppColors.ink)),
            ],
          ),
        ),
      );
}

String _short(String h) => h.length <= 16 ? h : '${h.substring(0, 8)}…${h.substring(h.length - 8)}';

/// O que foi conferido no replay, para quem quiser checar por conta própria.
void showReplayProofSheet(BuildContext context, AppController ctrl) {
  final r = ctrl.replay;
  final commit = r?.commit ?? ctrl.matchCommit ?? '';
  final server = r?.server ?? '';
  final mine = commit.isNotEmpty && ctrl.contributedTo(commit);
  final dev = ctrl.devicePub;
  Widget kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: AppText.label(size: 11))),
            Expanded(
              child: SelectableText(v, style: AppText.number(size: 13, color: AppColors.ink, weight: FontWeight.w500)),
            ),
          ],
        ),
      );
  final daily = r?.meta['mode'] == 'daily';
  String who(Map<String, dynamic> rp) {
    int n(String k) => (rp[k] as num?)?.toInt() ?? 0;
    final parts = <String>[
      if (n('signed') > 0) '${n('signed')} assinadas',
      if (n('unsigned') > 0) daily ? '${n('unsigned')} jogadas' : '${n('unsigned')} sem assinatura',
      if (n('bot') > 0) '${n('bot')} pelo bot',
      if (n('timeout') > 0) '${n('timeout')} no prazo esgotado',
      if (n('devices') > 1) 'trocou de aparelho',
    ];
    return parts.isEmpty ? 'nenhuma jogada' : parts.join(' · ');
  }

  showEstSheet<void>(
    context,
    maxWidth: 560,
    builder: (ctx) => EstSheetBody(
      title: r != null ? 'Dados verificados' : 'Dados verificáveis',
      onClose: () => Navigator.pop(ctx),
      children: [
        Text(
          daily
              ? 'Desafio do dia: o servidor entregou a semente dos dados no início da corrida e, no envio, refez a '
                  'partida inteira com o tabuleiro dele. O resultado e as estrelas do ranking são os que ele apurou. As '
                  'jogadas dos bots foram conferidas por serem exatamente as que o jogo faria.'
              : r != null
              ? 'O servidor fixou a semente secreta antes da partida e publicou o compromisso na sala de espera; cada '
                  'aparelho contribuiu depois de vê-lo. No fim, a semente revelada bate com o compromisso, e a partida '
                  'refeita aqui chega ao mesmo resultado. Cada jogada foi conferida: as dos jogadores pela assinatura do '
                  'aparelho deles; as do bot e as de prazo esgotado por serem exatamente as que o jogo faria.'
              : 'O servidor já se comprometeu com a semente secreta desta partida, antes das contribuições dos '
                  'aparelhos. Ela é revelada no fim, no replay, e qualquer um confere os dados e as jogadas.',
          style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.mute),
        ),
        const SizedBox(height: 14),
        kv('COMPROMISSO', _short(commit)),
        if (server.isNotEmpty) kv('SEMENTE', _short(server)),
        if (mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Este aparelho contribuiu depois de ver este compromisso.',
              style: AppText.label(size: 11, color: AppColors.ink),
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: 6),
          for (final p in r.proof) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p['name']}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                ),
                if (dev != null && (p['keys'] as List<dynamic>? ?? const []).contains(dev))
                  Text('ESTE APARELHO', style: AppText.label(size: 10.5, color: AppColors.ink)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              who(Map<String, dynamic>.from(p['report'] as Map? ?? const {})),
              style: const TextStyle(fontSize: 12.5, color: AppColors.mute),
            ),
            const SizedBox(height: 10),
          ],
        ],
        Text(
          'Conta: SHA-256(semente) = compromisso; dados = ChaCha8 com SHA-256(semente, contribuições); '
          'jogadas assinadas com Ed25519.',
          style: AppText.label(size: 10.5, color: AppColors.faint),
        ),
      ],
    ),
  );
}
