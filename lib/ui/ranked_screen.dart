import 'dart:async';

import 'package:flutter/material.dart';

import '../game/app_controller.dart';
import 'account_sheet.dart';
import 'crest_badge.dart';
import 'patente_badge.dart';
import 'theme.dart';

/// Ranqueada (Duelo): a sua patente e nota na temporada, a fila e o ranking da temporada.
class RankedScreen extends StatefulWidget {
  const RankedScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<RankedScreen> createState() => _RankedScreenState();
}

class _RankedScreenState extends State<RankedScreen> {
  Timer? _tick;

  AppController get c => widget.ctrl;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && c.rankedStatus == 'waiting') setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = EstLayout.of(context);
    final short = layout.size.height <= 520;
    final pad = layout.big ? 36.0 : (short ? 16.0 : 20.0);
    final wide = layout.size.width >= 760;
    final info = c.rankedInfo;
    final season = (info?['season'] as num?)?.toInt();
    final end = (info?['seasonEnd'] as num?)?.toInt();
    String sub = 'DUELO · 1 CONTRA 1';
    if (season != null && end != null) {
      final d = DateTime.fromMillisecondsSinceEpoch(end).subtract(const Duration(days: 1));
      sub = 'DUELO · TEMPORADA $season · ATÉ ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    }

    final left = _MePanel(ctrl: c, short: short);
    final right = _TopList(ctrl: c, short: short);

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, short ? 12 : 24, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      EstIconButton(
                        icon: EstIconKind.back,
                        size: 36,
                        iconSize: 16,
                        color: AppColors.ink,
                        tooltip: 'Voltar',
                        onPressed: () {
                          if (c.rankedStatus == 'waiting') unawaited(c.leaveRankedQueue());
                          c.goHome();
                        },
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Ranqueada', style: AppText.serif(size: layout.big ? 28 : (short ? 20 : 24))),
                            if (!short) ...[
                              const SizedBox(height: 2),
                              Text(sub, style: AppText.label(size: 11)),
                            ],
                          ],
                        ),
                      ),
                      Tooltip(
                        message: 'Atualizar',
                        child: InkWell(
                          onTap: c.rankedLoading ? null : c.refreshRanked,
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.sm),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: c.rankedLoading ? AppColors.mute : AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: short ? 12 : 22),
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 360, child: SingleChildScrollView(child: left)),
                              const SizedBox(width: 24),
                              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 24), child: right)),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [left, const SizedBox(height: 22), right],
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
}

/// A sua patente, a nota e a fila.
class _MePanel extends StatelessWidget {
  const _MePanel({required this.ctrl, required this.short});

  final AppController ctrl;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    final info = c.rankedInfo;
    final me = info?['me'] as Map<String, dynamic>?;
    final children = <Widget>[];

    if (!c.signedIn) {
      children.addAll([
        const Text(
          'A ranqueada vale nota e patente, então precisa de conta com e-mail confirmado.',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.mute),
        ),
        const SizedBox(height: 14),
        EstButton(label: 'Entrar ou criar conta', variant: EstButtonVariant.primary, onPressed: () => showAccountSheet(context, c)),
      ]);
    } else {
      final pat = (me?['patente'] as num?)?.toInt() ?? -1;
      final placement = (me?['placement'] as num?)?.toInt() ?? 5;
      final r = (me?['r'] as num?)?.toInt();
      final wins = (me?['wins'] as num?)?.toInt() ?? 0;
      final losses = (me?['losses'] as num?)?.toInt() ?? 0;
      final pos = (info?['position'] as num?)?.toInt() ?? 0;
      children.add(Row(
        children: [
          PatenteBadge(pat, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me?['patenteName'] as String? ?? 'Em colocação', style: AppText.title(size: 22)),
                const SizedBox(height: 3),
                Text(
                  me == null
                      ? 'Buscando a sua nota…'
                      : placement > 0
                          ? 'Faltam $placement ${placement == 1 ? 'partida' : 'partidas'} de colocação'
                          : 'Nota $r${pos > 0 ? ' · $posº lugar' : ''}',
                  style: const TextStyle(fontSize: 13, color: AppColors.mute),
                ),
              ],
            ),
          ),
          if (me != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$wins V · $losses D', style: AppText.number(size: 15, color: AppColors.ink, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${wins + losses} partidas', style: const TextStyle(fontSize: 11.5, color: AppColors.mute)),
              ],
            ),
        ],
      ));
      children.add(SizedBox(height: short ? 16 : 22));
      children.add(_QueueBox(ctrl: c));
    }
    children.addAll([
      SizedBox(height: short ? 16 : 22),
      const EstSectionTag('REGRAS DO DUELO'),
      const SizedBox(height: 8),
      const Text(
        '1 contra 1, turno de 60 s, Quartel e eventos ligados, sem ogivas e sem pactos. Sem espectadores: o replay sai '
        'no fim. Sair, cair por mais de 90 s ou deixar o prazo vencer 3 vezes seguidas conta como derrota por abandono '
        'e deixa você um tempo fora da fila. Desistir pelo menu não é abandono.',
        style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.mute),
      ),
      const SizedBox(height: 10),
      const Text(
        'A nota usa o Glicko-2: as primeiras 5 partidas mexem mais. As patentes vão de Recruta a Marechal, e o ranking '
        'recomeça a cada 2 meses, com a nota puxada para o meio.',
        style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.mute),
      ),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _QueueBox extends StatelessWidget {
  const _QueueBox({required this.ctrl});

  final AppController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    final info = c.rankedInfo;
    final room = info?['room'] as String?;
    final cooldown = (info?['cooldownUntil'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final err = c.rankedError;
    Widget errText(String m) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(m, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.bad)),
        );

    if (room != null && c.rankedStatus == 'idle') {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        EstButton(label: 'Voltar ao duelo', variant: EstButtonVariant.primary, height: 48, onPressed: c.rejoinRankedDuel),
        errText('Você tem um duelo em andamento. Se não voltar, ele conta como derrota por abandono.'),
      ]);
    }
    if (c.rankedStatus == 'waiting' || c.rankedStatus == 'joining' || c.rankedStatus == 'matched') {
      final secs = c.rankedWaitSecs;
      final mm = (secs ~/ 60).toString();
      final ss = (secs % 60).toString().padLeft(2, '0');
      final others = c.rankedQueueSize > 1 ? '${c.rankedQueueSize - 1} na fila com você' : 'só você na fila agora';
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.rankedStatus == 'matched' ? 'Adversário encontrado! Entrando…' : 'Procurando adversário',
                    style: AppText.title(size: 17),
                  ),
                ),
                Text('$mm:$ss', style: AppText.number(size: 17, color: AppColors.ink, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$others · quanto mais espera, mais larga a faixa de nota aceita',
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),
            const SizedBox(height: 12),
            EstButton(
              label: 'Sair da fila',
              variant: EstButtonVariant.ghost,
              onPressed: c.rankedStatus == 'waiting' ? c.leaveRankedQueue : null,
            ),
          ],
        ),
      );
    }
    final blocked = cooldown > now;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EstButton(
        label: 'Entrar na fila',
        variant: EstButtonVariant.primary,
        height: 48,
        onPressed: blocked || c.rankedLoading ? null : c.joinRankedQueue,
      ),
      if (blocked)
        errText('Por abandonar partidas ranqueadas, você volta à fila às '
            '${_hhmm(DateTime.fromMillisecondsSinceEpoch(cooldown))}.')
      else if (err != null)
        errText(err),
      if (info != null && info['verified'] == false)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: EstButton(
            small: true,
            variant: EstButtonVariant.ghost,
            label: 'Confirmar e-mail',
            onPressed: () => showAccountSheet(context, c),
          ),
        ),
    ]);
  }

  static String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// As maiores notas da temporada.
class _TopList extends StatelessWidget {
  const _TopList({required this.ctrl, required this.short});

  final AppController ctrl;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    final list = c.rankedTopList;
    final myName = c.account?.username;
    final rows = <Widget>[
      const EstSectionTag('RANKING DA TEMPORADA'),
      const SizedBox(height: 10),
    ];
    if (list.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          c.rankedLoading
              ? 'Buscando o ranking…'
              : (c.rankedError ?? 'Ninguém passou da colocação ainda nesta temporada. O pódio está livre.'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
        ),
      ));
    }
    for (final e in list) {
      final pos = (e['pos'] as num?)?.toInt() ?? 0;
      final mine = e['name'] == myName;
      rows.add(Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: mine ? AppColors.panel2 : AppColors.obsidian.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: mine ? AppColors.ink : AppColors.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$posº',
                style: AppText.number(size: 14, color: pos <= 3 ? AppColors.ink : AppColors.mute, weight: FontWeight.w700),
              ),
            ),
            PatenteBadge((e['patente'] as num?)?.toInt() ?? 0, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NameWithCrest(
                    e['name'] as String? ?? '',
                    crest: e['crest'] as String? ?? '',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  Text(
                    '${e['patenteName']} · ${e['wins']} V · ${e['losses']} D',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.mute),
                  ),
                ],
              ),
            ),
            Text('${e['r']}', style: AppText.number(size: 16, color: AppColors.ink, weight: FontWeight.w700)),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows);
  }
}
