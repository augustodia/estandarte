import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import 'theme.dart';

const double _mapPad = 30.0;

class WorldMapView extends StatefulWidget {
  const WorldMapView({super.key, required this.ctrl, this.onControllerReady});

  final AppController ctrl;
  final void Function(VoidCallback fitZoom)? onControllerReady;

  @override
  State<WorldMapView> createState() => _WorldMapViewState();
}

class _WorldMapViewState extends State<WorldMapView> with TickerProviderStateMixin {
  double _camX = 0;
  double _camY = 0;
  double _camZ = 1;
  Size _viewSize = Size.zero;
  bool _fitted = false;

  int? _hoverTerr;

  // Gesture state
  double _startZ = 1;
  Offset _startFocal = Offset.zero;
  Offset _startMapPoint = Offset.zero;

  // Pan animation
  Ticker? _panTicker;
  double _panStartX = 0, _panStartY = 0, _panStartZ = 1;
  double _panEndX = 0, _panEndY = 0, _panEndZ = 1;
  int _panStartMs = 0, _panDurMs = 0;

  // Shake animation
  late final AnimationController _shakeCtrl;
  bool _bigShake = false;

  // Continuous repaint ticker for marching ants, pulse, smoke, combat FX, nuke cinema
  late final Ticker _animTicker;
  final _MapAnimNotifier _animNotifier = _MapAnimNotifier();
  int _lastSubtleTickMs = 0;

  // Precomputed sea route geometry & label/paint cache
  List<_ComputedSeaRoute>? _seaCache;
  _MapPaintCache? _paintCache;

  _MapPaintCache _getPaintCache() => _paintCache ??= _MapPaintCache(widget.ctrl.mapData);

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animTicker = createTicker((_) {
      if (!mounted) return;
      final c = widget.ctrl;
      final now = DateTime.now().millisecondsSinceEpoch;
      final fogActive = c.view?['fog'] != null && c.view?['phase'] == 'play';
      final hasSpot = c.spotlightSet != null && c.spotlightUntilMs > now;
      final hasHeavyFx = c.pulses.isNotEmpty ||
          c.strikes.isNotEmpty ||
          c.arrows.isNotEmpty ||
          c.floats.isNotEmpty ||
          c.missile != null ||
          c.impactFx != null ||
          c.incomingTerr != null ||
          c.smoke.active;
      final bonusOnlyActive = c.canPlayNow() &&
          c.view?['step'] == 'reinforce' &&
          (c.view?['pool']?['free'] as num? ?? 0) == 0 &&
          !(c.eval?.mustTrade ?? false);
      final hasSubtleAnim = c.sel != null ||
          c.trenchMode ||
          c.airliftMode ||
          c.nukeMode ||
          bonusOnlyActive ||
          hasSpot ||
          fogActive;
      if (hasHeavyFx) {
        _lastSubtleTickMs = now;
        _animNotifier.tick(now);
      } else if (hasSubtleAnim && now - _lastSubtleTickMs >= 45) {
        // ~22 FPS is plenty for subtle border dashes & pulses while cutting CPU load by >60%
        _lastSubtleTickMs = now;
        _animNotifier.tick(now);
      }
    })
      ..start();

    widget.ctrl.onPanTo = _panTo;
    widget.ctrl.onShake = _triggerShake;
    widget.ctrl.getScreenMidY = (a, b) {
      final ta = widget.ctrl.mapData.territories[a];
      final tb = widget.ctrl.mapData.territories[b];
      return ((ta.y + tb.y) / 2 - _camY) * _camZ;
    };
    widget.onControllerReady?.call(toggleFit);
  }

  @override
  void dispose() {
    _panTicker?.dispose();
    _shakeCtrl.dispose();
    _animTicker.dispose();
    _animNotifier.dispose();
    _paintCache?.dispose();
    if (widget.ctrl.onPanTo == _panTo) widget.ctrl.onPanTo = null;
    if (widget.ctrl.onShake == _triggerShake) widget.ctrl.onShake = null;
    super.dispose();
  }

  List<_ComputedSeaRoute> _getSeaCache() {
    if (_seaCache != null) return _seaCache!;
    final md = widget.ctrl.mapData;
    final out = <_ComputedSeaRoute>[];
    for (final r in md.seaRoutes) {
      if (r.wrap) {
        final left = Path()
          ..moveTo(r.x1, r.y1)
          ..lineTo(-_mapPad - 20, r.y1);
        final right = Path()
          ..moveTo(r.x2, r.y2)
          ..lineTo(md.width + _mapPad + 20, r.y2);
        out.add(_ComputedSeaRoute(route: r, paths: [left, right]));
      } else {
        final dx = r.x2 - r.x1;
        final dy = r.y2 - r.y1;
        final len = hypot(dx, dy);
        final path = Path()..moveTo(r.x1, r.y1);
        if (len < 60) {
          path.lineTo(r.x2, r.y2);
        } else {
          final mx = (r.x1 + r.x2) / 2;
          final my = (r.y1 + r.y2) / 2;
          final nx = -dy / len;
          final ny = dx / len;
          final h = len * 0.16;
          double minDist(double cx, double cy) {
            var best = double.infinity;
            for (final t in md.territories) {
              final d = hypot(t.x - cx, t.y - cy);
              if (d < best) best = d;
            }
            return best;
          }
          final sg = minDist(mx + nx * h * 2, my + ny * h * 2) >=
                  minDist(mx - nx * h * 2, my - ny * h * 2)
              ? 1.0
              : -1.0;
          path.quadraticBezierTo(mx + nx * h * sg, my + ny * h * sg, r.x2, r.y2);
        }
        out.add(_ComputedSeaRoute(route: r, paths: [path]));
      }
    }
    _seaCache = out;
    return out;
  }

  (double contain, double cover, double maxZ) _limits() {
    if (_viewSize.width <= 0 || _viewSize.height <= 0) return (1.0, 1.0, 4.0);
    final md = widget.ctrl.mapData;
    final contain = min(
      _viewSize.width / (md.width + 2 * _mapPad),
      _viewSize.height / (md.height + 2 * _mapPad),
    );
    final cover = max(_viewSize.width / md.width, _viewSize.height / md.height);
    return (contain, cover, max(cover * 2.2, 1.4));
  }

  void _clampCam() {
    if (_viewSize.width <= 0 || _viewSize.height <= 0) return;
    final md = widget.ctrl.mapData;
    final (contain, _, maxZ) = _limits();
    _camZ = _camZ.clamp(contain, maxZ);
    final visW = _viewSize.width / _camZ;
    final visH = _viewSize.height / _camZ;
    if (visW >= md.width + 2 * _mapPad) {
      _camX = (md.width - visW) / 2;
    } else {
      _camX = _camX.clamp(-_mapPad, md.width + _mapPad - visW);
    }
    if (visH >= md.height + 2 * _mapPad) {
      _camY = (md.height - visH) / 2;
    } else {
      _camY = _camY.clamp(-_mapPad, md.height + _mapPad - visH);
    }
  }

  void fitInitial() {
    if (_viewSize.width <= 0 || _viewSize.height <= 0) return;
    final md = widget.ctrl.mapData;
    final layout = EstLayout.of(context, inGame: true, forceLand: widget.ctrl.forceLand);
    final (contain, cover, _) = _limits();
    final mid = min(cover, contain * 2.4);
    setState(() {
      if (layout.wide) {
        _camZ = contain;
      } else if (layout.tall) {
        _camZ = min(cover, contain * 1.2);
      } else {
        _camZ = mid;
      }
      _camX = (md.width - _viewSize.width / _camZ) / 2;
      _camY = (md.height - _viewSize.height / _camZ) / 2;
      _clampCam();
      _fitted = true;
    });
  }

  void toggleFit() {
    if (_viewSize.width <= 0 || _viewSize.height <= 0) return;
    final md = widget.ctrl.mapData;
    final (contain, cover, _) = _limits();
    final mid = min(cover, contain * 2.4);
    setState(() {
      _camZ = (_camZ - contain).abs() < 0.01 ? mid : contain;
      _camX = (md.width - _viewSize.width / _camZ) / 2;
      _camY = (md.height - _viewSize.height / _camZ) / 2;
      _clampCam();
      _fitted = true;
    });
  }

  void _panTo(double x0, double y0, double x1, double y1, int ms) {
    if (_viewSize.width <= 0 || _viewSize.height <= 0) return;
    final (contain, _, maxZ) = _limits();
    final bw = (x1 - x0).abs() + 260;
    final bh = (y1 - y0).abs() + 200;
    final z1 = max(contain, min(maxZ, min(_camZ, min(_viewSize.width / bw, _viewSize.height / bh))));
    final cx = (x0 + x1) / 2;
    final cy = (y0 + y1) / 2;
    _panStartX = _camX;
    _panStartY = _camY;
    _panStartZ = _camZ;
    _panEndZ = z1;
    _panEndX = cx - _viewSize.width / z1 / 2;
    _panEndY = cy - _viewSize.height / z1 / 2;
    _panStartMs = DateTime.now().millisecondsSinceEpoch;
    _panDurMs = ms;

    _panTicker?.dispose();
    _panTicker = createTicker((_) {
      if (!mounted) return;
      final t = ((DateTime.now().millisecondsSinceEpoch - _panStartMs) / _panDurMs).clamp(0.0, 1.0);
      final e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2;
      setState(() {
        _camZ = _panStartZ + (_panEndZ - _panStartZ) * e;
        _camX = _panStartX + (_panEndX - _panStartX) * e;
        _camY = _panStartY + (_panEndY - _panStartY) * e;
        _clampCam();
      });
      if (t >= 1.0) {
        _panTicker?.stop();
        _panTicker?.dispose();
        _panTicker = null;
      }
    })
      ..start();
  }

  void _triggerShake(bool conquer) {
    if (!mounted) return;
    _bigShake = conquer;
    _shakeCtrl.duration = Duration(milliseconds: conquer ? 550 : 350);
    _shakeCtrl.forward(from: 0);
  }

  Offset _screenToMap(Offset local) {
    return Offset(local.dx / _camZ + _camX, local.dy / _camZ + _camY);
  }

  int? _hitTerritory(Offset mapPos) {
    final terrs = widget.ctrl.mapData.territories;
    // Prioritize army badge hit radius (r=19 scaled by markK) just like svg2 .hit circles
    final markK = (10.5 / (12.5 * _camZ)).clamp(1.0, 2.2);
    final hitR = 19.0 * markK;
    for (var i = terrs.length - 1; i >= 0; i--) {
      if (hypot(mapPos.dx - terrs[i].x, mapPos.dy - terrs[i].y) <= hitR) {
        return i;
      }
    }
    for (var i = terrs.length - 1; i >= 0; i--) {
      if (terrs[i].bounds.contains(mapPos) && terrs[i].path.contains(mapPos)) {
        return i;
      }
    }
    return null;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final (contain, _, maxZ) = _limits();
      final factor = exp(-e.scrollDelta.dy * 0.0014);
      final nextZ = (_camZ * factor).clamp(contain, maxZ);
      if (nextZ == _camZ) return;
      final mp = _screenToMap(e.localPosition);
      setState(() {
        _camZ = nextZ;
        _camX = mp.dx - e.localPosition.dx / _camZ;
        _camY = mp.dy - e.localPosition.dy / _camZ;
        _clampCam();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final imp = c.impactFx;
    final nowSnap = DateTime.now().millisecondsSinceEpoch;
    final boomActive = imp != null && (nowSnap - imp.startMs) < 2500;

    return LayoutBuilder(
      builder: (context, constraints) {
        final sz = Size(constraints.maxWidth, constraints.maxHeight);
        if (sz != _viewSize && sz.width > 0 && sz.height > 0) {
          final wasZero = _viewSize == Size.zero;
          _viewSize = sz;
          c.mapViewportHeight = sz.height;
          if (wasZero || !_fitted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) fitInitial();
            });
          } else {
            _clampCam();
          }
        }

        final alarmActive = c.incomingTerr != null;
        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerSignal: _onPointerSignal,
              onPointerDown: (ev) {
                if ((ev.buttons & kSecondaryMouseButton) != 0) {
                  c.clearSelection();
                }
              },
              child: MouseRegion(
                cursor: _hoverTerr != null ? SystemMouseCursors.click : SystemMouseCursors.grab,
                onHover: (ev) {
                  final hit = _hitTerritory(_screenToMap(ev.localPosition));
                  if (hit != _hoverTerr) {
                    setState(() => _hoverTerr = hit);
                    c.setHoverInfoTerr(hit);
                  }
                },
                onExit: (_) {
                  if (_hoverTerr != null) {
                    setState(() => _hoverTerr = null);
                    c.setHoverInfoTerr(null);
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (d) {
                    _panTicker?.stop();
                    _startZ = _camZ;
                    _startFocal = d.localFocalPoint;
                    _startMapPoint = _screenToMap(d.localFocalPoint);
                  },
                  onScaleUpdate: (d) {
                    final (contain, _, maxZ) = _limits();
                    setState(() {
                      if ((d.scale - 1.0).abs() > 0.002) {
                        _camZ = (_startZ * d.scale).clamp(contain, maxZ);
                        _camX = _startMapPoint.dx - d.localFocalPoint.dx / _camZ;
                        _camY = _startMapPoint.dy - d.localFocalPoint.dy / _camZ;
                      } else {
                        final delta = d.localFocalPoint - _startFocal;
                        _camX -= delta.dx / _camZ;
                        _camY -= delta.dy / _camZ;
                        _startFocal = d.localFocalPoint;
                      }
                      _clampCam();
                    });
                  },
                  onTapUp: (d) {
                    final mp = _screenToMap(d.localPosition);
                    if (c.smoke.active) {
                      c.smoke.poke(mp.dx, mp.dy);
                    }
                    final t = _hitTerritory(mp);
                    if (t != null) {
                      c.tapTerritory(t);
                    } else {
                      c.clearSelection();
                    }
                  },
                  child: RepaintBoundary(
                    child: ClipRect(
                      child: CustomPaint(
                        size: sz,
                        painter: _WorldMapPainter(
                          repaint: Listenable.merge([c, c.smoke, _shakeCtrl, _animNotifier]),
                          ctrl: c,
                          cache: _getPaintCache(),
                          seaRoutes: _getSeaCache(),
                          shakeCtrl: _shakeCtrl,
                          bigShake: () => _bigShake,
                          animNotifier: _animNotifier,
                          camX: _camX,
                          camY: _camY,
                          camZ: _camZ,
                          hoverTerr: _hoverTerr,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Tabletop lighting vignette matching #mapwrap::before
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.15),
                      radius: 1.05,
                      colors: [Colors.transparent, Colors.transparent, Color(0xB304080F)],
                      stops: [0.0, 0.52, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Nuke alarm crimson perimeter glow
            if (alarmActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _animNotifier,
                    builder: (context, _) {
                      final pulse = sin(_animNotifier.nowMs * 0.015).abs();
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF3B2F).withValues(alpha: 0.35 + 0.65 * pulse),
                            width: 3.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0x88FF1E1E).withValues(alpha: 0.25 + 0.5 * pulse),
                              blurRadius: 90,
                              blurStyle: BlurStyle.inner,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Nuke boom screen flash
            if (boomActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _animNotifier,
                    builder: (context, _) {
                      final boomAge = ((_animNotifier.nowMs - imp.startMs) / 2500.0).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: (1.0 - Curves.easeOut.transform(boomAge)).clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(
                                (((imp.x - _camX) * _camZ / sz.width) * 2 - 1).clamp(-1.0, 1.0),
                                (((imp.y - _camY) * _camZ / sz.height) * 2 - 1).clamp(-1.0, 1.0),
                              ),
                              radius: 0.9,
                              colors: const [
                                Colors.white,
                                Color(0xFFFFF7DC),
                                Color(0xFFFFD98A),
                                Color(0x55B9FF7A),
                                Color(0x001D6A26),
                              ],
                              stops: const [0.0, 0.09, 0.22, 0.46, 0.78],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MapAnimNotifier extends ChangeNotifier {
  int nowMs = DateTime.now().millisecondsSinceEpoch;
  void tick(int now) {
    nowMs = now;
    notifyListeners();
  }
}

class _MapPaintCache {
  _MapPaintCache(this.md) {
    final terrs = md.territories;
    territoryOrder = List<int>.generate(terrs.length, (i) => i);
    territoryOrder.sort((a, b) {
      double minD(int idx) {
        var best = double.infinity;
        for (var j = 0; j < terrs.length; j++) {
          if (j == idx) continue;
          final d = hypot(terrs[j].x - terrs[idx].x, terrs[j].y - terrs[idx].y);
          if (d < best) best = d;
        }
        return best;
      }

      return minD(a).compareTo(minD(b));
    });

    terrNameFill = [
      for (final tr in terrs)
        TextPainter(
          text: TextSpan(
            text: tr.name,
            style: const TextStyle(
              fontSize: 8.0,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];

    terrNameStroke = [
      for (final tr in terrs)
        TextPainter(
          text: TextSpan(
            text: tr.name,
            style: TextStyle(
              fontSize: 8.0,
              fontWeight: FontWeight.w600,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xFF0C1626),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];

    lightPaintsNormal = [for (final tr in terrs) _makeLightPaint(tr.bounds, 1.0)];
    lightPaintsDim = [for (final tr in terrs) _makeLightPaint(tr.bounds, 0.22)];

    contStroke = [
      for (final c in md.continents)
        TextPainter(
          text: TextSpan(
            text: '${c.name} +${c.bonus}',
            style: AppText.serif(
              size: 17,
              letterSpacing: 0.06,
              color: _oceanColor,
            ).copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 5.0
                ..strokeJoin = StrokeJoin.round
                ..color = _oceanColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    contFillNormal = [
      for (final c in md.continents)
        TextPainter(
          text: TextSpan(
            text: '${c.name} +${c.bonus}',
            style: AppText.serif(
              size: 17,
              letterSpacing: 0.06,
              color: c.color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];

    compassPicture = _buildCompassPicture();
  }

  static const Color _oceanColor = AppColors.sea;
  final MapData md;
  late final List<int> territoryOrder;
  late final List<TextPainter> terrNameFill;
  late final List<TextPainter> terrNameStroke;
  late final List<Paint> lightPaintsNormal;
  late final List<Paint> lightPaintsDim;
  late final List<TextPainter> contStroke;
  late final List<TextPainter> contFillNormal;
  late final ui.Picture compassPicture;

  final Map<String, Color> dimColorCache = {};
  final Map<int, TextPainter> armyNumWhite = {};
  final Map<int, TextPainter> armyNumRad = {};
  final Map<int, Path> trenchDashPaths = {};
  final Map<int, Path> borderDashPaths = {};
  final Map<int, List<_LabelLayoutEntry>> labelLayoutCache = {};

  static Paint _makeLightPaint(Rect b, double alpha) => Paint()
    ..shader = ui.Gradient.linear(
      b.topLeft,
      b.bottomRight,
      [
        Colors.white.withValues(alpha: 0.24 * alpha),
        Colors.white.withValues(alpha: 0),
        Colors.black.withValues(alpha: 0),
        Colors.black.withValues(alpha: 0.30 * alpha),
      ],
      const [0.0, 0.42, 0.58, 1.0],
    );

  static ui.Picture _buildCompassPicture() {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const col = Color(0x339FC3FF);
    final circlePaint = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset.zero, 30, circlePaint);
    canvas.drawCircle(Offset.zero, 23, circlePaint);

    Path starRay(double len, double w) => Path()
      ..moveTo(0, 0)
      ..lineTo(w, -w)
      ..lineTo(0, -len)
      ..lineTo(-w, -w)
      ..close();

    final majorPaint = Paint()..color = col..style = PaintingStyle.fill;
    final minorPaint = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final majorPath = starRay(38, 5);
    final minorPath = starRay(22, 3.2);

    for (var k = 0; k < 8; k++) {
      canvas.save();
      canvas.rotate(k * pi / 4);
      canvas.drawPath(k.isOdd ? minorPath : majorPath, k.isOdd ? minorPaint : majorPaint);
      canvas.restore();
    }

    final nTp = TextPainter(
      text: TextSpan(
        text: 'N',
        style: AppText.serif(size: 11, color: col),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    nTp.paint(canvas, Offset(-nTp.width / 2, -42 - nTp.height / 2));
    return rec.endRecording();
  }

  TextPainter armyPainter(int armies, bool rad) {
    final map = rad ? armyNumRad : armyNumWhite;
    return map.putIfAbsent(armies, () {
      return TextPainter(
        text: TextSpan(
          text: '$armies',
          style: TextStyle(
            color: rad ? const Color(0xFFD8FF9A) : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  static Path _buildDashed(Path src, double dash, double gap, double phase) {
    final out = Path();
    final cycle = dash + gap;
    final offset = phase % cycle;
    for (final metric in src.computeMetrics()) {
      double dist = -offset;
      while (dist < metric.length) {
        final start = max(0.0, dist);
        final end = min(dist + dash, metric.length);
        if (end > start) {
          out.addPath(metric.extractPath(start, end), Offset.zero);
        }
        dist += cycle;
      }
    }
    return out;
  }

  Path trenchPathFor(int terrIdx) {
    return trenchDashPaths.putIfAbsent(
      terrIdx,
      () => _buildDashed(md.territories[terrIdx].path, 3, 3, 0),
    );
  }

  /// Cached quantized dashed territory border (8 discrete phases per cycle -> eliminates computeMetrics per frame).
  Path borderDashPathFor(int terrIdx, {required bool isMove, required int bucket}) {
    final key = (terrIdx << 4) | (isMove ? 8 : 0) | (bucket & 7);
    return borderDashPaths.putIfAbsent(key, () {
      final dash = isMove ? 4.0 : 6.0;
      final gap = isMove ? 5.0 : 4.0;
      final cycle = dash + gap;
      final phase = ((8 - (bucket & 7)) / 8.0) * cycle;
      return _buildDashed(md.territories[terrIdx].path, dash, gap, phase);
    });
  }

  void dispose() {
    compassPicture.dispose();
  }
}

class _ComputedSeaRoute {
  const _ComputedSeaRoute({required this.route, required this.paths});

  final SeaRouteGeo route;
  final List<Path> paths;
}

class _LabelLayoutEntry {
  const _LabelLayoutEntry({
    required this.terrIndex,
    required this.offset,
    required this.align,
    required this.tp,
  });

  final int terrIndex;
  final Offset offset;
  final TextAlign align;
  final TextPainter tp;
}

class _WorldMapPainter extends CustomPainter {
  _WorldMapPainter({
    super.repaint,
    required this.ctrl,
    required this.cache,
    required this.seaRoutes,
    required this.shakeCtrl,
    required this.bigShake,
    required this.animNotifier,
    required this.camX,
    required this.camY,
    required this.camZ,
    required this.hoverTerr,
  });

  final AppController ctrl;
  final _MapPaintCache cache;
  final List<_ComputedSeaRoute> seaRoutes;
  final Animation<double> shakeCtrl;
  final bool Function() bigShake;
  final _MapAnimNotifier animNotifier;
  final double camX;
  final double camY;
  final double camZ;
  final int? hoverTerr;
  int _nowMs = 0;
  int get nowMs => _nowMs;

  static const Color _oceanColor = AppColors.sea;

  // Exact TREFOIL geometry from main.js
  static final Path _trefoilPath = _buildTrefoil();
  static Path _buildTrefoil() {
    final p = Path();
    Offset pt(double r, double deg) {
      final rad = deg * pi / 180.0;
      return Offset(r * cos(rad), r * sin(rad));
    }

    for (final a in const [-90.0, 30.0, 150.0]) {
      final p0 = pt(2.4, a - 30);
      final p1 = pt(7.6, a - 30);
      final p2 = pt(7.6, a + 30);
      final p3 = pt(2.4, a + 30);
      p.moveTo(p0.dx, p0.dy);
      p.lineTo(p1.dx, p1.dy);
      p.arcToPoint(p2, radius: const Radius.circular(7.6));
      p.lineTo(p3.dx, p3.dy);
      p.arcToPoint(p0, radius: const Radius.circular(2.4), clockwise: false);
      p.close();
    }
    return p;
  }

  double _unitPx(double units, double maxPx) => min(units, maxPx / camZ);

  @override
  void paint(Canvas canvas, Size size) {
    _nowMs = DateTime.now().millisecondsSinceEpoch;
    final md = ctrl.mapData;
    final v = ctrl.view;

    var shakeDx = 0.0;
    var shakeDy = 0.0;
    if (shakeCtrl.value > 0 && shakeCtrl.value < 1) {
      final k = 1 - shakeCtrl.value;
      final amp = (bigShake() ? 9.0 : 4.0) * k;
      shakeDx = sin(shakeCtrl.value * 44) * amp;
      shakeDy = cos(shakeCtrl.value * 37) * amp;
    }

    // 1. Ocean background (--sea #0f1c2e so auracut & moat blend seamlessly)
    canvas.drawRect(Offset.zero & size, Paint()..color = _oceanColor);

    canvas.save();
    canvas.translate(shakeDx, shakeDy);
    canvas.scale(camZ, camZ);
    canvas.translate(-camX, -camY);

    // 2. Graticule lines every 71 units
    final gratPaint = Paint()
      ..color = const Color(0xFF9FC3FF).withValues(alpha: 0.055)
      ..strokeWidth = 1.0 / camZ;
    for (double x = -710; x <= md.width + 710; x += 71) {
      canvas.drawLine(Offset(x, -500), Offset(x, md.height + 500), gratPaint);
    }
    for (double y = -497; y <= md.height + 500; y += 71) {
      canvas.drawLine(Offset(-720, y), Offset(md.width + 720, y), gratPaint);
    }

    // 3. Compass Rose at (985, 590) in Indian Ocean (cached Picture)
    canvas.save();
    canvas.translate(985, 590);
    canvas.drawPicture(cache.compassPicture);
    canvas.restore();

    // Compute dynamic contour widths matching scaleMarks()
    final cut = _unitPx(8.0, 9.0);
    final aura = cut + _unitPx(5.5, 6.0);
    final moat = _unitPx(3.2, 4.0);
    final depth = _unitPx(3.0, 3.5);

    // 4. Continent Aura + Auracut (under land, creating offset colored coastline ring)
    for (final c in md.continents) {
      canvas.drawPath(
        c.path,
        Paint()
          ..color = c.color
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = aura,
      );
      canvas.drawPath(
        c.path,
        Paint()
          ..color = _oceanColor
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = cut,
      );
    }

    // 5. 3D Board thickness depth offset downward
    canvas.save();
    canvas.translate(0, depth);
    for (final c in md.continents) {
      canvas.drawPath(
        c.path,
        Paint()
          ..color = const Color(0xFF050A13)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        c.path,
        Paint()
          ..color = const Color(0xFF050A13)
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.0,
      );
    }
    canvas.restore();

    // Determine selection / target / dimming state
    final can = ctrl.canPlayNow();
    final targets = can ? ctrl.validTargets() : const <int>{};
    final terrs = v?['terr'] as List<dynamic>?;
    final colors = ctrl.engine.constants.colors;
    final ev = ctrl.eval;
    final pk = (!can && ctrl.peekState != null && v != null && ctrl.peekState!.n == v['n'])
        ? ctrl.peekState
        : null;
    final spot = (!can && ctrl.spotlightSet != null && ctrl.spotlightUntilMs > nowMs)
        ? ctrl.spotlightSet
        : null;
    final fogTerr = (v != null && v['fog'] != null && v['phase'] == 'play')
        ? (v['fog']['t'] as num).toInt()
        : null;
    final bonusOnly = can &&
        v != null &&
        v['step'] == 'reinforce' &&
        (v['pool']?['free'] as num? ?? 0) == 0 &&
        !(ev?.mustTrade ?? false);
    final poolCont = (v?['pool']?['cont'] as Map<String, dynamic>?) ?? const {};
    final turnIdx = (v?['turn'] as num?)?.toInt() ?? 0;

    // 6. Sea routes (drawn before highlight passes, matches svg layer order)
    for (final sr in seaRoutes) {
      final lit = can &&
          ctrl.sel != null &&
          ((sr.route.a == ctrl.sel && targets.contains(sr.route.b)) ||
              (sr.route.b == ctrl.sel && targets.contains(sr.route.a)));
      _drawSeaRoute(canvas, sr, lit);
    }

    // 7. Territories: fill + directional #landlight shading + default 1px border
    final frontOrder = <int>[];
    for (var i = 0; i < md.territories.length; i++) {
      final isSel = i == ctrl.sel ||
          (can && ctrl.trenchMode && i == ctrl.pendingTrenchTerr) ||
          (can && ctrl.airliftMode && i == ctrl.airliftFrom) ||
          (pk != null && i == pk.sel);
      final isTgt = (can && ctrl.trenchMode && terrs != null &&
              (terrs[i]['o'] as num).toInt() == turnIdx &&
              !(ev?.hq?.trenchBlocks.containsKey(i) ?? false)) ||
          (can && ctrl.airliftMode && ctrl.airliftFrom != null && terrs != null &&
              (ctrl.airliftTo != null
                  ? i == ctrl.airliftTo
                  : ((terrs[i]['o'] as num).toInt() == turnIdx && i != ctrl.airliftFrom))) ||
          (can && !ctrl.trenchMode && !ctrl.airliftMode &&
              (ctrl.target != null ? i == ctrl.target : targets.contains(i))) ||
          (pk != null && i == pk.target);
      final isSpot = spot != null && spot.contains(i);
      if (isSel || isTgt || isSpot || i == hoverTerr) {
        frontOrder.add(i);
      }

      _drawTerritoryFillAndLight(
        canvas,
        i,
        v,
        terrs,
        colors,
        ev,
        can,
        targets,
        bonusOnly,
        poolCont,
        turnIdx,
        pk,
        spot,
      );
    }

    // 8. Continent moat separators over territory borders
    for (final c in md.continents) {
      canvas.drawPath(
        c.path,
        Paint()
          ..color = _oceanColor
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = moat,
      );
    }

    // 9. Re-draw highlighted territory strokes on top so borders are never clipped
    final isOccupyOrMove = (v != null && (v['occupy'] != null || v['step'] == 'move')) ||
        (can && (ctrl.trenchMode || ctrl.airliftMode));
    for (final i in frontOrder) {
      _drawTerritoryHighlightBorder(
        canvas,
        i,
        can,
        terrs,
        turnIdx,
        ev,
        targets,
        pk,
        spot,
        isOccupyOrMove: isOccupyOrMove,
      );
    }

    // 9b. When only continent bonus armies remain, highlight those continents with a gentle border glow
    if (bonusOnly) {
      final pulse = 0.5 + 0.5 * sin(nowMs * 0.004);
      for (var ci = 0; ci < md.continents.length; ci++) {
        final bonusCount = (poolCont['$ci'] as num?)?.toInt() ?? 0;
        if (bonusCount > 0) {
          final c = md.continents[ci];
          canvas.drawPath(
            c.path,
            Paint()
              ..color = c.color.withValues(alpha: 0.20 + 0.16 * pulse)
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = 5.5 / camZ,
          );
          canvas.drawPath(
            c.path,
            Paint()
              ..color = Color.lerp(c.color, Colors.white, 0.35 + 0.25 * pulse)!
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = 1.8 / camZ,
          );
        }
      }
    }

    // 10. Smoke simulation overlay (above land/shade, below markers/labels)
    if (ctrl.smoke.active) {
      _drawSmokeOverlay(canvas);
    }

    // 11. Radioactive perimeter hazard animation (hz-line & hz-scan)
    if (fogTerr != null && fogTerr >= 0 && fogTerr < md.territories.length && ctrl.incomingTerr != fogTerr) {
      _drawHazardOutline(canvas, md.territories[fogTerr].path);
    }

    // 11b. Trincheiras do Quartel: contorno tracejado dourado, parado (cached)
    if (v != null && v['phase'] == 'play') {
      final trenchPaint = Paint()
        ..color = const Color(0xF0F3CD78)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2 / camZ;
      for (final x in v['trenches'] as List<dynamic>? ?? const []) {
        final t = ((x as Map<String, dynamic>)['t'] as num).toInt();
        if (t < 0 || t >= md.territories.length) continue;
        canvas.drawPath(cache.trenchPathFor(t), trenchPaint);
      }
    }

    // 12. Continent names (.cname) + Mandatory continent bonus badge
    for (var ci = 0; ci < md.continents.length; ci++) {
      final bonusCount = (poolCont['$ci'] as num?)?.toInt() ?? 0;
      _drawContinentLabel(canvas, ci, mandatoryBonus: bonusOnly ? bonusCount : 0);
    }

    // 13. Aim lines (.aim & .aim.one) + Occupy / Move / Airlift transfer line
    if (can && ctrl.airliftMode && ctrl.airliftFrom != null && ctrl.airliftTo != null) {
      _drawAimLine(
        canvas,
        ctrl.airliftFrom!,
        ctrl.airliftTo!,
        isChosen: true,
        isMove: true,
        allowLong: true,
        color: AppColors.gold,
      );
    } else if (can && v != null && v['occupy'] != null) {
      final occ = v['occupy'] as Map<String, dynamic>;
      final from = (occ['from'] as num).toInt();
      final to = (occ['to'] as num).toInt();
      _drawAimLine(
        canvas,
        from,
        to,
        isChosen: true,
        isMove: true,
        color: AppColors.gold,
      );
    } else if (can && !ctrl.trenchMode && !ctrl.airliftMode && ctrl.sel != null && v != null && v['step'] != 'reinforce' && v['occupy'] == null) {
      final from = ctrl.sel!;
      final dests = ctrl.target != null ? [ctrl.target!] : targets.toList();
      final isMoveStep = v['step'] == 'move';
      for (final j in dests) {
        _drawAimLine(
          canvas,
          from,
          j,
          isChosen: ctrl.target != null,
          isMove: isMoveStep,
          color: isMoveStep ? AppColors.gold : Colors.white,
        );
      }
    } else if (pk != null && pk.target != null && v != null) {
      final players = v['players'] as List<dynamic>;
      final col = parseHexColor(colors[(players[turnIdx]['color'] as num).toInt()].hex);
      _drawAimLine(canvas, pk.sel, pk.target!, isChosen: true, color: col);
    }

    // 14. Army badges (.bshadow, .badge, .num, .trefoil) + Collision-free Territory Names
    if (terrs != null && v != null) {
      _drawMarkersAndLabels(canvas, v, terrs, fogTerr);
    }

    // 15. Combat & Nuke FX
    _drawFx(canvas);
    _drawFloats(canvas);

    canvas.restore();
  }

  void _drawContinentLabel(Canvas canvas, int ci, {int mandatoryBonus = 0}) {
    final c = ctrl.mapData.continents[ci];
    final strokeTp = cache.contStroke[ci];
    final fillNormal = cache.contFillNormal[ci];
    final pos = Offset(c.x - fillNormal.width / 2, c.y - fillNormal.height * 0.72);
    strokeTp.paint(canvas, pos);

    final pulse = mandatoryBonus > 0 ? (0.5 + 0.5 * sin(nowMs * 0.005)) : 0.0;
    if (mandatoryBonus <= 0) {
      fillNormal.paint(canvas, pos);
      return;
    }

    final labelColor = Color.lerp(c.color, const Color(0xFFFFF3D1), 0.45 + 0.35 * pulse)!;
    final fillTp = TextPainter(
      text: TextSpan(
        text: '${c.name} +${c.bonus}',
        style: AppText.serif(
          size: 17,
          letterSpacing: 0.06,
          color: labelColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    fillTp.paint(canvas, pos);

    final pillTp = TextPainter(
      text: TextSpan(
        text: 'BÔNUS RESTANTE: +$mandatoryBonus',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: AppColors.gold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pw = pillTp.width + 14;
    final ph = pillTp.height + 5;
    // Place above the continent name (in open ocean) so it never collides with territory badges to the right
    final center = Offset(c.x, pos.dy - ph / 2 - 3);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: pw, height: ph),
      const Radius.circular(999),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xE60D1B30));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = AppColors.gold.withValues(alpha: 0.55 + 0.35 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    pillTp.paint(
      canvas,
      Offset(center.dx - pillTp.width / 2, center.dy - pillTp.height / 2),
    );
  }

  void _drawSeaRoute(Canvas canvas, _ComputedSeaRoute sr, bool lit) {
    final casePaint = Paint()
      ..color = const Color(0xFF081120)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.5 / camZ;
    for (final p in sr.paths) {
      canvas.drawPath(p, casePaint);
    }

    final routePaint = Paint()
      ..color = lit ? Colors.white : const Color(0xFFCFE3FF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (lit ? 3.0 : 1.8) / camZ;

    final dir = (lit && ctrl.sel == sr.route.b) ? 1.0 : -1.0;
    final phase = lit ? (11.0 + dir * ((nowMs / 800.0 * 20.0) % 11.0)) % 11.0 : 0.0;
    for (final p in sr.paths) {
      _drawDashedPath(
        canvas,
        p,
        routePaint,
        dash: lit ? 6.0 : 1.5,
        gap: lit ? 5.0 : 5.5,
        phase: phase,
      );
    }

    final r = sr.route;
    if (r.wrap) {
      final chevPaint = Paint()
        ..color = const Color(0xFFCFE3FF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.0 / camZ;
      final lx = -_mapPad + 8;
      final rx = ctrl.mapData.width + _mapPad - 8;
      final chevrons = Path()
        ..moveTo(lx, r.y1 - 5)
        ..lineTo(lx - 6, r.y1)
        ..lineTo(lx, r.y1 + 5)
        ..moveTo(lx + 8, r.y1 - 5)
        ..lineTo(lx + 2, r.y1)
        ..lineTo(lx + 8, r.y1 + 5)
        ..moveTo(rx, r.y2 - 5)
        ..lineTo(rx + 6, r.y2)
        ..lineTo(rx, r.y2 + 5)
        ..moveTo(rx - 8, r.y2 - 5)
        ..lineTo(rx - 2, r.y2)
        ..lineTo(rx - 8, r.y2 + 5);
      canvas.drawPath(chevrons, chevPaint);
    }

    // Port circles
    final portFill = Paint()..color = const Color(0xFFCFE3FF);
    final portStroke = Paint()
      ..color = const Color(0xFF081120)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final pt in [Offset(r.x1, r.y1), Offset(r.x2, r.y2)]) {
      canvas.drawCircle(pt, 3.1, portFill);
      canvas.drawCircle(pt, 3.1, portStroke);
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 6,
    double gap = 5,
    double phase = 0,
  }) {
    final cycle = dash + gap;
    final offset = phase % cycle;
    for (final metric in path.computeMetrics()) {
      double dist = -offset;
      while (dist < metric.length) {
        final start = max(0.0, dist);
        final end = min(dist + dash, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        dist += cycle;
      }
    }
  }

  Color _dimColor(String hex, Color base) {
    return cache.dimColorCache.putIfAbsent(hex, () {
      // Exact math from main.js dimColor(hex)
      const b = 0.36;
      const s = 0.45;
      final r = ((base.r * 255.0)) * b;
      final g = ((base.g * 255.0)) * b;
      final bl = ((base.b * 255.0)) * b;
      int ch(double x) => x.round().clamp(0, 255);
      return Color.fromARGB(
        255,
        ch((0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * bl),
        ch((0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * bl),
        ch((0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * bl),
      );
    });
  }

  void _drawTerritoryFillAndLight(
    Canvas canvas,
    int i,
    Map<String, dynamic>? v,
    List<dynamic>? terrs,
    List<dynamic> colors,
    dynamic ev,
    bool can,
    Set<int> targets,
    bool bonusOnly,
    Map<String, dynamic> poolCont,
    int turnIdx,
    ({int sel, int? target, int n})? pk,
    Set<int>? spot,
  ) {
    final tr = ctrl.mapData.territories[i];
    final hex = terrs != null
        ? colors[(v!['players'][(terrs[i]['o'] as num).toInt()]['color'] as num).toInt()].hex
            as String
        : ctrl.mapData.continents[tr.continent].colorHex;
    final baseColor = parseHexColor(hex);

    var dimmed = false;
    if (v != null && terrs != null) {
      if (can) {
        if (ctrl.nukeMode) {
          dimmed = ev?.nukeTargetBlocks.containsKey(i) ?? false;
        } else if (ctrl.trenchMode) {
          dimmed = (terrs[i]['o'] as num).toInt() != turnIdx ||
              (ev?.hq?.trenchBlocks.containsKey(i) ?? false);
        } else if (ctrl.airliftMode) {
          final own = (terrs[i]['o'] as num).toInt() == turnIdx;
          if (ctrl.airliftFrom == null) {
            dimmed = !own ||
                (ev?.hq?.airliftBlocks.containsKey(i) ?? false) ||
                (terrs[i]['a'] as num).toInt() < 2;
          } else {
            dimmed = !own;
          }
        } else if (ctrl.sel != null && v['step'] != 'reinforce') {
          dimmed = i != ctrl.sel && !targets.contains(i);
        } else if (bonusOnly) {
          final bonus = (poolCont['${tr.continent}'] as num?)?.toInt() ?? 0;
          dimmed = !((terrs[i]['o'] as num).toInt() == turnIdx && bonus > 0);
        }
      } else {
        if (v['phase'] == 'over') {
          dimmed = (terrs[i]['o'] as num).toInt() != (v['winner'] as num?)?.toInt();
        } else if (pk != null) {
          dimmed = i != pk.sel && i != pk.target;
        } else if (spot != null) {
          dimmed = !spot.contains(i);
        }
      }
    }

    final isSel = i == ctrl.sel ||
        (can && ctrl.trenchMode && i == ctrl.pendingTrenchTerr) ||
        (can && ctrl.airliftMode && i == ctrl.airliftFrom) ||
        (pk != null && i == pk.sel);
    final isLit = spot != null && spot.contains(i);
    var fillColor = dimmed ? _dimColor(hex, baseColor) : baseColor;
    if (isSel || isLit || (i == hoverTerr && !dimmed)) {
      fillColor = Color.lerp(fillColor, Colors.white, 0.16)!;
    }

    canvas.drawPath(tr.path, Paint()..color = fillColor);

    // #landlight diagonal lighting gradient per territory bounding box (pre-cached)
    canvas.drawPath(
      tr.path,
      dimmed ? cache.lightPaintsDim[i] : cache.lightPaintsNormal[i],
    );

    // Default 1px territory coast/border
    canvas.drawPath(
      tr.path,
      Paint()
        ..color = const Color(0xFF081120)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.0 / camZ,
    );
  }

  void _drawTerritoryHighlightBorder(
    Canvas canvas,
    int i,
    bool can,
    List<dynamic>? terrs,
    int turnIdx,
    dynamic ev,
    Set<int> targets,
    ({int sel, int? target, int n})? pk,
    Set<int>? spot, {
    bool isOccupyOrMove = false,
  }) {
    final tr = ctrl.mapData.territories[i];
    final isSel = i == ctrl.sel ||
        (can && ctrl.trenchMode && i == ctrl.pendingTrenchTerr) ||
        (can && ctrl.airliftMode && i == ctrl.airliftFrom) ||
        (pk != null && i == pk.sel);
    final isTgt = (can && ctrl.trenchMode && terrs != null &&
            (terrs[i]['o'] as num).toInt() == turnIdx &&
            !(ev?.hq?.trenchBlocks.containsKey(i) ?? false)) ||
        (can && ctrl.airliftMode && ctrl.airliftFrom != null && terrs != null &&
            (ctrl.airliftTo != null
                ? i == ctrl.airliftTo
                : ((terrs[i]['o'] as num).toInt() == turnIdx && i != ctrl.airliftFrom))) ||
        (can && !ctrl.trenchMode && !ctrl.airliftMode &&
            (ctrl.target != null ? i == ctrl.target : targets.contains(i))) ||
        (pk != null && i == pk.target);
    final isSpot = spot != null && spot.contains(i);

    if (isSel || isSpot) {
      final glowColor = (ctrl.trenchMode || ctrl.airliftMode)
          ? AppColors.gold.withValues(alpha: 0.45)
          : const Color(0x55FFFFFF);
      canvas.drawPath(
        tr.path,
        Paint()
          ..color = glowColor
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 6.0 / camZ,
      );
      canvas.drawPath(
        tr.path,
        Paint()
          ..color = (ctrl.trenchMode || ctrl.airliftMode) ? AppColors.gold : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3.2 / camZ,
      );
    } else if (isTgt) {
      final tgtColor = isOccupyOrMove ? AppColors.gold : Colors.white;
      final bucket = ((nowMs / 1000.0 * 2.0 * 8.0).floor()) & 7;
      canvas.drawPath(
        cache.borderDashPathFor(i, isMove: isOccupyOrMove, bucket: bucket),
        Paint()
          ..color = tgtColor
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.6 / camZ,
      );
    } else if (i == hoverTerr) {
      canvas.drawPath(
        tr.path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.8 / camZ,
      );
    }
  }

  void _drawHazardOutline(Canvas canvas, Path trPath) {
    final dashPhase = (nowMs / 12000.0 * 90.0) % 9.0;
    _drawDashedPath(
      canvas,
      trPath,
      Paint()
        ..color = const Color(0xD8B4FF86)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.6 / camZ,
      dash: 5,
      gap: 4,
      phase: dashPhase,
    );
    // Bright scanning spark along contour
    for (final metric in trPath.computeMetrics()) {
      final scanLen = metric.length * 0.08;
      final offset = ((nowMs % 5000) / 5000.0) * metric.length;
      final end = offset + scanLen;
      if (end <= metric.length) {
        canvas.drawPath(
          metric.extractPath(offset, end),
          Paint()
            ..color = const Color(0xFFF1FFE6)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.4 / camZ,
        );
      }
    }
  }

  void _drawStraightDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dash,
    required double gap,
    required double phase,
  }) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len <= 0.1) return;
    final ux = dx / len;
    final uy = dy / len;
    final cycle = dash + gap;
    var dist = -(phase % cycle);
    while (dist < len) {
      final s = max(0.0, dist);
      final e = min(dist + dash, len);
      if (e > s) {
        canvas.drawLine(
          Offset(a.dx + ux * s, a.dy + uy * s),
          Offset(a.dx + ux * e, a.dy + uy * e),
          paint,
        );
      }
      dist += cycle;
    }
  }

  void _drawAimLine(
    Canvas canvas,
    int a,
    int b, {
    required bool isChosen,
    required Color color,
    bool isMove = false,
    bool allowLong = false,
  }) {
    final ta = ctrl.mapData.territories[a];
    final tb = ctrl.mapData.territories[b];
    if (!allowLong && (ta.x - tb.x).abs() > ctrl.mapData.width / 2) return;

    final dash = isMove ? 3.5 : 7.0;
    final gap = isMove ? 6.5 : 6.0;
    final cycle = dash + gap;
    // Negative phase shift advances dashes from A -> B
    final phase = (cycle - ((nowMs / 750.0 * 20.0) % cycle)) % cycle;
    final pa = Offset(ta.x, ta.y);
    final pb = Offset(tb.x, tb.y);
    _drawStraightDashedLine(
      canvas,
      pa,
      pb,
      Paint()
        ..color = const Color(0xAA000000)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ((isChosen ? 4.0 : 2.5) + 2.2) / camZ,
      dash: dash,
      gap: gap,
      phase: phase,
    );
    _drawStraightDashedLine(
      canvas,
      pa,
      pb,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (isChosen ? 4.0 : 2.5) / camZ,
      dash: dash,
      gap: gap,
      phase: phase,
    );

    // Draw directional chevron(s) pointing from A to B when a destination is chosen or during troop movement
    if (isChosen || isMove) {
      final dx = tb.x - ta.x;
      final dy = tb.y - ta.y;
      final len = sqrt(dx * dx + dy * dy);
      if (len > 36) {
        final angle = atan2(dy, dx);
        final travel = ((nowMs % 1100) / 1100.0);
        final tPos = isMove ? (0.28 + 0.44 * travel) : 0.54;
        final cx = ta.x + dx * tPos;
        final cy = ta.y + dy * tPos;
        final sz = (isMove ? 7.5 : 6.5) / camZ;

        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(angle);
        final chev = Path()
          ..moveTo(-sz * 0.8, -sz * 0.75)
          ..lineTo(sz * 0.5, 0)
          ..lineTo(-sz * 0.8, sz * 0.75);
        canvas.drawPath(
          chev,
          Paint()
            ..color = const Color(0xBB000000)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 4.6 / camZ,
        );
        canvas.drawPath(
          chev,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2.6 / camZ,
        );
        canvas.restore();
      }
    }
  }

  void _drawSmokeOverlay(Canvas canvas) {
    final sim = ctrl.smoke;
    final fade = sim.ending >= 0 ? (1 - (sim.time - sim.ending) / 2.6).clamp(0.0, 1.0) : 1.0;
    final ox = sim.ox;
    final oy = sim.oy;
    final sz = sim.size;
    final k = sz / sim.gridN;
    double gxToMap(double gx) => ox + (gx - 0.5) * k;

    final gzx = gxToMap(sim.gx);
    final gzy = gxToMap(sim.gy);
    final reachMap = sim.reach * k;
    final heat = sim.det >= 0 ? (1 - (sim.age - 0.4) / 5.0).clamp(0.0, 1.0) : 0.0;

    final sg = Paint()
      ..shader = ui.Gradient.radial(
        Offset(gzx, gzy),
        reachMap * 0.95,
        [
          Color.fromRGBO(4, 7, 5, 0.62 * fade),
          Color.fromRGBO(6, 12, 8, 0.34 * fade),
          const Color.fromRGBO(6, 12, 8, 0),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(Offset(gzx, gzy), reachMap, sg);

    final cp = 0.5 + 0.5 * sin(sim.time * 3.1);
    final crackR = (110 + 145 * heat).round();
    final crackG = (255 - 95 * heat).round();
    final crackB = (90 - 50 * heat).round();
    for (final pass in const [(4.0, 0.16), (1.3, 0.85)]) {
      final cpPaint = Paint()
        ..color = Color.fromRGBO(
          crackR,
          crackG,
          crackB,
          pass.$2 * fade * (0.45 + 0.3 * cp + 0.25 * heat),
        )
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = pass.$1;
      for (final pts in sim.cracks) {
        if (pts.isEmpty) continue;
        final path = Path()..moveTo(gxToMap(pts[0].dx), gxToMap(pts[0].dy));
        for (var i = 1; i < pts.length; i++) {
          path.lineTo(gxToMap(pts[i].dx), gxToMap(pts[i].dy));
        }
        canvas.drawPath(path, cpPaint);
      }
    }

    final img = sim.smokeImage;
    if (img != null) {
      final dst = Rect.fromLTWH(ox, oy, sz, sz);
      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.high
          ..color = Colors.white.withValues(alpha: fade),
      );
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: 0.26 * fade),
      );
    }

    for (final m in sim.motes) {
      final e = sin(pi * m.l / m.ml);
      final a = e * (0.45 + 0.55 * sin(sim.time * 7 + m.ph)) * fade;
      if (a <= 0.02) continue;
      canvas.drawCircle(
        Offset(gxToMap(m.x), gxToMap(m.y)),
        m.s * 2.2,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Color.fromRGBO(140, 255, 130, a.clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }

    for (final q in sim.sparks) {
      final h = (1 - q.l / q.ml).clamp(0.0, 1.0);
      final sx = gxToMap(q.x);
      final sy = gxToMap(q.y);
      if (q.emb) {
        final col = h > 0.35 ? const Color(0xFFFF9632) : const Color(0xFF78FF6E);
        canvas.drawCircle(
          Offset(sx, sy),
          1.4 + 1.6 * h,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = col.withValues(alpha: (h * 1.4).clamp(0.0, 1.0)),
        );
      } else {
        final col = h > 0.7
            ? const Color(0xFFFFF6D8)
            : h > 0.42
                ? const Color(0xFFFFC24D)
                : h > 0.18
                    ? const Color(0xFFFF6D1F)
                    : const Color(0xFFB3260E);
        canvas.drawLine(
          Offset(gxToMap(q.px), gxToMap(q.py)),
          Offset(sx, sy),
          Paint()
            ..blendMode = BlendMode.plus
            ..color = col.withValues(alpha: (h * 1.6).clamp(0.0, 1.0))
            ..strokeWidth = 0.7 + 1.3 * h
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    for (final arc in sim.arcs) {
      if (arc.pts.isEmpty) continue;
      final f = ((1 - arc.l / arc.ml) * 0.9 * fade).clamp(0.0, 1.0);
      final path = Path()..moveTo(gxToMap(arc.pts[0].dx), gxToMap(arc.pts[0].dy));
      for (var i = 1; i < arc.pts.length; i++) {
        path.lineTo(gxToMap(arc.pts[i].dx), gxToMap(arc.pts[i].dy));
      }
      for (final pass in const [(4.5, 0.25, Color(0xFF78FF78)), (1.1, 1.0, Color(0xFFF0FFEB))]) {
        canvas.drawPath(
          path,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = pass.$3.withValues(alpha: f * pass.$2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = pass.$1,
        );
      }
    }

    if (sim.det >= 0) {
      final t = sim.age;
      if (t < 0.95) {
        final rr = (4 + 62 * t) * (sim.gridN / 72) * k;
        final q = 1 - t / 0.95;
        canvas.drawCircle(
          Offset(gzx, gzy),
          rr,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 + 10 * q
            ..color = const Color(0xFFD9FFC4).withValues(alpha: 0.5 * q),
        );
        canvas.drawCircle(
          Offset(gzx, gzy),
          rr + 2 + 5 * q,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = Colors.white.withValues(alpha: 0.9 * q),
        );
      }
      if (t < 0.5) {
        final q = 1 - t / 0.5;
        final rr = sz * (0.08 + 0.55 * t);
        canvas.drawCircle(
          Offset(gzx, gzy),
          rr,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(
              Offset(gzx, gzy),
              rr,
              [
                Colors.white.withValues(alpha: q * q),
                const Color(0xFFFFF4C8).withValues(alpha: 0.8 * q * q),
                const Color(0x00FFC878),
              ],
              const [0, 0.3, 1],
            ),
        );
      }
    }
  }

  void _drawFx(Canvas canvas) {
    final terrs = ctrl.mapData.territories;

    for (final p in ctrl.pulses) {
      final t = ((nowMs - p.startMs) / p.durMs).clamp(0.0, 1.0);
      final tr = terrs[p.terr];
      canvas.drawCircle(
        Offset(tr.x, tr.y),
        13 * (0.6 + 2.8 * t),
        Paint()
          ..color = p.color.withValues(alpha: 1 - t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - t),
      );
    }

    for (final a in ctrl.arrows) {
      final t = ((nowMs - a.startMs) / a.durMs).clamp(0.0, 1.0);
      final ta = terrs[a.from];
      final tb = terrs[a.to];
      final fade = t < 0.15 ? t / 0.15 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
      if ((ta.x - tb.x).abs() < ctrl.mapData.width / 2) {
        final p = Path()
          ..moveTo(ta.x, ta.y)
          ..lineTo(tb.x, tb.y);
        canvas.drawPath(
          p,
          Paint()
            ..color = a.color.withValues(alpha: 0.55 * fade)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 5.0,
        );
        _drawDashedPath(
          canvas,
          p,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9 * fade)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.5 / camZ,
          dash: 7,
          gap: 7,
          phase: (nowMs / 450.0 * 14.0) % 14.0,
        );
      }
      canvas.drawCircle(Offset(tb.x, tb.y), 7, Paint()..color = a.color.withValues(alpha: fade));
      canvas.drawCircle(
        Offset(tb.x, tb.y),
        7,
        Paint()
          ..color = Colors.white.withValues(alpha: fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    for (final s in ctrl.strikes) {
      final elapsed = nowMs - s.startMs;
      final ta = terrs[s.from];
      final tb = terrs[s.to];
      final far = (ta.x - tb.x).abs() > ctrl.mapData.width / 2;

      // Tracers 0..380ms
      if (!far && elapsed <= 380) {
        for (var k = 0; k < 3; k++) {
          final tk = ((elapsed - k * 75) / 300.0).clamp(0.0, 1.0);
          if (tk <= 0 || tk >= 1) continue;
          final curPos = Offset.lerp(Offset(ta.x, ta.y), Offset(tb.x, tb.y), tk)!;
          final tailPos = Offset.lerp(Offset(ta.x, ta.y), Offset(tb.x, tb.y), max(0.0, tk - 0.12))!;
          canvas.drawLine(
            tailPos,
            curPos,
            Paint()
              ..color = s.color
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 3.2 / camZ,
          );
          if (k == 0) {
            canvas.drawLine(
              tailPos,
              curPos,
              Paint()
                ..color = Colors.white
                ..strokeCap = StrokeCap.round
                ..strokeWidth = 1.4 / camZ,
            );
          }
        }
      }

      // Hit impact at target (starts immediately if wrap, else at 240ms)
      final hitAge = far ? elapsed : elapsed - 240;
      if (hitAge >= 0 && hitAge <= 650) {
        final ht = (hitAge / 500.0).clamp(0.0, 1.0);
        // White hit flash dot
        if (hitAge <= 380) {
          final ft = hitAge / 380.0;
          canvas.drawCircle(
            Offset(tb.x, tb.y),
            10 * (0.4 + 2.2 * ft),
            Paint()..color = Colors.white.withValues(alpha: 1 - ft),
          );
        }
        // 8 radial sparks
        for (var k = 0; k < 8; k++) {
          final ang = (k * 45 + ((s.to * 37) % 40)) * pi / 180.0;
          final r0 = 9.0 + 10.0 * ht;
          final r1 = r0 + 10.0 * (1 - ht * 0.4);
          canvas.drawLine(
            Offset(tb.x + sin(ang) * r0, tb.y - cos(ang) * r0),
            Offset(tb.x + sin(ang) * r1, tb.y - cos(ang) * r1),
            Paint()
              ..color = (k.isOdd ? Colors.white : s.color).withValues(alpha: 1 - ht)
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 2.2,
          );
        }
        // Expanding pulse
        canvas.drawCircle(
          Offset(tb.x, tb.y),
          13 * (0.6 + (s.won ? 2.8 : 1.8) * ht),
          Paint()
            ..color = s.color.withValues(alpha: 1 - ht)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (s.won ? 6 : 4) * (1 - ht),
        );
        // Territory white wash on conquest
        if (s.won) {
          final wt = (hitAge / 650.0).clamp(0.0, 1.0);
          canvas.drawPath(
            tb.path,
            Paint()..color = Colors.white.withValues(alpha: 0.85 * (1 - wt)),
          );
        }
      }
    }

    // Lock reticle & missile & impact shockwaves
    if (ctrl.incomingTerr != null && ctrl.missile != null) {
      final m = ctrl.missile!;
      final tr = terrs[ctrl.incomingTerr!];
      final totalMs = m.alarmMs + m.flightMs;
      final raw = ((nowMs - m.startMs) / totalMs).clamp(0.0, 1.0);
      final scale = 1.75 - 0.75 * raw;
      canvas.save();
      canvas.translate(tr.x, tr.y);
      canvas.rotate(raw * 3.14);
      canvas.scale(scale);
      final lp = Paint()
        ..color = const Color(0xFFFF5A3C).withValues(alpha: 0.4 + 0.6 * raw)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(Offset.zero, 28, lp);
      canvas.drawCircle(
        Offset.zero,
        18,
        Paint()
          ..color = const Color(0xFFFFD0C4).withValues(alpha: 0.4 + 0.6 * raw)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      for (var k = 0; k < 4; k++) {
        canvas.rotate(pi / 2);
        canvas.drawLine(const Offset(0, -44), const Offset(0, -30), lp);
      }
      canvas.restore();
    }

    final m = ctrl.missile;
    if (m != null) {
      final elapsed = nowMs - m.startMs;
      if (elapsed >= m.alarmMs && elapsed <= m.alarmMs + m.flightMs) {
        final raw = ((elapsed - m.alarmMs) / m.flightMs).clamp(0.0, 1.0);
        final k = raw * raw * (1.5 - 0.5 * raw);
        final dist = sqrt(pow(m.toX - m.fromX, 2) + pow(m.toY - m.fromY, 2));
        final cx = (m.fromX + m.toX) / 2;
        final cy = min(m.fromY, m.toY) - max(90.0, dist * 0.55);

        Offset evalBezier(double t) {
          final u = 1 - t;
          return Offset(
            u * u * m.fromX + 2 * u * t * cx + t * t * m.toX,
            u * u * m.fromY + 2 * u * t * cy + t * t * m.toY,
          );
        }

        for (double t = max(0.0, k - 0.35); t < k; t += 0.025) {
          final p = evalBezier(t);
          final fade = ((t - (k - 0.35)) / 0.35).clamp(0.0, 1.0);
          canvas.drawCircle(
            p,
            3.5 * (1.3 - fade * 0.3),
            Paint()..color = const Color(0xFFD7DDE6).withValues(alpha: 0.35 * fade),
          );
        }

        final pos = evalBezier(k);
        final next = evalBezier(min(1.0, k + 0.01));
        final ang = atan2(next.dy - pos.dy, next.dx - pos.dx);
        final sc = max(1.0, (10.5 / (12.5 * camZ)).clamp(1.0, 2.2));

        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(ang);
        canvas.scale(sc);
        canvas.drawPath(
          Path()
            ..moveTo(-9, 0)
            ..lineTo(-24, -3.2)
            ..lineTo(-31, 0)
            ..lineTo(-24, 3.2)
            ..close(),
          Paint()..color = const Color(0xFFFFCF5A),
        );
        canvas.drawPath(
          Path()
            ..moveTo(-10, -2.6)
            ..lineTo(8, -2.6)
            ..lineTo(13, 0)
            ..lineTo(8, 2.6)
            ..lineTo(-10, 2.6)
            ..close(),
          Paint()..color = const Color(0xFFE9EEF5),
        );
        canvas.drawPath(
          Path()
            ..moveTo(-10, -2.6)
            ..lineTo(-14, -6.5)
            ..lineTo(-6, -2.6)
            ..close()
            ..moveTo(-10, 2.6)
            ..lineTo(-14, 6.5)
            ..lineTo(-6, 2.6)
            ..close(),
          Paint()..color = const Color(0xFFC73A2E),
        );
        canvas.drawCircle(const Offset(10.5, 0), 1.6, Paint()..color = const Color(0xFFFF3B2F));
        canvas.restore();
      }
    }
  }

  void _drawMarkersAndLabels(
    Canvas canvas,
    Map<String, dynamic> v,
    List<dynamic> terrs,
    int? fogTerr,
  ) {
    final markK = (10.5 / (12.5 * camZ)).clamp(1.0, 2.2);
    final far = camZ < 0.5;
    final imp = ctrl.impactFx;
    final mapTerrs = ctrl.mapData.territories;

    // 1. Draw badges (.bshadow, .badge, .num, .trefoil)
    final positions = <Offset>[];
    for (var i = 0; i < mapTerrs.length; i++) {
      final tr = mapTerrs[i];
      var jx = 0.0;
      var jy = 0.0;
      if (imp != null) {
        final ageSec = (nowMs - imp.startMs) / 1000.0;
        if (ageSec >= 0 && ageSec < 1.2) {
          final dx = tr.x - imp.x;
          final dy = tr.y - imp.y;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist < 560 && i != imp.terr && dist > 1) {
            final delay = dist / 800.0;
            final localT = ageSec - delay;
            if (localT > 0 && localT < 0.7) {
              final amp = (20.0 / (1 + dist / 80.0)) * sin((localT / 0.7) * pi);
              jx = (dx / dist) * amp;
              jy = (dy / dist) * amp;
            }
          }
        }
      }
      final center = Offset(tr.x + jx, tr.y + jy);
      positions.add(center);

      final armies = (terrs[i]['a'] as num).toInt();
      final isRad = i == fogTerr && ctrl.incomingTerr != fogTerr;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(markK, markK);

      // .bshadow
      canvas.drawCircle(
        const Offset(0, 2),
        13.4,
        Paint()..color = const Color(0x7302060C),
      );
      // .badge dark navy disc with white ring
      canvas.drawCircle(
        Offset.zero,
        12.5,
        Paint()..color = isRad ? const Color(0xFF14260E) : const Color(0xFF0C1626),
      );
      canvas.drawCircle(
        Offset.zero,
        12.5,
        Paint()
          ..color = isRad ? const Color(0xFF8CFF4A) : const Color(0xDDFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );

      // .num (cached TextPainter)
      final numTp = cache.armyPainter(armies, isRad);
      numTp.paint(canvas, Offset(-numTp.width / 2, -numTp.height / 2 + 0.5));

      // .trefoil radiation badge at (13.5, -13.5)
      if (isRad) {
        canvas.save();
        canvas.translate(13.5, -13.5);
        canvas.drawCircle(Offset.zero, 7.6, Paint()..color = const Color(0xFFF4D21A));
        canvas.drawCircle(
          Offset.zero,
          7.6,
          Paint()
            ..color = const Color(0xFF141204)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        canvas.save();
        canvas.scale(0.72, 0.72);
        canvas.drawPath(_trefoilPath, Paint()..color = const Color(0xFF141204));
        canvas.restore();
        canvas.drawCircle(Offset.zero, 1.1, Paint()..color = const Color(0xFF141204));
        canvas.restore();
      }

      canvas.restore();
    }

    if (far) return;

    // 2. Exact 4-position layoutLabels from main.js (cached per zoom level when no earthquake)
    final markBucket = (markK * 200).round();
    final canUseCache = imp == null;
    List<_LabelLayoutEntry>? entries =
        canUseCache ? cache.labelLayoutCache[markBucket] : null;
    if (entries == null) {
      final rBox = 13.6 * markK;
      final placed = <Rect>[];
      final built = <_LabelLayoutEntry>[];

      bool hitsMark(Rect b, int self) {
        for (var j = 0; j < mapTerrs.length; j++) {
          if (j == self) continue;
          final t = positions[j];
          if (t.dx + rBox > b.left &&
              t.dx - rBox < b.right &&
              t.dy + rBox > b.top &&
              t.dy - rBox < b.bottom) {
            return true;
          }
        }
        return false;
      }

      bool hitsBox(Rect b) => placed.any((q) => b.overlaps(q));

      for (final i in cache.territoryOrder) {
        final pos = positions[i];
        final tp = cache.terrNameFill[i];
        final w = tp.width + 2.4;
        const hgt = 9.5;
        const opts = [
          (0.0, 24.0, TextAlign.center),
          (0.0, -18.0, TextAlign.center),
          (16.5, 3.0, TextAlign.left),
          (-16.5, 3.0, TextAlign.right),
        ];
        for (final opt in opts) {
          final cx = pos.dx + opt.$1 * markK;
          final cy = pos.dy + opt.$2 * markK;
          final x0 = opt.$3 == TextAlign.center
              ? cx - (w / 2) * markK
              : (opt.$3 == TextAlign.left ? cx : cx - w * markK);
          final rect = Rect.fromLTRB(
            x0 - 1,
            cy - hgt * markK * 0.8,
            x0 + w * markK + 1,
            cy + hgt * markK * 0.35,
          );
          if (hitsMark(rect, i) || hitsBox(rect)) continue;
          placed.add(rect);
          built.add(
            _LabelLayoutEntry(
              terrIndex: i,
              offset: Offset(cx, cy),
              align: opt.$3,
              tp: tp,
            ),
          );
          break;
        }
      }
      entries = built;
      if (canUseCache) {
        if (cache.labelLayoutCache.length > 32) {
          cache.labelLayoutCache.clear();
        }
        cache.labelLayoutCache[markBucket] = entries;
      }
    }

    for (final e in entries) {
      final strokeTp = cache.terrNameStroke[e.terrIndex];
      final dxLocal = e.align == TextAlign.center
          ? -e.tp.width / 2
          : (e.align == TextAlign.left ? 0.0 : -e.tp.width);
      final dyLocal = -e.tp.height * 0.72;

      canvas.save();
      canvas.translate(e.offset.dx, e.offset.dy);
      canvas.scale(markK, markK);
      strokeTp.paint(canvas, Offset(dxLocal, dyLocal));
      e.tp.paint(canvas, Offset(dxLocal, dyLocal));
      canvas.restore();
    }
  }

  void _drawFloats(Canvas canvas) {
    final markK = (10.5 / (12.5 * camZ)).clamp(1.0, 2.2);
    for (final f in ctrl.floats) {
      final t = ((nowMs - f.startMs) / f.durMs).clamp(0.0, 1.0);
      final fade = t < 0.15 ? t / 0.15 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
      final dy = t < 0.15 ? 6.0 * (1 - t / 0.15) : -36.0 * ((t - 0.15) / 0.85);
      final tr = ctrl.mapData.territories[f.terr];

      final strokeTp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..strokeJoin = StrokeJoin.round
              ..color = AppColors.deep.withValues(alpha: fade),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final fillTp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: fade),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pos = Offset(tr.x - fillTp.width / 2, tr.y - 18 * markK + dy);
      strokeTp.paint(canvas, pos);
      fillTp.paint(canvas, pos);
    }
  }

  @override
  bool shouldRepaint(covariant _WorldMapPainter old) =>
      old.camX != camX ||
      old.camY != camY ||
      old.camZ != camZ ||
      old.hoverTerr != hoverTerr ||
      old.ctrl != ctrl;
}

double hypot(double dx, double dy) => sqrt(dx * dx + dy * dy);
