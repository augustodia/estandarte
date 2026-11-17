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
import 'quartel_modal.dart';
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

/// "3 cartas" ou, nas partidas com Quartel, "3 medalhas".
String _handLabel(Map<String, dynamic> v, Map<String, dynamic> p) {
  if ((v['opts'] as Map<String, dynamic>?)?['hq'] == true) {
    final m = (p['medals'] as num?)?.toInt() ?? 0;
    return '$m medalha${m == 1 ? '' : 's'}';
  }
  final c = _handSize(p);
  return '$c carta${c == 1 ? '' : 's'}';
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
      title: 'Objetivo Secreto',
      titleIcon: const EstIcon(EstIconKind.goal, size: 20, color: AppColors.gold),
      onClose: () => Navigator.pop(ctx),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFF7D663D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  EstFactionSeal(color: col, size: 15, highlighted: true),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '${meP['name'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.brassDim),
                    ),
                    child: const Text(
                      'SIGILOSO',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const EstRuleDivider(),
              const SizedBox(height: 10),
              Text(
                text,
                style: const TextStyle(fontSize: 15.5, height: 1.42, color: AppColors.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const EstSectionTag('DOMÍNIO NO MAPA'),
        const SizedBox(height: 8),
        _DomainMeter(fraction: pct, color: col),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'Mantenha em segredo dos adversários.',
              style: TextStyle(fontSize: 12.5, color: AppColors.mute),
            ),
            const Spacer(),
            Text(
              '$owned de $total (${(pct * 100).round()}%)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        EstButton(
          label: 'Fechar',
          variant: EstButtonVariant.primary,
          onPressed: () => Navigator.pop(ctx),
        ),
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
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, val, _) => FractionallySizedBox(
          widthFactor: val,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, Color.lerp(color, Colors.white, 0.35)!],
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
  if (ctrl.hqOn) {
    // partida com Quartel: não há cartas, a mesma tecla e o mesmo botão abrem o Quartel
    showQuartelModal(context, ctrl);
    return;
  }
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
        final threePicked = chosen.length == 3;
        final validSet = threePicked && ctrl.engine.validTrade(chosen);
        final ok = canTrade && validSet;
        final String statusMsg;
        final Color statusColor;
        if (cards.isEmpty) {
          statusMsg = 'Conquiste um território no turno para ganhar sua primeira carta.';
          statusColor = AppColors.mute;
        } else if (!threePicked) {
          statusMsg =
              'Selecione ${3 - chosen.length} carta${3 - chosen.length == 1 ? '' : 's'} · próxima troca vale +${ev.tradeValue} exércitos';
          statusColor = AppColors.mute;
        } else if (!validSet) {
          statusMsg = 'Conjunto inválido · precisa de 3 símbolos iguais ou 3 diferentes (★ é coringa).';
          statusColor = AppColors.bad;
        } else if (!canTrade) {
          statusMsg = 'Trinca válida (+${ev.tradeValue}) · disponível no início do seu próximo turno.';
          statusColor = AppColors.gold;
        } else {
          statusMsg = 'Trinca pronta para troca · +${ev.tradeValue} exércitos agora!';
          statusColor = AppColors.gold;
        }

        return EstSheetBody(
          title: 'Cartas (${cards.length})',
          titleIcon: const EstIcon(EstIconKind.cards, size: 20, color: AppColors.gold),
          onClose: () => Navigator.pop(ctx),
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
                children: [
                  const TextSpan(
                    text:
                        'Troque 3 símbolos iguais ou 3 diferentes (★ vale qualquer um) no reforço. Próxima troca: ',
                  ),
                  TextSpan(
                    text: '+${ev.tradeValue} exércitos',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const TextSpan(
                    text: ' (+2 em territórios seus). Com 5 cartas a troca é obrigatória.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (cards.isNotEmpty)
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
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    transform: Matrix4.translationValues(0, isOn ? -5 : 0, 0),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF7EEDB), Color(0xFFE3D3B3)],
                      ),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isOn ? AppColors.gold : const Color(0xFFB39D74),
                        width: isOn ? 2.4 : 1.4,
                      ),
                      boxShadow: isOn
                          ? const [
                              BoxShadow(color: Color(0xAA000000), blurRadius: 16, offset: Offset(0, 8)),
                              BoxShadow(color: Color(0x66D9B25F), spreadRadius: 2),
                            ]
                          : const [
                              BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
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
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0x55FFFFFF), width: 1.0),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 23,
                                height: 23,
                                child: CustomPaint(painter: _CardSymbolPainter(info.symbol)),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                info.name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.18,
                                  color: Color(0xFF1C1408),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: ok
                      ? const Color(0xFF7D663D)
                      : (threePicked && !validSet ? AppColors.bad.withValues(alpha: 0.6) : AppColors.line),
                ),
              ),
              child: Text(
                statusMsg,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: EstButton(
                    label: ok ? 'Trocar (+${ev.tradeValue})' : 'Trocar selecionadas',
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
      title: 'Regras Extras',
      titleIcon: const EstIcon(EstIconKind.extras, size: 20, color: AppColors.gold),
      onClose: () => Navigator.pop(ctx),
      children: [
        if (opts['events'] == true) ...[
          const EstSectionTag('EVENTO DA RODADA'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: v['event'] != null ? const Color(0xFF7D663D) : AppColors.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (v['event'] != null)
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 15, height: 1.35, color: AppColors.ink),
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
                    style: TextStyle(fontSize: 13.5, color: AppColors.mute),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Os eventos surgem a partir da 2ª rodada, valem para todos por uma rodada e são seguidos de ao menos uma rodada calma:',
                  style: TextStyle(fontSize: 12.5, color: AppColors.mute),
                ),
                const SizedBox(height: 6),
                for (final x in ctrl.engine.constants.events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _RuleBullet(
                      x.name,
                      x.desc.replaceAll('América do Norte', 'um continente sorteado'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (opts['pacts'] == true) ...[
          const EstSectionTag('PACTOS DIPLOMÁTICOS'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pacts.isEmpty)
                  const Text(
                    'Nenhum pacto em vigor.',
                    style: TextStyle(fontSize: 13.5, color: AppColors.mute),
                  )
                else
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 13.5, color: AppColors.mute),
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
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 13.5, color: AppColors.mute),
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
                  icon: EstIconKind.pact,
                  label: offerIsMine
                      ? 'Responder à proposta'
                      : myTurn
                          ? 'Abrir pactos (propor ou romper)'
                          : 'Ver pactos',
                  onPressed: () {
                    replaceEstSheet(ctx, (safeCtx) {
                      if (offerIsMine) {
                        showOfferModal(safeCtx, ctrl);
                      } else {
                        showPactsModal(safeCtx, ctrl);
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (opts['nukes'] == true) ...[
          const EstSectionTag('OGIVA NUCLEAR'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: v['fog'] != null ? AppColors.rad.withValues(alpha: 0.55) : AppColors.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (v['fog'] != null) ...[
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
                      children: [
                        TextSpan(
                          text: 'Névoa sobre ${ctrl.mapData.territories[(v['fog']['t'] as num).toInt()].name}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.rad),
                        ),
                        const TextSpan(text: ', lançada por '),
                        playerTag((v['fog']['by'] as num).toInt()),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13.5, color: AppColors.mute),
                    children: [
                      TextSpan(
                        text: opts['hq'] == true
                            ? 'Ordem do Quartel (4 medalhas). Hoje destrói '
                            : 'No reforço (em vez da troca de 3 cartas), destrói ',
                      ),
                      TextSpan(
                        text: '${ev.nukeDamage} exércitos',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      TextSpan(
                        text: opts['hq'] == true
                            ? ' (dobro da Mobilização), sempre sobrando 1 no alvo.'
                            : ' (dobro da troca), sempre sobrando 1 no alvo.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                for (final b in [
                  if (opts['hq'] == true)
                    'Conta como sua ordem tática do turno e o restante da vez segue normal.'
                  else
                    'Você recebe 75% dos exércitos da troca (hoje ${ev.nukeRefund}).',
                  'O alvo fica radioativo até sua vez voltar: ninguém o ataca, mas o dono joga normalmente.',
                  'Lançar uma ogiva encerra seu pacto imediatamente.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('• $b', style: const TextStyle(fontSize: 12.5, color: AppColors.mute)),
                  ),
                if (myTurn && ev.nukeBlock.isNotEmpty && v['step'] == 'reinforce') ...[
                  const SizedBox(height: 6),
                  Text(ev.nukeBlock, style: const TextStyle(fontSize: 12.5, color: AppColors.bad)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (opts['hq'] == true && opts['spy'] == true) ...[
          const EstSectionTag('ESPIONAGEM'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in const [
                  '1ª espionagem no alvo: revela 2 objetivos possíveis (1 verdadeiro e 1 falso).',
                  '2ª espionagem no mesmo alvo: confirma o objetivo verdadeiro com certeza.',
                  'Ataques contra o alvo espionado no turno somam +1 ao maior dado (até 6).',
                  'Os relatórios ficam guardados no Quartel e só você lê.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('• $b', style: const TextStyle(fontSize: 12.5, color: AppColors.mute)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
      final terrs = _ownedCount(v, idx);
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EstFactionSeal(color: col, size: large ? 38 : 28, highlighted: true),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            Text(
              '$terrs terr. · ${_handLabel(v, p)}',
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
      title: 'Proposta de Pacto',
      titleIcon: const EstIcon(EstIconKind.pact, size: 20, color: AppColors.gold),
      onClose: () => Navigator.pop(ctx),
      children: [
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
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: EstSectionTag(t),
      );

  Widget pCard({required Widget child, bool highlight = false, bool dashed = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: highlight ? const Color(0xFF7D663D) : AppColors.line,
        ),
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
                          replaceEstSheet(ctx, (safeCtx) {
                            _showConfirmBreakPact(safeCtx, ctrl, other);
                          });
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

                          return Opacity(
                            opacity: why.isNotEmpty ? 0.62 : 1.0,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.obsidian,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Row(
                                children: [
                                  EstFactionSeal(color: col, size: 18),
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
      title: 'Romper Pacto?',
      titleIcon: const EstIcon(EstIconKind.pact, size: 20, color: AppColors.bad),
      onClose: () => Navigator.pop(ctx),
      children: [
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
          title: 'Mesa & Crônica',
          titleIcon: const EstIcon(EstIconKind.menu, size: 20, color: AppColors.gold),
          onClose: () => Navigator.pop(ctx),
          children: [
            const EstSectionTag('FORÇAS EM CAMPO'),
            const SizedBox(height: 8),
            for (var i = 0; i < players.length; i++)
              Builder(
                builder: (_) {
                  final p = players[i] as Map<String, dynamic>;
                  final col = parseHexColor(colors[(p['color'] as num).toInt()].hex);
                  final owned = _ownedCount(v!, i);
                  final seatIdx = (p['seat'] as num?)?.toInt() ?? i;
                  final seat = host && seatIdx < ctrl.seats.length ? ctrl.seats[seatIdx] : null;
                  final offline = p['ctrl'] == 'remote' &&
                      (host ? (seat == null || seat.link == null || seat.lag) : (ctrl.onlMap[i] != true));
                  final isNow = i == turnIdx;
                  final dead = p['alive'] != true;
                  final pct = (owned / totalTerr).clamp(0.0, 1.0);

                  return Opacity(
                    opacity: dead ? 0.45 : 1.0,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.obsidian,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: isNow ? col.withValues(alpha: 0.7) : AppColors.line,
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                            child: Row(
                              children: [
                                EstFactionSeal(color: col, size: 12, highlighted: isNow),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      style: const TextStyle(fontSize: 13, color: AppColors.ink),
                                      children: [
                                        TextSpan(
                                          text: '${p['name'] ?? ''}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            decoration: dead ? TextDecoration.lineThrough : null,
                                            color: isNow ? Colors.white : AppColors.ink,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' · $owned terr. · ${_handLabel(v, p)}${p['ctrl'] == 'bot' ? ' · bot' : ''}',
                                          style: const TextStyle(color: AppColors.mute),
                                        ),
                                        if (dead)
                                          const TextSpan(
                                            text: ' · eliminado',
                                            style: TextStyle(color: AppColors.mute),
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
                                if (host && p['ctrl'] == 'remote' && !dead && P2P.supported) ...[
                                  const SizedBox(width: 6),
                                  EstButton(
                                    small: true,
                                    height: 32,
                                    label: 'QR',
                                    onPressed: () {
                                      replaceEstSheet(ctx, (safeCtx) {
                                        showP2pInviteModal(safeCtx, ctrl, reconnectSeat: seatIdx);
                                      });
                                    },
                                  ),
                                ],
                                if (host && offline && !dead) ...[
                                  const SizedBox(width: 6),
                                  EstButton(
                                    small: true,
                                    height: 32,
                                    label: 'Virar bot',
                                    onPressed: () {
                                      ctrl.convertSeatToBot(seatIdx);
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
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
                    'Sala online #${ctrl.online!.code}',
                    style: const TextStyle(fontSize: 13, color: AppColors.mute, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  EstButton(
                    small: true,
                    label: 'Convidar de volta',
                    onPressed: () {
                      replaceEstSheet(ctx, (safeCtx) {
                        showOnlineInviteModal(safeCtx, ctrl);
                      });
                    },
                  ),
                ],
              ),
            ],
            if (log.isNotEmpty) ...[
              const SizedBox(height: 10),
              const EstSectionTag('CRÔNICA DA PARTIDA'),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 130),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.line),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in log)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            entry.toString(),
                            style: const TextStyle(fontSize: 12, height: 1.38, color: AppColors.mute),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (host && ctrl.relayCode != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF7D663D)),
                ),
                child: Row(
                  children: [
                    const EstIcon(EstIconKind.globe, size: 15, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        'Sala por código: #${ctrl.relayCode}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    EstButton(
                      small: true,
                      height: 30,
                      label: 'Copiar',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ctrl.relayCode!));
                        ctrl.showToast('Código #${ctrl.relayCode} copiado.');
                      },
                    ),
                    const SizedBox(width: 6),
                    EstButton(
                      small: true,
                      height: 30,
                      label: 'QR',
                      onPressed: () {
                        replaceEstSheet(ctx, (safeCtx) {
                          showOnlineInviteModal(safeCtx, ctrl);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
            if (host && ctrl.lanHostAddr != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFF7D663D)),
                ),
                child: Row(
                  children: [
                    const EstIcon(EstIconKind.lan, size: 15, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        'Host LAN: ${ctrl.lanHostAddr}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    EstButton(
                      small: true,
                      height: 30,
                      label: 'Copiar IP',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: ctrl.lanHostAddr!));
                        ctrl.showToast('IP copiado.');
                      },
                    ),
                  ],
                ),
              ),
            ],
            if (host && players.any((p) => p['ctrl'] == 'remote') && P2P.supported) ...[
              const SizedBox(height: 10),
              EstButton(
                small: true,
                icon: EstIconKind.qr,
                label: 'Reconectar por QR',
                onPressed: () {
                  replaceEstSheet(ctx, (safeCtx) {
                    showP2pInviteModal(safeCtx, ctrl);
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            const EstSectionTag('PREFERÊNCIAS'),
            const SizedBox(height: 8),
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
                    icon: EstIconKind.book,
                    label: 'Regras',
                    onPressed: () {
                      replaceEstSheet(ctx, (safeCtx) {
                        showRulesModal(safeCtx, ctrl);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstButton(
                    small: true,
                    variant: EstButtonVariant.warn,
                    label: 'Sair',
                    onPressed: () {
                      replaceEstSheet(ctx, (safeCtx) {
                        _showQuitConfirmModal(safeCtx, ctrl);
                      });
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
      title: watching ? 'Parar de assistir?' : 'Sair da partida?',
      onClose: () => Navigator.pop(ctx),
      children: [
        Text(desc, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.mute)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: EstButton(
                label: 'Sair',
                variant: EstButtonVariant.warn,
                onPressed: () {
                  Navigator.pop(ctx);
                  ctrl.leaveGame();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EstButton(
                label: 'Ficar',
                variant: EstButtonVariant.primary,
                onPressed: () => Navigator.pop(ctx),
              ),
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
  var tab = 0;

  Widget codexBox(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.obsidian,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget phaseStep(EstIconKind icon, String numStr, String title) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EstIcon(icon, size: 15, color: AppColors.gold),
              const SizedBox(height: 4),
              Text(
                '$numStr. $title',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ],
          ),
        ),
      );

  Widget keyRow(String keys, String desc) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 66),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.panel2,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF455B7A)),
              ),
              child: Text(
                keys,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                desc,
                style: const TextStyle(fontSize: 13, color: AppColors.ink),
              ),
            ),
          ],
        ),
      );

  showEstSheet<void>(
    context,
    maxWidth: 600,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        const tabs = [
          'Turno',
          'Quartel e Cartas',
          'Extras',
          'Atalhos e Rede',
        ];

        Widget content;
        switch (tab) {
          case 0:
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EstSectionTag('RITMO DA RODADA'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    phaseStep(EstIconKind.troop, '1', 'Reforço'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.brass),
                    ),
                    phaseStep(EstIconKind.sword, '2', 'Ataque'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.brass),
                    ),
                    phaseStep(EstIconKind.move, '3', 'Remanejar'),
                  ],
                ),
                const SizedBox(height: 12),
                codexBox(const [
                  _RuleBullet(
                    'Objetivo secreto',
                    'cada comandante recebe uma missão oculta (ícone de alvo ou tecla O). O primeiro a cumprir vence imediatamente.',
                  ),
                  _RuleBullet(
                    'Reforço',
                    'receba metade dos seus territórios em exércitos (mínimo 3), além do bônus de cada continente dominado por inteiro — esse bônus deve ser posicionado no próprio continente.',
                  ),
                  _RuleBullet(
                    'Ataque',
                    'a partir da 2ª rodada, ataque vizinhos com até 3 dados (sempre sobra ao menos 1 exército atrás). A defesa rola até 3 dados e vence empates. "Auto" repete com o máximo até conquistar ou parar.',
                  ),
                  _RuleBullet(
                    'Conquista e Remanejamento',
                    'ao zerar a defesa, ocupe com 1 a 3 exércitos. No fim da vez, desloque tropas entre territórios vizinhos seus (cada exército move uma vez).',
                  ),
                  _RuleBullet(
                    'Rotas marítimas',
                    'linhas pontilhadas também conectam fronteiras — inclusive a ligação do Alasca com o Extremo Oriente pela borda.',
                  ),
                ]),
              ],
            );
          case 1:
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EstSectionTag('QUARTEL (PADRÃO)'),
                const SizedBox(height: 8),
                codexBox(const [
                  _RuleBullet(
                    'Ganho de medalhas',
                    '1 medalha na primeira conquista do turno, +1 ao fechar um continente e +2 ao eliminar um comandante (máximo de 6 acumuladas).',
                  ),
                  _RuleBullet(
                    'Mobilização',
                    'por 3 medalhas no início do turno, receba o esforço de guerra: 4 exércitos na rodada 2, subindo +1 a cada nova rodada.',
                  ),
                  _RuleBullet(
                    'Ordens abertas',
                    '3 ordens ficam disponíveis para todos (Ponte aérea, Trincheira, Sabotagem, Espionagem e Ogiva). Cada jogador usa no máximo uma por turno e outra entra no lugar.',
                  ),
                  _RuleBullet(
                    'Espionagem',
                    '1ª vez revela 2 objetivos possíveis (1 verdadeiro e 1 falso); 2ª vez confirma o real, além de dar +1 ao maior dado contra o alvo no turno.',
                  ),
                ]),
                const EstSectionTag('CARTAS DE TERRITÓRIO (CLÁSSICO)'),
                const SizedBox(height: 8),
                codexBox(const [
                  _RuleBullet(
                    'Substitui o Quartel',
                    'com Quartel desligado, conquiste ao menos 1 território no turno para comprar uma carta ao fim da vez.',
                  ),
                  _RuleBullet(
                    'Trocas escalonadas',
                    'junte 3 símbolos iguais ou 3 diferentes (★ é coringa) para ganhar 4, 6, 8, 10, 12, 15 e +5 a cada troca seguinte (+2 no próprio território). Ao juntar 5 cartas, a troca torna-se obrigatória antes de reforçar.',
                  ),
                ]),
              ],
            );
          case 2:
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EstSectionTag('SISTEMAS OPCIONAIS'),
                const SizedBox(height: 8),
                codexBox([
                  _RuleBullet(
                    'Eventos de rodada',
                    'a partir da 2ª rodada, eventos globais podem surgir para todos por uma rodada, seguidos de ao menos uma rodada calma: $eventNames.',
                  ),
                  _RuleBullet(
                    'Pactos diplomáticos',
                    'proponha um acordo de não agressão de ${c.pactRounds} rodadas (1 por jogador). Romper antes custa metade do reforço do turno (mínimo ${c.pactPenalty}) e só pode ser feito antes de colocar tropas.',
                  ),
                  const _RuleBullet(
                    'Ogiva nuclear',
                    'destrói o dobro da Mobilização (ou da troca) no território alvo, deixando no mínimo 1 exército e criando névoa radioativa impenetrável até sua vez voltar. Lança-la encerra seu pacto atual.',
                  ),
                ]),
              ],
            );
          default:
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EstSectionTag('ATALHOS E CÂMERA'),
                const SizedBox(height: 8),
                codexBox([
                  keyRow('Clique / Arraste', 'Seleciona territórios e navega pelo mapa'),
                  keyRow('Botão direito', 'Desfaz a seleção atual no mapa'),
                  keyRow('Enter', 'Confirma a ação principal da barra inferior'),
                  keyRow('+ / − / Setas', 'Ajusta a quantidade de dados ou exércitos'),
                  keyRow('F', 'Alterna o enquadramento completo do mapa'),
                  keyRow('O · C · M', 'Abre Objetivo (O), Cartas/Quartel (C) ou Mesa (M)'),
                  keyRow('Esc', 'Cancela ordens ativas, seleções ou confirmações'),
                ]),
                const EstSectionTag('MODOS DE CONEXÃO'),
                const SizedBox(height: 8),
                codexBox(const [
                  _RuleBullet(
                    'Salas Online',
                    'jogue pela internet via fila rápida ou código de sala; se cair, reconecte pelo link para retomar seu assento.',
                  ),
                  _RuleBullet(
                    'Rede Local (QR P2P)',
                    'aparelhos no mesmo Wi-Fi ou hotspot conectam direto via QR Code sem depender de servidor.',
                  ),
                ]),
              ],
            );
        }

        return EstSheetBody(
          title: 'Manual de Campanha',
          titleIcon: const EstIcon(EstIconKind.book, size: 20, color: AppColors.gold),
          onClose: () => Navigator.pop(ctx),
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.line),
              ),
              child: Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => tab = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: tab == i ? AppColors.panel2 : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: tab == i ? Border.all(color: const Color(0xFF7D663D)) : null,
                        ),
                        child: Text(
                          tabs[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: tab == i ? FontWeight.w700 : FontWeight.w600,
                            color: tab == i ? AppColors.gold : AppColors.mute,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: KeyedSubtree(key: ValueKey(tab), child: content),
            ),
            const SizedBox(height: 4),
            EstButton(
              label: 'Fechar',
              variant: EstButtonVariant.primary,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
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
      title: 'Convidar · #$code',
      titleIcon: const EstIcon(EstIconKind.globe, size: 20, color: AppColors.gold),
      onClose: () => Navigator.pop(ctx),
      children: [
        const Text(
          'Compartilhe o link ou o QR abaixo. Quem abrir entra direto nesta sala; também dá para digitar o código em Salas Online.',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.mute),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.brass),
            ),
            child: Builder(
              builder: (qCtx) {
                final l = EstLayout.of(qCtx);
                final qrSize = l.land && !l.big ? 136.0 : 210.0;
                return QrImageView(data: url, size: qrSize, backgroundColor: Colors.white);
              },
            ),
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
                    title: 'Ultimato',
                    text: 'Vem jogar Ultimato comigo! Sala $code',
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
          title: title,
          titleIcon: const EstIcon(EstIconKind.qr, size: 20, color: AppColors.gold),
          onClose: () {
            invite?.cancel();
            Navigator.pop(ctx);
          },
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
              )
            else if (err != null)
              Text(err!, style: const TextStyle(fontSize: 14, color: AppColors.bad))
            else ...[
              Text(
                '1. O convidado abre o jogo, toca em “${ctrl.view != null ? 'Reconectar à partida' : 'Conectar por QR Code'}” e lê este QR.',
                style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
              ),
              const SizedBox(height: 4),
              const Text(
                '2. O aparelho dele mostra um QR de resposta: aponte a câmera deste aparelho para ele ou cole o código abaixo.',
                style: TextStyle(fontSize: 13.5, color: AppColors.ink),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.brass),
                  ),
                  child: Builder(
                    builder: (qCtx) {
                      final l = EstLayout.of(qCtx);
                      final qrSize = l.land && !l.big ? 136.0 : 200.0;
                      return QrImageView(
                        data: '${WebEnv.getBaseUrl()}#j=${Uri.encodeComponent(invite!.code)}',
                        size: qrSize,
                        backgroundColor: Colors.white,
                      );
                    },
                  ),
                ),
              ),
              if (QrScannerView.supported) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Builder(
                    builder: (sCtx) {
                      final l = EstLayout.of(sCtx);
                      return SizedBox(
                        height: l.land && !l.big ? 130.0 : 160.0,
                        child: QrScannerView(
                          onCode: acceptCode,
                          onError: (m) => ctrl.showToast(m),
                        ),
                      );
                    },
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
          title: result != null
              ? 'Mostre este QR ao anfitrião'
              : (ctrl.hasSavedGuest ? 'Reconectar à partida' : 'Entrar por QR Code'),
          titleIcon: const EstIcon(EstIconKind.qr, size: 20, color: AppColors.gold),
          onClose: () {
            result?.cancel();
            Navigator.pop(ctx);
          },
          children: [
            if (result != null) ...[
              const Text(
                'No aparelho dele, aponte para este QR. A conexão abre sozinha em seguida.',
                style: TextStyle(fontSize: 13.5, color: AppColors.mute),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.brass),
                  ),
                  child: Builder(
                    builder: (qCtx) {
                      final l = EstLayout.of(qCtx);
                      final qrSize = l.land && !l.big ? 136.0 : 210.0;
                      return QrImageView(
                        data: result!.code,
                        size: qrSize,
                        backgroundColor: Colors.white,
                      );
                    },
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
                  borderRadius: BorderRadius.circular(6),
                  child: Builder(
                    builder: (sCtx) {
                      final l = EstLayout.of(sCtx);
                      return SizedBox(
                        height: l.land && !l.big ? 140.0 : 190.0,
                        child: QrScannerView(
                          onCode: submitOffer,
                          onError: (m) => ctrl.showToast(m),
                        ),
                      );
                    },
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

void showLanJoinModal(BuildContext context, AppController ctrl) {
  final nameCtrl = TextEditingController(text: ctrl.savedName);
  final addrCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  void connect(BuildContext ctx) {
    final addr = addrCtrl.text.trim();
    if (addr.isEmpty) {
      ctrl.showToast('Digite o IP do anfitrião.');
      return;
    }
    Navigator.pop(ctx);
    ctrl.joinLanHost(addr, nameCtrl.text, pass: passCtrl.text);
  }

  showEstSheet<void>(
    context,
    maxWidth: 440,
    builder: (ctx) => EstSheetBody(
      title: 'Entrar na Rede Local',
      titleIcon: const EstIcon(EstIconKind.lan, size: 20, color: AppColors.gold),
      onClose: () => Navigator.pop(ctx),
      children: [
        const Text(
          'Conecte diretamente ao IP exibido na tela do anfitrião (mesmo Wi-Fi ou cabo, sem QR Code e sem servidor externo).',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.mute),
        ),
        const SizedBox(height: 12),
        const Text('Seu nome', style: TextStyle(fontSize: 12.5, color: AppColors.mute)),
        const SizedBox(height: 5),
        EstTextField(
          controller: nameCtrl,
          maxLength: 14,
          hintText: 'Seu apelido',
        ),
        const SizedBox(height: 10),
        const Text('Endereço do anfitrião (IP ou IP:Porta)', style: TextStyle(fontSize: 12.5, color: AppColors.mute)),
        const SizedBox(height: 5),
        EstTextField(
          controller: addrCtrl,
          autofocus: true,
          hintText: 'Ex.: 192.168.1.15 ou 192.168.1.15:7788',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
          onSubmitted: (_) => connect(ctx),
        ),
        const SizedBox(height: 10),
        const Text('Senha da sala (se houver)', style: TextStyle(fontSize: 12.5, color: AppColors.mute)),
        const SizedBox(height: 5),
        EstTextField(
          controller: passCtrl,
          obscureText: true,
          maxLength: 24,
          hintText: 'Deixe em branco se não houver senha',
          onSubmitted: (_) => connect(ctx),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: EstButton(
                variant: EstButtonVariant.primary,
                icon: EstIconKind.lan,
                label: 'Conectar',
                onPressed: () => connect(ctx),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EstButton(
                variant: EstButtonVariant.ghost,
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
