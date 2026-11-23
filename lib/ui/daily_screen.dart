import 'dart:async';
import 'package:flutter/material.dart';

import '../game/app_controller.dart';
import '../game/crests.dart';
import '../game/daily_challenge.dart';
import 'account_sheet.dart';
import 'crest_badge.dart';
import 'crests_sheet.dart';
import 'theme.dart';

class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  String _rightTab = 'ranking'; // 'ranking' | 'codex'
  bool _yesterday = false; // ranking de ontem (com os replays para assistir)
  Timer? _tick;
  int _elapsedSecs = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSecs++);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DailyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _formatCountdown(int baseSecs) {
    final rem = (baseSecs - _elapsedSecs).clamp(0, 86400);
    final h = rem ~/ 3600;
    final m = (rem % 3600) ~/ 60;
    final s = rem % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  String _formatDuration(int sec) {
    if (sec < 60) return '${sec}s';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final layout = EstLayout.of(context);
    final snap = c.dailySnapshot;
    final spec = snap?.challenge;
    final isHist = spec?.isHistorical == true;
    final todayStars = c.todayChallengeStars;

    Widget headerBar() => Row(
          children: [
            EstIconButton(
              icon: EstIconKind.back,
              size: 36,
              iconSize: 16,
              color: AppColors.ink,
              tooltip: 'Voltar',
              onPressed: c.goHome,
            ),
            const SizedBox(width: 12),
            EstIcon(
              isHist ? EstIconKind.book : EstIconKind.medal,
              size: layout.big ? 24 : 20,
              color: AppColors.gold,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isHist ? 'Quinta Histórica' : 'Desafio do Dia',
                overflow: TextOverflow.ellipsis,
                style: AppText.serif(
                  size: layout.big ? 28 : 22,
                  color: isHist ? AppColors.gold : AppColors.ink,
                ),
              ),
            ),
            if (snap != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: snap.fromServer ? AppColors.line : AppColors.brassDim,
                  ),
                ),
                child: Text(
                  'Reseta em ${_formatCountdown(snap.resetInSecs)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mute,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Material(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: c.dailyLoading
                    ? null
                    : () {
                        _elapsedSecs = 0;
                        c.refreshDailyChallenge();
                      },
                borderRadius: BorderRadius.circular(4),
                child: Tooltip(
                  message: 'Sincronizar com servidor',
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.line),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: c.dailyLoading ? AppColors.mute : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

    Widget starRow(int stars, String label, bool achieved) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  '★' * stars,
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 1.0,
                    color: achieved ? AppColors.gold : const Color(0xFF7D8796),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.32,
                    color: achieved ? AppColors.ink : AppColors.mute,
                    fontWeight: achieved ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );

    Widget ruleBadge(ChallengeRuleTag tag, {required bool isMutation}) {
      final accent = isMutation ? AppColors.bad : const Color(0xFF9AA4B2);
      return Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isMutation ? 'RESTRIÇÃO' : 'DOUTRINA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tag.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              tag.desc,
              style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.mute),
            ),
          ],
        ),
      );
    }

    Widget briefingPanel() {
      if (spec == null) {
        final isWaiting = c.dailyLoading;
        return EstGlassCard(
          ornate: false,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          borderRadius: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.obsidian,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.brassDim),
                  ),
                  alignment: Alignment.center,
                  child: EstIcon(
                    isWaiting ? EstIconKind.compass : EstIconKind.globe,
                    size: 20,
                    color: AppColors.gold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isWaiting ? 'Sincronizando operação…' : 'Servidor indisponível',
                textAlign: TextAlign.center,
                style: AppText.serif(size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                isWaiting
                    ? 'Buscando a semente oficial e o ranking de hoje.'
                    : (c.dailyError ?? 'Conecte-se à internet para baixar a missão de hoje.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
              ),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 210,
                  child: EstButton(
                    label: isWaiting ? 'Conectando…' : 'Tentar novamente',
                    variant: EstButtonVariant.pact,
                    height: 40,
                    onPressed: isWaiting ? null : () => c.refreshDailyChallenge(),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return EstGlassCard(
        highlight: isHist,
        padding: EdgeInsets.all(layout.big ? 20 : 16),
        borderRadius: 6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isHist
                        ? AppColors.gold.withValues(alpha: 0.16)
                        : AppColors.ink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isHist ? AppColors.brass : AppColors.line,
                    ),
                  ),
                  child: Text(
                    isHist
                        ? 'CRÔNICA CANÔNICA · ${spec.era.isNotEmpty ? spec.era : spec.date}'
                        : 'SEMENTE ${spec.date}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: isHist ? AppColors.gold : AppColors.mute,
                    ),
                  ),
                ),
                const Spacer(),
                if (todayStars > 0)
                  Text(
                    '★' * todayStars + '☆' * (3 - todayStars),
                    style: const TextStyle(fontSize: 13, color: AppColors.gold, letterSpacing: 1.5),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              spec.title,
              style: AppText.serif(size: layout.big ? 26 : 22),
            ),
            const SizedBox(height: 2),
            Text(
              spec.subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.gold, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              spec.briefing,
              style: const TextStyle(fontSize: 13, height: 1.42, color: Color(0xFFE8ECF1)),
            ),
            const SizedBox(height: 14),
            const EstSectionTag('OBJETIVO & MEDALHAS'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    spec.goal.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: AppColors.line),
                  const SizedBox(height: 6),
                  starRow(1, spec.goal.star1Desc, todayStars >= 1),
                  starRow(2, spec.goal.star2Desc, todayStars >= 2),
                  starRow(3, spec.goal.star3Desc, todayStars >= 3),
                ],
              ),
            ),
            if (spec.doctrines.isNotEmpty || spec.mutations.isNotEmpty) ...[
              const SizedBox(height: 14),
              const EstSectionTag('REGRAS DO TEATRO'),
              const SizedBox(height: 8),
              for (final d in spec.doctrines) ruleBadge(d, isMutation: false),
              for (final m in spec.mutations) ruleBadge(m, isMutation: true),
            ],
            const SizedBox(height: 10),
            const EstSectionTag('DIFICULDADE'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: EstChip(
                    label: 'Padrão',
                    height: 38,
                    selected: c.challengeDifficulty == 'standard',
                    onTap: () => c.setChallengeDifficulty('standard'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstChip(
                    label: 'Marechal (+Difícil)',
                    height: 38,
                    selected: c.challengeDifficulty == 'marechal',
                    onTap: () => c.setChallengeDifficulty('marechal'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              c.challengeDifficulty == 'marechal'
                  ? 'Fronteiras inimigas recebem +1 tropa, bots ganham medalha inicial extra e sua vitória pontua acima no ranking.'
                  : 'Equilíbrio oficial da missão de hoje.',
              style: const TextStyle(fontSize: 11, color: AppColors.mute),
            ),
            const SizedBox(height: 14),
            EstButton(
              icon: EstIconKind.sword,
              variant: EstButtonVariant.primary,
              height: 48,
              label: todayStars > 0 ? 'Jogar Novamente' : 'Iniciar Missão',
              onPressed: () => c.startDailyChallenge(),
            ),
          ],
        ),
      );
    }

    Widget rankingList(List<DailyRankEntry> entries) {
      if (entries.isEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          decoration: BoxDecoration(
            color: AppColors.obsidian.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            _yesterday
                ? 'Ninguém entrou no ranking ontem.'
                : 'Nenhum comandante concluiu esta missão hoje ainda.\nVença para inaugurar o pódio!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.mute),
          ),
        );
      }
      return Column(
        children: [
          for (final e in entries)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: e.rank == 1
                    ? AppColors.gold.withValues(alpha: 0.10)
                    : AppColors.obsidian.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: e.rank == 1 ? AppColors.brassDim : AppColors.line,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#${e.rank}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: e.rank == 1
                            ? AppColors.gold
                            : (e.rank <= 3 ? AppColors.ink : AppColors.mute),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: NameWithCrest(
                                e.playerName,
                                crest: e.crest,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            if (e.difficulty == 'marechal') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: AppColors.brassDim),
                                ),
                                child: const Text(
                                  'MARECHAL',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.gold,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${e.rounds} rodadas · −${e.armiesLost} baixas · ${_formatDuration(e.durationSec)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '★' * e.stars + '☆' * (3 - e.stars),
                    style: const TextStyle(fontSize: 13, color: AppColors.gold, letterSpacing: 1.0),
                  ),
                  if (e.replay.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    EstIconButton(
                      icon: EstIconKind.play,
                      size: 30,
                      iconSize: 15,
                      color: AppColors.mute,
                      tooltip: 'Assistir a partida',
                      onPressed: c.replayLoading ? null : () => c.openReplay(e.replay),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    }

    Widget codexPanel() {
      final weekDone = c.weeklyChallengeDaysCount;
      final unlockedCount =
          historicalCodexCatalog.where((m) => c.codexProgress.containsKey(m.id)).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: weekDone >= 4 ? AppColors.brass : AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'META SEMANAL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.gold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$weekDone / 4 dias recomendados (últimos 7 dias)',
                      style: const TextStyle(fontSize: 11, color: AppColors.mute),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: i < weekDone ? AppColors.gold : const Color(0xFF262E39),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: EstSectionTag('CÓDICE HISTÓRICO ($unlockedCount / ${historicalCodexCatalog.length})'),
              ),
              const SizedBox(width: 10),
              EstButton(
                small: true,
                variant: EstButtonVariant.ghost,
                icon: EstIconKind.crest,
                label: 'Brasões',
                onPressed: () => showCrestsSheet(context, c, onSignIn: () => showAccountSheet(context, c)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final meta in historicalCodexCatalog)
            Builder(
              builder: (_) {
                final rec = c.codexProgress[meta.id];
                final unlocked = rec is Map;
                final bStars = unlocked ? (rec['bestStars'] as num?)?.toInt() ?? 1 : 0;
                final bRounds = unlocked ? (rec['bestRounds'] as num?)?.toInt() ?? 0 : 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.obsidian.withValues(alpha: unlocked ? 0.9 : 0.45),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: unlocked ? AppColors.brassDim : AppColors.line,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CrestBadge(
                        verifiedStars(c.codexProgress, meta.id) > 0
                            ? '${meta.id}:${verifiedStars(c.codexProgress, meta.id)}'
                            : '${meta.id}:1',
                        size: 34,
                        locked: verifiedStars(c.codexProgress, meta.id) == 0,
                        tooltip: true,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            meta.era.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: unlocked ? AppColors.gold : AppColors.mute,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            unlocked ? '${'★' * bStars} · R$bRounds' : 'Bloqueado',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: unlocked ? AppColors.gold : const Color(0xFF7D8796),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: unlocked ? AppColors.ink : AppColors.mute,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        unlocked
                            ? meta.lore
                            : 'Disponível na rotação das Quintas-feiras Históricas.',
                        style: const TextStyle(fontSize: 12, height: 1.35, color: AppColors.mute),
                      ),
                    ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      );
    }

    Widget rightColumn() {
      final entries = snap?.ranking ?? const <DailyRankEntry>[];
      return EstGlassCard(
        ornate: false,
        padding: EdgeInsets.all(layout.big ? 20 : 16),
        borderRadius: 6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _DailyTab(
                      label: 'Ranking (${entries.length})',
                      active: _rightTab == 'ranking',
                      onTap: () => setState(() => _rightTab = 'ranking'),
                    ),
                  ),
                  Expanded(
                    child: _DailyTab(
                      label: 'Códice & Semana',
                      active: _rightTab == 'codex',
                      onTap: () => setState(() => _rightTab = 'codex'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_rightTab == 'ranking') ...[
              Row(
                children: [
                  for (final y in [false, true]) ...[
                    _DayChip(
                      label: y ? 'Ontem' : 'Hoje',
                      active: _yesterday == y,
                      onTap: () {
                        setState(() => _yesterday = y);
                        if (y && c.yesterdayRanking == null) c.loadYesterdayRanking();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                  const Spacer(),
                  if (!_yesterday && c.todayReplayId != null)
                    EstButton(
                      small: true,
                      variant: EstButtonVariant.ghost,
                      icon: EstIconKind.play,
                      label: 'Sua partida',
                      onPressed: c.replayLoading ? null : () => c.openReplay(c.todayReplayId!),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _yesterday
                    ? '${c.yesterdayTitle.isNotEmpty ? '${c.yesterdayTitle}. ' : ''}Use o botão de assistir para ver a partida de cada comandante.'
                    : 'Só entram partidas com conta, conferidas pelo servidor. Ordenado por Estrelas → Marechal → '
                        'Menos rodadas → Baixas. As partidas ficam para assistir quando o dia virar.',
                style: const TextStyle(fontSize: 11, height: 1.35, color: AppColors.mute),
              ),
              const SizedBox(height: 10),
              if (_yesterday && c.yesterdayRanking == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.faint),
                    ),
                  ),
                )
              else
                rankingList(_yesterday ? c.yesterdayRanking! : entries),
            ] else
              codexPanel(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Align(
          // no celular o topo fica no topo (centralizar deixava o cabeçalho flutuando no meio)
          alignment: layout.big ? Alignment.center : Alignment.topCenter,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(layout.big ? 26 : 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.big ? 1040 : 500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  headerBar(),
                  const SizedBox(height: 14),
                  if (layout.big)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 11, child: briefingPanel()),
                        const SizedBox(width: 22),
                        Expanded(flex: 10, child: rightColumn()),
                      ],
                    )
                  else ...[
                    briefingPanel(),
                    const SizedBox(height: 12),
                    rightColumn(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyTab extends StatelessWidget {
  const _DailyTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: active ? AppColors.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: active ? Border.all(color: const Color(0xFF7D8796)) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            color: active ? AppColors.ink : AppColors.mute,
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.panel2 : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: active ? AppColors.ink : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.ink : AppColors.mute,
            ),
          ),
        ),
      );
}
