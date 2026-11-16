import 'dart:math';

import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../engine/game_engine.dart';
import '../game/app_controller.dart';
import 'theme.dart';

// Quartel: a janela das medalhas e das ordens táticas (partidas com a opção "Quartel", que troca as cartas).
// Tudo o que aparece aqui vem do motor de regras: custos, o que está aberto e por que algo não pode ser comprado.

const _title = Color(0xFFFFF3DC);

void showQuartelModal(BuildContext context, AppController ctrl) {
  if (ctrl.view == null || ctrl.eval?.hq == null) return;

  // Estado da janela (fica fora do builder para sobreviver às atualizações da partida).
  String? picking; // ordem cujo alvo está sendo escolhido: airlift, trench, spy, sabotage
  int? airFrom;
  int? airTo;
  var airN = 1;

  showEstSheet<void>(
    context,
    builder: (ctx) => ListenableBuilder(
      listenable: ctrl,
      builder: (ctx, _) => StatefulBuilder(
        builder: (ctx, setState) {
          final v = ctrl.view;
          final ev = ctrl.eval;
          final hq = ev?.hq;
          if (v == null || ev == null || hq == null) {
            return EstSheetBody(
              title: 'Quartel',
              onClose: () => Navigator.pop(ctx),
              children: const [
                Text('Esta partida não usa o Quartel.', style: TextStyle(fontSize: 14, color: AppColors.mute)),
              ],
            );
          }
          final players = v['players'] as List<dynamic>;
          final terr = v['terr'] as List<dynamic>;
          final colors = ctrl.engine.constants.colors;
          final me = ctrl.me;
          final hasMe = me >= 0 && me < players.length;
          final medals = hasMe ? ctrl.medalsOf(me) : 0;
          final myTurn = hasMe && ctrl.canPlayNow() && (v['turn'] as num).toInt() == me;
          final canAct = myTurn && v['step'] == 'reinforce';

          Color colorOf(int p) =>
              parseHexColor(colors[((players[p] as Map<String, dynamic>)['color'] as num).toInt()].hex);
          String nameOf(int p) => '${(players[p] as Map<String, dynamic>)['name'] ?? ''}';
          int armies(int t) => ((terr[t] as Map<String, dynamic>)['a'] as num).toInt();
          int owner(int t) => ((terr[t] as Map<String, dynamic>)['o'] as num).toInt();
          String terrName(int t) => ctrl.mapData.territories[t].name;

          final mine = <int>[
            for (var t = 0; t < terr.length; t++)
              if (hasMe && owner(t) == me) t,
          ]..sort((a, b) => terrName(a).compareTo(terrName(b)));
          final foes = <int>[
            for (var p = 0; p < players.length; p++)
              if (p != me && (players[p] as Map<String, dynamic>)['alive'] == true) p,
          ];

          void back() => setState(() {
                picking = null;
                airFrom = null;
                airTo = null;
                airN = 1;
              });

          Widget sectionTitle(String text) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(text, style: AppText.serif(size: 19, color: _title)),
              );

          Widget note(String text) => Text(text, style: const TextStyle(fontSize: 13.5, color: AppColors.mute));

          Widget card({required List<Widget> children, Color border = AppColors.line}) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.deep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              );

          Widget costTag(int cost) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x33E2B04A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x88E2B04A)),
                ),
                child: Text(
                  '$cost medalha${cost == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFFFE2A3)),
                ),
              );

          Widget chips(List<Widget> items) => Wrap(spacing: 6, runSpacing: 6, children: items);

          Widget terrChip(int t, VoidCallback? onTap, {bool on = false}) => EstButton(
                small: true,
                variant: on ? EstButtonVariant.primary : EstButtonVariant.normal,
                label: '${terrName(t)} (${armies(t)})',
                onPressed: onTap,
              );

          // ---------------- escolha do alvo de uma ordem ----------------
          List<Widget> picker(HqOrder o) {
            final out = <Widget>[
              Row(
                children: [
                  Expanded(child: Text(o.name, style: AppText.serif(size: 19, color: _title))),
                  costTag(o.cost),
                ],
              ),
              const SizedBox(height: 6),
              note(o.desc),
              const SizedBox(height: 10),
            ];
            switch (o.key) {
              case 'spy' || 'sabotage':
                final blocks = o.key == 'spy' ? hq.spyBlocks : hq.sabotageBlocks;
                for (final q in foes) {
                  final why = blocks[q] ?? '';
                  out.add(
                    card(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(color: colorOf(q), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                nameOf(q),
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colorOf(q)),
                              ),
                            ),
                            EstButton(
                              small: true,
                              variant: EstButtonVariant.primary,
                              label: o.key == 'spy' ? 'Espionar' : 'Sabotar',
                              onPressed: why.isEmpty
                                  ? () {
                                      Navigator.pop(ctx);
                                      if (o.key == 'spy') {
                                        ctrl.orderSpy(q);
                                      } else {
                                        ctrl.orderSabotage(q);
                                      }
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        if (why.isNotEmpty) ...[const SizedBox(height: 4), note(why)],
                      ],
                    ),
                  );
                }
              case 'trench':
                final free = mine.where((t) => !hq.trenchBlocks.containsKey(t)).toList();
                out.add(note('Escolha o território que ficará protegido:'));
                out.add(const SizedBox(height: 8));
                out.add(
                  chips([
                    for (final t in free)
                      terrChip(t, () {
                        Navigator.pop(ctx);
                        ctrl.orderTrench(t);
                      }),
                  ]),
                );
              case 'airlift':
                final from = airFrom;
                final to = airTo;
                if (from == null || owner(from) != me || armies(from) < 2) {
                  final srcs = mine.where((t) => !hq.airliftBlocks.containsKey(t)).toList();
                  out.add(note('De onde saem os exércitos? (um sempre fica)'));
                  out.add(const SizedBox(height: 8));
                  if (srcs.isEmpty) {
                    out.add(note('Nenhum território seu tem 2 exércitos ou mais.'));
                  } else {
                    out.add(
                      chips([
                        for (final t in srcs)
                          terrChip(
                            t,
                            () => setState(() {
                              airFrom = t;
                              airTo = null;
                              airN = armies(t) - 1;
                            }),
                          ),
                      ]),
                    );
                  }
                } else {
                  final maxN = armies(from) - 1;
                  final n = min(max(1, airN), maxN);
                  out.add(
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 14, color: AppColors.mute),
                        children: [
                          const TextSpan(text: 'Origem: '),
                          TextSpan(
                            text: '${terrName(from)} (${armies(from)})',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                          ),
                          const TextSpan(text: '. Para onde vão?'),
                        ],
                      ),
                    ),
                  );
                  out.add(const SizedBox(height: 8));
                  out.add(
                    chips([
                      for (final t in mine)
                        if (t != from) terrChip(t, () => setState(() => airTo = t), on: t == to),
                    ]),
                  );
                  out.add(const SizedBox(height: 10));
                  out.add(
                    Row(
                      children: [
                        EstButton(
                          small: true,
                          label: '−',
                          onPressed: n > 1 ? () => setState(() => airN = n - 1) : null,
                        ),
                        Expanded(
                          child: Text(
                            '$n exército${n == 1 ? '' : 's'}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                          ),
                        ),
                        EstButton(
                          small: true,
                          label: '+',
                          onPressed: n < maxN ? () => setState(() => airN = n + 1) : null,
                        ),
                        const SizedBox(width: 6),
                        EstButton(
                          small: true,
                          label: 'Máx',
                          onPressed: n < maxN ? () => setState(() => airN = maxN) : null,
                        ),
                      ],
                    ),
                  );
                  out.add(const SizedBox(height: 10));
                  out.add(
                    EstButton(
                      variant: EstButtonVariant.primary,
                      label: to == null ? 'Escolha o destino' : 'Levar $n para ${terrName(to)}',
                      onPressed: to == null
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              ctrl.orderAirlift(from, to, n);
                            },
                    ),
                  );
                }
            }
            out.add(const SizedBox(height: 10));
            out.add(EstButton(label: 'Voltar', onPressed: back));
            return out;
          }

          HqOrder? pickingOrder;
          for (final o in hq.orders) {
            if (o.key == picking && o.block.isEmpty && canAct) pickingOrder = o;
          }
          if (pickingOrder != null) {
            return EstSheetBody(title: 'Quartel', onClose: () => Navigator.pop(ctx), children: picker(pickingOrder));
          }

          // ---------------- visão geral ----------------
          final seen = hasMe
              ? ((players[me] as Map<String, dynamic>)['seen'] as List<dynamic>? ?? const [])
                  .map((e) => (e as num).toInt())
                  .where((q) => q >= 0 && q < players.length)
                  .toList()
              : <int>[];
          final trenches = v['trenches'] as List<dynamic>? ?? const [];

          return EstSheetBody(
            title: 'Quartel',
            onClose: () => Navigator.pop(ctx),
            children: [
              if (hasMe) ...[
                Row(
                  children: [
                    for (var i = 0; i < hq.medalMax; i++)
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: i < medals
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFFF7D98A), Color(0xFFC98F26)],
                                )
                              : null,
                          color: i < medals ? null : AppColors.deep,
                          border: Border.all(color: i < medals ? const Color(0xFFF3CD78) : AppColors.line, width: 1.5),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$medals de ${hq.medalMax} medalhas',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              note(
                'Você ganha 1 medalha na primeira conquista do turno, +1 ao fechar um continente e +2 ao eliminar alguém. '
                'Guarde até ${hq.medalMax} e gaste no início do seu turno, antes de terminar o reforço.',
              ),
              const SizedBox(height: 12),
              sectionTitle('Mobilização'),
              card(
                border: const Color(0x88E2B04A),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 14, color: AppColors.mute),
                            children: [
                              const TextSpan(text: 'Esforço de guerra: vale '),
                              TextSpan(
                                text: '${hq.effort} exércitos',
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                              ),
                              const TextSpan(text: ' agora e sobe a cada rodada.'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      costTag(hq.mobilizeCost),
                    ],
                  ),
                  if (hasMe) ...[
                    const SizedBox(height: 10),
                    EstButton(
                      variant: EstButtonVariant.primary,
                      label: 'Mobilizar +${hq.effort}',
                      onPressed: canAct && hq.mobilizeBlock.isEmpty ? ctrl.mobilize : null,
                    ),
                    if (myTurn && hq.mobilizeBlock.isNotEmpty) ...[const SizedBox(height: 6), note(hq.mobilizeBlock)],
                  ],
                ],
              ),
              const SizedBox(height: 4),
              sectionTitle('Ordens abertas'),
              note('Abertas para todos. Cada jogador compra no máximo uma por turno; a comprada dá lugar a outra.'),
              const SizedBox(height: 8),
              for (final o in hq.orders)
                card(
                  border: o.key == 'nuke' ? AppColors.rad.withValues(alpha: 0.45) : AppColors.line,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: o.key == 'nuke' ? AppColors.rad : AppColors.ink,
                            ),
                          ),
                        ),
                        costTag(o.cost),
                      ],
                    ),
                    const SizedBox(height: 4),
                    note(
                      o.key == 'nuke'
                          ? '${o.desc} Hoje destrói ${ev.nukeDamage} exércitos (sempre sobra 1).'
                          : o.desc,
                    ),
                    if (hasMe) ...[
                      const SizedBox(height: 8),
                      EstButton(
                        small: true,
                        variant: o.key == 'nuke' ? EstButtonVariant.rad : EstButtonVariant.normal,
                        label: o.key == 'nuke' ? 'Escolher alvo no mapa' : 'Usar',
                        onPressed: canAct && o.block.isEmpty
                            ? () {
                                if (o.key == 'nuke') {
                                  Navigator.pop(ctx);
                                  ctrl.toggleNukeMode(true);
                                } else {
                                  setState(() => picking = o.key);
                                }
                              }
                            : null,
                      ),
                      if (myTurn && o.block.isNotEmpty) ...[const SizedBox(height: 6), note(o.block)],
                    ],
                  ],
                ),
              if (seen.isNotEmpty) ...[
                const SizedBox(height: 4),
                sectionTitle('Objetivos espionados'),
                for (final q in seen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 14, color: AppColors.ink),
                        children: [
                          TextSpan(
                            text: '${nameOf(q)}: ',
                            style: TextStyle(fontWeight: FontWeight.w700, color: colorOf(q)),
                          ),
                          TextSpan(text: ev.objectiveTexts[q] ?? '—'),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              sectionTitle('Na mesa'),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 14, color: AppColors.mute),
                  children: [
                    for (var p = 0; p < players.length; p++)
                      if ((players[p] as Map<String, dynamic>)['alive'] == true) ...[
                        TextSpan(
                          text: nameOf(p),
                          style: TextStyle(fontWeight: FontWeight.w700, color: colorOf(p)),
                        ),
                        TextSpan(
                          text: ' ${ctrl.medalsOf(p)}'
                              '${(players[p] as Map<String, dynamic>)['sabotaged'] == true ? ' (sabotado)' : ''}'
                              '   ',
                        ),
                      ],
                  ],
                ),
              ),
              if (trenches.isNotEmpty) ...[
                const SizedBox(height: 6),
                note(
                  'Trincheiras: ${trenches.map((x) {
                    final m = x as Map<String, dynamic>;
                    return '${terrName((m['t'] as num).toInt())} (${nameOf((m['by'] as num).toInt())})';
                  }).join(', ')}.',
                ),
              ],
              const SizedBox(height: 12),
              EstButton(label: 'Fechar', onPressed: () => Navigator.pop(ctx)),
            ],
          );
        },
      ),
    ),
  );
}
