// Névoa radioativa e detonação da ogiva.
//
// A fumaça é um fluido de verdade: uma simulação de "stable fluids" (Jos Stam) numa grade pequena, calculada na CPU, com
// advecção semi-lagrangiana, projeção de pressão (fluido incompressível), confinamento de vorticidade (mantém os redemoinhos
// vivos), expansão térmica (o gás quente empurra o resto) e vórtices errantes que mexem a nuvem. O território é a fonte:
// respiradouros dentro do contorno dele soltam fumaça, que escapa pelas bordas e se dissipa.
//
// O desenho é feito numa grade mais fina que a da simulação: densidade com detalhe de ruído arrastado pelo próprio
// escoamento ("flow map"), relevo iluminado a partir do gradiente da densidade, absorção (fumaça espessa escurece), brilho
// do solo radioativo por baixo, corpo negro para o fogo da explosão e um halo de brilho. Por cima vão as partículas:
// poeira luminosa levada pelo fluido, fagulhas e brasas da explosão, descargas elétricas dentro da nuvem e a onda de choque.
//
// Tudo num <canvas> 2D comum (sem WebGL), para funcionar igual em qualquer celular e offline.

const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const sm = (t) => t * t * (3 - 2 * t);
const TILE = 256;

// Ruído fractal que emenda nas bordas, 0..1.
function noiseTile(seed) {
  const out = new Float32Array(TILE * TILE);
  let a = seed >>> 0;
  const rnd = () => { a = (Math.imul(a, 1664525) + 1013904223) >>> 0; return a / 4294967296; };
  const octs = [4, 8, 16, 32, 64].map((P) => ({ P, v: Float32Array.from({ length: P * P }, rnd) }));
  let lo = 1, hi = 0;
  for (let y = 0; y < TILE; y++) for (let x = 0; x < TILE; x++) {
    let n = 0, amp = 0.5, tot = 0;
    for (const { P, v } of octs) {
      const fx = (x / TILE) * P, fy = (y / TILE) * P, x0 = fx | 0, y0 = fy | 0, tx = sm(fx - x0), ty = sm(fy - y0), x1 = (x0 + 1) % P, y1 = (y0 + 1) % P;
      n += ((v[y0 * P + x0] * (1 - tx) + v[y0 * P + x1] * tx) * (1 - ty) + (v[y1 * P + x0] * (1 - tx) + v[y1 * P + x1] * tx) * ty) * amp;
      tot += amp; amp *= 0.5;
    }
    n /= tot; out[y * TILE + x] = n; if (n < lo) lo = n; if (n > hi) hi = n;
  }
  for (let i = 0; i < out.length; i++) out[i] = (out[i] - lo) / (hi - lo);
  return out;
}
// Amostra bilinear do ruído, com repetição.
function nz(t, x, y) {
  const x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
  const xa = x0 & 255, xb = (x0 + 1) & 255, ya = (y0 & 255) << 8, yb = ((y0 + 1) & 255) << 8;
  return (t[ya | xa] * (1 - fx) + t[ya | xb] * fx) * (1 - fy) + (t[yb | xa] * (1 - fx) + t[yb | xb] * fx) * fy;
}
function glowSprite(r, g, b) {
  const c = document.createElement('canvas'); c.width = c.height = 32;
  const x = c.getContext('2d'), gr = x.createRadialGradient(16, 16, 0, 16, 16, 16);
  gr.addColorStop(0, `rgba(255,255,255,1)`); gr.addColorStop(0.25, `rgba(${r},${g},${b},.75)`); gr.addColorStop(1, `rgba(${r},${g},${b},0)`);
  x.fillStyle = gr; x.fillRect(0, 0, 32, 32);
  return c;
}
// Contorno do território transformado em máscara 0..1 (R×R), com a borda suavizada.
function rasterMask(path, ox, oy, size, R, blur) {
  const c = document.createElement('canvas'); c.width = c.height = R;
  const g = c.getContext('2d', { willReadFrequently: true }), k = R / size;
  g.setTransform(k, 0, 0, k, -ox * k, -oy * k);
  g.fill(new Path2D(path), 'evenodd');
  const a = g.getImageData(0, 0, R, R).data;
  let m = new Float32Array(R * R), t = new Float32Array(R * R);
  for (let i = 0; i < m.length; i++) m[i] = a[i * 4 + 3] / 255;
  for (let pass = 0; pass < blur; pass++) {
    for (let y = 0; y < R; y++) for (let x = 0; x < R; x++) {
      const xl = x ? x - 1 : x, xr = x < R - 1 ? x + 1 : x, yu = y ? y - 1 : y, yd = y < R - 1 ? y + 1 : y;
      t[y * R + x] = (m[y * R + x] * 2 + m[y * R + xl] + m[y * R + xr] + m[yu * R + x] + m[yd * R + x]) / 6;
    }
    [m, t] = [t, m];
  }
  return m;
}

// [células da simulação, pixels do desenho]: cai de nível sozinho se o aparelho não der conta
const QUALITY = [[72, 176], [60, 136], [46, 100]];
const MARGIN = 96; // quanto o domínio passa do território, em unidades do mapa

export function createSmoke(canvas) {
  const ctx = canvas.getContext('2d');
  const nzA = noiseTile(11), nzB = noiseTile(57);
  const off = document.createElement('canvas'), octx = off.getContext('2d');
  const tiny = document.createElement('canvas'), tctx = tiny.getContext('2d');
  const mote = glowSprite(120, 255, 110), ember = glowSprite(255, 150, 50);
  const still = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  let S = null, raf = 0, quality = 0, cost = 0, slow = 0, acc = 0, last = 0, cam = null, P = 0, hiddenBox = false;
  const rand = (a, b) => a + Math.random() * (b - a);

  function build(cfg, N, M, old) {
    const W = N + 2, size = cfg.size, ox = cfg.ox, oy = cfg.oy;
    const f = () => new Float32Array(W * W);
    const s = {
      cfg, N, W, M, size, ox, oy,
      u: f(), v: f(), u0: f(), v0: f(), d: f(), d0: f(), T: f(), T0: f(), p: f(), div: f(), curl: f(), mask: f(),
      B: new Float32Array(M * M), TB: new Float32Array(M * M), img: octx.createImageData(M, M),
      time: 0, age: 0, det: cfg.detonate ? 0 : -1, ending: -1, gain: 1, mean: 0, nextArc: 1.5,
      gx: ((cfg.cx - ox) / size) * N + 0.5, gy: ((cfg.cy - oy) / size) * N + 0.5,
      inside: [], vortons: [], vents: [], motes: [], sparks: [], arcs: [], cracks: [],
    };
    const m = rasterMask(cfg.path, ox, oy, size, N, 1);
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) { const val = m[j * N + i]; s.mask[i + 1 + W * (j + 1)] = val; if (val > 0.7) s.inside.push(i + 1 + W * (j + 1)); }
    if (!s.inside.length) s.inside.push((s.gx | 0) + W * (s.gy | 0));
    s.maskM = rasterMask(cfg.path, ox, oy, size, M, 2);
    s.ground = new Float32Array(M * M); // textura fixa do chão: onde ficam as manchas quentes
    for (let y = 0; y < M; y++) for (let x = 0; x < M; x++) s.ground[y * M + x] = nz(nzB, x * 150 / M + 31, y * 150 / M + 77) * 0.65 + nz(nzA, x * 330 / M, y * 330 / M) * 0.35;
    s.reach = Math.sqrt(s.inside.length / Math.PI); // "raio" do território, em células
    s.edge = new Float32Array(W);
    for (let i = 0; i < W; i++) s.edge[i] = sm(clamp(Math.min(i, W - 1 - i) / 6, 0, 1));
    const pick = () => { const k = s.inside[(Math.random() * s.inside.length) | 0]; return [k % W, (k / W) | 0]; };
    s.pick = pick;
    for (let k = 0; k < 5; k++) { const [x, y] = pick(), [ax, ay] = pick(); s.vortons.push({ x, y, ax, ay, s: (k % 2 ? 1 : -1) * rand(2.6, 5.4), r: rand(5, 9) * (N / 72), t: rand(2, 6) }); }
    for (let k = 0; k < 7; k++) { const [x, y] = pick(); s.vents.push({ x, y, ph: rand(0, 6.28), f: rand(0.5, 1.4), t: rand(3, 9) }); }
    for (let k = 0; k < 7; k++) { // rachaduras no solo a partir do ponto de impacto
      let a = rand(0, 6.28), x = s.gx, y = s.gy; const pts = [[x, y]], len = s.reach * rand(0.35, 0.8), n = 7;
      for (let q = 0; q < n; q++) { a += rand(-0.55, 0.55); x += Math.cos(a) * len / n; y += Math.sin(a) * len / n; pts.push([x, y]); }
      s.cracks.push(pts);
    }
    if (old) { // troca de qualidade: reaproveita o que já existia
      const k = old.N / N, smp = (src, x, y) => src[clamp(Math.round(x), 1, old.N) + old.W * clamp(Math.round(y), 1, old.N)];
      for (let j = 1; j <= N; j++) for (let i = 1; i <= N; i++) { const q = i + W * j; s.d[q] = smp(old.d, i * k, j * k); s.T[q] = smp(old.T, i * k, j * k); }
      Object.assign(s, { time: old.time, age: old.age, det: old.det, ending: old.ending, gain: old.gain });
    }
    return s;
  }

  function advect(dst, src, uu, vv, dt, s) {
    const { N, W } = s, hiC = N + 0.5;
    for (let j = 1; j <= N; j++) for (let i = 1; i <= N; i++) {
      const q = i + W * j;
      let x = i - dt * uu[q], y = j - dt * vv[q];
      x = x < 0.5 ? 0.5 : x > hiC ? hiC : x; y = y < 0.5 ? 0.5 : y > hiC ? hiC : y;
      const i0 = x | 0, j0 = y | 0, fx = x - i0, fy = y - j0, a = i0 + W * j0;
      dst[q] = (src[a] * (1 - fx) + src[a + 1] * fx) * (1 - fy) + (src[a + W] * (1 - fx) + src[a + W + 1] * fx) * fy;
    }
  }
  function gauss(s, f, x, y, r, amp) { // soma uma gaussiana ao campo
    const { N, W } = s, R = Math.ceil(r * 2.6), x0 = Math.max(1, (x - R) | 0), x1 = Math.min(N, (x + R) | 0), y0 = Math.max(1, (y - R) | 0), y1 = Math.min(N, (y + R) | 0), ir = 1 / (r * r);
    for (let j = y0; j <= y1; j++) for (let i = x0; i <= x1; i++) f[i + W * j] += amp * Math.exp(-((i - x) * (i - x) + (j - y) * (j - y)) * ir);
  }
  function radial(s, x, y, r, amp, ring) { // empurrão para fora a partir de (x,y); com ring > 0, concentrado num anel
    const { N, W, u, v } = s, R = Math.ceil((ring || 0) + r * 2.6), x0 = Math.max(1, (x - R) | 0), x1 = Math.min(N, (x + R) | 0), y0 = Math.max(1, (y - R) | 0), y1 = Math.min(N, (y + R) | 0), ir = 1 / (r * r);
    for (let j = y0; j <= y1; j++) for (let i = x0; i <= x1; i++) {
      const dx = i - x, dy = j - y, dist = Math.hypot(dx, dy) || 1e-3, e = dist - (ring || 0), g = amp * Math.exp(-e * e * ir), q = i + W * j;
      u[q] += (dx / dist) * g; v[q] += (dy / dist) * g;
    }
  }

  function step(dt) {
    const s = S, { N, W, mask, p, div, curl } = s;
    let { u, v, u0, v0, d, d0, T, T0 } = s;
    s.time += dt; s.age += dt;
    const sc = N / 72, ending = s.ending >= 0;
    // ---- fontes ----
    if (!ending) {
      const ramp = s.det >= 0 ? clamp((s.age - 0.3) / 3.2, 0, 1) : 1; // depois da explosão a névoa vai tomando o território aos poucos
      for (const vt of s.vents) {
        vt.t -= dt;
        if (vt.t <= 0) { [vt.x, vt.y] = s.pick(); vt.t = rand(3, 9); }
        gauss(s, d, vt.x, vt.y, 2.6 * sc, dt * 1.0 * s.gain * ramp * (0.55 + 0.45 * Math.sin(s.time * vt.f + vt.ph)));
      }
      const base = dt * 0.3 * s.gain * ramp;
      for (const q of s.inside) d[q] += base;
    }
    if (s.det >= 0) { // detonação: bola de fogo, sopro e anel de choque
      const t = s.age;
      if (t < 1.9) { const k = 1 - t / 1.9; gauss(s, T, s.gx, s.gy, 3.2 * sc, dt * 6.5 * k); gauss(s, d, s.gx, s.gy, 3.8 * sc, dt * 4.2 * k); }
      if (t < 0.85) { const k = 1 - t / 0.85; radial(s, s.gx, s.gy, 2.6 * sc, dt * 150 * k * sc, (4 + 62 * t) * sc); }
    }
    // ---- forças ----
    for (const vo of s.vortons) { // vórtices errantes: giram a fumaça e andam devagar pelo território
      vo.t -= dt;
      if (vo.t <= 0) { [vo.ax, vo.ay] = s.pick(); vo.t = rand(3, 7); }
      vo.x += (vo.ax - vo.x) * 0.25 * dt; vo.y += (vo.ay - vo.y) * 0.25 * dt;
      const R = Math.ceil(vo.r * 2.2), x0 = Math.max(1, (vo.x - R) | 0), x1 = Math.min(N, (vo.x + R) | 0), y0 = Math.max(1, (vo.y - R) | 0), y1 = Math.min(N, (vo.y + R) | 0), ir = 1 / (vo.r * vo.r), amp = vo.s * dt * 2.2 * sc;
      for (let j = y0; j <= y1; j++) for (let i = x0; i <= x1; i++) {
        const dx = i - vo.x, dy = j - vo.y, g = amp * Math.exp(-(dx * dx + dy * dy) * ir) / vo.r, q = i + W * j;
        u[q] -= dy * g; v[q] += dx * g;
      }
    }
    const wa = s.time * 0.11, wx = Math.cos(wa) * 0.7 * sc, wy = Math.sin(wa * 1.3) * 0.55 * sc, damp = Math.exp(-dt * 0.55), kT = 26 * dt;
    for (let j = 1; j <= N; j++) for (let i = 1; i <= N; i++) { const q = i + W * j; curl[q] = 0.5 * ((v[q + 1] - v[q - 1]) - (u[q + W] - u[q - W])); }
    for (let j = 2; j < N; j++) for (let i = 2; i < N; i++) {
      const q = i + W * j;
      const cx = 0.5 * (Math.abs(curl[q + 1]) - Math.abs(curl[q - 1])), cy = 0.5 * (Math.abs(curl[q + W]) - Math.abs(curl[q - W])), len = Math.hypot(cx, cy) + 1e-5, c = curl[q] * 4.6 * dt;
      // confinamento de vorticidade + expansão térmica + vento + atrito
      u[q] = (u[q] + (cy / len) * c - kT * 0.5 * (T[q + 1] - T[q - 1]) + (wx - u[q]) * 0.12 * dt) * damp;
      v[q] = (v[q] - (cx / len) * c - kT * 0.5 * (T[q + W] - T[q - W]) + (wy - v[q]) * 0.12 * dt) * damp;
    }
    // ---- advecção da velocidade e projeção (fluido incompressível, bordas abertas) ----
    advect(u0, u, u, v, dt, s); advect(v0, v, u, v, dt, s);
    [u, u0] = [u0, u]; [v, v0] = [v0, v];
    for (let j = 1; j <= N; j++) for (let i = 1; i <= N; i++) { const q = i + W * j; div[q] = -0.5 * (u[q + 1] - u[q - 1] + v[q + W] - v[q - W]); p[q] = 0; }
    for (let k = 0; k < 14; k++) for (let j = 1; j <= N; j++) for (let i = 1; i <= N; i++) { const q = i + W * j; p[q] = (div[q] + p[q - 1] + p[q + 1] + p[q - W] + p[q + W]) * 0.25; }
    for (let j = 1; j <= N; j++) for (let i = 1; i <= N; i++) { const q = i + W * j; u[q] -= 0.5 * (p[q + 1] - p[q - 1]); v[q] -= 0.5 * (p[q + W] - p[q - W]); }
    // ---- advecção da fumaça e do calor, dissipação ----
    advect(d0, d, u, v, dt, s); advect(T0, T, u, v, dt, s);
    [d, d0] = [d0, d]; [T, T0] = [T0, T];
    const cool = Math.exp(-dt * 1.15), kIn = ending ? 1.6 : 0.05, kOut = ending ? 2.4 : 1.05;
    let sum = 0;
    for (let j = 1; j <= N; j++) {
      const ej = s.edge[j];
      for (let i = 1; i <= N; i++) {
        const q = i + W * j, m = mask[q];
        d[q] *= Math.exp(-dt * (kOut + (kIn - kOut) * m)) * (1 - (1 - ej * s.edge[i]) * Math.min(1, dt * 9));
        T[q] *= cool;
        if (m > 0.7) sum += d[q];
      }
    }
    s.mean = sum / s.inside.length;
    let sp = 0; for (const q of s.inside) sp += Math.hypot(u[q], v[q]); s.speed = sp / s.inside.length;
    s.gain = clamp(s.gain + (0.8 - s.mean) * dt * 1.4, 0.15, 3.5); // mantém o território coberto
    Object.assign(s, { u, v, u0, v0, d, d0, T, T0 });
    particles(dt);
  }

  // velocidade do fluido num ponto (para as partículas)
  let su = 0, sv = 0, sd = 0;
  function sample(x, y) {
    const { N, W, u, v, d } = S;
    x = clamp(x, 1, N); y = clamp(y, 1, N);
    const i0 = x | 0, j0 = y | 0, fx = x - i0, fy = y - j0, a = i0 + W * j0, w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
    su = u[a] * w00 + u[a + 1] * w10 + u[a + W] * w01 + u[a + W + 1] * w11;
    sv = v[a] * w00 + v[a + 1] * w10 + v[a + W] * w01 + v[a + W + 1] * w11;
    sd = d[a] * w00 + d[a + 1] * w10 + d[a + W] * w01 + d[a + W + 1] * w11;
  }
  function particles(dt) {
    const s = S, { N } = s;
    // poeira luminosa: segue o escoamento
    if (s.motes.length < 70 && s.ending < 0 && s.mean > 0.15) { const [x, y] = s.pick(); s.motes.push({ x: x + rand(-1, 1), y: y + rand(-1, 1), l: 0, ml: rand(2.5, 6), s: rand(0.7, 1.9), ph: rand(0, 6.28) }); }
    for (let k = s.motes.length - 1; k >= 0; k--) {
      const m = s.motes[k];
      sample(m.x, m.y);
      m.x += (su + rand(-1.6, 1.6)) * dt; m.y += (sv + rand(-1.6, 1.6)) * dt; m.l += dt;
      if (m.l > m.ml || m.x < 1 || m.y < 1 || m.x > N || m.y > N) s.motes.splice(k, 1);
    }
    // fagulhas e brasas: saem em linha reta, perdem velocidade e passam a ser levadas pela fumaça
    for (let k = s.sparks.length - 1; k >= 0; k--) {
      const q = s.sparks[k];
      sample(q.x, q.y);
      const dr = Math.exp(-dt * q.drag);
      q.vx = q.vx * dr + (su - q.vx) * 0.9 * dt; q.vy = q.vy * dr + (sv - q.vy) * 0.9 * dt;
      q.px = q.x; q.py = q.y; q.x += q.vx * dt; q.y += q.vy * dt; q.l += dt;
      if (q.l > q.ml) s.sparks.splice(k, 1);
    }
    // descargas elétricas dentro da nuvem
    for (let k = s.arcs.length - 1; k >= 0; k--) { s.arcs[k].l += dt; if (s.arcs[k].l > s.arcs[k].ml) s.arcs.splice(k, 1); }
    s.nextArc -= dt;
    if (s.nextArc <= 0 && s.ending < 0) {
      s.nextArc = rand(0.9, 3.4);
      const [x, y] = s.pick(); sample(x, y);
      if (sd > 0.35) {
        const a = rand(0, 6.28), len = rand(5, 12) * (N / 72);
        let pts = [[x, y], [x + Math.cos(a) * len, y + Math.sin(a) * len]];
        for (let lv = 0, off = len * 0.28; lv < 4; lv++, off *= 0.55) { const nx = []; for (let i = 0; i < pts.length - 1; i++) { const [ax, ay] = pts[i], [bx, by] = pts[i + 1]; nx.push(pts[i], [(ax + bx) / 2 + rand(-off, off), (ay + by) / 2 + rand(-off, off)]); } nx.push(pts[pts.length - 1]); pts = nx; }
        s.arcs.push({ pts, l: 0, ml: rand(0.12, 0.22) });
        if (Math.random() < 0.45) { const mid = pts[(pts.length / 2) | 0], b = a + rand(-1.2, 1.2), bl = len * 0.45; s.arcs.push({ pts: [mid, [mid[0] + Math.cos(b) * bl * 0.5 + rand(-1, 1), mid[1] + Math.sin(b) * bl * 0.5 + rand(-1, 1)], [mid[0] + Math.cos(b) * bl, mid[1] + Math.sin(b) * bl]], l: 0, ml: 0.14 }); }
      }
    }
  }

  // ---- desenho ----
  function shade() {
    const s = S, { N, W, M, d, T, u, v, B, TB, maskM } = s, data = s.img.data, sc = N / M;
    // ruído arrastado pelo escoamento em duas fases defasadas, para o detalhe se mover junto com a fumaça sem esticar
    const cyc = s.time * 0.42, ph0 = cyc - Math.floor(cyc), ph1 = ph0 + 0.5 - Math.floor(ph0 + 0.5), wB = Math.abs(1 - 2 * ph0), wA = 1 - wB;
    const F = 190 / M, K = 1.5 * (72 / N), drift = s.time * 3.2, F2 = 70 / M;
    for (let py = 0; py < M; py++) {
      const gy = (py + 0.5) * sc + 0.5, j0 = gy | 0, fy = gy - j0, r0 = j0 * W;
      for (let px = 0; px < M; px++) {
        const gx = (px + 0.5) * sc + 0.5, i0 = gx | 0, fx = gx - i0, a = r0 + i0;
        const w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
        const dd = d[a] * w00 + d[a + 1] * w10 + d[a + W] * w01 + d[a + W + 1] * w11, k = py * M + px;
        TB[k] = T[a] * w00 + T[a + 1] * w10 + T[a + W] * w01 + T[a + W + 1] * w11;
        if (dd < 0.004) { B[k] = 0; continue; }
        const uu = (u[a] * w00 + u[a + 1] * w10 + u[a + W] * w01 + u[a + W + 1] * w11) * K, vv = (v[a] * w00 + v[a + 1] * w10 + v[a + W] * w01 + v[a + W + 1] * w11) * K;
        const bx = px * F, by = py * F;
        const det = nz(nzA, bx - uu * ph0, by - vv * ph0) * wA + nz(nzA, bx - uu * ph1 + 97.3, by - vv * ph1 + 41.7) * wB;
        const big = nz(nzB, px * F2 + drift, py * F2 - drift * 0.6);
        const val = dd * (0.3 + 1.45 * det) * (0.7 + 0.6 * big) - 0.05;
        B[k] = val > 0 ? val : 0;
      }
    }
    const relief = 5.2, G = s.ground;
    for (let py = 0; py < M; py++) {
      const yu = py ? -M : 0, yd = py < M - 1 ? M : 0;
      for (let px = 0; px < M; px++) {
        const k = py * M + px, o = k * 4, den = B[k], tt = TB[k], gm = maskM[k];
        if (den <= 0 && tt < 0.02 && gm < 0.02) { data[o + 3] = 0; continue; }
        // relevo: a densidade faz o papel de altura; luz vindo de cima à esquerda
        const gx = (B[k + (px < M - 1 ? 1 : 0)] - B[k - (px ? 1 : 0)]) * relief, gy = (B[k + yd] - B[k + yu]) * relief;
        let lit = (gx * 0.5 + gy * 0.62 + 0.6) / Math.sqrt(gx * gx + gy * gy + 1);
        lit = lit < 0 ? 0 : lit > 1 ? 1 : lit;
        const thick = Math.exp(-den * 0.55); // fumaça espessa absorve a luz
        const l2 = lit * lit, sh = (0.25 + 0.75 * lit) * (0.45 + 0.55 * thick);
        let r = 8 + 52 * sh + 112 * l2 * lit, g = 28 + 164 * sh + 62 * l2 * lit, b = 12 + 40 * sh + 66 * l2 * lit;
        let al = 1 - Math.exp(-den * 2.1); if (al > 0.95) al = 0.95;
        // por baixo da fumaça: o chão do território escurecido e manchas quentes de radiação que pulsam, cada uma no seu ritmo
        if (gm > 0.02) {
          const n = G[k], hot = n > 0.52 ? (n > 0.8 ? 1 : (n - 0.52) / 0.28) : 0;
          const e = gm * Math.exp(-den * 1.6) * hot * hot * (0.3 + 0.22 * Math.sin(s.time * 1.9 + n * 23)), ua = 0.26 * gm, k1 = 1 - al;
          const pa = ua + e * (1 - ua), na = al + pa * k1;
          r = (r * al + (5 * ua + 80 * e) * k1) / na; g = (g * al + (16 * ua + 255 * e) * k1) / na; b = (b * al + (9 * ua + 100 * e) * k1) / na; al = na;
        }
        if (tt > 0.02) { // fogo: do vermelho escuro ao branco, como um corpo negro
          const h = tt > 1.6 ? 1.6 : tt, e = h * h * 0.7;
          r += 255 * (h * 1.5); g += 255 * (e * 0.95 + (h > 1 ? (h - 1) * 0.8 : 0)); b += 255 * (h > 0.9 ? (h - 0.9) * 1.1 : 0) + 40 * e;
          const fa = h * 1.25; if (fa > al) al = fa > 1 ? 1 : fa;
        }
        data[o] = r > 255 ? 255 : r; data[o + 1] = g > 255 ? 255 : g; data[o + 2] = b > 255 ? 255 : b; data[o + 3] = al * 255;
      }
    }
    octx.putImageData(s.img, 0, 0);
  }

  function draw() {
    const s = S, { N } = s, k = P / N, X = (gx) => (gx - 0.5) * k, lw = P / 448;
    shade();
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, P, P);
    const fade = s.ending >= 0 ? clamp(1 - (s.time - s.ending) / 2.6, 0, 1) : 1;
    // chão queimado e rachaduras incandescentes
    const gzx = X(s.gx), gzy = X(s.gy), R = s.reach * k, heat = s.det >= 0 ? clamp(1 - (s.age - 0.4) / 5, 0, 1) : 0;
    const sg = ctx.createRadialGradient(gzx, gzy, 0, gzx, gzy, R * 0.95);
    sg.addColorStop(0, `rgba(4,7,5,${0.62 * fade})`); sg.addColorStop(0.55, `rgba(6,12,8,${0.34 * fade})`); sg.addColorStop(1, 'rgba(6,12,8,0)');
    ctx.fillStyle = sg; ctx.fillRect(gzx - R, gzy - R, R * 2, R * 2);
    ctx.lineCap = ctx.lineJoin = 'round';
    const cp = 0.5 + 0.5 * Math.sin(s.time * 3.1);
    for (const pass of [[5, 0.16], [1.6, 0.85]]) {
      ctx.lineWidth = pass[0] * lw;
      ctx.strokeStyle = `rgba(${Math.round(110 + 145 * heat)},${Math.round(255 - 95 * heat)},${Math.round(90 - 50 * heat)},${pass[1] * fade * (0.45 + 0.3 * cp + 0.25 * heat)})`;
      ctx.beginPath();
      for (const pts of s.cracks) { ctx.moveTo(X(pts[0][0]), X(pts[0][1])); for (let i = 1; i < pts.length; i++) ctx.lineTo(X(pts[i][0]), X(pts[i][1])); }
      ctx.stroke();
    }
    // a fumaça, ampliada com suavização, e um halo de brilho feito com a própria imagem em baixa resolução
    ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
    ctx.globalAlpha = fade; ctx.drawImage(off, 0, 0, P, P);
    tctx.clearRect(0, 0, tiny.width, tiny.height); tctx.drawImage(off, 0, 0, tiny.width, tiny.height);
    ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = 0.28 * fade; ctx.drawImage(tiny, 0, 0, P, P);
    // partículas
    for (const m of s.motes) { const e = Math.sin(Math.PI * m.l / m.ml), a = e * (0.45 + 0.55 * Math.sin(s.time * 7 + m.ph)) * fade; if (a <= 0.02) continue; const z = m.s * 3.4 * lw; ctx.globalAlpha = a > 1 ? 1 : a; ctx.drawImage(mote, X(m.x) - z, X(m.y) - z, z * 2, z * 2); }
    for (const q of s.sparks) {
      const h = 1 - q.l / q.ml;
      if (q.emb) { const z = (2.2 + 2.6 * h) * lw; ctx.globalAlpha = clamp(h * 1.6, 0, 1) * (0.6 + 0.4 * Math.sin(s.time * 20 + q.ml * 9)); ctx.drawImage(h > 0.35 ? ember : mote, X(q.x) - z, X(q.y) - z, z * 2, z * 2); continue; }
      ctx.globalAlpha = clamp(h * 1.7, 0, 1); ctx.lineWidth = (0.7 + 1.5 * h) * lw;
      ctx.strokeStyle = h > 0.7 ? '#fff6d8' : h > 0.42 ? '#ffc24d' : h > 0.18 ? '#ff6d1f' : '#b3260e';
      ctx.beginPath(); ctx.moveTo(X(q.px), X(q.py)); ctx.lineTo(X(q.x), X(q.y)); ctx.stroke();
    }
    for (const a of s.arcs) {
      const f = (1 - a.l / a.ml) * (0.55 + 0.45 * Math.random()) * fade;
      for (const pass of [[7, 0.22, '120,255,120'], [2.6, 0.5, '170,255,160'], [1, 1, '240,255,235']]) {
        ctx.globalAlpha = f * pass[1]; ctx.lineWidth = pass[0] * lw; ctx.strokeStyle = `rgb(${pass[2]})`;
        ctx.beginPath(); ctx.moveTo(X(a.pts[0][0]), X(a.pts[0][1])); for (let i = 1; i < a.pts.length; i++) ctx.lineTo(X(a.pts[i][0]), X(a.pts[i][1])); ctx.stroke();
      }
      const m = a.pts[(a.pts.length / 2) | 0], z = 26 * lw; ctx.globalAlpha = f * 0.5; ctx.drawImage(mote, X(m[0]) - z, X(m[1]) - z, z * 2, z * 2);
    }
    if (s.det >= 0) {
      const t = s.age;
      if (t < 0.95) { // onda de choque: frente clara e fina, com um rastro mais largo
        const rr = (4 + 62 * t) * (N / 72) * k, q = 1 - t / 0.95;
        ctx.globalAlpha = 0.5 * q; ctx.lineWidth = (2 + 16 * q) * lw; ctx.strokeStyle = '#d9ffc4'; ctx.beginPath(); ctx.arc(gzx, gzy, rr, 0, 6.2832); ctx.stroke();
        ctx.globalAlpha = 0.9 * q; ctx.lineWidth = 1.6 * lw; ctx.strokeStyle = '#ffffff'; ctx.beginPath(); ctx.arc(gzx, gzy, rr + (1 + 8 * q) * lw, 0, 6.2832); ctx.stroke();
      }
      if (t < 0.5) { // clarão no ponto de impacto
        const q = 1 - t / 0.5, rr = P * (0.1 + 0.75 * t), fg = ctx.createRadialGradient(gzx, gzy, 0, gzx, gzy, rr);
        fg.addColorStop(0, 'rgba(255,255,255,1)'); fg.addColorStop(0.3, 'rgba(255,244,200,.8)'); fg.addColorStop(1, 'rgba(255,200,120,0)');
        ctx.globalAlpha = q * q; ctx.fillStyle = fg; ctx.fillRect(gzx - rr, gzy - rr, rr * 2, rr * 2);
      }
    }
    ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
  }

  function place() {
    if (!S || !cam) return;
    const px = S.size * cam.z, left = (S.ox - cam.x) * cam.z, top = (S.oy - cam.y) * cam.z;
    canvas.style.left = left + 'px'; canvas.style.top = top + 'px'; canvas.style.width = canvas.style.height = px + 'px';
    hiddenBox = left > cam.w || top > cam.h || left + px < 0 || top + px < 0;
    const need = px * Math.min(window.devicePixelRatio || 1, 2), want = need <= 380 ? 320 : need <= 620 ? 448 : 640;
    if (want !== P) { P = want; canvas.width = canvas.height = P; if (S && !raf) draw(); }
  }
  function setQuality(q) {
    quality = q;
    const [N, M] = QUALITY[q];
    off.width = off.height = M; tiny.width = tiny.height = Math.round(M / 5);
    S = build(S.cfg, N, M, S);
  }
  function loop(now) {
    raf = requestAnimationFrame(loop);
    if (!S) return;
    // passo fixo pelo relógio (não pela taxa da tela): a explosão a 60 por segundo, a névoa parada a 30 (ou 20 em aparelho fraco)
    const fast = (S.det >= 0 && S.age < 5.5) || S.ending >= 0, dt = fast ? 1 / 60 : quality === 2 ? 1 / 20 : 1 / 30;
    acc += Math.min(0.1, (now - (last || now)) / 1000); last = now;
    if (acc < dt || (hiddenBox && !fast)) return; // fora da tela, a névoa fica parada (poupa bateria)
    acc = acc > 2 * dt ? 0 : acc - dt;
    const t0 = performance.now();
    step(dt);
    if (!hiddenBox) draw();
    cost += (performance.now() - t0 - cost) * 0.08;
    if (cost > (fast ? 12 : 14)) { if (++slow > 45 && quality < QUALITY.length - 1) { slow = 0; cost = 0; setQuality(quality + 1); } } else slow = 0;
    if (S.ending >= 0 && S.time - S.ending > 2.6) kill();
  }
  function kill() { cancelAnimationFrame(raf); raf = 0; S = null; canvas.hidden = true; }

  return {
    get active() { return !!S; },
    get stats() { return S ? { quality, cost: +cost.toFixed(2), N: S.N, M: S.M, P, mean: +S.mean.toFixed(2), speed: +(S.speed || 0).toFixed(1), age: +S.age.toFixed(1), motes: S.motes.length, sparks: S.sparks.length, arcs: S.arcs.length } : null; },
    // cfg: { path, bbox:{x,y,width,height}, cx, cy, detonate } em unidades do mapa
    start(cfg) {
      cancelAnimationFrame(raf); raf = 0;
      const b = cfg.bbox, size = Math.max(b.width, b.height) + 2 * MARGIN;
      const c = { path: cfg.path, cx: cfg.cx, cy: cfg.cy, detonate: !!cfg.detonate && !still, size, ox: b.x + b.width / 2 - size / 2, oy: b.y + b.height / 2 - size / 2 };
      const [N, M] = QUALITY[quality];
      off.width = off.height = M; tiny.width = tiny.height = Math.round(M / 5);
      S = build(c, N, M, null);
      canvas.hidden = false; P = 0; place();
      if (c.detonate) {
        const s = S, sc = N / 72;
        gauss(s, s.T, s.gx, s.gy, 3.6 * sc, 3.4); gauss(s, s.d, s.gx, s.gy, 4 * sc, 1.7); radial(s, s.gx, s.gy, 7 * sc, 78 * sc);
        for (let k = 0; k < 150; k++) { const a = rand(0, 6.28), sp = rand(22, 125) * sc; s.sparks.push({ x: s.gx, y: s.gy, px: s.gx, py: s.gy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, l: 0, ml: rand(0.35, 1.3), drag: rand(2, 3.6) }); }
        for (let k = 0; k < 46; k++) { const a = rand(0, 6.28), sp = rand(6, 40) * sc; s.sparks.push({ x: s.gx, y: s.gy, px: s.gx, py: s.gy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, l: 0, ml: rand(1.8, 4.6), drag: rand(1.2, 2.2), emb: true }); }
      } else for (let k = 0; k < 90; k++) step(1 / 20); // já havia névoa (página recarregada, quem entrou depois): começa formada
      draw();
      acc = 0; last = 0;
      if (!still) raf = requestAnimationFrame(loop);
    },
    // a névoa se desfaz em vez de sumir de uma vez
    stop(now) { if (!S) return; if (now || still || !raf) return kill(); if (S.ending < 0) S.ending = S.time; },
    // câmera do mapa: canto superior esquerdo (unidades do mapa), zoom (px por unidade) e tamanho visível em px
    view(x, y, z, w, h) { cam = { x, y, z, w, h }; place(); },
    // um toque na nuvem: um sopro que abre a fumaça por um instante
    poke(mx, my) {
      if (!S || still) return;
      const gx = ((mx - S.ox) / S.size) * S.N + 0.5, gy = ((my - S.oy) / S.size) * S.N + 0.5, sc = S.N / 72;
      radial(S, gx, gy, 4 * sc, 30 * sc); S.nextArc = Math.min(S.nextArc, 0.12);
    },
  };
}
