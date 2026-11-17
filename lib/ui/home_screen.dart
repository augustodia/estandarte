import 'dart:math';

import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../platform/lan_host.dart';
import 'modals.dart';
import 'theme.dart';

/// Tela inicial (sistema "Centro de Operações").
///
/// Deitado: coluna de comando à esquerda (marca, um único botão claro, lista de modos, nome) e o mapa à direita,
/// com o desafio do dia num cartão flutuante. Em pé: tudo numa coluna. Sem animação de fundo: o mapa é estático.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.ctrl.savedName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

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
                  opacity: landscape ? 1 : 0.35,
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
                    child: _commandColumn(compact: compact, withDaily: false),
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
                    Positioned(right: 0, top: 0, child: _howToPlay()),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: min(300.0, sz.width - _panelWidth(sz) - 40),
                      child: _DailyCard(ctrl: c, compact: compact, onTap: _openDaily, floating: true),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: _commandColumn(compact: compact, withDaily: true),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _panelWidth(Size sz) => sz.width >= 1100 ? 400 : (sz.width * 0.42).clamp(300.0, 360.0);

  void _openDaily() {
    c.savePlayerName(_nameCtrl.text);
    c.openDailyScreen();
  }

  Widget _howToPlay() => EstButton(
        small: true,
        icon: EstIconKind.book,
        label: 'Como jogar',
        onPressed: () => showRulesModal(context, c),
      );

  Widget _commandColumn({required bool compact, required bool withDaily}) {
    final items = <Widget>[
      if (c.hasSavedGuest)
        _ModeRow(
          title: 'Voltar à partida online',
          sub: 'Você saiu de uma partida que ainda está em curso',
          compact: compact,
          strong: true,
          onTap: c.resumeSavedGuest,
        ),
      if (c.hasSavedLocal)
        _ModeRow(
          title: 'Continuar partida salva',
          sub: 'Mesa local deste aparelho',
          compact: compact,
          strong: true,
          onTap: c.resumeSavedLocal,
        ),
      _ModeRow(
        title: 'Mesa local',
        sub: LanHost.supported ? 'Bots, rede local ou código de sala' : 'Bots, QR ou código de sala',
        compact: compact,
        onTap: () => c.startLocalSetup(hostName: _nameCtrl.text),
      ),
      _ModeRow(
        title: 'Salas online',
        sub: 'Escolha uma mesa ou entre com código',
        compact: compact,
        onTap: () {
          c.savePlayerName(_nameCtrl.text);
          c.openRoomsBrowser();
        },
      ),
      _ModeRow(
        title: 'Tutorial',
        sub: 'Aprenda o básico jogando',
        compact: compact,
        onTap: () => c.startTutorial(playerName: _nameCtrl.text),
      ),
      if (withDaily) ...[
        const SizedBox(height: Space.x3),
        _DailyCard(ctrl: c, compact: compact, onTap: _openDaily, floating: false),
        const SizedBox(height: Space.x2),
        Align(alignment: Alignment.centerLeft, child: _howToPlay()),
      ],
    ];

    final head = <Widget>[
        EstWordmark(size: compact ? 28 : 36),
        const SizedBox(height: 6),
        Text(
          'ESTRATÉGIA POR TERRITÓRIO · $appVersion'.toUpperCase(),
          style: AppText.label(size: 11),
        ),
        SizedBox(height: compact ? 12 : 20),
        _nameField(compact),
        SizedBox(height: compact ? 8 : 12),
        _QuickMatchButton(compact: compact, onTap: () => c.startQuickMatch(_nameCtrl.text)),
        SizedBox(height: compact ? 4 : 10),
    ];
    final footer = <Widget>[
        if (!c.netOnline)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text('SEM INTERNET · SÓ MESA LOCAL', style: AppText.label(size: 11, color: AppColors.mute)),
          ),
    ];

    return LayoutBuilder(builder: (context, box) {
      // Pouca altura (teclado aberto no celular deitado): tudo rola junto, com o nome visível no topo.
      if (box.maxHeight < 340) {
        return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...head, ...items, ...footer]),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...head,
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
            ),
          ),
          ...footer,
        ],
      );
    });
  }

  /// Nome do jogador: campo com rótulo, logo abaixo da marca (fica acima do teclado e é o primeiro passo).
  Widget _nameField(bool compact) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _nameCtrl,
      builder: (context, value, _) {
        final empty = value.text.trim().isEmpty;
        return Container(
          height: compact ? 42 : 48,
          padding: const EdgeInsets.only(left: Space.x3, right: Space.x2),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: empty ? AppColors.ink : AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Text('SEU NOME', style: AppText.label(size: 12, color: empty ? AppColors.ink : AppColors.faint)),
              Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.line),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  maxLength: 14,
                  onChanged: c.savePlayerName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  scrollPadding: const EdgeInsets.all(80),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                  decoration: const InputDecoration(
                    hintText: 'Como os outros vão te ver',
                    counterText: '',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              Icon(Icons.edit_outlined, size: 16, color: empty ? AppColors.ink : AppColors.faint),
            ],
          ),
        );
      },
    );
  }
}

/// O único botão claro da tela: a fila online.
class _QuickMatchButton extends StatelessWidget {
  const _QuickMatchButton({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.action,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          height: compact ? 46 : 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'PARTIDA RÁPIDA',
                    style: AppText.label(size: compact ? 17 : 19, color: AppColors.onAction, weight: FontWeight.w700)
                        .copyWith(letterSpacing: 1.0),
                  ),
                ),
                Text('ONLINE · ~45 S', style: AppText.label(size: 12, color: const Color(0xFF4A525E))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.title,
    required this.sub,
    required this.onTap,
    required this.compact,
    this.strong = false,
  });

  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool compact;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: compact ? 44 : 52,
        padding: const EdgeInsets.symmetric(horizontal: Space.x1),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(size: compact ? 15 : 18, color: strong ? AppColors.action : AppColors.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
          ],
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
