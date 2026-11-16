import 'dart:math';

import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../platform/lan_host.dart';
import 'modals.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final TextEditingController _nameCtrl;
  late final AnimationController _artCtrl;
  late final AnimationController _crestCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.ctrl.savedName);
    _artCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..repeat(reverse: true);
    _crestCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _artCtrl.dispose();
    _crestCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final layout = EstLayout.of(context);
    final sz = layout.size;
    final compactLand = !layout.big && sz.width > sz.height && sz.height <= 520;
    final twoColBig = layout.big && !layout.tall;

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background radial glow matching #home
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: twoColBig ? const Alignment(-0.4, -0.4) : const Alignment(0, -1.0),
                radius: twoColBig ? 1.05 : 1.15,
                colors: const [Color(0x991C2D46), Color(0x0009101B)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: twoColBig ? const Alignment(0.55, 0.35) : const Alignment(0, 1.0),
                radius: 0.95,
                colors: const [Color(0x44382A16), Color(0x0009101B)],
              ),
            ),
          ),

          // #homeart animated map silhouette with radial vignette mask
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _artCtrl,
                builder: (context, child) {
                  final t = Curves.easeInOut.transform(_artCtrl.value);
                  final scale = 1.0 + 0.06 * t;
                  final dx = -0.01 * sz.width * t;
                  final dy = 0.01 * sz.height * t;
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: ShaderMask(
                  shaderCallback: (bounds) => const RadialGradient(
                    center: Alignment(0, -0.1),
                    radius: 0.78,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.30, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: Opacity(
                    opacity: layout.big ? 0.16 : 0.10,
                    child: CustomPaint(painter: _HomeArtPainter(c.mapData)),
                  ),
                ),
              ),
            ),
          ),

          // Foreground content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: layout.big ? 28 : 16,
                  vertical: compactLand ? 10 : (layout.big ? 28 : 16),
                ),
                child: twoColBig
                    ? _buildTwoColDesktop(layout, sz)
                    : compactLand
                        ? _buildCompactLandscape()
                        : _buildSingleColumn(layout),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoColDesktop(EstLayout layout, Size sz) {
    final gap = (sz.width * 0.06).clamp(32.0, 96.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: _buildBrand(alignLeft: true, big: true, sz: sz),
        ),
        SizedBox(width: gap),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: EstGlassCard(
            padding: const EdgeInsets.all(22),
            borderRadius: 6,
            highlight: true,
            child: _buildForm(big: true, compactLand: false),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumn(EstLayout layout) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: layout.big ? 460 : 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBrand(alignLeft: false, big: layout.big, sz: layout.size),
          SizedBox(height: layout.big ? 28 : 14),
          if (layout.big)
            EstGlassCard(
              padding: const EdgeInsets.all(22),
              borderRadius: 6,
              highlight: true,
              child: _buildForm(big: true, compactLand: false),
            )
          else
            _buildForm(big: false, compactLand: false),
          if (!layout.big) ...[
            const SizedBox(height: 10),
            _buildMetaFooter(alignLeft: false),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactLandscape() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBrand(alignLeft: false, big: false, sz: const Size(720, 400), smallCrest: true),
                const SizedBox(height: 8),
                _buildMetaFooter(alignLeft: false),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(child: _buildForm(big: false, compactLand: true)),
        ],
      ),
    );
  }

  Widget _buildBrand({
    required bool alignLeft,
    required bool big,
    required Size sz,
    bool smallCrest = false,
  }) {
    final crestSize = smallCrest ? 60.0 : (big ? 84.0 : 72.0);
    final titleSize = alignLeft ? (sz.width * 0.054).clamp(48.0, 72.0) : 40.0;

    return Column(
      crossAxisAlignment: alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _crestCtrl,
          builder: (context, child) {
            final t = sin(_crestCtrl.value * pi);
            return Transform.translate(
              offset: Offset(0, -3 * t),
              child: Transform.rotate(
                angle: -0.026 * t,
                child: child,
              ),
            );
          },
          child: Container(
            width: crestSize,
            height: crestSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x66D64545), blurRadius: 28, spreadRadius: 2),
                BoxShadow(color: Color(0x33E6B652), blurRadius: 42),
              ],
            ),
            child: EstIcon(EstIconKind.crest, size: crestSize),
          ),
        ),
        SizedBox(height: big ? 12 : 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF6DF), Color(0xFFD8C39A)],
            ).createShader(bounds),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'U'),
                  TextSpan(
                    text: 'LTIMATO',
                    style: TextStyle(fontSize: titleSize * 0.78),
                  ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
              style: AppText.serif(
                size: titleSize,
                letterSpacing: alignLeft ? 0.06 : 0.08,
                height: 1.0,
                color: Colors.white,
              ).copyWith(
                shadows: const [
                  Shadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Conquiste territórios, cumpra seu objetivo secreto.',
          textAlign: alignLeft ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: big ? 19 : 14,
            color: big ? AppColors.ink : AppColors.mute,
            height: 1.35,
          ),
        ),
        if (big) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: Text(
              'Estratégia por turnos para 2 a 6 jogadores. Entre na fila rápida online, crie uma mesa com amigos ou jogue sem internet.',
              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.mute,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: alignLeft ? WrapAlignment.start : WrapAlignment.center,
            children: const [
              _FeaturePill(icon: EstIconKind.medal, text: 'Quartel & Ordens'),
              _FeaturePill(icon: EstIconKind.bolt, text: 'Fila Rápida 45s'),
              _FeaturePill(icon: EstIconKind.sword, text: '2 a 6 Comandantes'),
            ],
          ),
          const SizedBox(height: 16),
          _buildMetaFooter(alignLeft: alignLeft),
        ],
      ],
    );
  }

  Widget _buildMetaFooter({required bool alignLeft}) {
    final c = widget.ctrl;
    return Column(
      crossAxisAlignment: alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!c.netOnline)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              '✓ Pronto para jogar sem internet',
              style: TextStyle(fontSize: 13, color: Color(0xFF9FE6B4)),
            ),
          ),
        Text(
          'versão $appVersion',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.mute.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildForm({required bool big, required bool compactLand}) {
    final c = widget.ctrl;
    final btnHeight = big ? 46.0 : 42.0;
    final btnFs = big ? 14.5 : 13.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plaqueta de Comandante (rebaixada estilo gabinete imperial)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
          decoration: BoxDecoration(
            color: AppColors.obsidian.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              const EstIcon(EstIconKind.crest, size: 17),
              const SizedBox(width: 9),
              const Text(
                'COMANDANTE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.mute,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  maxLength: 14,
                  onChanged: c.savePlayerName,
                  textAlign: TextAlign.right,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(
                    fontSize: big ? 15.5 : 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Seu apelido',
                    counterText: '',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.edit_outlined, size: 14, color: AppColors.mute.withValues(alpha: 0.65)),
            ],
          ),
        ),
        SizedBox(height: big ? 14 : 10),

        // Ordem de Batalha Principal: Partida Rápida Online
        Container(
          padding: EdgeInsets.all(compactLand ? 11 : (big ? 15 : 13)),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF172539), Color(0xFF0C1422)],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF8C7141), width: 1.0),
            boxShadow: const [
              BoxShadow(color: Color(0x77000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const EstIcon(EstIconKind.bolt, size: 15, color: AppColors.brass),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'PARTIDA RÁPIDA',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF6B5734)),
                    ),
                    child: const Text(
                      'ONLINE · 45S',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                ],
              ),
              if (!compactLand) ...[
                const SizedBox(height: 8),
                const EstRuleDivider(diamond: false),
                const SizedBox(height: 8),
                const Text(
                  '4 comandantes · Quartel ativo · 1 min/turno',
                  style: TextStyle(fontSize: 12.5, color: AppColors.mute),
                ),
              ],
              const SizedBox(height: 11),
              EstButton(
                icon: EstIconKind.sword,
                label: 'ENTRAR EM BATALHA',
                variant: EstButtonVariant.primary,
                height: big ? 46 : 42,
                fontSize: big ? 14.5 : 13.5,
                onPressed: () => c.startQuickMatch(_nameCtrl.text),
              ),
            ],
          ),
        ),
        SizedBox(height: big ? 10 : 8),

        // Grid tático de Modos Secundários
        Row(
          children: [
            Expanded(
              child: _TacticalTile(
                icon: EstIconKind.globe,
                title: 'Salas Online',
                sub: 'Mesas e código',
                compact: compactLand,
                onTap: () {
                  c.savePlayerName(_nameCtrl.text);
                  c.openRoomsBrowser();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TacticalTile(
                icon: EstIconKind.board,
                title: 'Mesa Local',
                sub: LanHost.supported ? 'Bots, LAN ou código' : 'Bots, QR ou código',
                compact: compactLand,
                onTap: () => c.startLocalSetup(hostName: _nameCtrl.text),
              ),
            ),
          ],
        ),

        if (c.hasSavedGuest || c.hasSavedLocal) ...[
          const SizedBox(height: 8),
          if (c.hasSavedGuest)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: EstButton(
                icon: EstIconKind.globe,
                label: 'Reconectar à partida em curso',
                variant: EstButtonVariant.pact,
                height: btnHeight,
                fontSize: btnFs,
                onPressed: c.resumeSavedGuest,
              ),
            ),
          if (c.hasSavedLocal)
            EstButton(
              icon: EstIconKind.board,
              label: 'Retomar campanha salva',
              variant: EstButtonVariant.pact,
              height: btnHeight,
              fontSize: btnFs,
              onPressed: c.resumeSavedLocal,
            ),
        ],

        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: EstButton(
                icon: EstIconKind.compass,
                label: 'Tutorial',
                variant: EstButtonVariant.ghost,
                height: 38,
                fontSize: 13.5,
                onPressed: () => c.startTutorial(playerName: _nameCtrl.text),
              ),
            ),
            Container(width: 1, height: 18, color: AppColors.line),
            Expanded(
              child: EstButton(
                icon: EstIconKind.book,
                label: 'Como jogar',
                variant: EstButtonVariant.ghost,
                height: 38,
                fontSize: 13.5,
                onPressed: () => showRulesModal(context, c),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.text});
  final EstIconKind icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EstIcon(icon, size: 13, color: AppColors.brass),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDDE3EE),
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalTile extends StatelessWidget {
  const _TacticalTile({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.compact = false,
  });

  final EstIconKind icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF162336), Color(0xFF0C1422)],
            ),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  EstIcon(icon, size: 15, color: AppColors.brass),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.mute),
                ],
              ),
              SizedBox(height: compact ? 6 : 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.mute),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeArtPainter extends CustomPainter {
  const _HomeArtPainter(this.mapData);

  final MapData mapData;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const pad = 30.0;
    final srcW = mapData.width + 2 * pad;
    final srcH = mapData.height + 2 * pad;
    final scale = max(size.width / srcW, size.height / srcH);
    final tx = (size.width - mapData.width * scale) / 2;
    final ty = (size.height - mapData.height * scale) / 2;

    canvas.save();
    canvas.translate(tx, ty);
    canvas.scale(scale, scale);

    final stroke = Paint()
      ..color = AppColors.deep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;

    for (final tr in mapData.territories) {
      final fill = Paint()
        ..color = mapData.continents[tr.continent].color
        ..style = PaintingStyle.fill;
      canvas.drawPath(tr.path, fill);
      canvas.drawPath(tr.path, stroke);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HomeArtPainter old) => false;
}
