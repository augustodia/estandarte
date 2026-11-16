import 'dart:math';

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const sea = Color(0xFF0F1C2E);
  static const obsidian = Color(0xFF060A12);
  static const deep = Color(0xFF09101B);
  static const panel = Color(0xFF101928);
  static const panel2 = Color(0xFF172438);
  static const line = Color(0xFF26364D);
  static const glassBorder = Color(0xFF344966);
  static const ink = Color(0xFFEFE4CE);
  static const mute = Color(0xFF8FA1B9);
  static const gold = Color(0xFFD9B25F);
  static const brass = Color(0xFFB38B45);
  static const brassDim = Color(0x4CB38B45);
  static const bad = Color(0xFFD65E52);
  static const rad = Color(0xFF7DFF4A);

  // Backwards-compatible aliases if referenced in tests/widgets
  static const bg = deep;
  static const surface = panel;
  static const border = line;
  static const text = ink;
  static const muted = mute;
  static const danger = bad;

  static const glassGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xF7142033), Color(0xF70B121F)],
  );

  static const hudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF131F32), Color(0xFF0A111D)],
  );

  static const wideHudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF101B2C), Color(0xFF080E18)],
  );

  static const List<BoxShadow> edgeShadows = [
    BoxShadow(color: Color(0xB8000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
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
    final sz = MediaQuery.sizeOf(context);
    final minSide = min(sz.width, sz.height);
    final big = minSide >= 600;
    final portrait = sz.height > sz.width;
    final wide = big && sz.width >= 1000 && sz.width >= sz.height * 0.9;
    final tall = big && !wide;
    final rot = inGame && portrait && !big && forceLand;
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

abstract final class AppText {
  static const List<String> serifFallback = ['Georgia', 'Times New Roman', 'serif'];

  static TextStyle serif({
    double size = 20,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
    double letterSpacing = 0.04,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: 'Georgia',
      fontFamilyFallback: serifFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: size * letterSpacing,
      height: height,
    );
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.deep,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      secondary: AppColors.gold,
      surface: AppColors.panel,
      error: AppColors.bad,
      onPrimary: Color(0xFF1C1408),
      onSurface: AppColors.ink,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: AppColors.ink),
      bodySmall: TextStyle(fontSize: 13, height: 1.35, color: AppColors.mute),
    ),
    cardColor: AppColors.panel,
    dividerColor: AppColors.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0C1422),
      hintStyle: const TextStyle(color: Color(0xFF607491)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: Color(0xFF283A56)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: Color(0xFF283A56)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: const BorderSide(color: AppColors.brass),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
  );
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
    final h = height ?? (small ? 36.0 : 44.0);
    final fs = fontSize ?? (small ? 13.0 : 14.0);

    Color? bg;
    Gradient? grad;
    Color border;
    Color fg;
    Color? topBevel;
    List<BoxShadow>? shadows;

    if (askPulse) {
      grad = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE7BF66), Color(0xFFB5822B)],
      );
      border = const Color(0xFFF3D896);
      fg = const Color(0xFF191205);
      topBevel = const Color(0x66FFF4D6);
      shadows = const [
        BoxShadow(color: Color(0x77000000), blurRadius: 8, offset: Offset(0, 3)),
        BoxShadow(color: Color(0x44D9B25F), blurRadius: 12),
      ];
    } else {
      switch (variant) {
        case EstButtonVariant.primary:
          grad = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDFB85E), Color(0xFFA97824)],
          );
          border = const Color(0xFFE9CB81);
          fg = const Color(0xFF191104);
          topBevel = const Color(0x55FFF0C8);
          shadows = const [
            BoxShadow(color: Color(0x77000000), blurRadius: 8, offset: Offset(0, 3)),
          ];
        case EstButtonVariant.ghost:
          bg = Colors.transparent;
          border = Colors.transparent;
          fg = AppColors.mute;
        case EstButtonVariant.warn:
          grad = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF39181B), Color(0xFF210D10)],
          );
          border = AppColors.bad.withValues(alpha: 0.72);
          fg = const Color(0xFFFFD8D1);
          topBevel = const Color(0x1EFF9E92);
        case EstButtonVariant.rad:
          grad = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A3F22), Color(0xFF0C2211)],
          );
          border = AppColors.rad.withValues(alpha: 0.62);
          fg = AppColors.rad;
          topBevel = const Color(0x287DFF4A);
          shadows = [BoxShadow(color: AppColors.rad.withValues(alpha: 0.14), blurRadius: 8)];
        case EstButtonVariant.pact:
          grad = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF243854), Color(0xFF152236)],
          );
          border = AppColors.brass;
          fg = const Color(0xFFF3DEAC);
          topBevel = const Color(0x2EE9CB81);
          shadows = const [
            BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
          ];
        case EstButtonVariant.normal:
          grad = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A283E), Color(0xFF101928)],
          );
          border = const Color(0xFF2D405C);
          fg = AppColors.ink;
          topBevel = const Color(0x16FFFFFF);
          shadows = const [
            BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2)),
          ];
      }
    }

    final innerContent = child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              EstIcon(icon!, size: small ? 14 : 16, color: fg),
              SizedBox(width: small ? 6 : 8),
            ],
            Flexible(
              child: Text(
                label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                style: TextStyle(
                  fontSize: fs,
                  fontWeight: variant == EstButtonVariant.primary || askPulse
                      ? FontWeight.w800
                      : FontWeight.w600,
                  letterSpacing: variant == EstButtonVariant.primary ? 0.35 : 0.15,
                  color: fg,
                  height: 1.15,
                ),
              ),
            ),
          ],
        );

    const radius = 5.0;
    return Opacity(
      opacity: disabled ? 0.42 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(radius),
          child: Ink(
            height: h,
            decoration: BoxDecoration(
              color: grad == null ? bg : null,
              gradient: grad,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border),
              boxShadow: disabled ? null : shadows,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (topBevel != null)
                  Positioned(
                    left: 1,
                    right: 1,
                    top: 0,
                    height: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: topBevel,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(radius - 1)),
                      ),
                    ),
                  ),
                Padding(
                  padding: padding ?? EdgeInsets.symmetric(horizontal: small ? 11 : 15),
                  child: Center(
                    widthFactor: 1,
                    child: innerContent,
                  ),
                ),
              ],
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
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          hoverColor: dangerHover
              ? AppColors.bad.withValues(alpha: 0.16)
              : AppColors.panel2.withValues(alpha: 0.75),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.obsidian.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(4),
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
            color: _focused ? const Color(0xFF0A111D) : const Color(0xFF0C1422),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _focused ? AppColors.brass : const Color(0xFF283A56),
            ),
            boxShadow: _focused
                ? const [BoxShadow(color: Color(0x24D9B25F), blurRadius: 8)]
                : null,
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
                  style: widget.style ?? const TextStyle(fontSize: 13.5, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF607491),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: net ? const Color(0xFF102037) : const Color(0xFF112618),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: net ? const Color(0xFF2D4B73) : const Color(0xFF2D5D3B)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          height: 1.0,
          color: net ? const Color(0xFFA7C7F0) : const Color(0xFF9BE0B0),
        ),
      ),
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
      color: selected ? const Color(0xFF24344B) : AppColors.obsidian,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.line,
              width: selected ? 1.2 : 1.0,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.ink : AppColors.mute,
              height: 1.15,
            ),
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
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: topBorder ? const Border(top: BorderSide(color: AppColors.line)) : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 36,
              height: 20,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: value ? const Color(0xFF8C6B2C) : AppColors.obsidian,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: value ? AppColors.gold : AppColors.line),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: value ? AppColors.ink : AppColors.mute,
                    borderRadius: BorderRadius.circular(2.5),
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
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.mute,
                    ),
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
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 6,
    this.ornate = true,
    this.highlight = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool ornate;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final outerBorder = highlight ? const Color(0xFF8F7241) : AppColors.glassBorder;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.glassGradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: outerBorder, width: 1.0),
        boxShadow: AppColors.edgeShadows,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 1,
            right: 1,
            top: 0,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    (highlight ? AppColors.gold : Colors.white).withValues(alpha: highlight ? 0.24 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          if (ornate && highlight)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(max(2.0, borderRadius - 2.5)),
                      border: Border.all(color: const Color(0x28D9B25F), width: 0.9),
                    ),
                  ),
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class EstRuleDivider extends StatelessWidget {
  const EstRuleDivider({super.key, this.color, this.diamond = true});

  final Color? color;
  final bool diamond;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF394D69);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.withValues(alpha: 0.0), c]),
            ),
          ),
        ),
        if (diamond)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(
                width: 4.5,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.brass.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c, c.withValues(alpha: 0.0)]),
            ),
          ),
        ),
      ],
    );
  }
}

class EstSectionTag extends StatelessWidget {
  const EstSectionTag(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Transform.rotate(
          angle: pi / 4,
          child: Container(
            width: 4.5,
            height: 4.5,
            margin: const EdgeInsets.only(right: 8, left: 1),
            color: AppColors.brass,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.7,
            color: AppColors.mute,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x99344966), Color(0x14344966)],
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

class EstFactionSeal extends StatelessWidget {
  const EstFactionSeal({
    super.key,
    required this.color,
    this.size = 16,
    this.highlighted = false,
  });

  final Color color;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 6,
      height: size + 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.obsidian,
        border: Border.all(
          color: highlighted ? AppColors.gold : const Color(0xFF475C7A),
          width: highlighted ? 1.4 : 1.1,
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.28, -0.32),
            colors: [
              Color.lerp(color, Colors.white, 0.25)!,
              color,
              Color.lerp(color, Colors.black, 0.28)!,
            ],
          ),
          border: Border.all(color: Colors.black.withValues(alpha: 0.45), width: 0.7),
        ),
      ),
    );
  }
}

Future<T?> showEstSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool pactTheme = false,
  double maxWidth = 560,
}) {
  final layout = EstLayout.of(context);
  final centered = layout.big || layout.land;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Fechar',
    barrierColor: const Color(0xCC02060C),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, _) => SafeArea(
      child: Align(
        alignment: centered ? Alignment.center : Alignment.bottomCenter,
        child: Padding(
          padding: centered ? const EdgeInsets.all(20) : EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: centered ? (layout.land && !layout.big ? 560 : maxWidth) : 500,
              maxHeight: MediaQuery.sizeOf(ctx).height * (centered ? 0.90 : 0.92),
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: pactTheme
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xF7241F15), Color(0xF70D1727)],
                        )
                      : AppColors.glassGradient,
                  borderRadius: centered
                      ? BorderRadius.circular(6)
                      : const BorderRadius.vertical(top: Radius.circular(8)),
                  border: Border.all(color: pactTheme ? AppColors.brass : AppColors.glassBorder),
                  boxShadow: const [
                    BoxShadow(color: Color(0xCC000000), blurRadius: 36, offset: Offset(0, -4)),
                  ],
                ),
                child: builder(ctx),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      if (centered) {
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(curved),
            child: child,
          ),
        );
      }
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class EstSheetBody extends StatelessWidget {
  const EstSheetBody({
    super.key,
    required this.children,
    this.title,
    this.titleIcon,
    this.onClose,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
  });

  final String? title;
  final Widget? titleIcon;
  final VoidCallback? onClose;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF162235), Color(0xFF0E1725)],
              ),
              border: Border(
                top: BorderSide(color: Color(0x66B38B45), width: 1.5),
                bottom: BorderSide(color: AppColors.line),
              ),
            ),
            child: Row(
              children: [
                if (titleIcon != null) ...[
                  titleIcon!,
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: AppText.serif(size: 20, color: const Color(0xFFF9EFD7)),
                  ),
                ),
                EstIconButton(
                  icon: EstIconKind.close,
                  size: 30,
                  iconSize: 13,
                  onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: padding,
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
        // Lacre de cera vermelho com uma mira: a marca do Ultimato
        const c = Offset(32, 32);
        final seal = Path();
        for (var i = 0; i < 12; i++) {
          final a = i * pi / 6;
          seal.addOval(Rect.fromCircle(center: c + Offset(cos(a), sin(a)) * 21.5, radius: 7.5));
        }
        seal.addOval(Rect.fromCircle(center: c, radius: 23));
        canvas.drawPath(seal, Paint()..color = const Color(0xFFB8322F));
        canvas.drawCircle(c, 21, Paint()..color = const Color(0xFFD64545));
        canvas.drawCircle(
          c,
          17.5,
          Paint()
            ..color = const Color(0x55701A18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        final mark = Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(c, 10.5, mark);
        for (final d in const [Offset(0, -1), Offset(0, 1), Offset(-1, 0), Offset(1, 0)]) {
          canvas.drawLine(c + d * 5.5, c + d * 15.5, mark);
        }
        canvas.drawCircle(c, 1.8, Paint()..color = AppColors.ink);
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
