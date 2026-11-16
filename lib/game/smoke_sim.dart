import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class SmokeMote {
  SmokeMote({
    required this.x,
    required this.y,
    required this.ml,
    required this.s,
    required this.ph,
  });

  double x;
  double y;
  double l = 0;
  final double ml;
  final double s;
  final double ph;
}

class SmokeSpark {
  SmokeSpark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.ml,
    required this.drag,
    this.emb = false,
  })  : px = x,
        py = y;

  double x;
  double y;
  double px;
  double py;
  double vx;
  double vy;
  double l = 0;
  final double ml;
  final double drag;
  final bool emb;
}

class SmokeArc {
  SmokeArc({required this.pts, required this.ml});

  final List<ui.Offset> pts;
  double l = 0;
  final double ml;
}

class _Vorton {
  _Vorton(this.x, this.y, this.ax, this.ay, this.s, this.r, this.t);

  double x;
  double y;
  double ax;
  double ay;
  final double s;
  final double r;
  double t;
}

class _Vent {
  _Vent(this.x, this.y, this.ph, this.f, this.t);

  double x;
  double y;
  final double ph;
  final double f;
  double t;
}

class _SmokeState {
  _SmokeState({
    required this.n,
    required this.w,
    required this.m,
    required this.size,
    required this.ox,
    required this.oy,
    required this.gx,
    required this.gy,
    required this.det,
    required this.mask,
    required this.maskM,
    required this.inside,
    required this.ground,
    required this.reach,
    required this.edge,
    required this.vortons,
    required this.vents,
    required this.cracks,
  })  : u = Float32List(w * w),
        v = Float32List(w * w),
        u0 = Float32List(w * w),
        v0 = Float32List(w * w),
        d = Float32List(w * w),
        d0 = Float32List(w * w),
        tField = Float32List(w * w),
        t0 = Float32List(w * w),
        p = Float32List(w * w),
        div = Float32List(w * w),
        curl = Float32List(w * w),
        b = Float32List(m * m),
        tb = Float32List(m * m),
        rgba = Uint8List(m * m * 4);

  final int n;
  final int w;
  final int m;
  final double size;
  final double ox;
  final double oy;
  final double gx;
  final double gy;
  final int det;
  final Float32List mask;
  final Float32List maskM;
  final List<int> inside;
  final Float32List ground;
  final double reach;
  final Float32List edge;
  final List<_Vorton> vortons;
  final List<_Vent> vents;
  final List<List<ui.Offset>> cracks;

  Float32List u;
  Float32List v;
  Float32List u0;
  Float32List v0;
  Float32List d;
  Float32List d0;
  Float32List tField;
  Float32List t0;
  final Float32List p;
  final Float32List div;
  final Float32List curl;
  final Float32List b;
  final Float32List tb;
  final Uint8List rgba;

  double time = 0;
  double age = 0;
  double ending = -1;
  double gain = 1;
  double mean = 0;
  double nextArc = 1.5;

  final List<SmokeMote> motes = [];
  final List<SmokeSpark> sparks = [];
  final List<SmokeArc> arcs = [];

  (double, double) pick(Random rng) {
    final k = inside[rng.nextInt(inside.length)];
    return ((k % w).toDouble(), (k ~/ w).toDouble());
  }
}

class SmokeSim extends ChangeNotifier {
  static const int _tile = 256;
  static const double _margin = 96.0;
  static const List<(int, int)> _qualityLevels = [
    (72, 160),
    (56, 124),
    (44, 96),
  ];

  final Random _rng = Random();
  Float32List? _nzA;
  Float32List? _nzB;
  _SmokeState? _s;
  Ticker? _ticker;
  ui.Image? _image;
  bool _building = false;
  bool _decoding = false;
  bool _pendingShade = false;
  int _startToken = 0;
  int _quality = 0;
  int _slowFrames = 0;
  double _costMs = 0;
  double _acc = 0;
  Duration? _lastTick;
  bool _reducedMotion = false;
  int? activeTerrIndex;

  bool get active => _s != null;
  ui.Image? get smokeImage => _image;
  double get ox => _s?.ox ?? 0;
  double get oy => _s?.oy ?? 0;
  double get size => _s?.size ?? 1;
  double get gx => _s?.gx ?? 0;
  double get gy => _s?.gy ?? 0;
  int get gridN => _s?.n ?? 72;
  int get gridM => _s?.m ?? 160;
  double get time => _s?.time ?? 0;
  double get age => _s?.age ?? 0;
  int get det => _s?.det ?? -1;
  double get ending => _s?.ending ?? -1;
  double get reach => _s?.reach ?? 0;
  List<List<ui.Offset>> get cracks => _s?.cracks ?? const [];
  List<SmokeMote> get motes => _s?.motes ?? const [];
  List<SmokeSpark> get sparks => _s?.sparks ?? const [];
  List<SmokeArc> get arcs => _s?.arcs ?? const [];

  void setReducedMotion(bool value) {
    _reducedMotion = value;
  }

  double _rand(double a, double b) => a + _rng.nextDouble() * (b - a);
  double _clamp(double x, double a, double b) => x < a ? a : (x > b ? b : x);
  double _sm(double t) => t * t * (3 - 2 * t);

  void _ensureNoise() {
    if (_nzA != null) return;
    _nzA = _noiseTile(11);
    _nzB = _noiseTile(57);
  }

  Float32List _noiseTile(int seed) {
    final out = Float32List(_tile * _tile);
    var a = seed & 0xFFFFFFFF;
    double rnd() {
      a = ((a * 1664525) + 1013904223) & 0xFFFFFFFF;
      return a / 4294967296.0;
    }

    final octs = [4, 8, 16, 32, 64]
        .map((p) => (p: p, v: Float32List.fromList(List<double>.generate(p * p, (_) => rnd()))))
        .toList();
    var lo = 1.0;
    var hi = 0.0;
    for (var y = 0; y < _tile; y++) {
      for (var x = 0; x < _tile; x++) {
        var n = 0.0;
        var amp = 0.5;
        var tot = 0.0;
        for (final o in octs) {
          final p = o.p;
          final v = o.v;
          final fx = (x / _tile) * p;
          final fy = (y / _tile) * p;
          final x0 = fx.floor();
          final y0 = fy.floor();
          final tx = _sm(fx - x0);
          final ty = _sm(fy - y0);
          final x1 = (x0 + 1) % p;
          final y1 = (y0 + 1) % p;
          final n0 = v[y0 * p + x0] * (1 - tx) + v[y0 * p + x1] * tx;
          final n1 = v[y1 * p + x0] * (1 - tx) + v[y1 * p + x1] * tx;
          n += (n0 * (1 - ty) + n1 * ty) * amp;
          tot += amp;
          amp *= 0.5;
        }
        n /= tot;
        out[y * _tile + x] = n;
        if (n < lo) lo = n;
        if (n > hi) hi = n;
      }
    }
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    for (var i = 0; i < out.length; i++) {
      out[i] = (out[i] - lo) / span;
    }
    return out;
  }

  double _nz(Float32List t, double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final fx = x - x0;
    final fy = y - y0;
    final xa = x0 & 255;
    final xb = (x0 + 1) & 255;
    final ya = (y0 & 255) << 8;
    final yb = ((y0 + 1) & 255) << 8;
    return (t[ya | xa] * (1 - fx) + t[ya | xb] * fx) * (1 - fy) +
        (t[yb | xa] * (1 - fx) + t[yb | xb] * fx) * fy;
  }

  Future<Float32List> _rasterMask(
    ui.Path path,
    double ox,
    double oy,
    double size,
    int r,
    int blur,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, r.toDouble(), r.toDouble()));
    final k = r / size;
    canvas.translate(-ox * k, -oy * k);
    canvas.scale(k, k);
    final paint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    canvas.drawPath(path, paint);
    final picture = recorder.endRecording();
    final img = await picture.toImage(r, r);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    picture.dispose();
    img.dispose();

    var m = Float32List(r * r);
    var t = Float32List(r * r);
    if (byteData != null) {
      final bytes = byteData.buffer.asUint8List();
      for (var i = 0; i < m.length; i++) {
        m[i] = bytes[i * 4 + 3] / 255.0;
      }
    }
    for (var pass = 0; pass < blur; pass++) {
      for (var y = 0; y < r; y++) {
        for (var x = 0; x < r; x++) {
          final xl = x > 0 ? x - 1 : x;
          final xr = x < r - 1 ? x + 1 : x;
          final yu = y > 0 ? y - 1 : y;
          final yd = y < r - 1 ? y + 1 : y;
          t[y * r + x] = (m[y * r + x] * 2 +
                  m[y * r + xl] +
                  m[y * r + xr] +
                  m[yu * r + x] +
                  m[yd * r + x]) /
              6.0;
        }
      }
      final tmp = m;
      m = t;
      t = tmp;
    }
    return m;
  }

  Future<_SmokeState> _buildState(
    ui.Path path,
    ui.Rect bbox,
    double cx,
    double cy,
    double size,
    double ox,
    double oy,
    bool detonate,
    int n,
    int m,
  ) async {
    final w = n + 2;
    final gx = ((cx - ox) / size) * n + 0.5;
    final gy = ((cy - oy) / size) * n + 0.5;
    final maskN = await _rasterMask(path, ox, oy, size, n, 1);
    final mask = Float32List(w * w);
    final inside = <int>[];
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final val = maskN[j * n + i];
        final q = i + 1 + w * (j + 1);
        mask[q] = val;
        if (val > 0.7) inside.add(q);
      }
    }
    if (inside.isEmpty) {
      inside.add((gx.floor().clamp(1, n)) + w * (gy.floor().clamp(1, n)));
    }
    final maskM = await _rasterMask(path, ox, oy, size, m, 2);
    final ground = Float32List(m * m);
    final nzA = _nzA!;
    final nzB = _nzB!;
    for (var y = 0; y < m; y++) {
      for (var x = 0; x < m; x++) {
        ground[y * m + x] =
            _nz(nzB, x * 150 / m + 31, y * 150 / m + 77) * 0.65 +
                _nz(nzA, x * 330 / m, y * 330 / m) * 0.35;
      }
    }
    final reach = sqrt(inside.length / pi);
    final edge = Float32List(w);
    for (var i = 0; i < w; i++) {
      final minDist = i < w - 1 - i ? i : w - 1 - i;
      edge[i] = _sm(_clamp(minDist / 6.0, 0, 1));
    }

    (double, double) pick() {
      final k = inside[_rng.nextInt(inside.length)];
      return ((k % w).toDouble(), (k ~/ w).toDouble());
    }

    final vortons = <_Vorton>[];
    for (var k = 0; k < 5; k++) {
      final (x, y) = pick();
      final (ax, ay) = pick();
      vortons.add(
        _Vorton(
          x,
          y,
          ax,
          ay,
          (k % 2 == 1 ? 1.0 : -1.0) * _rand(2.6, 5.4),
          _rand(5, 9) * (n / 72),
          _rand(2, 6),
        ),
      );
    }

    final vents = <_Vent>[];
    for (var k = 0; k < 7; k++) {
      final (x, y) = pick();
      vents.add(_Vent(x, y, _rand(0, 6.28), _rand(0.5, 1.4), _rand(3, 9)));
    }

    final cracks = <List<ui.Offset>>[];
    for (var k = 0; k < 7; k++) {
      var a = _rand(0, 6.28);
      var x = gx;
      var y = gy;
      final pts = <ui.Offset>[ui.Offset(x, y)];
      final len = reach * _rand(0.35, 0.8);
      const segs = 7;
      for (var q = 0; q < segs; q++) {
        a += _rand(-0.55, 0.55);
        x += cos(a) * len / segs;
        y += sin(a) * len / segs;
        pts.add(ui.Offset(x, y));
      }
      cracks.add(pts);
    }

    return _SmokeState(
      n: n,
      w: w,
      m: m,
      size: size,
      ox: ox,
      oy: oy,
      gx: gx,
      gy: gy,
      det: detonate ? 0 : -1,
      mask: mask,
      maskM: maskM,
      inside: inside,
      ground: ground,
      reach: reach,
      edge: edge,
      vortons: vortons,
      vents: vents,
      cracks: cracks,
    );
  }

  Future<void> start({
    required int terrIndex,
    required ui.Path path,
    required ui.Rect bbox,
    required double cx,
    required double cy,
    required bool detonate,
  }) async {
    _ensureNoise();
    final token = ++_startToken;
    activeTerrIndex = terrIndex;
    _building = true;
    _stopTicker();

    final size = max(bbox.width, bbox.height) + 2 * _margin;
    final ox = bbox.left + bbox.width / 2 - size / 2;
    final oy = bbox.top + bbox.height / 2 - size / 2;
    final (n, m) = _qualityLevels[_quality];
    final state = await _buildState(
      path,
      bbox,
      cx,
      cy,
      size,
      ox,
      oy,
      detonate && !_reducedMotion,
      n,
      m,
    );
    if (token != _startToken) return;
    _building = false;
    _s = state;

    if (state.det >= 0) {
      final sc = n / 72;
      _gauss(state, state.tField, state.gx, state.gy, 3.6 * sc, 3.4);
      _gauss(state, state.d, state.gx, state.gy, 4 * sc, 1.7);
      _radial(state, state.gx, state.gy, 7 * sc, 78 * sc);
      for (var k = 0; k < 150; k++) {
        final a = _rand(0, 6.28);
        final sp = _rand(22, 125) * sc;
        state.sparks.add(
          SmokeSpark(
            x: state.gx,
            y: state.gy,
            vx: cos(a) * sp,
            vy: sin(a) * sp,
            ml: _rand(0.35, 1.3),
            drag: _rand(2, 3.6),
          ),
        );
      }
      for (var k = 0; k < 46; k++) {
        final a = _rand(0, 6.28);
        final sp = _rand(6, 40) * sc;
        state.sparks.add(
          SmokeSpark(
            x: state.gx,
            y: state.gy,
            vx: cos(a) * sp,
            vy: sin(a) * sp,
            ml: _rand(1.8, 4.6),
            drag: _rand(1.2, 2.2),
            emb: true,
          ),
        );
      }
    } else {
      for (var k = 0; k < 90; k++) {
        _step(state, 1 / 20);
      }
    }

    _requestShade();
    _acc = 0;
    _lastTick = null;
    if (!_reducedMotion) {
      _ticker = Ticker(_onTick)..start();
    }
    notifyListeners();
  }

  void stop([bool immediate = false]) {
    _startToken++;
    if (_s == null) {
      activeTerrIndex = null;
      _stopTicker();
      return;
    }
    if (immediate || _reducedMotion || _ticker == null) {
      _kill();
      return;
    }
    if (_s!.ending < 0) {
      _s!.ending = _s!.time;
    }
  }

  void poke(double mx, double my) {
    final s = _s;
    if (s == null || _reducedMotion) return;
    final gx = ((mx - s.ox) / s.size) * s.n + 0.5;
    final gy = ((my - s.oy) / s.size) * s.n + 0.5;
    final sc = s.n / 72;
    _radial(s, gx, gy, 4 * sc, 30 * sc);
    s.nextArc = min(s.nextArc, 0.12);
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  void _kill() {
    _stopTicker();
    _s = null;
    activeTerrIndex = null;
    _image?.dispose();
    _image = null;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final s = _s;
    if (s == null || _building) return;
    final last = _lastTick ?? elapsed;
    _lastTick = elapsed;
    final deltaSec = ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    final fast = (s.det >= 0 && s.age < 5.5) || s.ending >= 0;
    final dt = fast ? 1 / 60 : (_quality == 2 ? 1 / 20 : 1 / 30);
    _acc += deltaSec;
    if (_acc < dt) return;
    _acc = _acc > 2 * dt ? 0 : _acc - dt;

    final sw = Stopwatch()..start();
    _step(s, (s.det >= 0 && s.age < 4) ? dt * 0.5 : dt);
    _requestShade();
    sw.stop();

    _costMs += (sw.elapsedMicroseconds / 1000.0 - _costMs) * 0.08;
    if (_costMs > (fast ? 14 : 16)) {
      if (++_slowFrames > 45 && _quality < _qualityLevels.length - 1) {
        _slowFrames = 0;
        _costMs = 0;
        _quality++;
      }
    } else {
      _slowFrames = 0;
    }

    if (s.ending >= 0 && s.time - s.ending > 2.6) {
      _kill();
      return;
    }
    notifyListeners();
  }

  void _advect(Float32List dst, Float32List src, Float32List uu, Float32List vv, double dt, _SmokeState s) {
    final n = s.n;
    final w = s.w;
    final hiC = n + 0.5;
    for (var j = 1; j <= n; j++) {
      for (var i = 1; i <= n; i++) {
        final q = i + w * j;
        var x = i - dt * uu[q];
        var y = j - dt * vv[q];
        if (x < 0.5) x = 0.5;
        if (x > hiC) x = hiC;
        if (y < 0.5) y = 0.5;
        if (y > hiC) y = hiC;
        final i0 = x.floor();
        final j0 = y.floor();
        final fx = x - i0;
        final fy = y - j0;
        final a = i0 + w * j0;
        dst[q] = (src[a] * (1 - fx) + src[a + 1] * fx) * (1 - fy) +
            (src[a + w] * (1 - fx) + src[a + w + 1] * fx) * fy;
      }
    }
  }

  void _gauss(_SmokeState s, Float32List f, double x, double y, double r, double amp) {
    final n = s.n;
    final w = s.w;
    final rad = (r * 2.6).ceil();
    final x0 = max(1, (x - rad).floor());
    final x1 = min(n, (x + rad).floor());
    final y0 = max(1, (y - rad).floor());
    final y1 = min(n, (y + rad).floor());
    final ir = 1 / (r * r);
    for (var j = y0; j <= y1; j++) {
      for (var i = x0; i <= x1; i++) {
        final dx = i - x;
        final dy = j - y;
        f[i + w * j] += amp * exp(-(dx * dx + dy * dy) * ir);
      }
    }
  }

  void _radial(_SmokeState s, double x, double y, double r, double amp, [double ring = 0]) {
    final n = s.n;
    final w = s.w;
    final u = s.u;
    final v = s.v;
    final rad = (ring + r * 2.6).ceil();
    final x0 = max(1, (x - rad).floor());
    final x1 = min(n, (x + rad).floor());
    final y0 = max(1, (y - rad).floor());
    final y1 = min(n, (y + rad).floor());
    final ir = 1 / (r * r);
    for (var j = y0; j <= y1; j++) {
      for (var i = x0; i <= x1; i++) {
        final dx = i - x;
        final dy = j - y;
        var dist = sqrt(dx * dx + dy * dy);
        if (dist == 0) dist = 1e-3;
        final e = dist - ring;
        final g = amp * exp(-e * e * ir);
        final q = i + w * j;
        u[q] += (dx / dist) * g;
        v[q] += (dy / dist) * g;
      }
    }
  }

  void _step(_SmokeState s, double dt) {
    final n = s.n;
    final w = s.w;
    final mask = s.mask;
    final p = s.p;
    final div = s.div;
    final curl = s.curl;
    var u = s.u;
    var v = s.v;
    var u0 = s.u0;
    var v0 = s.v0;
    var d = s.d;
    var d0 = s.d0;
    var tField = s.tField;
    var t0 = s.t0;

    s.time += dt;
    s.age += dt;
    final sc = n / 72;
    final ending = s.ending >= 0;

    if (!ending) {
      final ramp = s.det >= 0 ? _clamp((s.age - 0.3) / 3.2, 0, 1) : 1.0;
      for (final vt in s.vents) {
        vt.t -= dt;
        if (vt.t <= 0) {
          final (nx, ny) = s.pick(_rng);
          vt.x = nx;
          vt.y = ny;
          vt.t = _rand(3, 9);
        }
        _gauss(s, d, vt.x, vt.y, 2.6 * sc, dt * 1.0 * s.gain * ramp * (0.55 + 0.45 * sin(s.time * vt.f + vt.ph)));
      }
      final base = dt * 0.3 * s.gain * ramp;
      for (final q in s.inside) {
        d[q] += base;
      }
    }

    if (s.det >= 0) {
      final t = s.age;
      if (t < 1.9) {
        final k = 1 - t / 1.9;
        _gauss(s, tField, s.gx, s.gy, 3.2 * sc, dt * 6.5 * k);
        _gauss(s, d, s.gx, s.gy, 3.8 * sc, dt * 4.2 * k);
      }
      if (t < 0.85) {
        final k = 1 - t / 0.85;
        _radial(s, s.gx, s.gy, 2.6 * sc, dt * 150 * k * sc, (4 + 62 * t) * sc);
      }
    }

    for (final vo in s.vortons) {
      vo.t -= dt;
      if (vo.t <= 0) {
        final (ax, ay) = s.pick(_rng);
        vo.ax = ax;
        vo.ay = ay;
        vo.t = _rand(3, 7);
      }
      vo.x += (vo.ax - vo.x) * 0.25 * dt;
      vo.y += (vo.ay - vo.y) * 0.25 * dt;
      final rad = (vo.r * 2.2).ceil();
      final x0 = max(1, (vo.x - rad).floor());
      final x1 = min(n, (vo.x + rad).floor());
      final y0 = max(1, (vo.y - rad).floor());
      final y1 = min(n, (vo.y + rad).floor());
      final ir = 1 / (vo.r * vo.r);
      final amp = vo.s * dt * 2.2 * sc;
      for (var j = y0; j <= y1; j++) {
        for (var i = x0; i <= x1; i++) {
          final dx = i - vo.x;
          final dy = j - vo.y;
          final g = amp * exp(-(dx * dx + dy * dy) * ir) / vo.r;
          final q = i + w * j;
          u[q] -= dy * g;
          v[q] += dx * g;
        }
      }
    }

    final wa = s.time * 0.11;
    final wx = cos(wa) * 0.7 * sc;
    final wy = sin(wa * 1.3) * 0.55 * sc;
    final damp = exp(-dt * 0.55);
    final kT = 26 * dt;

    for (var j = 1; j <= n; j++) {
      for (var i = 1; i <= n; i++) {
        final q = i + w * j;
        curl[q] = 0.5 * ((v[q + 1] - v[q - 1]) - (u[q + w] - u[q - w]));
      }
    }
    for (var j = 2; j < n; j++) {
      for (var i = 2; i < n; i++) {
        final q = i + w * j;
        final cx = 0.5 * (curl[q + 1].abs() - curl[q - 1].abs());
        final cy = 0.5 * (curl[q + w].abs() - curl[q - w].abs());
        final len = sqrt(cx * cx + cy * cy) + 1e-5;
        final c = curl[q] * 4.6 * dt;
        u[q] = (u[q] + (cy / len) * c - kT * 0.5 * (tField[q + 1] - tField[q - 1]) + (wx - u[q]) * 0.12 * dt) * damp;
        v[q] = (v[q] - (cx / len) * c - kT * 0.5 * (tField[q + w] - tField[q - w]) + (wy - v[q]) * 0.12 * dt) * damp;
      }
    }

    _advect(u0, u, u, v, dt, s);
    _advect(v0, v, u, v, dt, s);
    final tu = u;
    u = u0;
    u0 = tu;
    final tv = v;
    v = v0;
    v0 = tv;

    for (var j = 1; j <= n; j++) {
      for (var i = 1; i <= n; i++) {
        final q = i + w * j;
        div[q] = -0.5 * (u[q + 1] - u[q - 1] + v[q + w] - v[q - w]);
        p[q] = 0;
      }
    }
    for (var k = 0; k < 14; k++) {
      for (var j = 1; j <= n; j++) {
        for (var i = 1; i <= n; i++) {
          final q = i + w * j;
          p[q] = (div[q] + p[q - 1] + p[q + 1] + p[q - w] + p[q + w]) * 0.25;
        }
      }
    }
    for (var j = 1; j <= n; j++) {
      for (var i = 1; i <= n; i++) {
        final q = i + w * j;
        u[q] -= 0.5 * (p[q + 1] - p[q - 1]);
        v[q] -= 0.5 * (p[q + w] - p[q - w]);
      }
    }

    _advect(d0, d, u, v, dt, s);
    _advect(t0, tField, u, v, dt, s);
    final td = d;
    d = d0;
    d0 = td;
    final tt = tField;
    tField = t0;
    t0 = tt;

    final cool = exp(-dt * 1.15);
    final kIn = ending ? 1.6 : 0.05;
    final kOut = ending ? 2.4 : 1.05;
    var sum = 0.0;
    final edgeClamp = min(1.0, dt * 9);
    for (var j = 1; j <= n; j++) {
      final ej = s.edge[j];
      for (var i = 1; i <= n; i++) {
        final q = i + w * j;
        final mVal = mask[q];
        d[q] *= exp(-dt * (kOut + (kIn - kOut) * mVal)) * (1 - (1 - ej * s.edge[i]) * edgeClamp);
        tField[q] *= cool;
        if (mVal > 0.7) sum += d[q];
      }
    }
    s.mean = sum / s.inside.length;
    s.gain = _clamp(s.gain + (0.8 - s.mean) * dt * 1.4, 0.15, 3.5);
    s.u = u;
    s.v = v;
    s.u0 = u0;
    s.v0 = v0;
    s.d = d;
    s.d0 = d0;
    s.tField = tField;
    s.t0 = t0;

    _stepParticles(s, dt);
  }

  (double su, double sv, double sd) _sample(_SmokeState s, double x, double y) {
    final n = s.n;
    final w = s.w;
    final u = s.u;
    final v = s.v;
    final d = s.d;
    x = _clamp(x, 1, n.toDouble());
    y = _clamp(y, 1, n.toDouble());
    final i0 = x.floor();
    final j0 = y.floor();
    final fx = x - i0;
    final fy = y - j0;
    final a = i0 + w * j0;
    final w00 = (1 - fx) * (1 - fy);
    final w10 = fx * (1 - fy);
    final w01 = (1 - fx) * fy;
    final w11 = fx * fy;
    return (
      u[a] * w00 + u[a + 1] * w10 + u[a + w] * w01 + u[a + w + 1] * w11,
      v[a] * w00 + v[a + 1] * w10 + v[a + w] * w01 + v[a + w + 1] * w11,
      d[a] * w00 + d[a + 1] * w10 + d[a + w] * w01 + d[a + w + 1] * w11,
    );
  }

  void _stepParticles(_SmokeState s, double dt) {
    final n = s.n;
    if (s.motes.length < 70 && s.ending < 0 && s.mean > 0.15) {
      final (x, y) = s.pick(_rng);
      s.motes.add(
        SmokeMote(
          x: x + _rand(-1, 1),
          y: y + _rand(-1, 1),
          ml: _rand(2.5, 6),
          s: _rand(0.7, 1.9),
          ph: _rand(0, 6.28),
        ),
      );
    }
    for (var k = s.motes.length - 1; k >= 0; k--) {
      final m = s.motes[k];
      final (su, sv, _) = _sample(s, m.x, m.y);
      m.x += (su + _rand(-1.6, 1.6)) * dt;
      m.y += (sv + _rand(-1.6, 1.6)) * dt;
      m.l += dt;
      if (m.l > m.ml || m.x < 1 || m.y < 1 || m.x > n || m.y > n) {
        s.motes.removeAt(k);
      }
    }

    for (var k = s.sparks.length - 1; k >= 0; k--) {
      final q = s.sparks[k];
      final (su, sv, _) = _sample(s, q.x, q.y);
      final dr = exp(-dt * q.drag);
      q.vx = q.vx * dr + (su - q.vx) * 0.9 * dt;
      q.vy = q.vy * dr + (sv - q.vy) * 0.9 * dt;
      q.px = q.x;
      q.py = q.y;
      q.x += q.vx * dt;
      q.y += q.vy * dt;
      q.l += dt;
      if (q.l > q.ml) s.sparks.removeAt(k);
    }

    for (var k = s.arcs.length - 1; k >= 0; k--) {
      s.arcs[k].l += dt;
      if (s.arcs[k].l > s.arcs[k].ml) s.arcs.removeAt(k);
    }
    s.nextArc -= dt;
    if (s.nextArc <= 0 && s.ending < 0) {
      s.nextArc = _rand(0.9, 3.4);
      final (x, y) = s.pick(_rng);
      final (_, _, sd) = _sample(s, x, y);
      if (sd > 0.35) {
        final a = _rand(0, 6.28);
        final len = _rand(5, 12) * (n / 72);
        var pts = <ui.Offset>[
          ui.Offset(x, y),
          ui.Offset(x + cos(a) * len, y + sin(a) * len),
        ];
        var off = len * 0.28;
        for (var lv = 0; lv < 4; lv++, off *= 0.55) {
          final nx = <ui.Offset>[];
          for (var i = 0; i < pts.length - 1; i++) {
            final p0 = pts[i];
            final p1 = pts[i + 1];
            nx.add(p0);
            nx.add(ui.Offset((p0.dx + p1.dx) / 2 + _rand(-off, off), (p0.dy + p1.dy) / 2 + _rand(-off, off)));
          }
          nx.add(pts.last);
          pts = nx;
        }
        s.arcs.add(SmokeArc(pts: pts, ml: _rand(0.12, 0.22)));
        if (_rng.nextDouble() < 0.45) {
          final mid = pts[pts.length ~/ 2];
          final b = a + _rand(-1.2, 1.2);
          final bl = len * 0.45;
          s.arcs.add(
            SmokeArc(
              pts: [
                mid,
                ui.Offset(mid.dx + cos(b) * bl * 0.5 + _rand(-1, 1), mid.dy + sin(b) * bl * 0.5 + _rand(-1, 1)),
                ui.Offset(mid.dx + cos(b) * bl, mid.dy + sin(b) * bl),
              ],
              ml: 0.14,
            ),
          );
        }
      }
    }
  }

  void _requestShade() {
    if (_decoding) {
      _pendingShade = true;
      return;
    }
    final s = _s;
    if (s == null) return;
    _shade(s);
    _decoding = true;
    final token = _startToken;
    ui.decodeImageFromPixels(
      s.rgba,
      s.m,
      s.m,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        _decoding = false;
        if (token != _startToken || _s == null) {
          img.dispose();
          return;
        }
        _image?.dispose();
        _image = img;
        notifyListeners();
        if (_pendingShade) {
          _pendingShade = false;
          _requestShade();
        }
      },
    );
  }

  void _shade(_SmokeState s) {
    final n = s.n;
    final w = s.w;
    final m = s.m;
    final d = s.d;
    final tField = s.tField;
    final u = s.u;
    final v = s.v;
    final b = s.b;
    final tb = s.tb;
    final maskM = s.maskM;
    final data = s.rgba;
    final nzA = _nzA!;
    final nzB = _nzB!;

    final sc = n / m;
    final cyc = s.time * 0.42;
    final ph0 = cyc - cyc.floor();
    final ph1 = (ph0 + 0.5) - (ph0 + 0.5).floor();
    final wB = (1 - 2 * ph0).abs();
    final wA = 1 - wB;
    final f1 = 190 / m;
    final kFlow = 1.5 * (72 / n);
    final drift = s.time * 3.2;
    final f2 = 70 / m;

    for (var py = 0; py < m; py++) {
      final gy = (py + 0.5) * sc + 0.5;
      final j0 = gy.floor();
      final fy = gy - j0;
      final r0 = j0 * w;
      for (var px = 0; px < m; px++) {
        final gx = (px + 0.5) * sc + 0.5;
        final i0 = gx.floor();
        final fx = gx - i0;
        final a = r0 + i0;
        final w00 = (1 - fx) * (1 - fy);
        final w10 = fx * (1 - fy);
        final w01 = (1 - fx) * fy;
        final w11 = fx * fy;
        final dd = d[a] * w00 + d[a + 1] * w10 + d[a + w] * w01 + d[a + w + 1] * w11;
        final k = py * m + px;
        tb[k] = tField[a] * w00 + tField[a + 1] * w10 + tField[a + w] * w01 + tField[a + w + 1] * w11;
        if (dd < 0.004) {
          b[k] = 0;
          continue;
        }
        final uu = (u[a] * w00 + u[a + 1] * w10 + u[a + w] * w01 + u[a + w + 1] * w11) * kFlow;
        final vv = (v[a] * w00 + v[a + 1] * w10 + v[a + w] * w01 + v[a + w + 1] * w11) * kFlow;
        final bx = px * f1;
        final by = py * f1;
        final det = _nz(nzA, bx - uu * ph0, by - vv * ph0) * wA +
            _nz(nzA, bx - uu * ph1 + 97.3, by - vv * ph1 + 41.7) * wB;
        final big = _nz(nzB, px * f2 + drift, py * f2 - drift * 0.6);
        final val = dd * (0.3 + 1.45 * det) * (0.7 + 0.6 * big) - 0.05;
        b[k] = val > 0 ? val : 0;
      }
    }

    const relief = 5.2;
    final ground = s.ground;
    for (var py = 0; py < m; py++) {
      final yu = py > 0 ? -m : 0;
      final yd = py < m - 1 ? m : 0;
      for (var px = 0; px < m; px++) {
        final k = py * m + px;
        final o = k * 4;
        final den = b[k];
        final tt = tb[k];
        final gm = maskM[k];
        if (den <= 0 && tt < 0.02 && gm < 0.02) {
          data[o + 3] = 0;
          continue;
        }
        final gxVal = (b[k + (px < m - 1 ? 1 : 0)] - b[k - (px > 0 ? 1 : 0)]) * relief;
        final gyVal = (b[k + yd] - b[k + yu]) * relief;
        var lit = (gxVal * 0.5 + gyVal * 0.62 + 0.6) / sqrt(gxVal * gxVal + gyVal * gyVal + 1);
        lit = lit < 0 ? 0 : (lit > 1 ? 1 : lit);
        final thick = exp(-den * 0.55);
        final l2 = lit * lit;
        final sh = (0.25 + 0.75 * lit) * (0.45 + 0.55 * thick);
        var r = 8 + 52 * sh + 112 * l2 * lit;
        var g = 28 + 164 * sh + 62 * l2 * lit;
        var bl = 12 + 40 * sh + 66 * l2 * lit;
        var al = 1 - exp(-den * 2.1);
        if (al > 0.95) al = 0.95;

        if (gm > 0.02) {
          final nv = ground[k];
          final hot = nv > 0.52 ? (nv > 0.8 ? 1.0 : (nv - 0.52) / 0.28) : 0.0;
          final e = gm * exp(-den * 1.6) * hot * hot * (0.3 + 0.22 * sin(s.time * 1.9 + nv * 23));
          final ua = 0.26 * gm;
          final k1 = 1 - al;
          final pa = ua + e * (1 - ua);
          final na = al + pa * k1;
          if (na > 0) {
            r = (r * al + (5 * ua + 80 * e) * k1) / na;
            g = (g * al + (16 * ua + 255 * e) * k1) / na;
            bl = (bl * al + (9 * ua + 100 * e) * k1) / na;
            al = na;
          }
        }
        if (tt > 0.02) {
          final h = tt > 1.6 ? 1.6 : tt;
          final e = h * h * 0.7;
          r += 255 * (h * 1.5);
          g += 255 * (e * 0.95 + (h > 1 ? (h - 1) * 0.8 : 0));
          bl += 255 * (h > 0.9 ? (h - 0.9) * 1.1 : 0) + 40 * e;
          final fa = h * 1.25;
          if (fa > al) al = fa > 1 ? 1 : fa;
        }
        data[o] = (r > 255 ? 255 : (r < 0 ? 0 : r)).round();
        data[o + 1] = (g > 255 ? 255 : (g < 0 ? 0 : g)).round();
        data[o + 2] = (bl > 255 ? 255 : (bl < 0 ? 0 : bl)).round();
        data[o + 3] = (al * 255).clamp(0, 255).round();
      }
    }
  }

  @override
  void dispose() {
    _startToken++;
    _stopTicker();
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
