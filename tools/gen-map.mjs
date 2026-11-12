// Gera js/map.js a partir do Natural Earth 1:110m (domínio público), via world-atlas.
// Uso: npm i --no-save topojson-client world-atlas && node tools/gen-map.mjs
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const topojson = require('topojson-client');
const topo = require('world-atlas/countries-110m.json');

const W = 1400, LON0 = -169.5, LAT_TOP = 75.5, LAT_BOT = -56;
const merc = (lat) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
const K = W / (2 * Math.PI), H0 = (merc(LAT_TOP) - merc(LAT_BOT)) * K;
const flat = ([lon, lat]) => {
  if (lon < LON0) lon += 360;
  lat = Math.max(LAT_BOT, Math.min(LAT_TOP, lat));
  return [((lon - LON0) / 360) * W, (merc(LAT_TOP) - merc(lat)) * K];
};
// O mapa não é fiel em tamanho, de propósito: "lentes" ampliam regiões de territórios pequenos
// (Europa, América Central, ilhas da Ásia e da Oceania) para ficarem fáceis de ver e tocar.
// Cada lente é uma ampliação radial suave, que preserva vizinhanças. [lon, lat, raio em px, ganho]
const LENSES = [[12, 49, 95, 0.65], [-84, 15, 55, 0.75], [118, 2, 90, 0.55], [146, -6, 36, 0.5], [137, 37, 42, 0.65], [172, -41, 42, 0.95]];
const lens = (p, c, sigma, a) => {
  const dx = p[0] - c[0], dy = p[1] - c[1], m = 1 + a * Math.exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
  return [c[0] + dx * m, c[1] + dy * m];
};
const lensCenters = [];
const warp = (p, upTo = LENSES.length) => { for (let i = 0; i < upTo; i++) p = lens(p, lensCenters[i], LENSES[i][2], LENSES[i][3]); return p; };
LENSES.forEach(([lon, lat], i) => lensCenters.push(warp(flat([lon, lat]), i)));
// Inclinação do tabuleiro embutida na geometria: o mapa é achatado na vertical (SQUASH), como visto de cima em ângulo.
// PERSP > 0 faria as linhas convergirem para o norte; fica em 0 porque, com zoom numa lateral, a convergência parecia torta.
const PERSP = 0, SQUASH = 0.9, S_TOP = 1 / (1 + PERSP / 2), S_BOT = 1 / (1 - PERSP / 2);
const MAPW = Math.round(W * S_BOT), H = Math.round((H0 / 2) * SQUASH * (S_TOP + S_BOT));
const proj = (ll) => {
  const [x, y] = warp(flat(ll));
  const sc = 1 / (1 + PERSP * (0.5 - y / H0));
  return [MAPW / 2 + (x - W / 2) * sc, (H0 / 2) * SQUASH * S_TOP + (y - H0 / 2) * SQUASH * sc];
};

const CONT = [
  { n: 'América do Norte', bonus: 5, color: '#f0d9a0', at: [-146, 27] },
  { n: 'América do Sul', bonus: 2, color: '#a8e0b0', at: [-104, -28] },
  { n: 'Europa', bonus: 5, color: '#a9d4f5', at: [-24, 47] },
  { n: 'África', bonus: 3, color: '#f2b08c', at: [-10, -14] },
  { n: 'Ásia', bonus: 7, color: '#f0b0cf', at: [74, -4] },
  { n: 'Oceania', bonus: 2, color: '#c9c0f5', at: [128, -46] },
];
// chave: [nome, continente, rótulo lon, lat]
const T = {
  ala: ['Alasca', 0, -152, 65], cao: ['Canadá Oeste', 0, -123, 59], cac: ['Canadá Central', 0, -98, 57], cal: ['Canadá Leste', 0, -73, 53], gro: ['Groenlândia', 0, -42, 69],
  euo: ['EUA Oeste', 0, -112, 41], eul: ['EUA Leste', 0, -86, 37], mex: ['México', 0, -102, 24], cam: ['América Central', 0, -86, 14],
  col: ['Colômbia', 1, -69, 6], and: ['Peru e Chile', 1, -74.5, -11], bra: ['Brasil', 1, -52, -10], arg: ['Argentina', 1, -64, -34],
  bri: ['Reino Unido', 2, -2, 54], esc: ['Escandinávia', 2, 15, 63], fra: ['Europa Ocidental', 2, 1, 45], euc: ['Europa Central', 2, 12.5, 51.5],
  ita: ['Itália e Bálcãs', 2, 20.5, 43.5], eor: ['Ucrânia', 2, 31, 50], rus: ['Rússia', 2, 45, 57],
  mag: ['Magrebe', 3, 3, 29], egi: ['Egito', 3, 30, 22], afo: ['África Ocidental', 3, -3, 13], afc: ['Congo', 3, 20, 2], afl: ['África Oriental', 3, 38, 3],
  afa: ['África Austral', 3, 24, -20],
  tur: ['Turquia', 4, 36, 39.5], ara: ['Arábia', 4, 45, 24], ira: ['Irã', 4, 60, 31], asc: ['Cazaquistão', 4, 66, 46], ind: ['Índia', 4, 79, 22],
  sib: ['Sibéria', 4, 92, 63], ext: ['Extremo Oriente', 4, 140, 63], mon: ['Mongólia', 4, 104, 47], cho: ['China Ocidental', 4, 88, 36], chl: ['China', 4, 113, 31],
  cor: ['Japão e Coreia', 4, 138.5, 36.5], sea: ['Sudeste Asiático', 4, 102, 16],
  ins: ['Indonésia', 5, 114, 0], ngu: ['Nova Guiné', 5, 144, -6], aus: ['Austrália', 5, 134, -25], nze: ['Nova Zelândia', 5, 172, -42],
};
const whole = {
  gro: 'Greenland', mex: 'Mexico',
  cam: 'Guatemala;Belize;Honduras;El Salvador;Nicaragua;Costa Rica;Panama;Cuba;Haiti;Dominican Rep.;Jamaica;Bahamas;Puerto Rico;Trinidad and Tobago',
  col: 'Colombia;Venezuela;Guyana;Suriname', and: 'Ecuador;Peru;Bolivia;Chile', bra: 'Brazil', arg: 'Argentina;Uruguay;Paraguay;Falkland Is.',
  bri: 'United Kingdom;Ireland', esc: 'Sweden;Finland;Denmark;Iceland', fra: 'Spain;Portugal;Belgium;Netherlands;Luxembourg;Switzerland',
  euc: 'Germany;Poland;Czechia;Austria;Slovakia;Hungary',
  ita: 'Italy;Slovenia;Croatia;Bosnia and Herz.;Serbia;Montenegro;Kosovo;Albania;Macedonia;Greece;Bulgaria;Romania',
  eor: 'Ukraine;Belarus;Moldova;Lithuania;Latvia;Estonia',
  mag: 'Morocco;W. Sahara;Algeria;Tunisia;Libya', egi: 'Egypt;Sudan;S. Sudan',
  afo: "Mauritania;Mali;Niger;Senegal;Gambia;Guinea-Bissau;Guinea;Sierra Leone;Liberia;Côte d'Ivoire;Ghana;Togo;Benin;Burkina Faso;Nigeria",
  afc: 'Chad;Cameroon;Central African Rep.;Eq. Guinea;Gabon;Congo;Dem. Rep. Congo',
  afl: 'Ethiopia;Eritrea;Djibouti;Somalia;Somaliland;Kenya;Uganda;Tanzania;Rwanda;Burundi',
  afa: 'Angola;Zambia;Malawi;Mozambique;Zimbabwe;Namibia;Botswana;South Africa;Lesotho;eSwatini;Madagascar',
  tur: 'Turkey;Cyprus;N. Cyprus;Georgia;Armenia;Azerbaijan',
  ara: 'Saudi Arabia;Yemen;Oman;United Arab Emirates;Qatar;Kuwait;Jordan;Israel;Palestine;Lebanon;Syria;Iraq',
  ira: 'Iran;Afghanistan;Pakistan', asc: 'Kazakhstan;Uzbekistan;Turkmenistan;Kyrgyzstan;Tajikistan', ind: 'India;Nepal;Bhutan;Bangladesh;Sri Lanka',
  mon: 'Mongolia', chl: 'Taiwan', cor: 'Japan;North Korea;South Korea', sea: 'Myanmar;Thailand;Laos;Cambodia;Vietnam',
  ins: 'Indonesia;Brunei;Timor-Leste;Philippines', ngu: 'Papua New Guinea;Solomon Is.', aus: 'Australia', nze: 'New Zealand;New Caledonia;Vanuatu;Fiji',
};
// países divididos entre territórios (Voronoi pelos rótulos) e regras por polígono
const split = { 'United States of America': ['euo', 'eul'], Canada: ['cao', 'cac', 'cal'], Russia: ['rus', 'sib', 'ext'], China: ['cho', 'chl'] };
const perPoly = {
  France: ([lon]) => (lon < -40 ? 'col' : 'fra'),
  Malaysia: ([lon]) => (lon > 108 ? 'ins' : 'sea'),
  Norway: ([, lat]) => (lat > 73 ? null : 'esc'),
};
const dropPoly = {
  'United States of America': ([lon, lat]) => lon < -150 && lat < 30, // Havaí
  Russia: ([lon, lat]) => lon > 18 && lon < 24 && lat < 56, // Kaliningrado
};
// polígonos inteiros de um país dividido que vão direto para um território
const splitWhole = { 'United States of America': ([, lat]) => (lat > 50 ? 'ala' : null) };
// sementes do corte quando diferem do rótulo
const SEED = {};
const DROP = new Set(['Antarctica', 'Fr. S. Antarctic Lands']);
// fronteiras: terrestres e rotas marítimas (~)
const EDGES = `ala-cao ala~ext cao-cac cac-cal cao-euo cac-euo cac-eul cal-eul cal~gro gro~esc euo-eul euo-mex eul~cam mex-cam cam-col
col-and col-bra and-bra and-arg bra-arg bra~afo
bri~esc bri~fra esc-euc esc-rus esc~eor fra-euc fra-ita fra~mag euc-ita euc-eor ita-eor ita-tur ita~mag eor-rus rus-tur rus-asc rus-sib
mag-egi mag-afo mag-afc egi-afc egi-afl egi-ara afo-afc afc-afl afc-afa afl-afa afl~ara
tur-ara tur-ira ara-ira ira-asc ira-ind ira-cho asc-sib asc-cho ind-cho ind-sea sib-mon sib-cho sib-ext ext-mon ext-chl ext~cor mon-cho mon-chl cho-chl cho-sea chl-sea chl-cor
sea~ins cor~ins ins-ngu ins~aus ngu~aus ngu~nze aus~nze`.split(/\s+/);

const keys = Object.keys(T), idx = Object.fromEntries(keys.map((k, i) => [k, i]));
const byName = {};
for (const [k, names] of Object.entries(whole)) for (const n of names.split(';')) byName[n] = k;
const centroidLL = (ring) => { let x = 0, y = 0; for (const [a, b] of ring) { x += a < LON0 ? a + 360 : a; y += b; } return [x / ring.length, y / ring.length]; };
const groups = Object.fromEntries(keys.map((k) => [k, { arcs: [], rings: [] }]));
const unassigned = [];
for (const g of topo.objects.countries.geometries) {
  const name = g.properties.name;
  if (DROP.has(name)) continue;
  const polys = g.type === 'Polygon' ? [g.arcs] : g.arcs;
  for (const arcs of polys) {
    const outer = topojson.feature(topo, { type: 'Polygon', arcs }).geometry.coordinates[0];
    const c = centroidLL(outer);
    if (dropPoly[name] && dropPoly[name](c)) continue;
    if (split[name]) {
      const ring = outer.map(proj);
      const xs = ring.map((p) => p[0]);
      if (Math.max(...xs) - Math.min(...xs) > W / 2) continue; // ilha partida pela borda do mapa
      const direct = splitWhole[name] && splitWhole[name](c);
      if (direct) { groups[direct].rings.push(ring); continue; }
      const seeds = split[name].map((k) => proj(SEED[k] || [T[k][2], T[k][3]]));
      split[name].forEach((k, i) => {
        let r = ring;
        seeds.forEach((s, j) => { if (j !== i && r.length) r = clipHalf(r, seeds[i], s); });
        if (r.length >= 3) groups[k].rings.push(r);
      });
      continue;
    }
    const k = perPoly[name] ? perPoly[name](c) : byName[name];
    if (k === null) continue;
    if (!k) { unassigned.push(name); continue; }
    groups[k].arcs.push({ type: 'Polygon', arcs });
  }
}
if (unassigned.length) console.warn('SEM TERRITÓRIO:', [...new Set(unassigned)].join(', '));

// Sutherland–Hodgman: mantém o lado mais próximo de a do que de b
function clipHalf(ring, a, b) {
  const nx = b[0] - a[0], ny = b[1] - a[1], mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
  const side = (p) => (p[0] - mx) * nx + (p[1] - my) * ny; // <= 0 fica
  const out = [];
  for (let i = 0; i < ring.length; i++) {
    const p = ring[i], q = ring[(i + 1) % ring.length], sp = side(p), sq = side(q);
    if (sp <= 0) out.push(p);
    if ((sp < 0 && sq > 0) || (sp > 0 && sq < 0)) { const t = sp / (sp - sq); out.push([p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]); }
  }
  return out;
}
const area = (r) => Math.abs(r.reduce((s, p, i) => { const q = r[(i + 1) % r.length]; return s + p[0] * q[1] - q[0] * p[1]; }, 0) / 2);
const f1 = (v) => +v.toFixed(1);
const keep = (ring) => { const xs = ring.map((p) => p[0]); return Math.max(...xs) - Math.min(...xs) <= W / 2 && area(ring) >= 9; };
function toPath(rings) {
  let d = '';
  for (const ring of rings) {
    if (!keep(ring)) continue;
    let last = '';
    const pts = [];
    for (const p of ring) { const s = `${f1(p[0])},${f1(p[1])}`; if (s !== last) pts.push(s); last = s; }
    if (pts.length > 1 && pts[0] === pts[pts.length - 1]) pts.pop();
    // remove "espinhos" de largura zero (vai e volta pelo mesmo ponto), que sobram dos cortes e da união
    for (let i = 0, n = 0; pts.length >= 3 && n < pts.length;) {
      const prev = pts[(i - 1 + pts.length) % pts.length], next = pts[(i + 1) % pts.length];
      if (prev === next) { pts.splice(i, 1); pts.splice(i % pts.length, 1); i = Math.max(0, i - 1); n = 0; }
      else { i = (i + 1) % pts.length; n++; }
    }
    if (pts.length >= 3) d += 'M' + pts.join('L') + 'Z';
  }
  return d;
}
// ---- formas simplificadas ----
// O mapa é desenhado numa grade e redesenhado a partir dela. Na grade, cada território passa por um
// "fechamento" (cresce e encolhe de volta): ilhas próximas se fundem, baías estreitas e buracos somem.
// Depois, ilhotas são descartadas e as fronteiras são retraçadas e suavizadas, sempre iguais dos dois lados.
const CLOSE = { ins: 17, nze: 15, cor: 12, cam: 12, ngu: 11, bri: 9, cao: 9, cac: 9, cal: 9, esc: 7, ext: 7, sea: 7, ita: 6, gro: 5, ala: 5 };
const S = 2, GW = Math.ceil(MAPW * S), GH = Math.ceil(H * S), EPS = 2.6; // células por unidade; tolerância da suavização (células)
const own = new Int16Array(GW * GH).fill(-1);
function fillRing(ring, label) {
  let y0 = Infinity, y1 = -Infinity;
  for (const p of ring) { y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); }
  for (let gy = Math.max(0, Math.floor(y0 * S)); gy <= Math.min(GH - 1, Math.ceil(y1 * S)); gy++) {
    const yy = (gy + 0.5) / S, xs = [];
    for (let i = 0; i < ring.length; i++) {
      const a = ring[i], b = ring[(i + 1) % ring.length];
      if ((a[1] > yy) !== (b[1] > yy)) xs.push(a[0] + ((yy - a[1]) / (b[1] - a[1])) * (b[0] - a[0]));
    }
    xs.sort((p, q) => p - q);
    for (let k = 0; k + 1 < xs.length; k += 2)
      for (let gx = Math.max(0, Math.ceil(xs[k] * S - 0.5)); gx <= Math.min(GW - 1, Math.floor(xs[k + 1] * S - 0.5)); gx++)
        if (own[gy * GW + gx] === -1) own[gy * GW + gx] = label;
  }
}
keys.forEach((k, i) => {
  const g = groups[k];
  const rings = [...g.rings];
  if (g.arcs.length) for (const poly of topojson.merge(topo, g.arcs).coordinates) rings.push(poly[0].map(proj)); // só o anel externo
  rings.filter(keep).forEach((r) => fillRing(r, i));
});
// distância aproximada (chanfro 3-4) até as células marcadas em src
function chamfer(src, w, h) {
  const d = new Int32Array(w * h).fill(1e9);
  for (let i = 0; i < w * h; i++) if (src[i]) d[i] = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x; let v = d[i];
    if (x > 0) v = Math.min(v, d[i - 1] + 3);
    if (y > 0) { v = Math.min(v, d[i - w] + 3); if (x > 0) v = Math.min(v, d[i - w - 1] + 4); if (x < w - 1) v = Math.min(v, d[i - w + 1] + 4); }
    d[i] = v;
  }
  for (let y = h - 1; y >= 0; y--) for (let x = w - 1; x >= 0; x--) {
    const i = y * w + x; let v = d[i];
    if (x < w - 1) v = Math.min(v, d[i + 1] + 3);
    if (y < h - 1) { v = Math.min(v, d[i + w] + 3); if (x < w - 1) v = Math.min(v, d[i + w + 1] + 4); if (x > 0) v = Math.min(v, d[i + w - 1] + 4); }
    d[i] = v;
  }
  return d;
}
const bbox = keys.map(() => [GW, GH, -1, -1]);
for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) { const l = own[y * GW + x]; if (l >= 0) { const b = bbox[l]; if (x < b[0]) b[0] = x; if (y < b[1]) b[1] = y; if (x > b[2]) b[2] = x; if (y > b[3]) b[3] = y; } }
const fin = Int16Array.from(own);
const order = keys.map((_, i) => i).sort((a, b) => (CLOSE[keys[a]] || 3.5) - (CLOSE[keys[b]] || 3.5)); // arquipélagos por último: cedem aos vizinhos
for (const i of order) {
  const R = Math.round((CLOSE[keys[i]] || 3.5) * S), pad = R + 3, [bx0, by0, bx1, by1] = bbox[i];
  const wx = bx0 - pad, wy = by0 - pad, w = bx1 - bx0 + 1 + 2 * pad, h = by1 - by0 + 1 + 2 * pad; // a janela pode sair da grade: fora dela é mar
  const A = new Uint8Array(w * h);
  for (let y = by0; y <= by1; y++) for (let x = bx0; x <= bx1; x++) if (own[y * GW + x] === i) A[(y - wy) * w + (x - wx)] = 1;
  const d1 = chamfer(A, w, h), notD = new Uint8Array(w * h);
  for (let k = 0; k < w * h; k++) notD[k] = d1[k] > R * 3 ? 1 : 0;
  const d2 = chamfer(notD, w, h), C = new Uint8Array(w * h);
  for (let k = 0; k < w * h; k++) C[k] = A[k] || d2[k] > R * 3 ? 1 : 0;
  // tapa buracos: tudo o que não é alcançável pela borda da janela
  const seen = new Uint8Array(w * h), st = [];
  for (let x = 0; x < w; x++) st.push(x, (h - 1) * w + x);
  for (let y = 0; y < h; y++) st.push(y * w, y * w + w - 1);
  while (st.length) {
    const k = st.pop();
    if (seen[k] || C[k]) continue;
    seen[k] = 1;
    const x = k % w, y = (k - x) / w;
    if (x > 0) st.push(k - 1); if (x < w - 1) st.push(k + 1); if (y > 0) st.push(k - w); if (y < h - 1) st.push(k + w);
  }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const gx = x + wx, gy = y + wy;
    if (gx < 0 || gy < 0 || gx >= GW || gy >= GH || seen[y * w + x]) continue;
    if (fin[gy * GW + gx] === -1) fin[gy * GW + gx] = i; // só ocupa mar: nunca a terra de outro território
  }
}
// componentes conexos de um predicado; devolve listas de células
function components(test) {
  const mark = new Uint8Array(GW * GH), out = [];
  for (let s0 = 0; s0 < GW * GH; s0++) {
    if (mark[s0] || !test(s0)) continue;
    const cells = [], st = [s0]; mark[s0] = 1;
    while (st.length) {
      const k = st.pop(); cells.push(k);
      const x = k % GW;
      for (const n of [x > 0 ? k - 1 : -1, x < GW - 1 ? k + 1 : -1, k - GW, k + GW]) if (n >= 0 && n < GW * GH && !mark[n] && test(n)) { mark[n] = 1; st.push(n); }
    }
    out.push(cells);
  }
  return out;
}
// ilhotas: de cada território fica só o que tem pelo menos 10% da sua maior parte
keys.forEach((_, i) => {
  const comps = components((k) => fin[k] === i), big = Math.max(...comps.map((c) => c.length));
  for (const c of comps) if (c.length < Math.max(70 * S * S, big * 0.1)) for (const k of c) fin[k] = -1;
});
// lagos pequenos cercados de terra viram terra do vizinho
for (const c of components((k) => fin[k] === -1)) {
  if (c.length >= 700 * S * S) continue;
  let pending = c;
  for (let guard = 0; pending.length && guard < 400; guard++) {
    const next = [], set = [];
    for (const k of pending) {
      const x = k % GW, nb = [x > 0 ? k - 1 : -1, x < GW - 1 ? k + 1 : -1, k - GW, k + GW].find((n) => n >= 0 && n < GW * GH && fin[n] >= 0);
      if (nb === undefined) next.push(k); else set.push(k, fin[nb]);
    }
    if (!set.length) break;
    for (let q = 0; q < set.length; q += 2) fin[set[q]] = set[q + 1];
    pending = next;
  }
}
// ---- da grade de volta para polígonos ----
const at = (x, y) => (x < 0 || y < 0 || x >= GW || y >= GH ? -1 : fin[y * GW + x]);
const VW = GW + 1;
const isJunction = (v) => { const x = v % VW, y = (v - x) / VW; return new Set([at(x - 1, y - 1), at(x, y - 1), at(x - 1, y), at(x, y)]).size >= 3; };
// contornos (sentido horário na tela) de cada rótulo dado por labelOf(célula)
function traceLoops(labelOf, nLabels) {
  const edges = Array.from({ length: nLabels }, () => new Map());
  const add = (l, a, b) => { const m = edges[l]; if (m.has(a)) m.get(a).push(b); else m.set(a, [b]); };
  const lab = (x, y) => (x < 0 || y < 0 || x >= GW || y >= GH ? -1 : labelOf(fin[y * GW + x]));
  for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) {
    const l = lab(x, y);
    if (l < 0) continue;
    const v = y * VW + x;
    if (lab(x, y - 1) !== l) add(l, v, v + 1);
    if (lab(x + 1, y) !== l) add(l, v + 1, v + 1 + VW);
    if (lab(x, y + 1) !== l) add(l, v + 1 + VW, v + VW);
    if (lab(x - 1, y) !== l) add(l, v + VW, v);
  }
  const dirOf = (a, b) => (b === a + 1 ? 0 : b === a + VW ? 1 : b === a - 1 ? 2 : 3);
  return edges.map((m) => {
    const loops = [];
    for (const start of [...m.keys()]) {
      while (m.has(start)) {
        const loop = [start];
        let cur = start, dir = -1;
        for (;;) {
          const outs = m.get(cur);
          let pick = 0;
          if (outs.length > 1 && dir >= 0) { // num ponto de aperto, vira à direita primeiro: mantém as partes separadas
            const pref = [(dir + 1) % 4, dir, (dir + 3) % 4];
            pick = outs.map((b, j) => [pref.indexOf(dirOf(cur, b)), j]).filter((q) => q[0] >= 0).sort((p, q) => p[0] - q[0])[0][1];
          }
          const nxt = outs.splice(pick, 1)[0];
          if (!outs.length) m.delete(cur);
          dir = dirOf(cur, nxt); cur = nxt;
          if (cur === start) break;
          loop.push(cur);
        }
        loops.push(loop);
      }
    }
    return loops;
  });
}
const P = (v) => [v % VW, Math.floor(v / VW)];
function dp(pts, eps) { // Douglas–Peucker, extremos fixos
  const keepIdx = new Uint8Array(pts.length); keepIdx[0] = keepIdx[pts.length - 1] = 1;
  const st = [[0, pts.length - 1]];
  while (st.length) {
    const [a, b] = st.pop();
    const [ax, ay] = pts[a], [bx, by] = pts[b], dx = bx - ax, dy = by - ay, len = Math.hypot(dx, dy) || 1;
    let far = -1, fd = eps;
    for (let i = a + 1; i < b; i++) { const d = len === 1 && !dx && !dy ? Math.hypot(pts[i][0] - ax, pts[i][1] - ay) : Math.abs(dy * (pts[i][0] - ax) - dx * (pts[i][1] - ay)) / len; if (d > fd) { fd = d; far = i; } }
    if (far >= 0) { keepIdx[far] = 1; st.push([a, far], [far, b]); }
  }
  return pts.filter((_, i) => keepIdx[i]);
}
// simplifica um arco sempre no mesmo sentido, para os dois vizinhos chegarem à mesma linha
function arc(vs) {
  const a = vs[0], b = vs[vs.length - 1], flip = a > b || (a === b && vs[1] > vs[vs.length - 2]);
  const pts = (flip ? [...vs].reverse() : vs).map(P), out = dp(pts, EPS);
  return flip ? out.reverse() : out;
}
function simplifyLoop(loop) {
  const jx = []; loop.forEach((v, i) => { if (isJunction(v)) jx.push(i); });
  const out = [];
  if (!jx.length) { // ilha sem vizinhos: começa no menor vértice e corta em dois arcos
    const i0 = loop.indexOf(Math.min(...loop)), r = [...loop.slice(i0), ...loop.slice(0, i0)], mid = r.length >> 1;
    out.push(...arc(r.slice(0, mid + 1)).slice(0, -1), ...arc([...r.slice(mid), r[0]]).slice(0, -1));
  } else for (let q = 0; q < jx.length; q++) {
    const i = jx[q], j = jx[(q + 1) % jx.length];
    const seg = j > i ? loop.slice(i, j + 1) : [...loop.slice(i), ...loop.slice(0, j + 1)];
    out.push(...arc(seg).slice(0, -1));
  }
  return out.map(([x, y]) => [x / S, y / S]);
}
const signed = (r) => r.reduce((s2, p, i) => { const q = r[(i + 1) % r.length]; return s2 + p[0] * q[1] - q[0] * p[1]; }, 0) / 2;
// contornos externos; com lakes=true entram também os mares internos grandes que sobraram (viram furos no preenchimento)
const ringsOf = (loops, lakes) => loops.map(simplifyLoop).filter((r) => r.length >= 3 && (signed(r) > 9 || (lakes && signed(r) < -9)));
const terrLoops = traceLoops((l) => l, keys.length), contLoops = traceLoops((l) => (l < 0 ? -1 : T[keys[l]][1]), CONT.length);
const TERR = keys.map((k, i) => {
  const [x, y] = proj([T[k][2], T[k][3]]);
  return { n: T[k][0], c: T[k][1], x: Math.round(x), y: Math.round(y), d: toPath(ringsOf(terrLoops[i])), adj: [] };
});
// contorno externo de cada continente, feito dos mesmos arcos das fronteiras dos territórios
const outline = contLoops.map((loops) => toPath(ringsOf(loops, true)));
const SEA = [];
for (const e of EDGES) {
  const [a, sep, b] = e.split(/([-~])/);
  if (!(a in idx) || !(b in idx)) throw new Error('fronteira inválida: ' + e);
  TERR[idx[a]].adj.push(idx[b]); TERR[idx[b]].adj.push(idx[a]);
  if (sep === '~') SEA.push(e === 'ala~ext' ? [idx[a], idx[b], 1] : [idx[a], idx[b]]);
}
TERR.forEach((t) => t.adj.sort((a, b) => a - b));
const CONTINENTS = CONT.map((c) => { const [x, y] = proj(c.at); return { n: c.n, bonus: c.bonus, color: c.color, x: Math.round(x), y: Math.round(y), d: outline[CONT.indexOf(c)] }; });
const out = `// Gerado por tools/gen-map.mjs (geografia: Natural Earth, domínio público). Não editar à mão.
export const MAP_W=${MAPW}, MAP_H=${H};
export const CONTINENTS=${JSON.stringify(CONTINENTS).replace(/\},\{/g, '},\n{')};
export const TERR=${JSON.stringify(TERR).replace(/\},\{/g, '},\n{')};
// rotas marítimas [a, b, cruzaBorda?]
export const SEA=${JSON.stringify(SEA)};
`;
writeFileSync(new URL('../js/map.js', import.meta.url), out);
console.log(`${TERR.length} territórios, ${EDGES.length} fronteiras, ${MAPW}x${H}, ${(out.length / 1024).toFixed(0)} KB; vazios: ${TERR.filter((t) => !t.d).map((t) => t.n)}`);
