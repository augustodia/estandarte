import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Patentes da ranqueada, da mais baixa à mais alta (iguais às do servidor).
const List<String> patenteNames = [
  'Recruta', 'Soldado', 'Cabo', 'Sargento', 'Tenente', 'Capitão', 'Major', 'Coronel', 'General', 'Marechal',
];

/// Insígnia desenhada da patente (arte própria): divisas para as praças (Soldado a Sargento), estrelas para os
/// oficiais (Tenente a General) e uma estrela com coroa de louros para o Marechal. [index] -1 = em colocação.
class PatenteBadge extends StatelessWidget {
  const PatenteBadge(this.index, {super.key, this.size = 20, this.color});

  final int index;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _PatentePainter(index, color ?? (index >= 8 ? const Color(0xFFD9B45E) : AppColors.ink)),
        ),
      );
}

class _PatentePainter extends CustomPainter {
  _PatentePainter(this.index, this.color);

  final int index;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    final small = size.width < 22;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = small ? 2.1 : 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    final faint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    void chevrons(int n) {
      final gap = 4.6;
      final top = 12 - (n - 1) * gap / 2 - 2;
      for (var i = 0; i < n; i++) {
        final y = top + i * gap;
        canvas.drawPath(Path()..moveTo(5.5, y)..lineTo(12, y + 4.2)..lineTo(18.5, y), line);
      }
    }

    void stars(int n) {
      final r = n <= 2 ? 4.4 : (n == 3 ? 3.7 : 3.1);
      final pts = <Offset>[];
      switch (n) {
        case 1:
          pts.add(const Offset(12, 12));
        case 2:
          pts.addAll(const [Offset(7.6, 12), Offset(16.4, 12)]);
        case 3:
          pts.addAll(const [Offset(12, 7.4), Offset(7.2, 15), Offset(16.8, 15)]);
        case 4:
          pts.addAll(const [Offset(7.6, 7.8), Offset(16.4, 7.8), Offset(7.6, 16.2), Offset(16.4, 16.2)]);
        default:
          pts.addAll(const [Offset(12, 5.6), Offset(6.2, 10.6), Offset(17.8, 10.6), Offset(8.4, 17.6), Offset(15.6, 17.6)]);
      }
      for (final c in pts) {
        canvas.drawPath(_star(c, r, r * 0.42), fill);
      }
    }

    switch (index) {
      case < 0: // em colocação: só o contorno
        canvas.drawCircle(const Offset(12, 12), 8.5, faint);
        canvas.drawLine(const Offset(9, 12), const Offset(15, 12), faint);
      case 0: // Recruta: uma barra
        canvas.drawLine(const Offset(6.5, 12), const Offset(17.5, 12), line);
      case 1 || 2 || 3: // Soldado, Cabo, Sargento
        chevrons(index);
      case 4 || 5 || 6 || 7 || 8: // Tenente a General
        stars(index - 3);
      default: // Marechal: estrela com louros
        canvas.drawPath(_star(const Offset(12, 10.6), 5.2, 2.2), fill);
        for (final side in [-1.0, 1.0]) {
          final p = Path()..moveTo(12 + side * 2.4, 20.5);
          p.quadraticBezierTo(12 + side * 9.8, 18.6, 12 + side * 9.4, 8.4);
          canvas.drawPath(p, line);
          for (final t in [0.35, 0.62, 0.86]) {
            final x = 12 + side * (2.4 + 7.2 * t);
            final y = 20.5 - 11 * t * t;
            canvas.drawCircle(Offset(x, y), small ? 1.2 : 0.95, fill);
          }
        }
    }
    canvas.restore();
  }

  static Path _star(Offset c, double outer, double inner) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -pi / 2 + i * pi / 5;
      final pt = Offset(c.dx + r * cos(a), c.dy + r * sin(a));
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_PatentePainter old) => old.index != index || old.color != color;
}
