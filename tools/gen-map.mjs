// Gera js/map.js a partir do Natural Earth 1:110m (domínio público), via world-atlas.
// Uso: npm i --no-save topojson-client world-atlas && node tools/gen-map.mjs
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const topojson = require('topojson-client');
const topo = require('world-atlas/countries-110m.json');

const W = 1400, LON0 = -169.5, LAT_TOP = 75.5, LAT_BOT = -56;
const merc = (lat) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
const K = W / (2 * Math.PI), H = Math.round((merc(LAT_TOP) - merc(LAT_BOT)) * K);
const proj = ([lon, lat]) => {
  if (lon < LON0) lon += 360;
  lat = Math.max(LAT_BOT, Math.min(LAT_TOP, lat));
  return [((lon - LON0) / 360) * W, (merc(LAT_TOP) - merc(lat)) * K];
};

const CONT = [
  { n: 'América do Norte', bonus: 5, color: '#c9a55a', at: [-146, 27] },
  { n: 'América do Sul', bonus: 3, color: '#6aa673', at: [-104, -28] },
  { n: 'Europa', bonus: 5, color: '#6a9fc6', at: [-24, 47] },
  { n: 'África', bonus: 4, color: '#c07a55', at: [-10, -14] },
  { n: 'Ásia', bonus: 7, color: '#b9799a', at: [74, -4] },
  { n: 'Oceania', bonus: 2, color: '#8d85c0', at: [128, -46] },
];
// chave: [nome, continente, rótulo lon, lat]
const T = {
  ala: ['Alasca', 0, -152, 65], cao: ['Canadá Oeste', 0, -118, 58], cal: ['Canadá Leste', 0, -78, 54], gro: ['Groenlândia', 0, -42, 69],
  euo: ['EUA Oeste', 0, -112, 41], eul: ['EUA Leste', 0, -86, 37], mex: ['México', 0, -102, 24], cam: ['América Central', 0, -86, 14],
  col: ['Colômbia', 1, -68, 6], and: ['Peru', 1, -74, -10], ama: ['Amazônia', 1, -60, -5], bra: ['Brasil', 1, -46, -13], arg: ['Argentina', 1, -64, -33], chi: ['Chile', 1, -71.5, -43],
  bri: ['Reino Unido', 2, -2, 54], esc: ['Escandinávia', 2, 15, 63], ibe: ['Ibéria', 2, -4, 40], fra: ['França', 2, 3, 47], euc: ['Europa Central', 2, 12.5, 51.5],
  ita: ['Itália e Bálcãs', 2, 20.5, 43.5], eor: ['Ucrânia', 2, 31, 50], rus: ['Rússia', 2, 45, 57],
  mag: ['Magrebe', 3, 3, 29], egi: ['Egito', 3, 30, 22], afo: ['África Ocidental', 3, -3, 13], afc: ['Congo', 3, 20, 2], afl: ['África Oriental', 3, 38, 3],
  afa: ['África Austral', 3, 24, -20], mad: ['Madagascar', 3, 47, -19],
  tur: ['Turquia', 4, 36, 39.5], ara: ['Arábia', 4, 45, 24], ira: ['Irã', 4, 60, 31], asc: ['Cazaquistão', 4, 66, 46], ind: ['Índia', 4, 79, 22],
  sib: ['Sibéria', 4, 92, 63], ext: ['Extremo Oriente', 4, 140, 63], mon: ['Mongólia', 4, 104, 47], cho: ['China Ocidental', 4, 88, 36], chl: ['China', 4, 113, 31],
  cor: ['Japão e Coreia', 4, 138.5, 36.5], sea: ['Sudeste Asiático', 4, 102, 16],
  ins: ['Indonésia', 5, 114, 0], ngu: ['Nova Guiné', 5, 144, -6], auo: ['Austrália Oeste', 5, 123, -25], aul: ['Austrália Leste', 5, 145, -25], nze: ['Nova Zelândia', 5, 172, -42],
};
const whole = {
  gro: 'Greenland', mex: 'Mexico',
  cam: 'Guatemala;Belize;Honduras;El Salvador;Nicaragua;Costa Rica;Panama;Cuba;Haiti;Dominican Rep.;Jamaica;Bahamas;Puerto Rico;Trinidad and Tobago',
  col: 'Colombia;Venezuela;Guyana;Suriname', and: 'Ecuador;Peru;Bolivia', arg: 'Argentina;Uruguay;Paraguay;Falkland Is.', chi: 'Chile',
  bri: 'United Kingdom;Ireland', esc: 'Sweden;Finland;Denmark;Iceland', ibe: 'Spain;Portugal', fra: 'Belgium;Netherlands;Luxembourg;Switzerland',
  euc: 'Germany;Poland;Czechia;Austria;Slovakia;Hungary',
  ita: 'Italy;Slovenia;Croatia;Bosnia and Herz.;Serbia;Montenegro;Kosovo;Albania;Macedonia;Greece;Bulgaria;Romania',
  eor: 'Ukraine;Belarus;Moldova;Lithuania;Latvia;Estonia',
  mag: 'Morocco;W. Sahara;Algeria;Tunisia;Libya', egi: 'Egypt;Sudan;S. Sudan',
  afo: "Mauritania;Mali;Niger;Senegal;Gambia;Guinea-Bissau;Guinea;Sierra Leone;Liberia;Côte d'Ivoire;Ghana;Togo;Benin;Burkina Faso;Nigeria",
  afc: 'Chad;Cameroon;Central African Rep.;Eq. Guinea;Gabon;Congo;Dem. Rep. Congo',
  afl: 'Ethiopia;Eritrea;Djibouti;Somalia;Somaliland;Kenya;Uganda;Tanzania;Rwanda;Burundi',
  afa: 'Angola;Zambia;Malawi;Mozambique;Zimbabwe;Namibia;Botswana;South Africa;Lesotho;eSwatini', mad: 'Madagascar',
  tur: 'Turkey;Cyprus;N. Cyprus;Georgia;Armenia;Azerbaijan',
  ara: 'Saudi Arabia;Yemen;Oman;United Arab Emirates;Qatar;Kuwait;Jordan;Israel;Palestine;Lebanon;Syria;Iraq',
  ira: 'Iran;Afghanistan;Pakistan', asc: 'Kazakhstan;Uzbekistan;Turkmenistan;Kyrgyzstan;Tajikistan', ind: 'India;Nepal;Bhutan;Bangladesh;Sri Lanka',
  mon: 'Mongolia', chl: 'Taiwan', cor: 'Japan;North Korea;South Korea', sea: 'Myanmar;Thailand;Laos;Cambodia;Vietnam',
  ins: 'Indonesia;Brunei;Timor-Leste;Philippines', ngu: 'Papua New Guinea;Solomon Is.', nze: 'New Zealand;New Caledonia;Vanuatu;Fiji',
};
// países divididos entre territórios (Voronoi pelos rótulos) e regras por polígono
const split = { 'United States of America': ['euo', 'eul'], Canada: ['cao', 'cal'], Russia: ['rus', 'sib', 'ext'], Brazil: ['ama', 'bra'], China: ['cho', 'chl'], Australia: ['auo', 'aul'] };
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
// sementes do corte quando diferem do rótulo (alinha as divisas do Canadá e dos EUA)
const SEED = { cao: [-114, 58], cal: [-74, 54] };
const DROP = new Set(['Antarctica', 'Fr. S. Antarctic Lands']);
// fronteiras: terrestres e rotas marítimas (~)
const EDGES = `ala-cao ala~ext cao-cal cao-euo cal-eul cal~gro gro~esc euo-eul euo-mex eul-mex eul~cam mex-cam cam-col
col-and col-ama and-ama and-bra and-arg and-chi ama-bra bra-arg arg-chi bra~afo
bri~esc bri~fra esc-euc esc-rus esc~eor ibe-fra ibe~mag fra-euc fra-ita euc-ita euc-eor ita-eor ita-tur ita~mag eor-rus rus-tur rus-asc rus-sib
mag-egi mag-afo mag-afc egi-afc egi-afl egi-ara afo-afc afc-afl afc-afa afl-afa afa~mad afl~mad afl~ara
tur-ara tur-ira ara-ira ira-asc ira-ind ira-cho asc-sib asc-cho ind-cho ind-sea sib-mon sib-cho sib-ext ext-mon ext-chl ext~cor mon-cho mon-chl cho-chl cho-sea chl-sea chl-cor
sea~ins cor~ins ins-ngu ins~auo ngu~aul ngu~nze auo-aul aul~nze`.split(/\s+/);

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
function toPath(rings) {
  let d = '';
  for (const ring of rings) {
    const xs = ring.map((p) => p[0]);
    if (Math.max(...xs) - Math.min(...xs) > W / 2) { console.warn('anel cruzando a borda descartado'); continue; }
    if (area(ring) < 5) continue;
    let last = '';
    const pts = [];
    for (const p of ring) { const s = `${f1(p[0])},${f1(p[1])}`; if (s !== last) pts.push(s); last = s; }
    if (pts.length > 1 && pts[0] === pts[pts.length - 1]) pts.pop();
    if (pts.length >= 3) d += 'M' + pts.join('L') + 'Z';
  }
  return d;
}
const TERR = keys.map((k) => {
  const g = groups[k];
  const rings = [...g.rings];
  if (g.arcs.length) for (const poly of topojson.merge(topo, g.arcs).coordinates) for (const ring of poly) rings.push(ring.map(proj));
  const [x, y] = proj([T[k][2], T[k][3]]);
  return { n: T[k][0], c: T[k][1], x: Math.round(x), y: Math.round(y), d: toPath(rings), adj: [] };
});
const SEA = [];
for (const e of EDGES) {
  const [a, sep, b] = e.split(/([-~])/);
  if (!(a in idx) || !(b in idx)) throw new Error('fronteira inválida: ' + e);
  TERR[idx[a]].adj.push(idx[b]); TERR[idx[b]].adj.push(idx[a]);
  if (sep === '~') SEA.push(e === 'ala~ext' ? [idx[a], idx[b], 1] : [idx[a], idx[b]]);
}
TERR.forEach((t) => t.adj.sort((a, b) => a - b));
const CONTINENTS = CONT.map((c) => { const [x, y] = proj(c.at); return { n: c.n, bonus: c.bonus, color: c.color, x: Math.round(x), y: Math.round(y) }; });
const out = `// Gerado por tools/gen-map.mjs (geografia: Natural Earth, domínio público). Não editar à mão.
export const MAP_W=${W}, MAP_H=${H};
export const CONTINENTS=${JSON.stringify(CONTINENTS)};
export const TERR=${JSON.stringify(TERR).replace(/\},\{/g, '},\n{')};
// rotas marítimas [a, b, cruzaBorda?]
export const SEA=${JSON.stringify(SEA)};
`;
writeFileSync(new URL('../js/map.js', import.meta.url), out);
console.log(`${TERR.length} territórios, ${EDGES.length} fronteiras, ${W}x${H}, ${(out.length / 1024).toFixed(0)} KB; vazios: ${TERR.filter((t) => !t.d).map((t) => t.n)}`);
