// Efeitos sonoros sintetizados com Web Audio: sem arquivos, funcionam offline.
let ctx = null, enabled = true;
export const soundOn = () => enabled;
export function setSound(v) { enabled = !!v; }
// Navegadores só liberam áudio depois de um toque: chame isto em qualquer interação.
export function unlock() {
  try {
    ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
    if (ctx.state === 'suspended') ctx.resume();
  } catch {}
}
function tone(f, at, dur, { type = 'sine', vol = 0.18, to = null } = {}) {
  const o = ctx.createOscillator(), g = ctx.createGain(), t = ctx.currentTime + at;
  o.type = type; o.frequency.setValueAtTime(f, t);
  if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
  g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + 0.012); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  o.connect(g).connect(ctx.destination); o.start(t); o.stop(t + dur + 0.03);
}
let noiseBuf = null;
function noise(at, dur, { vol = 0.25, freq = 1200, kind = 'lowpass' } = {}) {
  if (!noiseBuf) {
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 0.5, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  }
  const s = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain(), t = ctx.currentTime + at;
  s.buffer = noiseBuf; f.type = kind; f.frequency.value = freq;
  g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  s.connect(f).connect(g).connect(ctx.destination); s.start(t); s.stop(t + dur + 0.02);
}
const SOUNDS = {
  place: () => tone(520, 0, 0.09, { to: 760, vol: 0.14 }),
  move: () => { tone(392, 0, 0.08, { vol: 0.12 }); tone(523, 0.07, 0.1, { vol: 0.12 }); },
  dice: () => { for (let i = 0; i < 4; i++) noise(i * 0.045, 0.03, { vol: 0.16, freq: 2600, kind: 'highpass' }); },
  attack: () => { noise(0.14, 0.2, { vol: 0.3, freq: 900 }); tone(130, 0.14, 0.22, { to: 48, vol: 0.3 }); },
  conquer: () => { noise(0.14, 0.25, { vol: 0.3, freq: 700 }); [523, 659, 784].forEach((f, i) => tone(f, 0.3 + i * 0.09, 0.16, { type: 'triangle', vol: 0.2 })); },
  lost: () => { noise(0.14, 0.25, { vol: 0.3, freq: 700 }); tone(392, 0.3, 0.3, { to: 220, type: 'sawtooth', vol: 0.1 }); },
  turn: () => { tone(659, 0, 0.16, { vol: 0.2 }); tone(988, 0.14, 0.28, { vol: 0.2 }); },
  other: () => tone(440, 0, 0.1, { vol: 0.07 }),
  phase: () => tone(784, 0, 0.07, { type: 'triangle', vol: 0.14 }),
  trade: () => [784, 988, 1175].forEach((f, i) => tone(f, i * 0.06, 0.12, { vol: 0.14 })),
  card: () => { tone(880, 0, 0.08, { vol: 0.12 }); tone(1175, 0.07, 0.14, { vol: 0.12 }); },
  warn: () => { tone(1000, 0, 0.09, { type: 'square', vol: 0.08 }); tone(1000, 0.16, 0.09, { type: 'square', vol: 0.08 }); },
  tick: () => tone(1000, 0, 0.04, { type: 'square', vol: 0.06 }),
  timeout: () => tone(300, 0, 0.4, { to: 150, type: 'sawtooth', vol: 0.12 }),
  nuke: () => { tone(900, 0, 0.5, { to: 140, type: 'sawtooth', vol: 0.1 }); noise(0.5, 1.6, { vol: 0.5, freq: 320 }); tone(70, 0.5, 1.5, { to: 28, vol: 0.4 }); noise(0.55, 0.5, { vol: 0.3, freq: 1800 }); },
  dead: () => tone(220, 0, 0.6, { to: 70, type: 'sawtooth', vol: 0.14 }),
  win: () => [523, 659, 784, 1047, 1319].forEach((f, i) => tone(f, i * 0.13, i === 4 ? 0.6 : 0.18, { type: 'triangle', vol: 0.22 })),
};
export function play(name) {
  if (!enabled || !ctx || ctx.state !== 'running' || !SOUNDS[name]) return;
  try { SOUNDS[name](); } catch {}
}
