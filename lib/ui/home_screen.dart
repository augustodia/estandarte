import 'dart:math';

import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../platform/lan_host.dart';
import 'account_sheet.dart';
import 'modals.dart';
import 'theme.dart';

/// Tela inicial (sistema "Centro de Operações").
///
/// Os modos se organizam pelo tempo que a pessoa tem, numa tabela de três linhas:
/// AGORA (partida rápida e salas online), NO SEU TEMPO (correspondência, 24 h por jogada) e NA MESA (local, sem
/// internet). A conta é um selo no canto; o tutorial e as regras ficam no rodapé. Deitado: a tabela numa coluna à
/// esquerda e o mapa à direita, com o desafio do dia flutuando. Em pé: tudo numa coluna.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController get c => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final landscape = sz.width > sz.height && sz.width >= 640;
    final compact = estCompact(context);

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            left: landscape ? _panelWidth(sz) : 0,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Opacity(
                  opacity: landscape ? 1 : 0.3,
                  child: CustomPaint(painter: _HomeMapPainter(c.mapData)),
                ),
              ),
            ),
          ),
          if (landscape) ...[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _panelWidth(sz),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.deep,
                  border: Border(right: BorderSide(color: AppColors.line)),
                ),
                child: SafeArea(
                  right: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 20 : 28, compact ? 16 : 28, compact ? 20 : 28, compact ? 10 : 18),
                    child: _commandColumn(dense: compact, portrait: false),
                  ),
                ),
              ),
            ),
            SafeArea(
              left: false,
              child: Padding(
                padding: EdgeInsets.all(compact ? 14 : 22),
                child: Stack(
                  children: [
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FriendsButton(ctrl: c),
                          const SizedBox(width: 8),
                          _AccountSeal(ctrl: c, onTap: _openAccount),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: min(300.0, sz.width - _panelWidth(sz) - 40),
                      child: _DailyCard(ctrl: c, compact: compact, onTap: c.openDailyScreen, floating: true),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                    child: _commandColumn(dense: false, portrait: true),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _panelWidth(Size sz) => sz.width >= 1100 ? 420 : (sz.width * 0.44).clamp(320.0, 380.0);

  void _openAccount() => showAccountSheet(context, c);

  Widget _commandColumn({required bool dense, required bool portrait}) {
    final resume = <Widget>[
      if (c.hasSavedGuest)
        _ResumeRow(
          title: 'Voltar à partida online',
          sub: 'Ainda em curso',
          dense: dense,
          onTap: c.resumeSavedGuest,
        ),
      if (c.hasSavedLocal)
        _ResumeRow(
          title: 'Continuar partida salva',
          sub: 'Mesa local deste aparelho',
          dense: dense,
          onTap: c.resumeSavedLocal,
        ),
    ];

    final ledger = _PaceLedger(ctrl: c, dense: dense);

    final head = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: EstWordmark(size: dense ? 28 : 36),
                ),
                const SizedBox(height: 6),
                Text(
                  'ESTRATÉGIA POR TERRITÓRIO · $appVersion'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(size: 11),
                ),
              ],
            ),
          ),
          if (portrait) ...[
            _FriendsButton(ctrl: c),
            const SizedBox(width: 8),
            _AccountSeal(ctrl: c, onTap: _openAccount),
          ],
        ],
      ),
      SizedBox(height: portrait ? 36 : (dense ? 16 : 30)),
      for (final r in resume) ...[r, SizedBox(height: dense ? 8 : 10)],
    ];

    final footer = _Footer(ctrl: c, dense: dense);

    return LayoutBuilder(builder: (context, box) {
      if (portrait) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...head,
                  ledger,
                  const SizedBox(height: 28),
                  _DailyStrip(ctrl: c, onTap: c.openDailyScreen),
                  const Spacer(),
                  const SizedBox(height: 20),
                  footer,
                ],
              ),
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...head, ledger]),
            ),
          ),
          SizedBox(height: dense ? 6 : 12),
          footer,
        ],
      );
    });
  }
}

/// Os modos pelo tempo que você tem: uma coluna estreita com o ritmo e, ao lado, o que jogar.
class _PaceLedger extends StatelessWidget {
  const _PaceLedger({required this.ctrl, required this.dense});

  final AppController ctrl;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    final yours = c.corrYourTurn;
    final invites = c.corrInvites;
    final playing = c.corrGames.where((g) => g.playing).length;
    final String corrSub;
    if (!c.signedIn) {
      corrSub = '24 h por jogada · avisamos por e-mail';
    } else if (invites.isNotEmpty) {
      corrSub = invites.length == 1 ? '${invites.first.from} te chamou para uma partida' : '${invites.length} convites de amigos';
    } else if (yours > 0) {
      corrSub = yours == 1 ? 'Uma partida espera a sua jogada' : '$yours partidas esperam a sua jogada';
    } else if (playing > 0) {
      corrSub = playing == 1 ? '1 em andamento · vez dos outros' : '$playing em andamento · vez dos outros';
    } else {
      corrSub = '24 h por jogada · avisamos por e-mail';
    }

    final me = c.signedIn ? (c.rankedInfo?['me'] as Map<String, dynamic>?) : null;
    final rankedSub = c.rankedInfo?['room'] != null
        ? 'Você tem um duelo em andamento'
        : me != null && ((me['placement'] as num?)?.toInt() ?? 5) == 0
            ? '${me['patenteName']} · nota ${me['r']}'
            : 'Duelo 1 contra 1 · vale nota e patente';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuickMatchRow(dense: dense, onTap: () => c.startQuickMatch(c.onlineName)),
        _LedgerRow(
          pace: null,
          title: 'Salas online',
          sub: 'Escolha uma mesa ou entre com código',
          dense: dense,
          onTap: c.openRoomsBrowser,
        ),
        _LedgerRow(
          pace: 'VALENDO\nPATENTE',
          title: 'Ranqueada',
          sub: rankedSub,
          dense: dense,
          onTap: c.openRankedScreen,
        ),
        _LedgerRow(
          pace: 'NO SEU\nTEMPO',
          title: 'Correspondência',
          sub: corrSub,
          dense: dense,
          badge: yours + invites.length > 0 ? '${yours + invites.length}' : null,
          onTap: c.openCorrScreen,
        ),
        _LedgerRow(
          pace: 'NA MESA',
          title: 'Mesa local',
          sub: LanHost.supported ? 'Bots, rede local ou código · sem internet' : 'Bots, QR ou código · sem internet',
          dense: dense,
          onTap: () => c.startLocalSetup(),
          last: true,
        ),
      ],
    );
  }
}

const double _paceCol = 74;

/// AGORA: a linha clara, o único botão claro da tela.
class _QuickMatchRow extends StatelessWidget {
  const _QuickMatchRow({required this.dense, required this.onTap});

  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const dim = Color(0xFF59616D);
    return Material(
      color: AppColors.action,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          height: dense ? 48 : 56,
          child: Row(
            children: [
              SizedBox(
                width: _paceCol,
                child: Padding(
                  padding: const EdgeInsets.only(left: Space.x3),
                  child: Text('AGORA', style: AppText.label(size: 11.5, color: dim, weight: FontWeight.w700)),
                ),
              ),
              Expanded(
                child: Text(
                  'PARTIDA RÁPIDA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(size: dense ? 17 : 19, color: AppColors.onAction, weight: FontWeight.w700)
                      .copyWith(letterSpacing: 1.0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.x3, left: Space.x2),
                child: Text('ONLINE · ~45 S', style: AppText.label(size: 12, color: dim)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.pace,
    required this.title,
    required this.sub,
    required this.dense,
    required this.onTap,
    this.badge,
    this.last = false,
  });

  final String? pace;
  final String title;
  final String sub;
  final bool dense;
  final String? badge;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = dense ? 50.0 : 62.0;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          border: Border(
            top: pace != null ? const BorderSide(color: AppColors.line) : BorderSide.none,
            bottom: last ? const BorderSide(color: AppColors.line) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _paceCol,
              child: pace == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: Space.x3),
                      child: Text(pace!, style: AppText.label(size: 11.5).copyWith(height: 1.2)),
                    ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(size: dense ? 16 : 19),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: badge != null ? AppColors.ink : AppColors.mute),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(11)),
                child: Text(badge!, style: AppText.number(size: 13, color: AppColors.onAction, weight: FontWeight.w700)),
              ),
            const SizedBox(width: Space.x2),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
            const SizedBox(width: Space.x1),
          ],
        ),
      ),
    );
  }
}

/// Partida guardada para retomar: aparece acima da tabela, com a cor de ação no título.
class _ResumeRow extends StatelessWidget {
  const _ResumeRow({required this.title, required this.sub, required this.dense, required this.onTap});

  final String title;
  final String sub;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          height: dense ? 42 : 48,
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                    TextSpan(text: '  ·  $sub', style: const TextStyle(color: AppColors.mute)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Amigos: quantos estão com o jogo aberto; pedidos de amizade esperando resposta acendem um número.
class _FriendsButton extends StatelessWidget {
  const _FriendsButton({required this.ctrl});

  final AppController ctrl;

  @override
  Widget build(BuildContext context) {
    final pending = ctrl.friends.incoming.length;
    final online = ctrl.friendsOnline;
    return Tooltip(
      message: 'Amigos',
      child: Material(
        color: AppColors.deep,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          onTap: ctrl.openFriendsScreen,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.group_outlined, size: 17, color: AppColors.ink),
                if (pending > 0) ...[
                  const SizedBox(width: 7),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(9)),
                    child: Text('$pending', style: AppText.number(size: 11.5, color: AppColors.onAction, weight: FontWeight.w700)),
                  ),
                ] else if (online > 0) ...[
                  const SizedBox(width: 7),
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('$online', style: AppText.number(size: 13, color: AppColors.ink, weight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selo da conta: o nome (ou ENTRAR). E-mail sem confirmar ganha um ponto.
class _AccountSeal extends StatelessWidget {
  const _AccountSeal({required this.ctrl, required this.onTap});

  final AppController ctrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = ctrl.account;
    final warn = ctrl.accountNeedsConfirm;
    return Material(
      color: AppColors.deep,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          height: 36,
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: warn ? AppColors.medal : AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EstIcon(EstIconKind.crest, size: 14, color: a == null ? AppColors.mute : AppColors.ink),
              const SizedBox(width: 8),
              Flexible(
                child: a == null
                    ? Text('ENTRAR', style: AppText.label(size: 13, color: AppColors.ink, weight: FontWeight.w700))
                    : Text(
                        a.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
              ),
              if (warn) ...[
                const SizedBox(width: 8),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: AppColors.medal, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rodapé: tutorial e regras. Para quem chega pela primeira vez, o tutorial vem na frente e aceso.
class _Footer extends StatelessWidget {
  const _Footer({required this.ctrl, required this.dense});

  final AppController ctrl;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    final fresh = c.isNewcomer;
    Widget link(String label, VoidCallback onTap, {bool lit = false}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x1, vertical: Space.x2),
            child: Text(label, style: AppText.label(size: 12.5, color: lit ? AppColors.ink : AppColors.mute)),
          ),
        );
    Widget sep() => Container(width: 1, height: 12, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.line);
    return Row(
      children: [
        Expanded(
          child: FittedBox( // telas estreitas: os atalhos encolhem em vez de estourar a linha
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fresh) ...[
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                  ),
                  link('PRIMEIRA VEZ? TUTORIAL', () => c.startTutorial(), lit: true),
                ] else
                  link('TUTORIAL', () => c.startTutorial()),
                sep(),
                link('COMO JOGAR', () => showRulesModal(context, c)),
                sep(),
                link('COMANDANTE', c.openStoreScreen, lit: c.isComandante),
              ],
            ),
          ),
        ),
        if (!c.netOnline) ...[
          const SizedBox(width: 8),
          Text('SEM INTERNET', style: AppText.label(size: 11, color: AppColors.bad)),
        ],
      ],
    );
  }
}

/// Desafio do dia em pé: uma faixa fina abaixo da tabela.
class _DailyStrip extends StatelessWidget {
  const _DailyStrip({required this.ctrl, required this.onTap});

  final AppController ctrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spec = ctrl.dailySnapshot?.challenge;
    final isHist = spec?.isHistorical == true || DateTime.now().weekday == DateTime.thursday;
    final stars = ctrl.todayChallengeStars;
    final title = spec?.title ?? (isHist ? 'Crônica de quinta' : 'Mesma partida para todos');
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Text((isHist ? 'QUINTA HISTÓRICA' : 'DESAFIO DO DIA'), style: AppText.label(size: 11)),
              Container(width: 1, height: 14, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.line),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 15,
                    color: AppColors.medal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.ctrl,
    required this.compact,
    required this.onTap,
    required this.floating,
  });

  final AppController ctrl;
  final bool compact;
  final VoidCallback onTap;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final snap = ctrl.dailySnapshot;
    final spec = snap?.challenge;
    final isHist = spec?.isHistorical == true || DateTime.now().weekday == DateTime.thursday;
    final stars = ctrl.todayChallengeStars;
    final title = spec?.title ?? (isHist ? 'Crônica de quinta' : 'Desafio do dia');
    final sub = spec != null
        ? (isHist ? '${spec.era} · mesma partida para todos' : '${spec.subtitle} · ${snap?.totalRanked ?? 0} no ranking')
        : (ctrl.dailyLoading ? 'Sincronizando…' : 'Mesma partida para todos. Vença em menos rodadas.');

    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Ink(
          padding: EdgeInsets.all(compact ? Space.x3 : Space.x4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: AppColors.line),
            boxShadow: floating ? AppColors.edgeShadows : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (isHist ? 'Quinta histórica' : 'Desafio do dia').toUpperCase(),
                      style: AppText.label(size: 11),
                    ),
                  ),
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(
                        i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 15,
                        color: AppColors.medal,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.x1),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title(size: compact ? 18 : 22)),
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.mute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O mapa de fundo da tela inicial: territórios em tons escuros do continente, sem números.
class _HomeMapPainter extends CustomPainter {
  const _HomeMapPainter(this.mapData);

  final MapData mapData;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.sea);
    final scale = max(size.width / mapData.width, size.height / mapData.height) * 1.02;
    final tx = (size.width - mapData.width * scale) / 2;
    final ty = (size.height - mapData.height * scale) / 2;

    canvas.save();
    canvas.translate(tx, ty);
    canvas.scale(scale, scale);

    final grid = Paint()
      ..color = const Color(0xFF111821)
      ..strokeWidth = 1 / scale;
    for (var x = 0.0; x <= mapData.width; x += 71) {
      canvas.drawLine(Offset(x, 0), Offset(x, mapData.height.toDouble()), grid);
    }
    for (var y = 0.0; y <= mapData.height; y += 71) {
      canvas.drawLine(Offset(0, y), Offset(mapData.width.toDouble(), y), grid);
    }

    final stroke = Paint()
      ..color = AppColors.deep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / scale
      ..strokeJoin = StrokeJoin.round;
    for (final tr in mapData.territories) {
      final base = mapData.continents[tr.continent].color;
      canvas.drawPath(tr.path, Paint()..color = Color.lerp(base, AppColors.deep, 0.78)!);
      canvas.drawPath(tr.path, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HomeMapPainter old) => old.mapData != mapData;
}
