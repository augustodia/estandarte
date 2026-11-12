// node test/engine.test.mjs — simula partidas completas entre bots e confere invariantes.
import assert from 'node:assert';
import { newGame, apply, botAction, viewFor, validTrade, OBJECTIVES, COLORS } from '../js/game.js';
import { TERR, SEA } from '../js/map.js';

function rngFrom(seed) { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

// mapa: adjacência simétrica e grafo conexo
TERR.forEach((t, i) => t.adj.forEach((j) => assert(TERR[j].adj.includes(i), `adj assimétrica ${i}-${j}`)));
const seen = new Set([0]); const q = [0];
while (q.length) TERR[q.pop()].adj.forEach((j) => { if (!seen.has(j)) { seen.add(j); q.push(j); } });
assert.equal(seen.size, TERR.length, 'mapa desconexo');
TERR.forEach((t) => assert(t.d && t.adj.length, 'território sem forma ou sem fronteira: ' + t.n));

assert(validTrade([0, 3, 6])); assert(validTrade([0, 1, 2])); assert(!validTrade([0, 3, 1])); assert(validTrade([0, 3, TERR.length])); assert(!validTrade([0, 0, 3]));

let finished = 0, turnsTotal = 0;
for (let seed = 1; seed <= 300; seed++) {
  const n = 2 + (seed % 5);
  const rng = rngFrom(seed);
  const s = newGame(Array.from({ length: n }, (_, i) => ({ name: 'B' + i, color: i, ctrl: 'bot' })), rng);
  let steps = 0;
  while (s.phase === 'play' && steps++ < 60000) {
    const p = s.turn, a = botAction(s);
    const err = apply(s, p, a, rng);
    assert.equal(err, null, `seed ${seed}: ${err} ${JSON.stringify(a)}`);
    assert(s.terr.every((t) => t.a >= 1 && s.players[t.o].alive), 'território inválido');
    const cards = s.deck.length + s.discard.length + s.players.reduce((k, q) => k + q.cards.length, 0);
    assert.equal(cards, TERR.length + 2, 'cartas não conservadas');
    if (s.phase === 'play') assert.notEqual(apply(s, (s.turn + 1) % n, { t: 'endTurn' }, rng), null, 'ação fora da vez aceita');
  }
  if (s.phase === 'over') { finished++; turnsTotal += s.round; }
  const v = viewFor(s, 0);
  assert.equal(typeof v.deck, 'number');
  if (s.phase === 'play' && n > 1) assert.equal(v.players[1].obj, null);
}
console.log(`ok — ${finished}/300 partidas terminadas, média de ${(turnsTotal / finished).toFixed(1)} rodadas; ${TERR.length} territórios, ${OBJECTIVES.length} objetivos, ${COLORS.length} cores, ${SEA.length} rotas marítimas`);

// troca automática: quem começa o turno com 5 cartas tem a troca feita pelo jogo
{
  const rng = rngFrom(7);
  const s = newGame([0, 1, 2].map((i) => ({ name: 'P' + i, color: i, ctrl: 'local' })), rng);
  const next = (s.turn + 1) % 3;
  s.players[next].cards = s.deck.splice(0, 5);
  const before = s.trades;
  while (s.turn !== next) assert.equal(apply(s, s.turn, botAction(s), rng), null);
  const ev = s.ev.find((e) => e.t === 'trade');
  assert(ev && ev.auto && ev.p === next, 'troca automática não aconteceu');
  assert.equal(s.players[next].cards.length, 2);
  assert.equal(s.trades, before + 1);
  assert.equal(s.deck.length + s.discard.length + s.players.reduce((k, q) => k + q.cards.length, 0), TERR.length + 2);
  console.log('ok — troca automática com 5 cartas');
}
