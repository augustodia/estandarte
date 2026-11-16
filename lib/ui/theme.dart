import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const sea = Color(0xFF0F1C2E);
  static const deep = Color(0xFF0A1422);
  static const panel = Color(0xFF15263D);
  static const panel2 = Color(0xFF1B3050);
  static const line = Color(0xFF2B4466);
  static const glassBorder = Color(0xFF35557F);
  static const ink = Color(0xFFF1E6CF);
  static const mute = Color(0xFF9DB0C8);
  static const gold = Color(0xFFE2B04A);
  static const bad = Color(0xFFE06A5A);
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
    colors: [Color(0xF21A2E4B), Color(0xF211203A)],
  );

  static const hudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF172A45), Color(0xFF0F1D33)],
  );

  static const wideHudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF152741), Color(0xFF0F1D33)],
  );

  static const List<BoxShadow> edgeShadows = [
    BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 8)),
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
      fillColor: AppColors.deep,
      hintStyle: const TextStyle(color: Color(0xFF5D7492)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.gold),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
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
  final EstButtonVariant variant;
  final bool small;
  final double? height;
  final bool askPulse;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final h = height ?? (small ? 40.0 : 46.0);
    final fs = fontSize ?? (small ? 14.0 : 15.0);

    Color? bg;
    Gradient? grad;
    Color border;
    Color fg;
    List<BoxShadow>? shadows;

    if (askPulse) {
      bg = AppColors.gold;
      border = AppColors.gold;
      fg = const Color(0xFF1C1408);
      shadows = const [BoxShadow(color: Color(0x55E2B04A), blurRadius: 10)];
    } else {
      switch (variant) {
        case EstButtonVariant.primary:
          grad = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0C35E), Color(0xFFD39B2F)],
          );
          border = const Color(0xFFF3CD78);
          fg = const Color(0xFF1C1408);
          shadows = const [
            BoxShadow(color: Color(0x44D39B2F), blurRadius: 8, offset: Offset(0, 2)),
          ];
        case EstButtonVariant.ghost:
          bg = Colors.transparent;
          border = Colors.transparent;
          fg = AppColors.mute;
        case EstButtonVariant.warn:
          bg = const Color(0xFF281519);
          border = AppColors.bad;
          fg = const Color(0xFFFFD9D2);
        case EstButtonVariant.rad:
          grad = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E4A28), Color(0xFF123018)],
          );
          border = AppColors.rad.withValues(alpha: 0.6);
          fg = AppColors.rad;
        case EstButtonVariant.pact:
          bg = AppColors.panel2;
          border = const Color(0x88E2B04A);
          fg = const Color(0xFFFFE2A3);
        case EstButtonVariant.normal:
          bg = AppColors.panel2;
          border = AppColors.line;
          fg = AppColors.ink;
          shadows = const [
            BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
          ];
      }
    }

    return Opacity(
      opacity: disabled ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            height: h,
            padding: padding ?? EdgeInsets.symmetric(horizontal: small ? 12 : 16),
            decoration: BoxDecoration(
              color: grad == null ? bg : null,
              gradient: grad,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
              boxShadow: disabled ? null : shadows,
            ),
            child: Center(
              widthFactor: 1,
              child: child ??
                  Text(
                    label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fs,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1.0,
                    ),
                  ),
            ),
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
        color: net ? const Color(0xFF13284A) : const Color(0xFF12301A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: net ? const Color(0xFF2F5385) : const Color(0xFF2F6B41)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          height: 1.0,
          color: net ? const Color(0xFFA9CDFB) : const Color(0xFF9FE6B4),
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
    this.height = 40,
    this.fontSize = 14,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.deep,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: selected ? const Color(0xFF1C1408) : AppColors.ink,
              height: 1.0,
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
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: topBorder ? const Border(top: BorderSide(color: AppColors.line)) : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 38,
              height: 22,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? AppColors.gold : AppColors.line,
                borderRadius: BorderRadius.circular(11),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: value ? const Color(0xFF1C1408) : AppColors.ink,
                    shape: BoxShape.circle,
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
                      fontSize: 14,
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
    this.borderRadius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: AppColors.glassGradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: AppColors.edgeShadows,
      ),
      child: child,
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
    barrierColor: const Color(0xB302060C),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, _) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: SafeArea(
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
                            colors: [Color(0xF52A2619), Color(0xF511203A)],
                          )
                        : AppColors.glassGradient,
                    borderRadius: centered
                        ? BorderRadius.circular(18)
                        : const BorderRadius.vertical(top: Radius.circular(18)),
                    border: Border.all(color: AppColors.glassBorder),
                    boxShadow: const [
                      BoxShadow(color: Color(0xB3000000), blurRadius: 40, offset: Offset(0, -6)),
                    ],
                  ),
                  child: builder(ctx),
                ),
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
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
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
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            decoration: const BoxDecoration(
              color: AppColors.panel,
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
                    style: AppText.serif(size: 21, color: const Color(0xFFFFF3DC)),
                  ),
                ),
                InkWell(
                  onTap: onClose ?? () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.deep,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '✕',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                  ),
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

enum EstIconKind { goal, cards, menu, extras, pact, fit, crest, cup }

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
        // Pole M14 6v52 + Red banner M16 10h34l-8 11 8 11H16z
        canvas.drawLine(
          const Offset(14, 6),
          const Offset(14, 58),
          Paint()
            ..color = AppColors.ink
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
        final banner = Path()
          ..moveTo(16, 10)
          ..lineTo(50, 10)
          ..lineTo(42, 21)
          ..lineTo(50, 32)
          ..lineTo(16, 32)
          ..close();
        canvas.drawPath(
          banner,
          Paint()
            ..color = const Color(0xFFD64545)
            ..style = PaintingStyle.fill,
        );
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
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EstIconPainter old) => old.kind != kind || old.color != color;
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
