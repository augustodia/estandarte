import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

web.AudioContext? _ctx;
web.AudioBuffer? _noiseBuf;
final _rng = Random();

void unlockAudio() {
  try {
    if (_ctx == null) {
      final ctor = web.window.getProperty('AudioContext'.toJS) ??
          web.window.getProperty('webkitAudioContext'.toJS);
      if (ctor != null) {
        _ctx = web.AudioContext();
      }
    }
    if (_ctx != null && _ctx!.state == 'suspended') {
      _ctx!.resume();
    }
  } catch (_) {}
}

void _tone(
  double f,
  double at,
  double dur, {
  String type = 'sine',
  double vol = 0.18,
  double? to,
}) {
  final ctx = _ctx!;
  final o = ctx.createOscillator();
  final g = ctx.createGain();
  final t = ctx.currentTime + at;
  o.type = type;
  o.frequency.setValueAtTime(f, t);
  if (to != null) {
    o.frequency.exponentialRampToValueAtTime(to, t + dur);
  }
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(vol, t + 0.012);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g);
  g.connect(ctx.destination);
  o.start(t);
  o.stop(t + dur + 0.03);
}

void _noise(
  double at,
  double dur, {
  double vol = 0.25,
  double freq = 1200,
  String kind = 'lowpass',
}) {
  final ctx = _ctx!;
  if (_noiseBuf == null) {
    final len = (ctx.sampleRate * 0.5).round();
    final buf = ctx.createBuffer(1, len, ctx.sampleRate);
    final data = buf.getChannelData(0).toDart;
    for (var i = 0; i < data.length; i++) {
      data[i] = _rng.nextDouble() * 2 - 1;
    }
    _noiseBuf = buf;
  }
  final s = ctx.createBufferSource();
  final f = ctx.createBiquadFilter();
  final g = ctx.createGain();
  final t = ctx.currentTime + at;
  s.buffer = _noiseBuf;
  s.loop = dur > 0.45;
  f.type = kind;
  f.frequency.value = freq;
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  s.connect(f);
  f.connect(g);
  g.connect(ctx.destination);
  s.start(t);
  s.stop(t + dur + 0.02);
}

void playSound(String name) {
  final ctx = _ctx;
  if (ctx == null || ctx.state != 'running') return;
  try {
    switch (name) {
      case 'place':
        _tone(520, 0, 0.09, to: 760, vol: 0.14);
      case 'move':
        _tone(392, 0, 0.08, vol: 0.12);
        _tone(523, 0.07, 0.1, vol: 0.12);
      case 'dice':
        for (var i = 0; i < 4; i++) {
          _noise(i * 0.045, 0.03, vol: 0.16, freq: 2600, kind: 'highpass');
        }
      case 'attack':
        _noise(0.14, 0.2, vol: 0.3, freq: 900);
        _tone(130, 0.14, 0.22, to: 48, vol: 0.3);
      case 'conquer':
        _noise(0.14, 0.25, vol: 0.3, freq: 700);
        const freqs = [523.0, 659.0, 784.0];
        for (var i = 0; i < freqs.length; i++) {
          _tone(freqs[i], 0.3 + i * 0.09, 0.16, type: 'triangle', vol: 0.2);
        }
      case 'lost':
        _noise(0.14, 0.25, vol: 0.3, freq: 700);
        _tone(392, 0.3, 0.3, to: 220, type: 'sawtooth', vol: 0.1);
      case 'turn':
        _tone(659, 0, 0.16, vol: 0.2);
        _tone(988, 0.14, 0.28, vol: 0.2);
      case 'other':
        _tone(440, 0, 0.1, vol: 0.07);
      case 'phase':
        _tone(784, 0, 0.07, type: 'triangle', vol: 0.14);
      case 'trade':
        const freqs = [784.0, 988.0, 1175.0];
        for (var i = 0; i < freqs.length; i++) {
          _tone(freqs[i], i * 0.06, 0.12, vol: 0.14);
        }
      case 'card':
        _tone(880, 0, 0.08, vol: 0.12);
        _tone(1175, 0.07, 0.14, vol: 0.12);
      case 'warn':
        _tone(1000, 0, 0.09, type: 'square', vol: 0.08);
        _tone(1000, 0.16, 0.09, type: 'square', vol: 0.08);
      case 'tick':
        _tone(1000, 0, 0.04, type: 'square', vol: 0.06);
      case 'timeout':
        _tone(300, 0, 0.4, to: 150, type: 'sawtooth', vol: 0.12);
      case 'siren':
        for (var k = 0; k < 6; k++) {
          _tone(420, k * 0.6, 0.3, to: 880, type: 'sawtooth', vol: 0.06);
          _tone(880, k * 0.6 + 0.3, 0.3, to: 420, type: 'sawtooth', vol: 0.06);
          _tone(210, k * 0.6, 0.6, type: 'square', vol: 0.02);
        }
      case 'launch':
        _noise(0, 2.9, vol: 0.16, freq: 420);
        _tone(70, 0, 2.9, to: 140, type: 'sawtooth', vol: 0.05);
        _tone(1800, 2.1, 0.8, to: 300, type: 'sine', vol: 0.07);
      case 'boom':
        _noise(0, 0.09, vol: 0.8, freq: 3200, kind: 'highpass');
        _noise(0, 3.2, vol: 0.62, freq: 300);
        _noise(0.05, 4.4, vol: 0.36, freq: 110);
        _tone(96, 0, 3.0, to: 22, vol: 0.5);
        _tone(48, 0.02, 3.6, to: 18, vol: 0.34, type: 'triangle');
        for (var k = 0; k < 12; k++) {
          _noise(
            0.4 + _rng.nextDouble() * 2.6,
            0.03 + _rng.nextDouble() * 0.05,
            vol: 0.1 + _rng.nextDouble() * 0.12,
            freq: 1500 + _rng.nextDouble() * 2500,
            kind: 'highpass',
          );
        }
      case 'geiger':
        var t = 0.0;
        for (var k = 0; k < 16; k++) {
          t += 0.02 + _rng.nextDouble() * _rng.nextDouble() * 0.22;
          _noise(t, 0.006, vol: 0.34, freq: 2800, kind: 'highpass');
        }
      case 'dead':
        _tone(220, 0, 0.6, to: 70, type: 'sawtooth', vol: 0.14);
      case 'win':
        const freqs = [523.0, 659.0, 784.0, 1047.0, 1319.0];
        for (var i = 0; i < freqs.length; i++) {
          _tone(freqs[i], i * 0.13, i == 4 ? 0.6 : 0.18, type: 'triangle', vol: 0.22);
        }
    }
  } catch (_) {}
}
