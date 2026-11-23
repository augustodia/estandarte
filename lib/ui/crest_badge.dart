import 'dart:math';

import 'package:flutter/material.dart';

import '../game/crests.dart';
import 'theme.dart';

/// Metal de cada nível: bronze (1★), prata (2★) e ouro (3★).
const List<Color> crestMetals = [
  Color(0xFF4A5363), // bloqueado
  Color(0xFFB4794A),
  Color(0xFFC5CDD8),
  Color(0xFFD9B45E),
];

/// Brasão desenhado (arte própria): escudo com o emblema da crônica no metal da melhor campanha, ou a medalha
/// de uma insígnia. Com [locked], mostra só a silhueta apagada.
class CrestBadge extends StatelessWidget {
  const CrestBadge(this.crest, {super.key, this.size = 18, this.locked = false, this.tooltip = false});

  final String crest;
  final double size;
  final bool locked;
  final bool tooltip; // mostra o nome do brasão ao passar o mouse / segurar

  @override
  Widget build(BuildContext context) {
    final p = parseCrest(crest);
    if (p == null) return SizedBox(width: size, height: size);
    final w = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CrestPainter(
          emblem: p.insignia?.id ?? p.chronicle!.id,
          insignia: p.insignia != null,
          metal: locked ? crestMetals[0] : crestMetals[p.tier],
          locked: locked,
        ),
      ),
    );
    if (!tooltip || locked) return w;
    return Tooltip(message: crestTitle(crest), child: w);
  }
}

class _CrestPainter extends CustomPainter {
  _CrestPainter({required this.emblem, required this.insignia, required this.metal, required this.locked});

  final String emblem;
  final bool insignia;
  final Color metal;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s, s);
    final small = size.width < 22; // nos nomes: traço mais grosso, sem detalhes finos
    final stroke = Paint()
      ..color = metal
      ..style = PaintingStyle.stroke
      ..strokeWidth = small ? 2.0 : 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = metal;
    final ground = Paint()..color = locked ? const Color(0xFF0E1318) : const Color(0xFF151B23);

    final Path frame;
    if (!insignia) {
      frame = Path() // escudo
        ..moveTo(3.5, 2.5)
        ..lineTo(20.5, 2.5)
        ..lineTo(20.5, 11)
        ..cubicTo(20.5, 16.6, 16.4, 20.2, 12, 22)
        ..cubicTo(7.6, 20.2, 3.5, 16.6, 3.5, 11)
        ..close();
    } else if (emblem == 'ins_estrategista') {
      frame = Path(); // hexágono
      for (var i = 0; i < 6; i++) {
        final a = pi / 6 + i * pi / 3;
        final pt = Offset(12 + 10 * cos(a), 12 + 10 * sin(a));
        if (i == 0) {
          frame.moveTo(pt.dx, pt.dy);
        } else {
          frame.lineTo(pt.dx, pt.dy);
        }
      }
      frame.close();
    } else {
      frame = Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9.6));
    }
    canvas.drawPath(frame, ground);
    canvas.drawPath(frame, stroke);
    if (locked) {
      canvas.restore();
      return; // silhueta: só a moldura
    }

    final line = Paint()
      ..color = metal
      ..style = PaintingStyle.stroke
      ..strokeWidth = small ? 1.9 : 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (emblem) {
      case 'hist_dday_1944': // desembarque: divisa subindo sobre as ondas
        canvas.drawPath(Path()..moveTo(8, 10.5)..lineTo(12, 6.5)..lineTo(16, 10.5), line);
        for (final y in [13.6, 16.6]) {
          final w = Path()..moveTo(7, y);
          for (var x = 7.0; x < 17; x += 2.5) {
            w.quadraticBezierTo(x + 1.25, y - 1.4, x + 2.5, y);
          }
          canvas.drawPath(w, line);
        }
      case 'hist_britain_1940': // roseta de defesa aérea com asas
        canvas.drawCircle(const Offset(12, 11), 3.4, line);
        canvas.drawCircle(const Offset(12, 11), 1.3, fill);
        canvas.drawLine(const Offset(6, 11), const Offset(8.4, 11), line);
        canvas.drawLine(const Offset(15.6, 11), const Offset(18, 11), line);
        canvas.drawLine(const Offset(6.8, 8.6), const Offset(8.8, 9.4), line);
        canvas.drawLine(const Offset(17.2, 8.6), const Offset(15.2, 9.4), line);
      case 'hist_constantinople_1453': // duas torres e a corrente do estreito
        canvas.drawPath(Path()..moveTo(6.5, 17)..lineTo(6.5, 8)..lineTo(9, 8)..lineTo(9, 17), line);
        canvas.drawPath(Path()..moveTo(15, 17)..lineTo(15, 8)..lineTo(17.5, 8)..lineTo(17.5, 17), line);
        canvas.drawPath(Path()..moveTo(9, 11.5)..quadraticBezierTo(12, 14.5, 15, 11.5), line);
        if (!small) {
          for (final x in [10.5, 12.0, 13.5]) {
            canvas.drawCircle(Offset(x, x == 12 ? 13 : 12.5), 0.7, fill);
          }
        }
      case 'hist_pacific_1942': // estrela-guia sobre o arquipélago
        canvas.drawPath(_star(const Offset(12, 8.6), 3.4, 1.4), fill);
        for (final x in [7.8, 12.0, 16.2]) {
          canvas.drawOval(Rect.fromCenter(center: Offset(x, x == 12 ? 16.2 : 15), width: 3.2, height: 1.8), fill);
        }
      case 'hist_stalingrad_1942': // o rio e a pinça fechando
        final river = Path()..moveTo(12, 5.5);
        river.cubicTo(10, 8.5, 14, 11, 12, 14);
        river.cubicTo(10.6, 16, 12.6, 17.5, 12, 19);
        canvas.drawPath(river, line);
        canvas.drawPath(Path()..moveTo(5.5, 8)..quadraticBezierTo(8.5, 11, 9.4, 12.5), line);
        canvas.drawPath(Path()..moveTo(18.5, 8)..quadraticBezierTo(15.5, 11, 14.6, 12.5), line);
        canvas.drawPath(Path()..moveTo(7.6, 12.6)..lineTo(9.6, 12.8)..lineTo(9.6, 10.8), line);
        canvas.drawPath(Path()..moveTo(16.4, 12.6)..lineTo(14.4, 12.8)..lineTo(14.4, 10.8), line);
      case 'hist_napoleon_1805': // manobra central: losango que divide três colunas
        canvas.drawPath(
          Path()..moveTo(12, 8.6)..lineTo(14.2, 11)..lineTo(12, 13.4)..lineTo(9.8, 11)..close(),
          fill,
        );
        for (final a in [-2.4, -0.74, pi / 2]) {
          final from = Offset(12 + 3.6 * cos(a), 11 + 3.6 * sin(a));
          final to = Offset(12 + 7 * cos(a), 11 + 7 * sin(a));
          canvas.drawLine(from, to, line);
        }
      case 'hist_thermopylae_480': // a passagem estreita entre as montanhas, com a muralha
        canvas.drawPath(Path()..moveTo(5, 17)..lineTo(9, 7)..lineTo(11, 17), line);
        canvas.drawPath(Path()..moveTo(13, 17)..lineTo(15, 7)..lineTo(19, 17), line);
        canvas.drawLine(const Offset(10.6, 13.5), const Offset(13.4, 13.5), line);
      case 'hist_carthage_218': // cordilheira e a marcha por cima
        canvas.drawPath(
          Path()..moveTo(5.5, 17)..lineTo(9, 11)..lineTo(11.5, 14)..lineTo(14.5, 9.5)..lineTo(18.5, 17),
          line,
        );
        canvas.drawPath(Path()..moveTo(6, 8.5)..quadraticBezierTo(11, 3.5, 17, 6.5), line);
        canvas.drawPath(Path()..moveTo(15, 5.2)..lineTo(17.2, 6.6)..lineTo(15.6, 8.4), line);
      case 'hist_spiceroute_1509': // rosa dos ventos
        canvas.drawPath(_star(const Offset(12, 11), 6.6, 1.6, points: 4), fill);
        if (!small) canvas.drawCircle(const Offset(12, 11), 3.6, line..strokeWidth = 1);
      case 'hist_coldwar_1962': // radar: alvo e varredura
        canvas.drawCircle(const Offset(12, 11), 1.4, fill);
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 11), radius: 4), -2.6, 4.2, false, line);
        canvas.drawArc(Rect.fromCircle(center: const Offset(12, 11), radius: 6.8), -2.2, 3.4, false, line);
        canvas.drawLine(const Offset(12, 11), const Offset(16.6, 6.6), line);
      case 'ins_veterano': // três divisas
        for (final y in [8.0, 11.5, 15.0]) {
          canvas.drawPath(Path()..moveTo(7.5, y)..lineTo(12, y + 2.6)..lineTo(16.5, y), line);
        }
      case 'ins_estrategista': // estrela cheia no hexágono
        canvas.drawPath(_star(const Offset(12, 12.4), 5.6, 2.3), fill);
      case 'ins_historiador': // livro aberto
        final book = Path()
          ..moveTo(6.5, 8.6)
          ..quadraticBezierTo(9.5, 7.8, 12, 9.4)
          ..quadraticBezierTo(14.5, 7.8, 17.5, 8.6)
          ..lineTo(17.5, 15.8)
          ..quadraticBezierTo(14.5, 15, 12, 16.6)
          ..quadraticBezierTo(9.5, 15, 6.5, 15.8)
          ..close();
        canvas.drawPath(book, line);
        canvas.drawLine(const Offset(12, 9.4), const Offset(12, 16.6), line);
    }
    canvas.restore();
  }

  static Path _star(Offset c, double outer, double inner, {int points = 5}) {
    final p = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outer : inner;
      final a = -pi / 2 + i * pi / points;
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
  bool shouldRepaint(_CrestPainter old) =>
      old.emblem != emblem || old.metal != metal || old.locked != locked || old.insignia != insignia;
}

/// Nome com o brasão ao lado (o brasão some quando não há).
class NameWithCrest extends StatelessWidget {
  const NameWithCrest(this.name, {super.key, this.crest = '', required this.style, this.size = 15});

  final String name;
  final String crest;
  final TextStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    if (parseCrest(crest) == null) return t;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: t),
        const SizedBox(width: 6),
        CrestBadge(crest, size: size, tooltip: true),
      ],
    );
  }
}

/// Moldura de seleção usada na coleção.
BoxDecoration crestTileDecoration({required bool selected, required bool earned}) => BoxDecoration(
      color: selected ? AppColors.panel2 : AppColors.obsidian.withValues(alpha: earned ? 0.9 : 0.45),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: selected ? AppColors.ink : AppColors.line, width: selected ? 1.4 : 1),
    );
