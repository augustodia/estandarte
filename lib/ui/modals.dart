import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../platform/p2p.dart';
import '../platform/qr_scanner.dart';
import '../platform/sound.dart';
import '../platform/web_env.dart';
import 'theme.dart';

int _ownedCount(Map<String, dynamic> v, int playerIdx) {
  final terrs = v['terr'] as List<dynamic>;
  var n = 0;
  for (final t in terrs) {
    if ((t['o'] as num).toInt() == playerIdx) n++;
  }
  return n;
}

int _handSize(Map<String, dynamic> p) {
  final raw = p['cards'];
  if (raw is List) return raw.length;
  if (raw is num) return raw.toInt();
  return 0;
}

// ---------- 1. Objective Modal ----------

void showObjectiveModal(BuildContext context, AppController ctrl) {
  final v = ctrl.view;
  final ev = ctrl.eval;
  if (v == null || ev == null) return;
  final players = v['players'] as List<dynamic>;
  if (ctrl.me < 0 || ctrl.me >= players.length) return;
  final meP = players[ctrl.me] as Map<String, dynamic>;
  final col = parseHexColor(
    ctrl.engine.constants.colors[(meP['color'] as num).toInt()].hex,
  );
  final owned = _ownedCount(v, ctrl.me);
  final total = ctrl.mapData.territories.length;
  final pct = (owned / max(1, total)).clamp(0.0, 1.0);
  final text = ev.objectiveTexts[ctrl.me] ?? '—';

  showEstSheet<void>(
    context,
    builder: (ctx) => EstSheetBody(
      children: [
        Text(
          'Objetivo de ${meP['name'] ?? ''}',
          style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC)),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          style: const TextStyle(fontSize: 16, height: 1.4, color: AppColors.ink),
        ),
        const SizedBox(height: 12),
        _DomainMeter(fraction: pct, color: col),
        const SizedBox(height: 10),
        Text(
          'Mantenha em segredo. Territórios: $owned de $total.',
          style: const TextStyle(fontSize: 14, color: AppColors.mute),
        ),
        const SizedBox(height: 12),
        EstButton(label: 'Fechar', onPressed: () => Navigator.pop(ctx)),
      ],
    ),
  );
}

class _DomainMeter extends StatelessWidget {
  const _DomainMeter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.deep,
        borderRadius: BorderRadius.circular(5),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, val, _) => FractionallySizedBox(
          widthFactor: val,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, Color.lerp(color, Colors.white, 0.4)!],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- 2. Playing Cards Modal ----------

void showCardsModal(BuildContext context, AppController ctrl) {
  final v = ctrl.view;
  final ev = ctrl.eval;
  if (v == null || ev == null) return;
  final players = v['players'] as List<dynamic>;
  if (ctrl.me < 0 || ctrl.me >= players.length) return;
  final meP = players[ctrl.me] as Map<String, dynamic>;
  final rawCards = meP['cards'];
  final cards = rawCards is List<dynamic> ? rawCards.map((e) => (e as num).toInt()).toList() : <int>[];
  final canTrade = ctrl.canPlayNow() &&
      (v['turn'] as num).toInt() == ctrl.me &&
      v['step'] == 'reinforce';
  final picked = <int>{};

  showEstSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final chosen = picked.toList();
        final ok = canTrade && chosen.length == 3 && ctrl.engine.validTrade(chosen);
        return EstSheetBody(
          children: [
            Text(
              'Cartas (${cards.length})',
              style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC)),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.mute),
                children: [
                  const TextSpan(
                    text:
                        'Troque 3 símbolos iguais ou 3 diferentes (★ vale qualquer um) no início do seu turno. Próxima troca vale ',
                  ),
                  TextSpan(
                    text: '${ev.tradeValue}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const TextSpan(
                    text: ' exércitos; cartas de territórios seus dão +2 neles. Com 5 cartas a troca é automática.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (cards.isEmpty)
              const Text(
                'Nenhuma carta ainda. Conquiste um território no turno para ganhar uma.',
                style: TextStyle(fontSize: 14, color: AppColors.mute),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 118,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 94,
                ),
                itemCount: cards.length,
                itemBuilder: (_, idx) {
                  final c = cards[idx];
                  final info = ctrl.engine.cardInfo(c);
                  final isOn = picked.contains(c);
                  final rot = isOn ? 0.0 : (idx.isEven ? -0.0175 : 0.0175);
                  return Transform.rotate(
                    angle: rot,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      transform: Matrix4.translationValues(0, isOn ? -6 : 0, 0),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFBF3E1), Color(0xFFE9DCC0)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isOn ? AppColors.gold : const Color(0xFFC9B48A),
                          width: isOn ? 3 : 2,
                        ),
                        boxShadow: isOn
                            ? const [
                                BoxShadow(color: Color(0xAA000000), blurRadius: 18, offset: Offset(0, 8)),
                                BoxShadow(color: Color(0x99E2B04A), spreadRadius: 3),
                              ]
                            : const [
                                BoxShadow(color: Color(0x77000000), blurRadius: 8, offset: Offset(0, 3)),
                              ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              if (picked.contains(c)) {
                                picked.remove(c);
                              } else if (picked.length < 3) {
                                picked.add(c);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0x66FFFFFF), width: 1.5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CustomPaint(painter: _CardSymbolPainter(info.symbol)),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  info.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                    color: Color(0xFF1C1408),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: EstButton(
                    label: 'Trocar selecionadas',
                    variant: EstButtonVariant.primary,
                    onPressed: ok
                        ? () {
                            Navigator.pop(ctx);
                            ctrl.tradeCards(chosen);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstButton(label: 'Fechar', onPressed: () => Navigator.pop(ctx)),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _CardSymbolPainter extends CustomPainter {
  const _CardSymbolPainter(this.symbol);

  final int symbol;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s, s);
    final p = Paint()
      ..color = const Color(0xFF2A1F0E)
      ..style = PaintingStyle.fill;
    if (symbol == 0) {
      canvas.drawCircle(const Offset(12, 12), 9.5, p);
    } else if (symbol == 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(3.5, 3.5, 17, 17), const Radius.circular(1.5)),
        p,
      );
    } else if (symbol == 2) {
      canvas.drawPath(
        Path()
          ..moveTo(12, 2.5)
          ..lineTo(22, 20.5)
          ..lineTo(2, 20.5)
          ..close(),
        p,
      );
    } else {
      // Star (matching SYM_SVG[3])
      final star = Path()
        ..moveTo(12, 1.8)
        ..lineTo(15, 8.7)
        ..lineTo(22.5, 9.4)
        ..lineTo(16.8, 14.4)
        ..lineTo(18.5, 21.8)
        ..lineTo(12, 17.9)
        ..lineTo(5.5, 21.8)
        ..lineTo(7.2, 14.4)
        ..lineTo(1.5, 9.4)
        ..lineTo(9, 8.7)
        ..close();
      canvas.drawPath(star, p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CardSymbolPainter old) => old.symbol != symbol;
}

// ---------- 3. Extras Modal ----------

void showExtrasModal(BuildContext context, AppController ctrl) {
  final v = ctrl.view;
  final ev = ctrl.eval;
  if (v == null || ev == null) return;
  final opts = v['opts'] as Map<String, dynamic>? ?? const {};
  final players = v['players'] as List<dynamic>;
  final colors = ctrl.engine.constants.colors;
  final pacts = (v['pacts'] as List<dynamic>? ?? const []);
  final offer = v['offer'] as Map<String, dynamic>?;
  final myTurn = ctrl.canPlayNow() && (v['turn'] as num).toInt() == ctrl.me;
  final offerIsMine = offer != null &&
      (ctrl.role == 'guest'
          ? (offer['to'] as num).toInt() == ctrl.me
          : players[(offer['to'] as num).toInt()]['ctrl'] == 'local');

  TextSpan playerTag(int idx) {
    final p = players[idx] as Map<String, dynamic>;
    final c = parseHexColor(colors[(p['color'] as num).toInt()].hex);
    return TextSpan(
      text: '${p['name'] ?? ''}',
      style: TextStyle(fontWeight: FontWeight.w700, color: c),
    );
  }

  showEstSheet<void>(
    context,
    builder: (ctx) => EstSheetBody(
      title: 'Regras extras',
      onClose: () => Navigator.pop(ctx),
      children: [
        if (opts['events'] == true) ...[
          Text('Evento da rodada', style: AppText.serif(size: 19, color: const Color(0xFFFFF3DC))),
          const SizedBox(height: 6),
          if (v['event'] != null)
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 16, color: AppColors.ink),
                children: [
                  TextSpan(
                    text: '${eventTitles[v['event']['k']] ?? v['event']['k']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
                  ),
                  TextSpan(text: ' · ${ev.eventText}'),
                ],
              ),
            )
          else
            const Text(
              'Rodada calma: nenhum evento em vigor.',
              style: TextStyle(fontSize: 14, color: AppColors.mute),
            ),
          const SizedBox(height: 8),
          const Text(
            'Os eventos aparecem de surpresa, a partir da rodada 2: valem para todos por uma rodada e depois vem ao menos uma rodada calma.',
            style: TextStyle(fontSize: 14, color: AppColors.mute),
          ),
          const SizedBox(height: 8),
          for (final x in ctrl.engine.constants.events)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 13, color: AppColors.mute),
                  children: [
                    const TextSpan(text: '• '),
                    TextSpan(
                      text: '${x.name}: ',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    TextSpan(text: x.desc.replaceAll('América do Norte', 'um continente sorteado')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (opts['pacts'] == true) ...[
          Text('Pactos', style: AppText.serif(size: 19, color: const Color(0xFFFFF3DC))),
          const SizedBox(height: 6),
          if (pacts.isEmpty)
            const Text('Nenhum pacto em vigor.', style: TextStyle(fontSize: 14, color: AppColors.mute))
          else
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.mute),
                children: [
                  for (var i = 0; i < pacts.length; i++) ...[
                    if (i > 0) const TextSpan(text: '; '),
                    playerTag((pacts[i]['a'] as num).toInt()),
                    const TextSpan(text: ' e '),
                    playerTag((pacts[i]['b'] as num).toInt()),
                    TextSpan(text: ' até o fim da rodada ${(pacts[i]['until'] as num).toInt() + 1}'),
                  ],
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          if (offer != null) ...[
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.mute),
                children: [
                  playerTag((offer['from'] as num).toInt()),
                  const TextSpan(text: ' propôs um pacto a '),
                  playerTag((offer['to'] as num).toInt()),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          EstButton(
            variant: EstButtonVariant.pact,
            onPressed: () {
              Navigator.pop(ctx);
              if (offerIsMine) {
                showOfferModal(context, ctrl);
              } else {
                showPactsModal(context, ctrl);
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EstIcon(EstIconKind.pact, size: 16, color: Color(0xFFFFE2A3)),
                const SizedBox(width: 6),
                Text(
                  offerIsMine
                      ? 'Responder à proposta'
                      : myTurn
                          ? 'Abrir pactos (propor ou romper)'
                          : 'Ver pactos',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFE2A3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (opts['nukes'] == true) ...[
          Text('Ogiva nuclear', style: AppText.serif(size: 19, color: const Color(0xFFFFF3DC))),
          const SizedBox(height: 6),
          if (v['fog'] != null) ...[
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 16, color: AppColors.ink),
                children: [
                  TextSpan(
                    text: 'Névoa sobre ${ctrl.mapData.territories[(v['fog']['t'] as num).toInt()].name}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.rad),
                  ),
                  const TextSpan(text: ', lançada por '),
                  playerTag((v['fog']['by'] as num).toInt()),
                  const TextSpan(text: '. Dissipa quando a vez voltar para quem lançou.'),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 14, color: AppColors.mute),
              children: [
                const TextSpan(
                  text:
                      'No reforço, em vez de trocar 3 cartas por exércitos, você pode lançar a ogiva em qualquer território inimigo. Hoje ela destrói ',
                ),
                TextSpan(
                  text: '${ev.nukeDamage}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const TextSpan(
                  text:
                      ' exércitos, o dobro do valor da troca, sempre sobrando 1 no alvo. Não há sorteio.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final b in [
            'Você recebe 75% dos exércitos da troca (hoje ${ev.nukeRefund}) e joga o resto do turno normalmente.',
            'O território atingido fica radioativo: até a sua vez voltar, ninguém pode atacá-lo, nem você. O dono joga normalmente: reforça, ataca a partir dele e recebe o bônus do continente.',
            'Quando a névoa some, você é o primeiro a poder atacar ali.',
            'Só uma névoa no mapa por vez.',
            'A primeira troca de cada jogador é sempre normal, e depois de uma ogiva a troca seguinte também.',
            'O lançamento conta na escada: a próxima troca de qualquer jogador vale o degrau seguinte.',
            'O pacto de quem lança acaba na hora.',
          ])
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 3),
              child: Text('• $b', style: const TextStyle(fontSize: 13, color: AppColors.mute)),
            ),
          if (myTurn && ev.nukeBlock.isNotEmpty && v['step'] == 'reinforce') ...[
            const SizedBox(height: 6),
            Text(ev.nukeBlock, style: const TextStyle(fontSize: 13.5, color: AppColors.mute)),
          ],
          const SizedBox(height: 12),
        ],
        EstButton(
          label: 'Fechar',
          variant: EstButtonVariant.primary,
          onPressed: () => Navigator.pop(ctx),
        ),
      ],
    ),
  );
}

// ---------- 4. Pacts & Offer Modals ----------

class _PactPairWidget extends StatelessWidget {
  const _PactPairWidget({
    required this.ctrl,
    required this.a,
    required this.b,
    this.note,
    this.large = false,
  });

  final AppController ctrl;
  final int a;
  final int b;
  final String? note;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final v = ctrl.view!;
    final players = v['players'] as List<dynamic>;
    final colors = ctrl.engine.constants.colors;

    Widget side(int idx) {
      final p = players[idx] as Map<String, dynamic>;
      final col = parseHexColor(colors[(p['color'] as num).toInt()].hex);
      final name = '${p['name'] ?? ''}';
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      final terrs = _ownedCount(v, idx);
      final cards = _handSize(p);
      final avSize = large ? 52.0 : 40.0;
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: avSize,
              height: avSize,
              decoration: BoxDecoration(
                color: col,
                shape: BoxShape.circle,
                boxShadow: [
                  const BoxShadow(color: Color(0xFF0B1626), spreadRadius: 3),
                  BoxShadow(color: col, spreadRadius: 4),
                  BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 16),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: TextStyle(
                  color: const Color(0xFF0B1626),
                  fontSize: large ? 22 : 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            Text(
              '$terrs territórios · $cards carta${cards == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11, color: AppColors.mute),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        side(a),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EstIcon(
                EstIconKind.pact,
                size: large ? 40 : 30,
                color: AppColors.gold,
              ),
              if (note != null) ...[
                const SizedBox(height: 3),
                Text(
                  note!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFE2A3),
                  ),
                ),
              ],
            ],
          ),
        ),
        side(b),
      ],
    );
  }
}

void showOfferModal(BuildContext context, AppController ctrl) {
  final v = ctrl.view;
  if (v == null || v['offer'] == null) return;
  final of = v['offer'] as Map<String, dynamic>;
  final fromIdx = (of['from'] as num).toInt();
  final toIdx = (of['to'] as num).toInt();
  final players = v['players'] as List<dynamic>;
  final fromP = players[fromIdx] as Map<String, dynamic>;
  final fromCol = parseHexColor(ctrl.engine.constants.colors[(fromP['color'] as num).toInt()].hex);
  final round = (v['round'] as num).toInt();
  final c = ctrl.engine.constants;

  SoundPlayer.play('turn');
  WebEnv.vibrate(120);

  showEstSheet<void>(
    context,
    pactTheme: true,
    builder: (ctx) => EstSheetBody(
      children: [
        const Text(
          'PROPOSTA DE PACTO',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.7,
            color: AppColors.gold,
          ),
        ),
        const SizedBox(height: 12),
        _PactPairWidget(
          ctrl: ctrl,
          a: fromIdx,
          b: toIdx,
          note: '${c.pactRounds} rodadas',
          large: true,
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
            children: [
              TextSpan(
                text: '${fromP['name']}',
                style: TextStyle(fontWeight: FontWeight.w700, color: fromCol),
              ),
              TextSpan(
                text:
                    ' propõe que vocês não se ataquem até o fim da rodada ${round + c.pactRounds + 1}.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        for (final t in [
          'Nenhum dos dois pode atacar o outro enquanto o pacto valer.',
          'Cada jogador só tem um pacto por vez.',
          'Romper antes custa metade do reforço do turno (no mínimo ${c.pactPenalty}) e só pode no início do próprio turno.',
        ])
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 3),
            child: Text('• $t', style: const TextStyle(fontSize: 13, color: AppColors.mute)),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: EstButton(
                label: 'Aceitar pacto',
                variant: EstButtonVariant.primary,
                onPressed: () {
                  Navigator.pop(ctx);
                  ctrl.replyPact(true);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EstButton(
                label: 'Recusar',
                onPressed: () {
                  Navigator.pop(ctx);
                  ctrl.replyPact(false);
                },
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

void showPactsModal(BuildContext context, AppController ctrl) {
  final v = ctrl.view;
  final ev = ctrl.eval;
  if (v == null || ev == null) return;
  final opts = v['opts'] as Map<String, dynamic>? ?? const {};
  if (opts['pacts'] != true) return;

  final players = v['players'] as List<dynamic>;
  final colors = ctrl.engine.constants.colors;
  final c = ctrl.engine.constants;
  final round = (v['round'] as num).toInt();
  final pacts = (v['pacts'] as List<dynamic>? ?? const []);
  final offer = v['offer'] as Map<String, dynamic>?;
  final me = ctrl.me;
  final watching = me < 0 || me >= players.length;
  final myTurn = !watching &&
      ctrl.canPlayNow() &&
      (v['turn'] as num).toInt() == me &&
      v['phase'] == 'play';
  final alive = players.where((p) => p['alive'] == true).length;

  Map<String, dynamic>? mine;
  if (!watching) {
    for (final x in pacts) {
      final xm = x as Map<String, dynamic>;
      if ((xm['a'] as num).toInt() == me || (xm['b'] as num).toInt() == me) {
        mine = xm;
        break;
      }
    }
  }

  String leftStr(Map<String, dynamic> x) {
    final until = (x['until'] as num).toInt();
    final rem = until - round + 1;
    return rem == 1 ? 'última rodada' : 'até a rodada ${until + 1}';
  }

  Widget secTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: AppColors.mute,
          ),
        ),
      );

  Widget pCard({required Widget child, bool highlight = false, bool dashed = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x8C0B1626),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? const Color(0x88E2B04A) : const Color(0xFF233C5E),
        ),
        boxShadow: highlight
            ? const [BoxShadow(color: Color(0x14E2B04A), blurRadius: 24)]
            : null,
      ),
      child: child,
    );
  }

  showEstSheet<void>(
    context,
    pactTheme: true,
    builder: (ctx) => EstSheetBody(
      title: 'Pactos',
      titleIcon: const EstIcon(EstIconKind.pact, size: 22, color: AppColors.gold),
      onClose: () => Navigator.pop(ctx),
      children: [
        Text(
          'Acordo de não agressão por ${c.pactRounds} rodadas. Cada jogador tem no máximo um pacto por vez.',
          style: const TextStyle(fontSize: 13, color: AppColors.mute),
        ),

        if (mine != null) ...[
          secTitle('Seu pacto'),
          Builder(
            builder: (_) {
              final a = (mine!['a'] as num).toInt();
              final b = (mine['b'] as num).toInt();
              final other = a == me ? b : a;
              final until = (mine['until'] as num).toInt();
              final canBreak = myTurn && v['step'] == 'reinforce' && v['placed'] != true;
              return pCard(
                highlight: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PactPairWidget(ctrl: ctrl, a: me, b: other, note: leftStr(mine)),
                    const SizedBox(height: 8),
                    Text(
                      'Vale até o fim da rodada ${until + 1}. Nenhum dos dois pode atacar o outro.',
                      style: const TextStyle(fontSize: 13, color: AppColors.mute),
                    ),
                    const SizedBox(height: 8),
                    if (canBreak)
                      EstButton(
                        variant: EstButtonVariant.warn,
                        label: 'Romper o pacto (perde ${ev.pactPenalty} exércitos)',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showConfirmBreakPact(context, ctrl, other);
                        },
                      )
                    else
                      Text(
                        myTurn
                            ? 'Romper só no início do turno, antes de colocar reforços.'
                            : 'Romper só no início da sua vez, antes de colocar reforços.',
                        style: TextStyle(fontSize: 13, color: AppColors.mute.withValues(alpha: 0.8)),
                      ),
                  ],
                ),
              );
            },
          ),
        ],

        if (offer != null) ...[
          Builder(
            builder: (_) {
              final from = (offer['from'] as num).toInt();
              final to = (offer['to'] as num).toInt();
              final offerIsMine =
                  ctrl.role == 'guest' ? to == me : players[to]['ctrl'] == 'local';
              if (offerIsMine) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    secTitle('Proposta para você'),
                    pCard(
                      highlight: true,
                      child: Column(
                        children: [
                          _PactPairWidget(ctrl: ctrl, a: from, b: to, note: 'proposta'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: EstButton(
                                  label: 'Aceitar',
                                  variant: EstButtonVariant.primary,
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    ctrl.replyPact(true);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: EstButton(
                                  label: 'Recusar',
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    ctrl.replyPact(false);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  secTitle('Proposta em andamento'),
                  pCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PactPairWidget(ctrl: ctrl, a: from, b: to, note: 'aguardando'),
                        const SizedBox(height: 8),
                        Text(
                          '${players[to]['name']} ainda não respondeu. A proposta vale até o fim deste turno.',
                          style: const TextStyle(fontSize: 13, color: AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],

        if (!watching && mine == null && alive > 2) ...[
          secTitle('Propor pacto'),
          Builder(
            builder: (_) {
              final used = players[me]['offered'] == '${v['round']}:${v['turn']}';
              final head = !myTurn
                  ? 'Você propõe pactos na sua vez.'
                  : used
                      ? 'Você já fez a proposta deste turno (uma por turno).'
                      : offer != null
                          ? 'Espere a resposta da proposta em andamento.'
                          : 'Escolha com quem quer um pacto. A outra pessoa decide se aceita.';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(head, style: const TextStyle(fontSize: 13, color: AppColors.mute)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < players.length; i++)
                    if (i != me && players[i]['alive'] == true)
                      Builder(
                        builder: (_) {
                          final p = players[i] as Map<String, dynamic>;
                          final col = parseHexColor(colors[(p['color'] as num).toInt()].hex);
                          final why = ev.pactBlocks[i] ?? '';
                          final canOffer = myTurn && why.isEmpty && !used && offer == null;
                          final sub = why.isNotEmpty
                              ? why
                              : '${_ownedCount(v, i)} territórios · ${_handSize(p)} carta${_handSize(p) == 1 ? '' : 's'}${p['ctrl'] == 'bot' ? ' · bot' : ''}';
                          final initial =
                              '${p['name'] ?? ''}'.isNotEmpty ? '${p['name']}'[0].toUpperCase() : '?';

                          return Opacity(
                            opacity: why.isNotEmpty ? 0.62 : 1.0,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0x8C0B1626),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF233C5E)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: col,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        const BoxShadow(color: Color(0xFF0B1626), spreadRadius: 2),
                                        BoxShadow(color: col, spreadRadius: 3),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Color(0xFF0B1626),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${p['name'] ?? ''}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                        Text(
                                          sub,
                                          style: const TextStyle(fontSize: 12, color: AppColors.mute),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (canOffer)
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(minWidth: 84),
                                      child: EstButton(
                                        small: true,
                                        variant: EstButtonVariant.primary,
                                        label: 'Propor',
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          ctrl.proposePact(i);
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ],
              );
            },
          ),
        ] else if (!watching && mine == null)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Com só dois jogadores em jogo não há pactos.',
              style: TextStyle(fontSize: 13, color: AppColors.mute),
            ),
          ),

        Builder(
          builder: (_) {
            final others = pacts.where((x) => x != mine).toList();
            if (others.isEmpty && !watching) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                secTitle(watching ? 'Pactos em vigor' : 'Outros pactos'),
                if (others.isEmpty)
                  const Text(
                    'Nenhum pacto em vigor.',
                    style: TextStyle(fontSize: 13, color: AppColors.mute),
                  )
                else
                  for (final x in others)
                    pCard(
                      child: _PactPairWidget(
                        ctrl: ctrl,
                        a: (x['a'] as num).toInt(),
                        b: (x['b'] as num).toInt(),
                        note: leftStr(x as Map<String, dynamic>),
                      ),
                    ),
              ],
            );
          },
        ),

        const SizedBox(height: 10),
        Theme(
          data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
              title: const Text(
                'Como funcionam os pactos',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              children: [
                for (final r in [
                  'Quem está na vez pode propor um pacto a outro jogador (uma proposta por turno). A outra pessoa aceita ou recusa na hora.',
                  'Aceito, nenhum dos dois ataca o outro até o fim da rodada ${round + c.pactRounds + 1} (o resto desta rodada e mais ${c.pactRounds}).',
                  'Romper antes só no início do próprio turno, antes de colocar reforços, e custa metade do reforço daquele turno (no mínimo ${c.pactPenalty}). Todos ficam sabendo.',
                  'Depois de um pacto (cumprido ou rompido) os mesmos dois esperam ${c.pactCool} rodadas para fazer outro.',
                  'Lançar uma ogiva desfaz o pacto de quem lançou.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $r', style: const TextStyle(fontSize: 13, color: AppColors.mute)),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

void _showConfirmBreakPact(BuildContext context, AppController ctrl, int otherPlayer) {
  final v = ctrl.view!;
  final ev = ctrl.eval!;
  final players = v['players'] as List<dynamic>;
  showEstSheet<void>(
    context,
    pactTheme: true,
    builder: (ctx) => EstSheetBody(
      children: [
        const Text(
          'ROMPER O PACTO?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.7,
            color: Color(0xFFFF8F7A),
          ),
        ),
        const SizedBox(height: 12),
        _PactPairWidget(ctrl: ctrl, a: ctrl.me, b: otherPlayer, note: 'rompendo', large: true),
        const SizedBox(height: 12),
        Text(
          'Você perde ${ev.pactPenalty} exércitos, metade do reforço deste turno, e volta a poder atacar ${players[otherPlayer]['name']} (e vice-versa). Vocês só poderão fazer outro pacto depois de 2 rodadas. Todos ficam sabendo.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.ink),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: EstButton(
                label: 'Romper',
                variant: EstButtonVariant.warn,
                onPressed: () {
                  Navigator.pop(ctx);
                  ctrl.breakPact(otherPlayer);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EstButton(label: 'Manter o pacto', onPressed: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ],
    ),
  );
}

// ---------- 5. Menu & Quit Modals ----------

void showMenuModal(BuildContext context, AppController ctrl) {
  final v = ctrl.view;
  final log = (v?['log'] as List<dynamic>? ?? const []).reversed.toList();
  final players = (v?['players'] as List<dynamic>? ?? const []);
  final colors = ctrl.engine.constants.colors;
  final totalTerr = max(1, ctrl.mapData.territories.length);
  final host = ctrl.role != 'guest';
  final layout = EstLayout.of(context, inGame: true, forceLand: ctrl.forceLand);

  showEstSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final turnIdx = (v?['turn'] as num?)?.toInt() ?? -1;
        return EstSheetBody(
          children: [
            Text('Jogadores', style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC))),
            const SizedBox(height: 8),
            for (var i = 0; i < players.length; i++)
              Builder(
                builder: (_) {
                  final p = players[i] as Map<String, dynamic>;
                  final col = parseHexColor(colors[(p['color'] as num).toInt()].hex);
                  final owned = _ownedCount(v!, i);
                  final cards = _handSize(p);
                  final seatIdx = (p['seat'] as num?)?.toInt() ?? i;
                  final seat = host && seatIdx < ctrl.seats.length ? ctrl.seats[seatIdx] : null;
                  final offline = p['ctrl'] == 'remote' &&
                      (host ? (seat == null || seat.link == null || seat.lag) : (ctrl.onlMap[i] != true));
                  final isNow = i == turnIdx;
                  final pct = (owned / totalTerr).clamp(0.0, 1.0);

                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: const BorderSide(color: AppColors.line),
                        left: isNow ? BorderSide(color: col, width: 3.5) : BorderSide.none,
                      ),
                    ),
                    padding: EdgeInsets.only(left: isNow ? 8 : 0, top: 6, bottom: 8),
                    child: Column(
                      children: [
                        Row(
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
                              child: Text.rich(
                                TextSpan(
                                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                                  children: [
                                    if (p['alive'] != true) const TextSpan(text: '☠ '),
                                    TextSpan(
                                      text: '${p['name'] ?? ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: isNow ? Colors.white : AppColors.ink,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' · $owned terr. · $cards ${cards == 1 ? 'carta' : 'cartas'}${p['ctrl'] == 'bot' ? ' · bot' : ''}',
                                    ),
                                    if (offline)
                                      TextSpan(
                                        text:
                                            ' · ${seat != null && seat.link != null ? 'sem resposta' : 'offline'}',
                                        style: const TextStyle(color: AppColors.bad),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (host && p['ctrl'] == 'remote' && p['alive'] == true && P2P.supported) ...[
                              const SizedBox(width: 6),
                              EstButton(
                                small: true,
                                height: 34,
                                label: 'QR',
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  showP2pInviteModal(context, ctrl, reconnectSeat: seatIdx);
                                },
                              ),
                            ],
                            if (host && offline && p['alive'] == true) ...[
                              const SizedBox(width: 6),
                              EstButton(
                                small: true,
                                height: 34,
                                label: 'Virar bot',
                                onPressed: () {
                                  ctrl.convertSeatToBot(seatIdx);
                                  Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: pct,
                            child: Container(
                              height: 2,
                              color: col.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (ctrl.online != null && ctrl.online!.code != null) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Sala online ${ctrl.online!.code}',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.mute, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  EstButton(
                    small: true,
                    label: 'Convidar de volta',
                    onPressed: () {
                      Navigator.pop(ctx);
                      showOnlineInviteModal(context, ctrl);
                    },
                  ),
                ],
              ),
            ],
            if (log.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in log)
                        Text(
                          entry.toString(),
                          style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.mute),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (host && players.any((p) => p['ctrl'] == 'remote') && P2P.supported) ...[
              const SizedBox(height: 10),
              EstButton(
                small: true,
                label: 'Reconectar por QR',
                onPressed: () {
                  Navigator.pop(ctx);
                  showP2pInviteModal(context, ctrl);
                },
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (!layout.big) ...[
                  Expanded(
                    child: EstButton(
                      small: true,
                      label: 'Tela deitada: ${ctrl.forceLand ? 'sempre' : 'automática'}',
                      onPressed: () {
                        ctrl.toggleForceLand();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: EstButton(
                    small: true,
                    label: 'Som: ${SoundPlayer.enabled ? 'ligado' : 'desligado'}',
                    onPressed: () {
                      ctrl.toggleSound();
                      if (SoundPlayer.enabled) SoundPlayer.play('turn');
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: EstButton(
                    small: true,
                    label: 'Regras',
                    onPressed: () {
                      Navigator.pop(ctx);
                      showRulesModal(context, ctrl);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstButton(
                    small: true,
                    label: 'Sair',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showQuitConfirmModal(context, ctrl);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstButton(
                    small: true,
                    variant: EstButtonVariant.primary,
                    label: 'Voltar',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

void _showQuitConfirmModal(BuildContext context, AppController ctrl) {
  final watching = ctrl.online != null && (ctrl.me < 0);
  final desc = watching
      ? 'Você volta para a tela inicial.'
      : ctrl.online != null
          ? 'Um bot assume o seu lugar. Para voltar, abra de novo o link da sala.'
          : ctrl.role != 'guest'
              ? 'A partida fica salva neste aparelho e pode ser retomada na tela inicial.'
              : 'Você poderá voltar lendo um novo QR do anfitrião.';

  showEstSheet<void>(
    context,
    maxWidth: 440,
    builder: (ctx) => EstSheetBody(
      children: [
        Text(
          watching ? 'Parar de assistir?' : 'Sair da partida?',
          style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC)),
        ),
        const SizedBox(height: 8),
        Text(desc, style: const TextStyle(fontSize: 14, color: AppColors.mute)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: EstButton(
                label: 'Sair',
                variant: EstButtonVariant.primary,
                onPressed: () {
                  Navigator.pop(ctx);
                  ctrl.leaveGame();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EstButton(label: 'Ficar', onPressed: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ],
    ),
  );
}

// ---------- 6. Rules Modal ----------

void showRulesModal(BuildContext context, AppController ctrl) {
  final c = ctrl.engine.constants;
  final eventNames = c.events.map((e) => e.name).join(', ');
  showEstSheet<void>(
    context,
    builder: (ctx) => EstSheetBody(
      title: 'Como jogar',
      onClose: () => Navigator.pop(ctx),
      children: [
        const _RuleBullet(
          'Objetivo',
          'cada jogador recebe um objetivo secreto (🎯). Quem cumprir primeiro vence.',
        ),
        const _RuleBullet(
          'Reforço',
          'no início do turno você recebe metade dos seus territórios em exércitos (mínimo 3), mais o bônus de cada continente inteiro que dominar (o bônus só pode ser colocado no próprio continente).',
        ),
        const _RuleBullet(
          'Ataque',
          'a partir da 2ª rodada, ataque vizinhos com até 3 dados (precisa deixar 1 exército para trás); use − e + para escolher quantos. A defesa rola até 3. Compare do maior para o menor; empate é da defesa. “Auto” repete o ataque com o máximo de dados até conquistar ou não poder mais.',
        ),
        const _RuleBullet(
          'Conquista',
          'ao zerar a defesa você ocupa o território com 1 a 3 exércitos e, no fim do turno, ganha uma carta.',
        ),
        const _RuleBullet(
          'Cartas',
          'troque 3 iguais ou 3 diferentes por exércitos (4, 6, 8, 10, 12, 15, depois +5 a cada troca). Com 5 cartas a troca é obrigatória e o jogo faz sozinho no início do turno, escolhendo a melhor trinca. Com menos, o botão “Trocar cartas” aparece no reforço.',
        ),
        const _RuleBullet(
          'Remanejamento',
          'ao final, mova exércitos entre territórios vizinhos seus; cada exército anda uma vez por turno.',
        ),
        const _RuleBullet(
          'Rotas marítimas',
          'linhas pontilhadas também são fronteiras. O Alasca liga com o Extremo Oriente pela borda do mapa.',
        ),
        const SizedBox(height: 10),
        Text(
          'Regras extras (opcionais)',
          style: AppText.serif(size: 19, color: const Color(0xFFFFF3DC)),
        ),
        const SizedBox(height: 6),
        _RuleBullet(
          'Eventos de rodada',
          'da 2ª rodada em diante, de vez em quando uma rodada começa com um evento surpresa, que vale para todos até ela acabar e é seguido de ao menos uma rodada calma: $eventNames. O raio no painel mostra o evento em vigor.',
        ),
        _RuleBullet(
          'Pactos',
          'na sua vez, proponha a outro jogador um pacto de não agressão de ${c.pactRounds} rodadas. Enquanto valer, um não ataca o outro. Cada jogador só pode ter um pacto por vez. Para romper antes, só no início do seu turno, antes de reforçar, ao custo de metade do reforço (no mínimo ${c.pactPenalty}). Com dois jogadores em jogo os pactos acabam.',
        ),
        const _RuleBullet(
          'Ogiva nuclear',
          'no reforço, em vez de trocar 3 cartas por exércitos, lance a ogiva em qualquer território inimigo. Ele perde o dobro do que a troca valeria (sempre sobra 1) e fica radioativo: até a sua vez voltar, ninguém pode atacá-lo, nem você, mas o dono joga normalmente. Você recebe 75% dos exércitos da troca e segue o turno normalmente, atacando em outros lugares. Só há uma névoa por vez; a primeira troca de cada jogador é normal e, depois de uma ogiva, a seguinte também.',
        ),
        const SizedBox(height: 10),
        Text(
          'Mouse e teclado',
          style: AppText.serif(size: 19, color: const Color(0xFFFFF3DC)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Clique para escolher, arraste para mover o mapa, roda do mouse para o zoom e botão direito para desfazer a seleção. Enter confirma a ação principal, + e − (ou as setas) mudam a quantidade, Esc cancela, F ajusta o zoom, C cartas, O objetivo, M menu.',
          style: TextStyle(fontSize: 14, color: AppColors.mute),
        ),
        const SizedBox(height: 10),
        Text('Conexão', style: AppText.serif(size: 19, color: const Color(0xFFFFF3DC))),
        const SizedBox(height: 4),
        const Text(
          'Os aparelhos falam direto entre si, sem servidor e sem internet: basta estarem no mesmo Wi-Fi ou no hotspot de um dos celulares. Permita a câmera quando o navegador pedir. Se alguém cair, o jogo tenta voltar sozinho em alguns segundos. Se não conseguir, o anfitrião toca em “Reconectar” e o jogador lê o novo QR em “Reconectar à partida”: ele volta para o mesmo lugar.',
          style: TextStyle(fontSize: 14, color: AppColors.mute),
        ),
        const SizedBox(height: 6),
        const Text(
          'Online: em “Jogar online”, um cria a sala e manda o link ou o código; cada um joga do próprio celular, de qualquer lugar com internet. Se a conexão cair, o jogo volta sozinho para o mesmo lugar. Quem sai no meio da partida vira bot (e pode voltar pelo link). Sem relógio, a vez de quem está desconectado passa depois de um minuto e meio.',
          style: TextStyle(fontSize: 14, color: AppColors.mute),
        ),
        const SizedBox(height: 14),
        EstButton(label: 'Fechar', onPressed: () => Navigator.pop(ctx)),
      ],
    ),
  );
}

class _RuleBullet extends StatelessWidget {
  const _RuleBullet(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: AppColors.ink, height: 1.4),
          children: [
            const TextSpan(text: '• '),
            TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: body),
          ],
        ),
      ),
    );
  }
}

// ---------- 7. Invites (Online & P2P QR) ----------

void showOnlineInviteModal(BuildContext context, AppController ctrl) {
  final code = ctrl.lobbyCode ?? ctrl.online?.code;
  if (code == null) return;
  final url = '${WebEnv.getBaseUrl()}?sala=$code';

  showEstSheet<void>(
    context,
    builder: (ctx) => EstSheetBody(
      children: [
        Text(
          'Convidar para a sala $code',
          style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Mande o link (ou peça para lerem o QR). Quem abrir entra direto nesta sala; também dá para digitar o código em “Jogar online”.',
          style: TextStyle(fontSize: 14, color: AppColors.mute),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(data: url, size: 220, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        SelectableText(
          url,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.mute),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: EstButton(
                small: true,
                variant: EstButtonVariant.primary,
                label: 'Copiar link',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ctrl.showToast('Copiado.');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EstButton(
                small: true,
                label: 'Compartilhar',
                onPressed: () async {
                  await WebEnv.shareOrCopy(
                    title: 'Estandarte',
                    text: 'Vem jogar Estandarte comigo! Sala $code',
                    url: url,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EstButton(
                small: true,
                variant: EstButtonVariant.ghost,
                label: 'Fechar',
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

void showP2pInviteModal(BuildContext context, AppController ctrl, {int? reconnectSeat}) {
  P2PInvite? invite;
  String? err;
  bool loading = true;
  final ansCtrl = TextEditingController();

  showEstSheet<void>(
    context,
    dismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        if (loading && invite == null && err == null) {
          ctrl.createP2PInviteForSeat(reconnectSeat: reconnectSeat).then((inv) {
            if (!ctx.mounted) {
              inv.cancel();
              return;
            }
            setState(() {
              invite = inv;
              loading = false;
            });
          }).catchError((Object e) {
            if (!ctx.mounted) return;
            setState(() {
              err = 'Não foi possível criar a conexão: $e';
              loading = false;
            });
          });
        }

        Future<void> acceptCode(String raw) async {
          if (invite == null || raw.trim().isEmpty) return;
          try {
            await invite!.accept(raw.trim());
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            ctrl.showToast('Resposta inválida ($e).');
          }
        }

        final title = reconnectSeat != null
            ? 'Reconectar ${ctrl.seats[reconnectSeat].name}'
            : ctrl.view != null
                ? 'Reconectar jogador'
                : 'Convidar jogador';

        return EstSheetBody(
          children: [
            Text(title, style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC))),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
              )
            else if (err != null)
              Text(err!, style: const TextStyle(fontSize: 14, color: AppColors.bad))
            else ...[
              Text(
                '1. O convidado abre o jogo, toca em “${ctrl.view != null ? 'Reconectar à partida' : 'Rede local → Entrar por QR'}” e lê este QR.',
                style: const TextStyle(fontSize: 14, color: AppColors.ink),
              ),
              const SizedBox(height: 4),
              const Text(
                '2. O celular dele mostra um QR de resposta: aponte a câmera deste aparelho para ele ou cole o código abaixo.',
                style: TextStyle(fontSize: 14, color: AppColors.ink),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: '${WebEnv.getBaseUrl()}#j=${Uri.encodeComponent(invite!.code)}',
                    size: 210,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              if (QrScannerView.supported) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 160,
                    child: QrScannerView(
                      onCode: acceptCode,
                      onError: (m) => ctrl.showToast(m),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: EstButton(
                      small: true,
                      label: 'Copiar link',
                      onPressed: () {
                        final url =
                            '${WebEnv.getBaseUrl()}#j=${Uri.encodeComponent(invite!.code)}';
                        Clipboard.setData(ClipboardData(text: url));
                        ctrl.showToast('Copiado.');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Ou cole o código de resposta',
                style: TextStyle(fontSize: 13, color: AppColors.mute),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: ansCtrl,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: EstButton(
                      small: true,
                      variant: EstButtonVariant.primary,
                      label: 'Usar código colado',
                      onPressed: () => acceptCode(ansCtrl.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: EstButton(
                      small: true,
                      variant: EstButtonVariant.ghost,
                      label: 'Cancelar',
                      onPressed: () {
                        invite?.cancel();
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ],
            if (loading || err != null) ...[
              const SizedBox(height: 12),
              EstButton(
                small: true,
                variant: EstButtonVariant.ghost,
                label: 'Cancelar',
                onPressed: () {
                  invite?.cancel();
                  Navigator.pop(ctx);
                },
              ),
            ],
          ],
        );
      },
    ),
  );
}

void showP2pJoinModal(BuildContext context, AppController ctrl, {String? initialOffer}) {
  final nameCtrl = TextEditingController(text: ctrl.savedName);
  final offerCtrl = TextEditingController(text: initialOffer ?? '');
  P2PJoinResult? result;
  bool joining = false;

  showEstSheet<void>(
    context,
    dismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> submitOffer(String raw) async {
          if (joining || raw.trim().isEmpty) return;
          var offer = raw.trim();
          final idx = offer.indexOf('#j=');
          if (idx >= 0) {
            offer = Uri.decodeComponent(offer.substring(idx + 3));
          }
          setState(() => joining = true);
          try {
            final res = await ctrl.joinViaQrCode(offer, nameCtrl.text);
            if (!ctx.mounted) {
              res.cancel();
              return;
            }
            setState(() {
              result = res;
              joining = false;
            });
          } catch (e) {
            if (!ctx.mounted) return;
            setState(() => joining = false);
            ctrl.showToast('Código de convite inválido ($e).');
          }
        }

        if (ctrl.guestLink != null && ctrl.guestLink!.isOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) Navigator.pop(ctx);
          });
        }

        return EstSheetBody(
          children: [
            Text(
              result != null
                  ? 'Mostre este QR ao anfitrião'
                  : (ctrl.hasSavedGuest ? 'Reconectar à partida' : 'Entrar em partida'),
              style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC)),
            ),
            const SizedBox(height: 8),
            if (result != null) ...[
              const Text(
                'No celular dele, aponte para este QR. A conexão abre sozinha em seguida.',
                style: TextStyle(fontSize: 14, color: AppColors.mute),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: result!.code,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: EstButton(
                      small: true,
                      label: 'Copiar código',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: result!.code));
                        ctrl.showToast('Copiado.');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: EstButton(
                      small: true,
                      variant: EstButtonVariant.ghost,
                      label: 'Cancelar',
                      onPressed: () {
                        result?.cancel();
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              const Text('Seu nome', style: TextStyle(fontSize: 13, color: AppColors.mute)),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                maxLength: 14,
                decoration: const InputDecoration(
                  hintText: 'Como quer ser chamado',
                  counterText: '',
                ),
              ),
              if (QrScannerView.supported && initialOffer == null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 190,
                    child: QrScannerView(
                      onCode: submitOffer,
                      onError: (m) => ctrl.showToast(m),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Ou cole o link/código do convite',
                style: TextStyle(fontSize: 13, color: AppColors.mute),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: offerCtrl,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: EstButton(
                      small: true,
                      variant: EstButtonVariant.primary,
                      label: joining ? 'Conectando…' : 'Usar código colado',
                      onPressed: joining ? null : () => submitOffer(offerCtrl.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: EstButton(
                      small: true,
                      variant: EstButtonVariant.ghost,
                      label: 'Cancelar',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}
