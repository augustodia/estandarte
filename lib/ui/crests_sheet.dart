import 'package:flutter/material.dart';

import '../game/app_controller.dart';
import '../game/crests.dart';
import '../game/daily_challenge.dart';
import 'crest_badge.dart';
import 'theme.dart';

/// Coleção de brasões: as dez crônicas das Quintas Históricas (no metal da melhor campanha) e as insígnias.
/// Com conta, tocar num brasão conquistado o põe ao lado do nome nas salas, partidas, amigos e ranking.
void showCrestsSheet(BuildContext context, AppController c, {VoidCallback? onSignIn}) {
  showEstSheet<void>(
    context,
    maxWidth: 620,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) => EstSheetBody(
        title: 'Brasões',
        titleIcon: const EstIcon(EstIconKind.crest, size: 18, color: AppColors.mute),
        onClose: () => Navigator.pop(ctx),
        children: [_CrestsBody(ctrl: c, onSignIn: onSignIn == null ? null : () {
          Navigator.pop(ctx);
          onSignIn();
        })],
      ),
    ),
  );
}

class _CrestsBody extends StatefulWidget {
  const _CrestsBody({required this.ctrl, this.onSignIn});

  final AppController ctrl;
  final VoidCallback? onSignIn;

  @override
  State<_CrestsBody> createState() => _CrestsBodyState();
}

class _CrestsBodyState extends State<_CrestsBody> {
  String? _busy; // brasão sendo gravado
  String? _error;

  Future<void> _pick(String crest) async {
    final c = widget.ctrl;
    if (!c.signedIn || _busy != null) return;
    final next = c.account?.crest == crest ? '' : crest; // tocar no escolhido tira
    setState(() {
      _busy = crest;
      _error = null;
    });
    final err = await c.setCrest(next);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final codex = c.codexProgress;
    final current = c.signedIn ? (c.account?.crest ?? '') : '';
    final gotChron = chroniclesWith(codex, 1);
    final gotIns = insigniaCatalog.where((i) => crestEarned(codex, i.id)).length;

    Widget tile({required String crest, required String title, required String sub, required bool got}) {
      final selected = got && crest == current;
      final busy = _busy == crest;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: got && c.signedIn ? () => _pick(crest) : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: crestTileDecoration(selected: selected, earned: got),
            child: Column(
              children: [
                Opacity(
                  opacity: busy ? 0.4 : 1,
                  child: CrestBadge(crest, size: 40, locked: !got),
                ),
                const SizedBox(height: 7),
                Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: got ? AppColors.ink : AppColors.mute,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  selected ? 'Em destaque' : sub,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.ink : AppColors.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget grid(List<Widget> tiles) => LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final cols = box.maxWidth >= 500 ? 4 : 3;
            final tw = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final t in tiles) SizedBox(width: tw, child: t)],
            );
          },
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Cada crônica das Quintas Históricas dá um brasão. O metal mostra a sua melhor campanha: '
          'bronze ★, prata ★★, ouro ★★★. Vale a partida jogada com conta e internet, que o servidor confere.',
          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
        ),
        const SizedBox(height: 6),
        Text(
          c.signedIn
              ? 'Toque num brasão conquistado para exibi-lo ao lado do seu nome nas salas, partidas, amigos e ranking.'
              : 'Com conta, o brasão escolhido aparece ao lado do seu nome nas salas, partidas, amigos e ranking.',
          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
        ),
        const SizedBox(height: 14),
        EstSectionTag('CRÔNICAS · $gotChron / ${historicalCodexCatalog.length}'),
        const SizedBox(height: 8),
        grid([
          for (final m in historicalCodexCatalog)
            () {
              final s = verifiedStars(codex, m.id);
              final played = codexStars(codex, m.id);
              return tile(
                crest: s > 0 ? '${m.id}:$s' : '${m.id}:1',
                title: m.title,
                sub: s > 0
                    ? '${tierNames[s]} · ${m.era}'
                    : (played > 0 ? 'Jogada sem conferir · ${m.era}' : 'Quinta-feira · ${m.era}'),
                got: s > 0,
              );
            }(),
        ]),
        const SizedBox(height: 16),
        EstSectionTag('INSÍGNIAS · $gotIns / ${insigniaCatalog.length}'),
        const SizedBox(height: 8),
        grid([
          for (final i in insigniaCatalog)
            () {
              final got = crestEarned(codex, i.id);
              final have = chroniclesWith(codex, i.stars);
              return tile(
                crest: i.id,
                title: i.title,
                sub: got ? i.rule : '${i.rule} ($have/${i.count})',
                got: got,
              );
            }(),
        ]),
        const SizedBox(height: 16),
        const EstSectionTag('COMANDANTE'),
        const SizedBox(height: 8),
        grid([
          for (final i in shopInsignias)
            () {
              final got = i.id == 'ins_fundador' ? c.signedIn && c.ent.fundador > 0 : c.isComandante;
              return tile(
                crest: i.id,
                title: i.id == 'ins_fundador' && got ? 'Fundador nº ${c.ent.fundador}' : i.title,
                sub: got ? i.rule : 'Na loja',
                got: got,
              );
            }(),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.bad)),
        ],
        if (!c.signedIn && widget.onSignIn != null) ...[
          const SizedBox(height: 14),
          EstButton(label: 'Entrar para exibir', onPressed: widget.onSignIn),
        ] else if (c.signedIn && current.isNotEmpty) ...[
          const SizedBox(height: 14),
          EstButton(
            variant: EstButtonVariant.ghost,
            label: 'Não exibir brasão',
            onPressed: _busy != null ? null : () => _pick(current),
          ),
        ],
      ],
    );
  }
}
