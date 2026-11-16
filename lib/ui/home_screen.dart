import 'dart:math';

import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
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
                radius: twoColBig ? 1.0 : 1.15,
                colors: const [Color(0x9922406A), Color(0x000A1422)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: twoColBig ? const Alignment(0.5, 0.4) : const Alignment(0, 1.0),
                radius: 0.9,
                colors: const [Color(0x661B2F4D), Color(0x000A1422)],
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
          constraints: const BoxConstraints(maxWidth: 440),
          child: _buildBrand(alignLeft: true, big: true, sz: sz),
        ),
        SizedBox(width: gap),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: EstGlassCard(
            padding: const EdgeInsets.all(26),
            borderRadius: 20,
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
              padding: const EdgeInsets.all(26),
              borderRadius: 20,
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
              boxShadow: [
                BoxShadow(color: Color(0x55D64545), blurRadius: 18, offset: Offset(0, 6)),
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
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              'Estratégia por turnos para 2 a 6 jogadores. No mesmo Wi-Fi, sem internet, ou online com quem está longe.',
              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppColors.mute,
              ),
            ),
          ),
          const SizedBox(height: 14),
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
    final btnHeight = big ? 50.0 : 46.0;
    final btnFs = big ? 16.0 : 15.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Seu nome',
          style: TextStyle(fontSize: 13, color: AppColors.mute),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtrl,
          maxLength: 14,
          onChanged: c.savePlayerName,
          style: TextStyle(fontSize: big ? 16 : 15, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Como quer ser chamado',
            counterText: '',
            contentPadding: EdgeInsets.symmetric(
              horizontal: big ? 14 : 12,
              vertical: big ? 13 : 11,
            ),
          ),
        ),
        SizedBox(height: big ? 12 : 10),

        // Rede local card
        _ModeCard(
          title: 'Rede local',
          badge: const EstBadge(text: 'sem internet'),
          description: compactLand
              ? null
              : 'Celulares no mesmo Wi-Fi ou no hotspot de um deles, conectados por QR.',
          padding: compactLand ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8) : (big ? const EdgeInsets.all(14) : const EdgeInsets.all(12)),
          children: [
            Row(
              children: [
                Expanded(
                  child: EstButton(
                    label: 'Criar partida',
                    variant: EstButtonVariant.primary,
                    height: btnHeight,
                    fontSize: btnFs,
                    onPressed: () => c.startLocalSetup(hostName: _nameCtrl.text),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstButton(
                    label: 'Entrar por QR',
                    height: btnHeight,
                    fontSize: btnFs,
                    onPressed: () {
                      c.savePlayerName(_nameCtrl.text);
                      showP2pJoinModal(context, c);
                    },
                  ),
                ),
              ],
            ),
            if (c.hasSavedGuest) ...[
              const SizedBox(height: 8),
              EstButton(
                label: 'Reconectar à partida',
                height: btnHeight,
                fontSize: btnFs,
                onPressed: c.resumeSavedGuest,
              ),
            ],
            if (c.hasSavedLocal) ...[
              const SizedBox(height: 8),
              EstButton(
                label: 'Continuar partida salva',
                height: btnHeight,
                fontSize: btnFs,
                onPressed: c.resumeSavedLocal,
              ),
            ],
          ],
        ),
        SizedBox(height: big ? 12 : 10),

        // Online card
        _ModeCard(
          title: 'Online',
          badge: const EstBadge(text: 'pela internet', net: true),
          description: compactLand
              ? null
              : 'Cada um no próprio celular, de qualquer lugar: crie uma sala e mande o link.',
          padding: compactLand ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8) : (big ? const EdgeInsets.all(14) : const EdgeInsets.all(12)),
          children: [
            EstButton(
              label: 'Jogar online',
              height: btnHeight,
              fontSize: btnFs,
              onPressed: () {
                c.savePlayerName(_nameCtrl.text);
                c.openRoomsBrowser();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        EstButton(
          label: 'Como jogar',
          variant: EstButtonVariant.ghost,
          height: btnHeight,
          fontSize: btnFs,
          onPressed: () => showRulesModal(context, c),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.badge,
    this.description,
    required this.children,
    required this.padding,
  });

  final String title;
  final Widget badge;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0x8C0B1626),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2D4A72)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 8),
              badge,
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.mute,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ...children,
        ],
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
