import 'dart:math';

import 'package:flutter/material.dart';

/// Sistema "Centro de Operações": a cor fica no mapa (facções); a interface é neutra.
/// Regra: um único botão claro (ação) por tela; o metal só aparece nas medalhas.
abstract final class AppColors {
  // chão e superfícies
  static const sea = Color(0xFF0A0E13); // mar do mapa
  static const obsidian = Color(0xFF0B0F14); // fundo da tela
  static const deep = Color(0xFF0B0F14);
  static const panel = Color(0xFF12171E); // painéis
  static const panel2 = Color(0xFF1A2029); // item ativo, hover
  static const line = Color(0xFF262E39); // divisórias e contorno de painel
  static const glassBorder = Color(0xFF3A4452); // contorno de botão secundário
  // texto
  static const ink = Color(0xFFE8ECF1);
  static const mute = Color(0xFF9AA4B2);
  static const faint = Color(0xFF7D8796); // rótulos terciários (4,6:1 sobre o painel)
  // papéis com cor
  static const action = Color(0xFFF2EEE6); // o botão da próxima jogada
  static const onAction = Color(0xFF0B0F14);
  static const medal = Color(0xFFC9A45C); // só medalhas/Quartel
  static const bad = Color(0xFFFF6B5E);
  static const rad = Color(0xFFC8FF3E); // só ogiva
  static const onRad = Color(0xFF11140A);

  // nomes antigos, apontando para os papéis novos (as telas ainda os usam)
  static const gold = action;
  static const brass = mute;
  static const brassDim = Color(0x4C9AA4B2);
  static const bg = deep;
  static const surface = panel;
  static const border = line;
  static const text = ink;
  static const muted = mute;
  static const danger = bad;

  // sem degradê: os "gradientes" antigos agora são chapados
  static const glassGradient = LinearGradient(colors: [panel, panel]);
  static const hudGradient = LinearGradient(colors: [deep, deep]);
  static const wideHudGradient = LinearGradient(colors: [deep, deep]);

  /// A única sombra do sistema: o que flutua sobre o mapa.
  static const List<BoxShadow> edgeShadows = [
    BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// Paleta das facções, na ordem do motor (Vermelho, Azul, Verde, Amarelo, Roxo, Cinza).
/// Cada facção tem uma insígnia além da cor: leitura para daltônicos e com o mapa afastado.
enum FactionShape { triangle, circle, square, diamond, hexagon, cross }

abstract final class Factions {
  static const hex = ['#E0483E', '#3D7FE3', '#2E9E62', '#E9B530', '#8E5BD6', '#9AA6B4'];
  static const colors = [
    Color(0xFFE0483E),
    Color(0xFF3D7FE3),
    Color(0xFF2E9E62),
    Color(0xFFE9B530),
    Color(0xFF8E5BD6),
    Color(0xFF9AA6B4),
  ];
  static const shapes = [
    FactionShape.triangle,
    FactionShape.circle,
    FactionShape.square,
    FactionShape.diamond,
    FactionShape.hexagon,
    FactionShape.cross,
  ];

  static FactionShape shapeOf(Color c) {
    final i = colors.indexWhere((x) => x.toARGB32() == c.toARGB32());
    return i < 0 ? FactionShape.circle : shapes[i];
  }

  /// Número escuro sobre as facções claras (Amarelo, Cinza).
  static Color onColor(Color c) =>
      c.computeLuminance() > 0.35 ? AppColors.onAction : Colors.white;

  /// Contorno da insígnia de raio [r], centrada na origem.
  static Path path(FactionShape k, double r) {
    switch (k) {
      case FactionShape.circle:
        return Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r));
      case FactionShape.square:
        final h = r * 0.9;
        return Path()
          ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-h, -h, h, h), Radius.circular(r * 0.12)));
      case FactionShape.diamond:
        final h = r * 1.22;
        return Path()
          ..moveTo(0, -h)
          ..lineTo(h, 0)
          ..lineTo(0, h)
          ..lineTo(-h, 0)
          ..close();
      case FactionShape.triangle:
        return Path()
          ..moveTo(0, -r * 1.25)
          ..lineTo(r * 1.2, r * 0.85)
          ..lineTo(-r * 1.2, r * 0.85)
          ..close();
      case FactionShape.hexagon:
        final p = Path();
        for (var k = 0; k < 6; k++) {
          final a = pi / 6 + k * pi / 3;
          final o = Offset(cos(a), sin(a)) * (r * 1.08);
          k == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
        }
        return p..close();
      case FactionShape.cross:
        final a = r * 1.05, b = r * 0.42;
        return Path()
          ..moveTo(-b, -a)
          ..lineTo(b, -a)
          ..lineTo(b, -b)
          ..lineTo(a, -b)
          ..lineTo(a, b)
          ..lineTo(b, b)
          ..lineTo(b, a)
          ..lineTo(-b, a)
          ..lineTo(-b, b)
          ..lineTo(-a, b)
          ..lineTo(-a, -b)
          ..lineTo(-b, -b)
          ..close();
    }
  }

  /// O triângulo tem o centro visual mais baixo: o número desce um pouco.
  static double textNudge(FactionShape k, double r) => k == FactionShape.triangle ? r * 0.2 : 0;
}

/// Espaçamento em múltiplos de 4.
abstract final class Space {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

/// Raios: 2 (selos, etiquetas), 4 (controles), 8 (painéis).
abstract final class Radii {
  static const xs = 2.0;
  static const sm = 4.0;
  static const md = 8.0;
}

class EstRotatedScope extends InheritedWidget {
  const EstRotatedScope({
    super.key,
    required this.rotated,
    this.watch,
    this.resolveRotated,
    required super.child,
  });

  final bool rotated;
  final Listenable? watch;
  final bool Function(BuildContext rootCtx)? resolveRotated;

  static EstRotatedScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EstRotatedScope>();
  }

  static bool of(BuildContext context) => maybeOf(context)?.rotated ?? false;

  @override
  bool updateShouldNotify(EstRotatedScope oldWidget) =>
      rotated != oldWidget.rotated || watch != oldWidget.watch;
}

class EstRotatedStage extends StatelessWidget {
  const EstRotatedStage({
    super.key,
    required this.rotated,
    this.watch,
    this.resolveRotated,
    required this.child,
  });

  final bool rotated;
  final Listenable? watch;
  final bool Function(BuildContext rootCtx)? resolveRotated;
  final Widget child;

  static EdgeInsets _rotInsets(EdgeInsets e) => EdgeInsets.fromLTRB(
        e.top,
        e.right,
        e.bottom,
        e.left,
      );

  @override
  Widget build(BuildContext context) {
    if (!rotated) {
      return EstRotatedScope(
        rotated: false,
        watch: watch,
        resolveRotated: resolveRotated,
        child: child,
      );
    }
    final mq = MediaQuery.of(context);
    final raw = mq.size;
    final rotMq = mq.copyWith(
      size: Size(raw.height, raw.width),
      padding: _rotInsets(mq.padding),
      viewPadding: _rotInsets(mq.viewPadding),
      viewInsets: _rotInsets(mq.viewInsets),
    );
    return RotatedBox(
      quarterTurns: 1,
      child: MediaQuery(
        data: rotMq,
        child: EstRotatedScope(
          rotated: true,
          watch: watch,
          resolveRotated: resolveRotated,
          child: child,
        ),
      ),
    );
  }
}

class EstLayout {
  EstLayout._({
    required this.size,
    required this.big,
    required this.wide,
    required this.tall,
    required this.land,
    required this.rot,
  });

  final Size size;
  final bool big;
  final bool wide;
  final bool tall;
  final bool land;
  final bool rot;

  factory EstLayout.of(BuildContext context, {bool inGame = false, bool forceLand = false}) {
    final rawSz = MediaQuery.sizeOf(context);
    final scopedRot = EstRotatedScope.of(context);
    // Se já estamos dentro de EstRotatedStage, MediaQuery.size já foi rotacionado (não inverter duas vezes).
    final rawMin = min(rawSz.width, rawSz.height);
    final rawPortrait = rawSz.height > rawSz.width;
    final rot = scopedRot || (inGame && rawPortrait && rawMin < 600 && forceLand);
    final sz = (!scopedRot && rot) ? Size(rawSz.height, rawSz.width) : rawSz;
    final minSide = min(sz.width, sz.height);
    final big = minSide >= 600;
    final portrait = !rot && sz.height > sz.width;
    final wide = big && sz.width >= 1000 && sz.width >= sz.height * 0.9;
    final tall = big && !wide;
    final land = rot || (!portrait && sz.height <= 520);
    return EstLayout._(
      size: sz,
      big: big,
      wide: wide,
      tall: tall,
      land: land,
      rot: rot,
    );
  }
}

/// Tipografia: Barlow Condensed para comando (títulos, rótulos, números), Barlow para leitura.
/// Escala única: 11 · 12 · 13 · 15 · 18 · 22 · 28.
abstract final class AppText {
  static const cond = 'Barlow Condensed';
  static const body = 'Barlow';
  static const List<String> condFallback = ['Barlow', 'Arial Narrow', 'sans-serif'];
  static const List<String> serifFallback = condFallback; // nome antigo

  static const tabular = [FontFeature.tabularFigures()];

  /// Títulos e nomes de lugar (substitui a antiga serifa).
  static TextStyle serif({
    double size = 18,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
    double letterSpacing = 0.01,
    double height = 1.15,
  }) {
    return TextStyle(
      fontFamily: cond,
      fontFamilyFallback: condFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: size * letterSpacing,
      height: height,
    );
  }

  static TextStyle title({double size = 18, Color color = AppColors.ink}) => serif(size: size, color: color);

  /// Rótulo de comando: condensada, caixa alta, espaçada.
  static TextStyle label({
    double size = 12,
    Color color = AppColors.faint,
    FontWeight weight = FontWeight.w600,
  }) {
    return TextStyle(
      fontFamily: cond,
      fontFamilyFallback: condFallback,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size * 0.08,
      height: 1.1,
      color: color,
    );
  }

  /// Números (exércitos, tempo, medalhas): condensada com algarismos tabulares.
  static TextStyle number({double size = 15, Color color = AppColors.ink, FontWeight weight = FontWeight.w600}) {
    return TextStyle(
      fontFamily: cond,
      fontFamilyFallback: condFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.1,
      fontFeatures: tabular,
    );
  }
}

ThemeData buildAppTheme() {
  const fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
    borderSide: BorderSide(color: AppColors.glassBorder),
  );
  return ThemeData(
    brightness: Brightness.dark,
    fontFamily: AppText.body,
    scaffoldBackgroundColor: AppColors.deep,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.action,
      secondary: AppColors.action,
      surface: AppColors.panel,
      error: AppColors.bad,
      onPrimary: AppColors.onAction,
      onSurface: AppColors.ink,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: AppColors.ink),
      bodySmall: TextStyle(fontSize: 13, height: 1.35, color: AppColors.mute),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x14FFFFFF),
    hoverColor: const Color(0x0DFFFFFF),
    cardColor: AppColors.panel,
    dividerColor: AppColors.line,
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
        border: Border.fromBorderSide(BorderSide(color: AppColors.line)),
      ),
      textStyle: TextStyle(fontFamily: AppText.body, fontSize: 12, color: AppColors.ink),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.deep,
      hintStyle: TextStyle(color: AppColors.faint),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
        borderSide: BorderSide(color: AppColors.ink),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
  );
}

/// Celular deitado (pouca altura): controles mais baixos e paddings menores.
bool estCompact(BuildContext context) {
  final sz = MediaQuery.sizeOf(context);
  return min(sz.width, sz.height) < 500;
}

enum EstButtonVariant { normal, primary, ghost, warn, rad, pact }

class EstButton extends StatelessWidget {
  const EstButton({
    super.key,
    required this.onPressed,
    this.label,
    this.child,
    this.icon,
    this.variant = EstButtonVariant.normal,
    this.small = false,
    this.height,
    this.askPulse = false,
    this.fontSize,
    this.padding,
  });

  final VoidCallback? onPressed;
  final String? label;
  final Widget? child;
  final EstIconKind? icon;
  final EstButtonVariant variant;
  final bool small;
  final double? height;
  final bool askPulse;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final compact = estCompact(context);
    final h = height ?? (small ? (compact ? 30.0 : 34.0) : (compact ? 36.0 : 40.0));
    final fs = fontSize ?? (small ? 12.0 : 13.0);

    Color bg = Colors.transparent;
    Color border = Colors.transparent;
    Color fg;
    var weight = FontWeight.w600;

    if (askPulse) {
      bg = AppColors.action;
      fg = AppColors.onAction;
      weight = FontWeight.w700;
    } else {
      switch (variant) {
        case EstButtonVariant.primary:
          bg = AppColors.action;
          fg = AppColors.onAction;
          weight = FontWeight.w700;
        case EstButtonVariant.ghost:
          fg = AppColors.mute;
        case EstButtonVariant.warn:
          border = AppColors.bad;
          fg = AppColors.bad;
        case EstButtonVariant.rad:
          bg = AppColors.rad;
          fg = AppColors.onRad;
          weight = FontWeight.w700;
        case EstButtonVariant.pact:
          border = AppColors.mute;
          fg = AppColors.ink;
        case EstButtonVariant.normal:
          border = AppColors.glassBorder;
          fg = AppColors.ink;
      }
    }

    final innerContent = child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              EstIcon(icon!, size: small ? 14 : 16, color: fg),
              SizedBox(width: small ? 5 : 7),
            ],
            Flexible(
              child: Text(
                (label ?? '').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                style: AppText.label(size: fs + 1, color: fg, weight: weight),
              ),
            ),
          ],
        );

    const radius = Radii.sm;
    return Opacity(
      opacity: disabled ? 0.38 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(radius),
          hoverColor: bg == Colors.transparent ? const Color(0x0FFFFFFF) : const Color(0x14000000),
          child: Ink(
            height: h,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: border == Colors.transparent ? null : Border.all(color: border),
            ),
            child: Padding(
              padding: padding ?? EdgeInsets.symmetric(horizontal: small ? 10 : (compact ? 12 : 14)),
              child: Center(widthFactor: 1, child: innerContent),
            ),
          ),
        ),
      ),
    );
  }
}

class EstIconButton extends StatelessWidget {
  const EstIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 30,
    this.iconSize = 14,
    this.color = AppColors.mute,
    this.tooltip,
    this.dangerHover = false,
  });

  final EstIconKind icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color color;
  final String? tooltip;
  final bool dangerHover;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final btn = Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Radii.sm),
          hoverColor: dangerHover ? AppColors.bad.withValues(alpha: 0.14) : AppColors.panel2,
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.deep,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: AppColors.line),
            ),
            child: Center(
              child: EstIcon(icon, size: iconSize, color: color),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

class EstTextField extends StatefulWidget {
  const EstTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.height = 40,
    this.maxLength,
    this.obscureText = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.onChanged,
    this.onSubmitted,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String? hintText;
  final double height;
  final int? maxLength;
  final bool obscureText;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;
  final Widget? suffix;

  @override
  State<EstTextField> createState() => _EstTextFieldState();
}

class _EstTextFieldState extends State<EstTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focused != _focusNode.hasFocus && mounted) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusNode.requestFocus,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.height,
          padding: EdgeInsets.only(
            left: widget.prefix != null ? 10 : 12,
            right: widget.suffix != null ? 4 : 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.deep,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: _focused ? AppColors.ink : AppColors.glassBorder),
          ),
          alignment: Alignment.center,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.prefix != null) ...[
                widget.prefix!,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  maxLines: 1,
                  maxLength: widget.maxLength,
                  obscureText: widget.obscureText,
                  autofocus: widget.autofocus,
                  textCapitalization: widget.textCapitalization,
                  textAlignVertical: TextAlignVertical.center,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: widget.style ?? const TextStyle(fontSize: 15, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(color: AppColors.faint, fontSize: 15),
                    counterText: '',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              if (widget.suffix != null) ...[
                const SizedBox(width: 4),
                widget.suffix!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EstBadge extends StatelessWidget {
  const EstBadge({super.key, required this.text, this.net = false});

  final String text;
  final bool net;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(text.toUpperCase(), style: AppText.label(size: 11, color: net ? AppColors.ink : AppColors.mute)),
    );
  }
}

class EstChip extends StatelessWidget {
  const EstChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 38,
    this.fontSize = 13.5,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.panel2 : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          height: estCompact(context) ? min(height, 32) : height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: AppText.number(size: fontSize + 1, color: selected ? AppColors.ink : AppColors.mute),
          ),
        ),
      ),
    );
  }
}

class EstSwitchOpt extends StatelessWidget {
  const EstSwitchOpt({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.topBorder = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Container(
        constraints: BoxConstraints(minHeight: estCompact(context) ? 44 : 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: topBorder ? const Border(top: BorderSide(color: AppColors.line)) : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 34,
              height: 20,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? AppColors.action : AppColors.deep,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: value ? AppColors.action : AppColors.glassBorder),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: value ? AppColors.onAction : AppColors.mute,
                    borderRadius: BorderRadius.circular(Radii.xs),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.mute),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EstGlassCard extends StatelessWidget {
  const EstGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = Radii.md,
    this.ornate = true,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool ornate; // sem efeito: o sistema não tem ornamentos
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: highlight ? AppColors.panel2 : AppColors.panel,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: highlight ? AppColors.glassBorder : AppColors.line),
      ),
      child: child,
    );
  }
}

class EstRuleDivider extends StatelessWidget {
  const EstRuleDivider({super.key, this.color, this.diamond = true});

  final Color? color;
  final bool diamond; // sem efeito: divisória é uma linha

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color ?? AppColors.line);
}

class EstSectionTag extends StatelessWidget {
  const EstSectionTag(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label.toUpperCase(), style: AppText.label(size: 11)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppColors.line)),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

/// Insígnia da facção: forma + cor. [size] é a largura da forma.
class EstFactionSeal extends StatelessWidget {
  const EstFactionSeal({
    super.key,
    required this.color,
    this.size = 16,
    this.highlighted = false,
    this.shape,
  });

  final Color color;
  final double size;
  final bool highlighted;
  final FactionShape? shape;

  @override
  Widget build(BuildContext context) {
    final box = size + 4;
    return SizedBox(
      width: box,
      height: box,
      child: CustomPaint(
        painter: _InsigniaPainter(
          color: color,
          shape: shape ?? Factions.shapeOf(color),
          ring: highlighted,
        ),
      ),
    );
  }
}

class _InsigniaPainter extends CustomPainter {
  const _InsigniaPainter({required this.color, required this.shape, required this.ring});

  final Color color;
  final FactionShape shape;
  final bool ring;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 * 0.72;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final path = Factions.path(shape, r);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring ? 1.6 : 1.0
        ..strokeJoin = StrokeJoin.round
        ..color = ring ? AppColors.ink : AppColors.deep,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InsigniaPainter old) => old.color != color || old.shape != shape || old.ring != ring;
}

/// Marca: ULTIMAT + a mira no lugar do O.
class EstWordmark extends StatelessWidget {
  const EstWordmark({super.key, this.size = 32, this.color = AppColors.ink});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ultimato',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ULTIMAT',
              style: TextStyle(
                fontFamily: AppText.cond,
                fontFamilyFallback: AppText.condFallback,
                fontWeight: FontWeight.w700,
                fontSize: size,
                height: 1,
                letterSpacing: size * 0.06,
                color: color,
              ),
            ),
            SizedBox(width: size * 0.02),
            EstIcon(EstIconKind.crest, size: size * 0.74, color: color),
          ],
        ),
      ),
    );
  }
}

final Expando<EstRotatedScope> _navigatorSheetScope = Expando<EstRotatedScope>();

/// Pops the current sheet ([sheetCtx]) and invokes [openNext] on the root
/// [Navigator]'s live [BuildContext] while preserving [EstRotatedScope], so
/// chained modals remain mounted and rotated even if the original button
/// unmounted after layout or `Tela deitada` changes.
void replaceEstSheet(
  BuildContext sheetCtx,
  void Function(BuildContext safeCtx) openNext,
) {
  final nav = Navigator.of(sheetCtx, rootNavigator: true);
  final activeScope = EstRotatedScope.maybeOf(sheetCtx);
  _navigatorSheetScope[nav] = activeScope;
  Navigator.pop(sheetCtx);
  final safeCtx = nav.context;
  if (safeCtx.mounted) {
    openNext(safeCtx);
  }
  _navigatorSheetScope[nav] = null;
}

Future<T?> showEstSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool pactTheme = false,
  double maxWidth = 560,
}) {
  if (!context.mounted) return Future<T?>.value(null);
  final nav = Navigator.of(context, rootNavigator: true);
  final inheritedScope = EstRotatedScope.maybeOf(context);
  final carriedScope = _navigatorSheetScope[nav];
  _navigatorSheetScope[nav] = null;
  final scope = inheritedScope ?? carriedScope;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Fechar',
    barrierColor: const Color(0xB3000000),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (rootCtx, anim, _) {
      Widget buildAnimatedDialog(BuildContext rCtx) {
        final layout = EstLayout.of(rCtx);
        final centered = layout.big || layout.land;
        final compactLand = layout.land && !layout.big;
        final sz = MediaQuery.sizeOf(rCtx);
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);

        final panel = Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: centered
                  ? BorderRadius.circular(Radii.md)
                  : const BorderRadius.vertical(top: Radius.circular(Radii.md)),
              border: Border.all(color: pactTheme ? AppColors.glassBorder : AppColors.line),
              boxShadow: AppColors.edgeShadows,
            ),
            child: builder(rCtx),
          ),
        );

        final animated = centered
            ? FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween(begin: 0.95, end: 1.0).animate(curved),
                  child: panel,
                ),
              )
            : FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
                  child: panel,
                ),
              );

        return SafeArea(
          child: Align(
            alignment: centered ? Alignment.center : Alignment.bottomCenter,
            child: Padding(
              padding: centered
                  ? EdgeInsets.symmetric(
                      horizontal: compactLand ? 12 : 20,
                      vertical: compactLand ? 8 : 20,
                    )
                  : EdgeInsets.zero,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: centered
                      ? min(compactLand ? 580.0 : maxWidth, max(260.0, sz.width - (compactLand ? 32 : 40)))
                      : min(500.0, sz.width),
                  maxHeight: sz.height * (compactLand ? 0.96 : (centered ? 0.90 : 0.92)),
                ),
                child: animated,
              ),
            ),
          ),
        );
      }

      if (scope?.watch != null && scope?.resolveRotated != null) {
        return ListenableBuilder(
          listenable: scope!.watch!,
          builder: (wCtx, _) {
            final isRot = scope.resolveRotated!(wCtx);
            return EstRotatedStage(
              rotated: isRot,
              watch: scope.watch,
              resolveRotated: scope.resolveRotated,
              child: Builder(builder: buildAnimatedDialog),
            );
          },
        );
      }

      return EstRotatedStage(
        rotated: scope?.rotated ?? false,
        child: Builder(builder: buildAnimatedDialog),
      );
    },
    transitionBuilder: (_, _, _, child) => child,
  );
}

class EstSheetBody extends StatelessWidget {
  const EstSheetBody({
    super.key,
    required this.children,
    this.title,
    this.titleIcon,
    this.onClose,
    this.padding,
  });

  final String? title;
  final Widget? titleIcon;
  final VoidCallback? onClose;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final compact = estCompact(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Container(
            height: compact ? 44 : 52,
            padding: EdgeInsets.only(left: compact ? 14 : 18, right: compact ? 8 : 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                if (titleIcon != null) ...[
                  titleIcon!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(size: compact ? 18 : 22),
                  ),
                ),
                EstIconButton(
                  icon: EstIconKind.close,
                  size: 32,
                  iconSize: 13,
                  tooltip: 'Fechar',
                  onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: padding ?? EdgeInsets.fromLTRB(compact ? 14 : 18, compact ? 12 : 16, compact ? 14 : 18, compact ? 14 : 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- Exact SVG Icon Painters from main.js ----------

enum EstIconKind {
  goal,
  cards,
  medal,
  menu,
  extras,
  pact,
  fit,
  crest,
  cup,
  sword,
  shield,
  airlift,
  nuke,
  spy,
  sabotage,
  troop,
  move,
  bolt,
  compass,
  book,
  globe,
  board,
  qr,
  close,
  back,
  plus,
  minus,
  lock,
  lan,
}

class EstIcon extends StatelessWidget {
  const EstIcon(this.kind, {super.key, this.size = 18, this.color = AppColors.ink});

  final EstIconKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EstIconPainter(kind: kind, color: color)),
    );
  }
}

class _EstIconPainter extends CustomPainter {
  const _EstIconPainter({required this.kind, required this.color});

  final EstIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / (kind == EstIconKind.crest || kind == EstIconKind.cup ? 64.0 : 24.0);
    canvas.save();
    canvas.scale(s, s);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case EstIconKind.goal:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawCircle(const Offset(12, 12), 5, stroke);
        canvas.drawCircle(const Offset(12, 12), 1.4, Paint()..color = color);
      case EstIconKind.cards:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(4, 6, 11, 15), const Radius.circular(2)),
          stroke,
        );
        final p = Path()
          ..moveTo(9, 3)
          ..lineTo(18, 3)
          ..arcToPoint(const Offset(20, 5), radius: const Radius.circular(2))
          ..lineTo(20, 18);
        canvas.drawPath(p, stroke);
      case EstIconKind.medal:
        // Fita no topo convergente + medalha circular com estrela
        final ribbon = Path()
          ..moveTo(7, 3)
          ..lineTo(17, 3)
          ..lineTo(14.5, 9.2)
          ..lineTo(9.5, 9.2)
          ..close();
        canvas.drawPath(ribbon, stroke);
        canvas.drawLine(const Offset(12, 3), const Offset(12, 9), stroke);
        canvas.drawCircle(const Offset(12, 15), 6, stroke);
        final star = _starPath(const Offset(12, 15), 3.1, 1.35);
        canvas.drawPath(star, Paint()..color = color..style = PaintingStyle.fill);
      case EstIconKind.menu:
        canvas.drawLine(const Offset(4, 7), const Offset(20, 7), stroke);
        canvas.drawLine(const Offset(4, 12), const Offset(20, 12), stroke);
        canvas.drawLine(const Offset(4, 17), const Offset(20, 17), stroke);
      case EstIconKind.extras:
        // M13 3 5 13.5h6L10 21l8-10.5h-6z
        final bolt = Path()
          ..moveTo(13, 3)
          ..lineTo(5, 13.5)
          ..lineTo(11, 13.5)
          ..lineTo(10, 21)
          ..lineTo(18, 10.5)
          ..lineTo(12, 10.5)
          ..close();
        canvas.drawPath(bolt, Paint()..color = color..style = PaintingStyle.fill);
      case EstIconKind.pact:
        // M2 12l4-4 4 2 3-2 4 1 5 3-4 4-3 1-4-2-3 1z + M8 13l3 2M10 11l3 2
        stroke.strokeWidth = 1.6;
        final hand = Path()
          ..moveTo(2, 12)
          ..lineTo(6, 8)
          ..lineTo(10, 10)
          ..lineTo(13, 8)
          ..lineTo(17, 9)
          ..lineTo(22, 12)
          ..lineTo(18, 16)
          ..lineTo(15, 17)
          ..lineTo(11, 15)
          ..lineTo(8, 16)
          ..close();
        canvas.drawPath(hand, stroke);
        canvas.drawLine(const Offset(8, 13), const Offset(11, 15), stroke);
        canvas.drawLine(const Offset(10, 11), const Offset(13, 13), stroke);
      case EstIconKind.fit:
        final p = Path()
          ..moveTo(4, 9)
          ..lineTo(4, 4)
          ..lineTo(9, 4)
          ..moveTo(20, 9)
          ..lineTo(20, 4)
          ..lineTo(15, 4)
          ..moveTo(4, 15)
          ..lineTo(4, 20)
          ..lineTo(9, 20)
          ..moveTo(20, 15)
          ..lineTo(20, 20)
          ..lineTo(15, 20);
        canvas.drawPath(p, stroke);
      case EstIconKind.crest:
        // A marca: mira (anel grosso + quatro marcas), na cor pedida
        const c = Offset(32, 32);
        canvas.drawCircle(
          c,
          23,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8.4,
        );
        final tick = Paint()
          ..color = color
          ..strokeWidth = 5.2;
        canvas.drawLine(const Offset(32, 0), const Offset(32, 16), tick);
        canvas.drawLine(const Offset(32, 48), const Offset(32, 64), tick);
        canvas.drawLine(const Offset(0, 32), const Offset(16, 32), tick);
        canvas.drawLine(const Offset(48, 32), const Offset(64, 32), tick);
      case EstIconKind.cup:
        final cupBody = Path()
          ..moveTo(20, 10)
          ..lineTo(44, 10)
          ..lineTo(44, 24)
          ..arcToPoint(const Offset(20, 24), radius: const Radius.circular(12))
          ..close();
        canvas.drawPath(cupBody, Paint()..color = color.withValues(alpha: 0.30));
        stroke.strokeWidth = 3.0;
        canvas.drawPath(cupBody, stroke);
        final details = Path()
          ..moveTo(20, 14)
          ..lineTo(12, 14)
          ..lineTo(12, 18)
          ..arcToPoint(const Offset(20, 26), radius: const Radius.circular(8), clockwise: false)
          ..moveTo(44, 14)
          ..lineTo(52, 14)
          ..lineTo(52, 18)
          ..arcToPoint(const Offset(44, 26), radius: const Radius.circular(8))
          ..moveTo(32, 36)
          ..lineTo(32, 46)
          ..moveTo(22, 54)
          ..lineTo(42, 54)
          ..addRect(const Rect.fromLTWH(26, 46, 12, 8));
        canvas.drawPath(details, stroke);
      case EstIconKind.sword:
        // Espadas cruzadas
        final p = Path()
          ..moveTo(5, 19)
          ..lineTo(19, 5)
          ..moveTo(15, 5)
          ..lineTo(19, 5)
          ..lineTo(19, 9)
          ..moveTo(6, 15)
          ..lineTo(9, 18)
          ..moveTo(19, 19)
          ..lineTo(5, 5)
          ..moveTo(9, 5)
          ..lineTo(5, 5)
          ..lineTo(5, 9)
          ..moveTo(18, 15)
          ..lineTo(15, 18);
        canvas.drawPath(p, stroke);
      case EstIconKind.shield:
        // Escudo tático (trincheira / defesa)
        final p = Path()
          ..moveTo(12, 3)
          ..lineTo(19, 5.8)
          ..lineTo(19, 11.5)
          ..quadraticBezierTo(19, 17.5, 12, 21)
          ..quadraticBezierTo(5, 17.5, 5, 11.5)
          ..lineTo(5, 5.8)
          ..close();
        canvas.drawPath(p, Paint()..color = color.withValues(alpha: 0.16));
        canvas.drawPath(p, stroke);
        canvas.drawLine(const Offset(12, 7.5), const Offset(12, 16.5), stroke);
        canvas.drawLine(const Offset(8.5, 11.5), const Offset(15.5, 11.5), stroke);
      case EstIconKind.airlift:
        // Aeronave tática inclinada para cima/direita
        final plane = Path()
          ..moveTo(21, 3)
          ..lineTo(14.5, 20)
          ..lineTo(11.5, 13.5)
          ..lineTo(4, 10.5)
          ..close();
        canvas.drawPath(plane, Paint()..color = color.withValues(alpha: 0.20));
        canvas.drawPath(plane, stroke);
        canvas.drawLine(const Offset(11.5, 13.5), const Offset(20.5, 3.5), stroke);
      case EstIconKind.nuke:
        // Símbolo radioativo limpo (centro + 3 pás)
        canvas.drawCircle(const Offset(12, 12), 2.1, Paint()..color = color);
        for (final ang in const [-90.0, 30.0, 150.0]) {
          final r1 = (ang - 26) * pi / 180;
          final r2 = (ang + 26) * pi / 180;
          final p = Path()
            ..moveTo(12 + cos(r1) * 4.2, 12 + sin(r1) * 4.2)
            ..lineTo(12 + cos(r1) * 9.5, 12 + sin(r1) * 9.5)
            ..arcToPoint(
              Offset(12 + cos(r2) * 9.5, 12 + sin(r2) * 9.5),
              radius: const Radius.circular(9.5),
            )
            ..lineTo(12 + cos(r2) * 4.2, 12 + sin(r2) * 4.2)
            ..arcToPoint(
              Offset(12 + cos(r1) * 4.2, 12 + sin(r1) * 4.2),
              radius: const Radius.circular(4.2),
              clockwise: false,
            )
            ..close();
          canvas.drawPath(p, Paint()..color = color);
        }
      case EstIconKind.spy:
        // Olho / retículo de espionagem
        final eye = Path()
          ..moveTo(2.5, 12)
          ..quadraticBezierTo(12, 4.5, 21.5, 12)
          ..quadraticBezierTo(12, 19.5, 2.5, 12)
          ..close();
        canvas.drawPath(eye, stroke);
        canvas.drawCircle(const Offset(12, 12), 3.1, stroke);
        canvas.drawCircle(const Offset(12, 12), 1.2, Paint()..color = color);
      case EstIconKind.sabotage:
        // Hexágono partido por um corte diagonal (sabotagem)
        canvas.drawCircle(const Offset(12, 12), 7.5, stroke);
        canvas.drawLine(const Offset(6, 18), const Offset(18, 6), stroke);
        canvas.drawLine(const Offset(12, 2.5), const Offset(12, 5.5), stroke);
        canvas.drawLine(const Offset(12, 18.5), const Offset(12, 21.5), stroke);
      case EstIconKind.troop:
        // Divisas militares (3 chevrons de reforço)
        final ch = Path()
          ..moveTo(5, 18)
          ..lineTo(12, 12.5)
          ..lineTo(19, 18)
          ..moveTo(5, 13)
          ..lineTo(12, 7.5)
          ..lineTo(19, 13)
          ..moveTo(7.5, 7.5)
          ..lineTo(12, 4)
          ..lineTo(16.5, 7.5);
        canvas.drawPath(ch, stroke);
      case EstIconKind.move:
        // Setas duplas de deslocamento
        final mv = Path()
          ..moveTo(4, 9)
          ..lineTo(19, 9)
          ..moveTo(15, 5.5)
          ..lineTo(19.5, 9)
          ..lineTo(15, 12.5)
          ..moveTo(20, 16)
          ..lineTo(5, 16)
          ..moveTo(9, 12.5)
          ..lineTo(4.5, 16)
          ..lineTo(9, 19.5);
        canvas.drawPath(mv, stroke);
      case EstIconKind.bolt:
        final b = Path()
          ..moveTo(13.5, 2.5)
          ..lineTo(5.5, 13)
          ..lineTo(11.5, 13)
          ..lineTo(10.5, 21.5)
          ..lineTo(18.5, 11)
          ..lineTo(12.5, 11)
          ..close();
        canvas.drawPath(b, Paint()..color = color..style = PaintingStyle.fill);
      case EstIconKind.compass:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        final needle = Path()
          ..moveTo(15.5, 8.5)
          ..lineTo(13.2, 13.2)
          ..lineTo(8.5, 15.5)
          ..lineTo(10.8, 10.8)
          ..close();
        canvas.drawPath(needle, Paint()..color = color..style = PaintingStyle.fill);
      case EstIconKind.book:
        final bk = Path()
          ..moveTo(12, 6)
          ..quadraticBezierTo(8, 4.5, 3.5, 6)
          ..lineTo(3.5, 18.5)
          ..quadraticBezierTo(8, 17, 12, 19)
          ..quadraticBezierTo(16, 17, 20.5, 18.5)
          ..lineTo(20.5, 6)
          ..quadraticBezierTo(16, 4.5, 12, 6)
          ..moveTo(12, 6)
          ..lineTo(12, 19);
        canvas.drawPath(bk, stroke);
      case EstIconKind.globe:
        canvas.drawCircle(const Offset(12, 12), 8.8, stroke);
        canvas.drawOval(const Rect.fromLTWH(8.2, 3.2, 7.6, 17.6), stroke);
        canvas.drawLine(const Offset(3.5, 12), const Offset(20.5, 12), stroke);
      case EstIconKind.board:
        // Torre/peão tático de tabuleiro local
        final p = Path()
          ..moveTo(6, 20)
          ..lineTo(18, 20)
          ..moveTo(8, 20)
          ..lineTo(9.5, 9)
          ..lineTo(14.5, 9)
          ..lineTo(16, 20)
          ..moveTo(7.5, 9)
          ..lineTo(7.5, 4.5)
          ..lineTo(10, 4.5)
          ..lineTo(10, 6.5)
          ..lineTo(14, 6.5)
          ..lineTo(14, 4.5)
          ..lineTo(16.5, 4.5)
          ..lineTo(16.5, 9)
          ..close();
        canvas.drawPath(p, stroke);
      case EstIconKind.qr:
        final q = Path()
          ..addRect(const Rect.fromLTWH(4, 4, 6, 6))
          ..addRect(const Rect.fromLTWH(14, 4, 6, 6))
          ..addRect(const Rect.fromLTWH(4, 14, 6, 6))
          ..moveTo(14, 14)
          ..lineTo(17, 14)
          ..lineTo(17, 17)
          ..moveTo(14, 20)
          ..lineTo(20, 20)
          ..lineTo(20, 15);
        canvas.drawPath(q, stroke);
      case EstIconKind.close:
        canvas.drawLine(const Offset(6.5, 6.5), const Offset(17.5, 17.5), stroke);
        canvas.drawLine(const Offset(17.5, 6.5), const Offset(6.5, 17.5), stroke);
      case EstIconKind.back:
        final p = Path()
          ..moveTo(14.5, 6)
          ..lineTo(8.5, 12)
          ..lineTo(14.5, 18);
        canvas.drawPath(p, stroke);
      case EstIconKind.plus:
        canvas.drawLine(const Offset(12, 6), const Offset(12, 18), stroke);
        canvas.drawLine(const Offset(6, 12), const Offset(18, 12), stroke);
      case EstIconKind.minus:
        canvas.drawLine(const Offset(6, 12), const Offset(18, 12), stroke);
      case EstIconKind.lock:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(5, 10.5, 14, 10), const Radius.circular(2)),
          stroke,
        );
        final shackle = Path()
          ..moveTo(8, 10.5)
          ..lineTo(8, 7.5)
          ..arcToPoint(const Offset(16, 7.5), radius: const Radius.circular(4))
          ..lineTo(16, 10.5);
        canvas.drawPath(shackle, stroke);
        canvas.drawCircle(const Offset(12, 15.5), 1.3, Paint()..color = color);
      case EstIconKind.lan:
        // Nó central de servidor local conectado a dois pares na base
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(7.5, 3.5, 9, 6), const Radius.circular(1.5)),
          stroke,
        );
        canvas.drawLine(const Offset(12, 9.5), const Offset(12, 14), stroke);
        canvas.drawLine(const Offset(6, 14), const Offset(18, 14), stroke);
        canvas.drawLine(const Offset(6, 14), const Offset(6, 16.5), stroke);
        canvas.drawLine(const Offset(18, 14), const Offset(18, 16.5), stroke);
        canvas.drawCircle(const Offset(6, 19), 2.2, stroke);
        canvas.drawCircle(const Offset(18, 19), 2.2, stroke);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EstIconPainter old) => old.kind != kind || old.color != color;
}

Path _starPath(Offset center, double outerR, double innerR) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? outerR : innerR;
    final ang = -pi / 2 + i * pi / 5;
    final pt = Offset(center.dx + cos(ang) * r, center.dy + sin(ang) * r);
    if (i == 0) {
      p.moveTo(pt.dx, pt.dy);
    } else {
      p.lineTo(pt.dx, pt.dy);
    }
  }
  p.close();
  return p;
}

class EstMedalBadge extends StatelessWidget {
  const EstMedalBadge({super.key, required this.earned, this.size = 28});

  final bool earned;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EstMedalBadgePainter(earned: earned)),
    );
  }
}

class _EstMedalBadgePainter extends CustomPainter {
  const _EstMedalBadgePainter({required this.earned});

  final bool earned;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 28.0;
    canvas.save();
    canvas.scale(s, s);

    // Fita superior em V (passador + fita militar)
    final ribbon = Path()
      ..moveTo(7.5, 2.0)
      ..lineTo(20.5, 2.0)
      ..lineTo(17.5, 10.5)
      ..lineTo(10.5, 10.5)
      ..close();

    if (earned) {
      canvas.drawPath(ribbon, Paint()..color = const Color(0xFFB53732));
      canvas.drawRect(const Rect.fromLTWH(12.2, 2.0, 3.6, 8.5), Paint()..color = const Color(0xFFF3CD78));
      canvas.drawPath(
        ribbon,
        Paint()
          ..color = const Color(0xCCFFE5A3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      canvas.drawPath(ribbon, Paint()..color = AppColors.deep);
      canvas.drawPath(
        ribbon,
        Paint()
          ..color = AppColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Argolinha de ligação
    canvas.drawCircle(
      const Offset(14, 10.8),
      1.6,
      Paint()
        ..color = earned ? const Color(0xFFF7D98A) : AppColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Medalhão circular
    const c = Offset(14, 18.2);
    const r = 7.8;
    if (earned) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFEEAD), Color(0xFFE2B04A), Color(0xFFA97015)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = const Color(0xFFFFF3CC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(
        c,
        r - 2.1,
        Paint()
          ..color = const Color(0x665E3D07)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
      canvas.drawPath(
        _starPath(c, 4.1, 1.8),
        Paint()..color = const Color(0xFF4F3103),
      );
    } else {
      canvas.drawCircle(c, r, Paint()..color = AppColors.deep);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = AppColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      canvas.drawPath(
        _starPath(c, 3.7, 1.6),
        Paint()
          ..color = AppColors.line.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EstMedalBadgePainter old) => old.earned != earned;
}

class DieFace extends StatelessWidget {
  const DieFace({
    super.key,
    required this.value,
    required this.color,
    this.size = 30,
    this.lost = false,
    this.won = false,
  });

  final int value;
  final Color color;
  final double size;
  final bool lost;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: lost ? 0.86 : 1.0,
      child: Opacity(
        opacity: lost ? 0.34 : 1.0,
        child: Container(
          width: size,
          height: size,
          decoration: won
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
                )
              : null,
          child: CustomPaint(
            painter: _DiePainter(
              value: value,
              faceColor: lost ? Color.lerp(color, const Color(0xFF4A5360), 0.7)! : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  const _DiePainter({required this.value, required this.faceColor});

  final int value;
  final Color faceColor;

  static const _pips = <int, List<Offset>>{
    1: [Offset(12, 12)],
    2: [Offset(7.2, 7.2), Offset(16.8, 16.8)],
    3: [Offset(7, 7), Offset(12, 12), Offset(17, 17)],
    4: [Offset(7.2, 7.2), Offset(16.8, 7.2), Offset(7.2, 16.8), Offset(16.8, 16.8)],
    5: [Offset(7, 7), Offset(17, 7), Offset(12, 12), Offset(7, 17), Offset(17, 17)],
    6: [
      Offset(7.2, 6.4),
      Offset(16.8, 6.4),
      Offset(7.2, 12),
      Offset(16.8, 12),
      Offset(7.2, 17.6),
      Offset(16.8, 17.6),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s, s);
    final rr = RRect.fromRectAndRadius(const Rect.fromLTWH(1, 1, 22, 22), const Radius.circular(5.5));
    canvas.drawRRect(rr, Paint()..color = faceColor);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    final pipPaint = Paint()..color = Colors.white;
    for (final pt in _pips[value] ?? const <Offset>[]) {
      canvas.drawCircle(pt, 2.15, pipPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiePainter old) =>
      old.value != value || old.faceColor != faceColor;
}
