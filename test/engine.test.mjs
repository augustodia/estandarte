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

// Jogadas aleatórias, válidas e inválidas, de qualquer jogador: as regras nunca podem ser quebradas,
// e uma jogada recusada não pode mudar nada.
{
  const { invariant } = await import('../js/game.js');
  const kinds = ['place', 'attack', 'occupy', 'endAttack', 'move', 'endTurn', 'trade', 'bogus'];
  let accepted = 0, refused = 0, round0Attacks = 0;
  for (let seed = 1; seed <= 120; seed++) {
    const rng = rngFrom(1000 + seed), n = 2 + (seed % 5);
    const R = (k) => Math.floor(rng() * k);
    const s = newGame(Array.from({ length: n }, (_, i) => ({ name: 'F' + i, color: i, ctrl: 'bot' })), rng);
    for (let step = 0; step < 1500 && s.phase === 'play'; step++) {
      const smart = rng() < 0.55; // mistura jogadas do bot com jogadas ao acaso
      const p = smart || rng() < 0.8 ? s.turn : R(n);
      const a = smart ? botAction(s) : { t: kinds[R(kinds.length)], t0: R(46) - 2, from: R(46) - 2, to: R(46) - 2, n: R(40) - 5, dice: R(6) - 1, blitz: rng() < 0.3, cards: [R(46), R(46), R(46)] };
      const before = JSON.stringify(s), armies = s.terr.reduce((k, t) => k + t.a, 0), round = s.round;
      const err = apply(s, p, a, rng);
      if (err) { refused++; assert.equal(JSON.stringify(s), before, 'jogada recusada alterou o estado: ' + JSON.stringify(a)); continue; }
      accepted++;
      assert.equal(invariant(s), null, `seed ${seed}: ${invariant(s)} após ${JSON.stringify(a)}`);
      const after = s.terr.reduce((k, t) => k + t.a, 0), evs = s.ev.map((e) => e.t);
      if (round === 0 && (evs.includes('attack') || evs.includes('move'))) round0Attacks++;
      const tradeBonus = s.ev.filter((e) => e.t === 'trade').reduce((k, e) => k + 2 * e.bonus.length, 0); // +2 por carta de território próprio
      if (a.t === 'move' || a.t === 'occupy' || a.t === 'endAttack') assert.equal(after, armies, 'exércitos criados ou perdidos sem combate');
      if (a.t === 'endTurn' || a.t === 'trade') assert.equal(after, armies + tradeBonus, 'exércitos criados fora de reforço ou troca');
      if (a.t === 'attack') assert(after <= armies, 'ataque criou exércitos');
      if (a.t === 'place') assert(after - tradeBonus > armies && after - tradeBonus - armies <= Math.max(1, a.n), 'reforço fora do pedido');
    }
  }
  assert.equal(round0Attacks, 0, 'houve ataque na primeira rodada');
  console.log(`ok — jogadas ao acaso: ${accepted} aceitas, ${refused} recusadas sem efeito, 0 ataques na primeira rodada`);
}

// Regras opcionais: eventos de rodada e pactos
{
  const G = await import('../js/game.js');
  const { SEA: SEAS, CONTINENTS: CONT } = await import('../js/map.js');
  const mk = (n, opts, seed = 5) => { const rng = rngFrom(seed); return [newGame(Array.from({ length: n }, (_, i) => ({ name: 'P' + i, color: i, ctrl: 'local' })), rng, opts), rng]; };
  const toAttack = (s, rng) => { while (s.round === 0 || s.step !== 'attack') { if (s.step === 'attack') apply(s, s.turn, { t: 'endAttack' }, rng); const a = s.step === 'reinforce' ? botAction(s) : { t: 'endTurn' }; assert.equal(apply(s, s.turn, a.t === 'trade' || a.t === 'place' ? a : { t: 'endTurn' }, rng), null); } };
  // sem as opções, nada disso existe
  { const [s, rng] = mk(3, {}); toAttack(s, rng); assert.equal(s.event, null); assert.notEqual(apply(s, s.turn, { t: 'pactOffer', to: (s.turn + 1) % 3 }, rng), null); }
  // eventos: um por rodada a partir da 2ª, nunca repetido em seguida
  { const seen = new Set(); let rounds = 0, withEv = 0;
    for (let g = 0; g < 20; g++) { const [s, rng] = mk(3 + (g % 4), { events: true }, 50 + g); assert.equal(s.event, null); let last = null, calm = 0, prevHad = false;
    for (let i = 0; i < 4000 && s.phase === 'play'; i++) { const r = s.round; apply(s, s.turn, botAction(s), rng); if (s.round !== r) { rounds++; if (s.event) { assert(G.EVENTS[s.event.k]); assert(!prevHad, 'dois eventos em rodadas seguidas'); assert.notEqual(s.event.k, last, 'evento repetido'); last = s.event.k; seen.add(last); withEv++; calm = 0; prevHad = true; } else { calm++; prevHad = false; assert(calm <= 3, 'mais de 3 rodadas calmas seguidas'); } } }
    }
    assert(seen.size >= 6, 'pouca variedade de eventos: ' + [...seen]); assert(withEv / rounds > 0.2 && withEv / rounds < 0.5, 'frequência de eventos fora do esperado: ' + withEv + '/' + rounds); }
  // cada efeito, forçando o evento
  { const [s, rng] = mk(3, { events: true }); toAttack(s, rng); const p = s.turn;
    const [a, b] = SEAS.find(([x, y, , , , , w]) => !w); s.terr[a] = { o: p, a: 5 }; s.terr[b] = { o: (p + 1) % 3, a: 1 };
    s.event = { k: 'sea' }; assert.match(apply(s, p, { t: 'attack', from: a, to: b }, rng), /Mar revolto/);
    s.event = { k: 'ceasefire', c: TERR[b].c }; assert.match(apply(s, p, { t: 'attack', from: a, to: b }, rng), /Cessar-fogo/);
    s.event = { k: 'storm', c: TERR[b].c }; s.terr[b].a = 9; assert.equal(apply(s, p, { t: 'attack', from: a, to: b, dice: 3 }, rng), null); assert.equal(s.roll.att.length, 2, 'tempestade deveria limitar a 2 dados');
    let hi = 0; s.event = { k: 'charge' }; for (let i = 0; i < 60; i++) { s.terr[a].a = 9; s.terr[b] = { o: (p + 1) % 3, a: 9 }; s.occupy = null; apply(s, p, { t: 'attack', from: a, to: b }, rng); hi = Math.max(hi, ...s.roll.att, ...s.roll.def); assert(s.roll.att[0] >= 2, 'ofensiva não somou ao maior dado'); }
    assert(hi <= 6, 'dado passou de 6'); }
  { const [s] = mk(3, { events: true }); const base = Math.max(3, Math.floor(G.owned(s, 0) / 2)); const rng = rngFrom(9);
    while (s.round === 0) apply(s, s.turn, botAction(s), rng); // chega à 2ª rodada, com ou sem evento; confere a conta do reforço
    const want = Math.max(3, Math.floor(G.owned(s, s.turn) / 2)), k = s.event ? s.event.k : null;
    assert.equal(s.pool.free, k === 'recruit' ? want + 2 : k === 'shortage' ? Math.max(3, want - 2) : want, 'reforço com evento ' + k); }
  // pactos: proposta, resposta fora da vez, bloqueio de ataque, rompimento com custo, prazo
  { const [s, rng] = mk(3, { pacts: true }); toAttack(s, rng); const p = s.turn, q = (p + 1) % 3, r = (p + 2) % 3;
    assert.equal(apply(s, p, { t: 'pactOffer', to: q }, rng), null); assert.deepEqual(s.offer, { from: p, to: q });
    assert.notEqual(apply(s, r, { t: 'pactReply', accept: true }, rng), null, 'terceiro respondeu');
    assert.notEqual(apply(s, p, { t: 'pactOffer', to: r }, rng), null, 'duas propostas no mesmo turno');
    assert.equal(apply(s, q, { t: 'pactReply', accept: true }, rng), null); assert(G.pactOf(s, p, q) && !s.offer);
    const from = s.terr.findIndex((t, i) => t.o === p && TERR[i].adj.some((j) => s.terr[j].o === q)), to = TERR[from].adj.find((j) => s.terr[j].o === q); s.terr[from].a = 6;
    assert.match(apply(s, p, { t: 'attack', from, to }, rng), /pacto/); assert.match(apply(s, p, { t: 'pactBreak', with: q }, rng), /início do seu turno/);
    const until = G.pactOf(s, p, q).until; assert.equal(until, s.round + G.PACT_ROUNDS);
    apply(s, p, { t: 'endAttack' }, rng); apply(s, p, { t: 'endTurn' }, rng);
    while (s.turn !== p) apply(s, s.turn, botAction(s), rng);
    const free = s.pool.free; assert.equal(apply(s, p, { t: 'pactBreak', with: q }, rng), null); assert.equal(s.pool.free, Math.max(0, free - G.PACT_PENALTY)); assert.equal(G.pactOf(s, p, q), null);
    // prazo: outro pacto e deixa as rodadas passarem
    apply(s, p, botAction(s), rng); while (s.step === 'reinforce' && s.turn === p) apply(s, p, botAction(s), rng);
    if (s.turn === p && s.phase === 'play') { assert.equal(apply(s, p, { t: 'pactOffer', to: r }, rng), null); assert.equal(apply(s, r, G.botPactReply(s), rng) , null); const had = !!G.pactOf(s, p, r), u = had ? G.pactOf(s, p, r).until : 0;
      for (let i = 0; i < 3000 && s.phase === 'play' && s.round <= u + 1; i++) { const x = botAction(s); if (x.t === 'attack' && had && s.round <= u) assert(!([s.terr[x.from].o, s.terr[x.to].o].includes(p) && [s.terr[x.from].o, s.terr[x.to].o].includes(r)), 'bot atacou parceiro de pacto'); apply(s, s.turn, x, rng); }
      if (s.phase === 'play' && had) assert.equal(G.pactOf(s, p, r), null, 'pacto não venceu no prazo'); } }
  // jogadas ao acaso com as duas opções ligadas
  { const kinds = ['place', 'attack', 'occupy', 'endAttack', 'move', 'endTurn', 'trade', 'pactOffer', 'pactReply', 'pactBreak'];
    let ok = 0;
    for (let seed = 1; seed <= 60; seed++) { const rng = rngFrom(7000 + seed), n = 3 + (seed % 4), R = (k) => Math.floor(rng() * k);
      const s = newGame(Array.from({ length: n }, (_, i) => ({ name: 'F' + i, color: i, ctrl: 'bot' })), rng, { events: true, pacts: true });
      for (let step = 0; step < 1500 && s.phase === 'play'; step++) { const smart = rng() < 0.6, p = smart || rng() < 0.7 ? s.turn : R(n);
        const a = s.offer && rng() < 0.5 ? G.botPactReply(s) : smart ? botAction(s) : { t: kinds[R(kinds.length)], t0: R(44), from: R(44), to: R(n + 40), with: R(n), n: R(30), accept: rng() < 0.5, cards: [R(44), R(44), R(44)] };
        const who = a.t === 'pactReply' && s.offer && rng() < 0.8 ? s.offer.to : p, before = JSON.stringify(s), r0 = s.round, ev0 = s.event;
        const err = apply(s, who, a, rng);
        if (err) { assert.equal(JSON.stringify(s), before); continue; }
        ok++; assert.equal(G.invariant(s), null, `seed ${seed}: ${G.invariant(s)} após ${JSON.stringify(a)}`);
        if (a.t === 'attack') { const e = s.ev.find((x) => x.t === 'attack'); assert(!(ev0 && ev0.k === 'ceasefire' && TERR[e.to].c === ev0.c), 'ataque durante cessar-fogo'); assert(!(ev0 && ev0.k === 'sea' && G.isSea(e.from, e.to)), 'ataque por mar com mar revolto'); }
        if (r0 === 0) assert(!s.ev.some((x) => x.t === 'attack'), 'ataque na primeira rodada'); } }
    console.log(`ok — eventos e pactos: efeitos conferidos e ${ok} jogadas ao acaso sem quebrar regras`); }
}

// Regra opcional: ogiva nuclear
{
  const G = await import('../js/game.js');
  const seats = (n, ctrl = 'bot') => Array.from({ length: n }, (_, i) => ({ name: 'N' + i, color: i, ctrl }));
  { const rng = rngFrom(3), s = newGame(seats(3), rng); assert.match(apply(s, s.turn, { t: 'nuke', cards: [0, 1, 2], to: 0 }, rng), /não tem ogiva/); assert.equal(s.fog, null); }
  // partidas inteiras entre bots com todas as opções, conferindo cada regra da ogiva a cada jogada
  let launched = 0, games = 0, fogTurns = 0, choice = 0;
  for (let seed = 1; seed <= 200; seed++) {
    const rng = rngFrom(9000 + seed), n = 2 + (seed % 5);
    const s = newGame(seats(n), rng, { events: seed % 2 === 0, pacts: seed % 3 === 0, nukes: true });
    const hist = Array.from({ length: n }, () => []);
    let nukedThisTurn = null;
    for (let step = 0; step < 60000 && s.phase === 'play'; step++) {
      const p = s.turn, fog0 = s.fog ? { ...s.fog } : null, trades0 = s.trades, pool0 = G.poolTotal(s), key0 = s.round + ':' + s.turn;
      const a = s.offer && rng() < 0.9 ? G.botPactReply(s) : botAction(s), who = a.t === 'pactReply' ? s.offer.to : p;
      assert.notEqual(botAction(s, { noNuke: true }).t, 'nuke', 'bot lançou mesmo proibido');
      if (s.step === 'reinforce' && s.players[p].cards.length >= 5) { choice++; assert.equal(G.nukeBlock(s, p), null, 'troca obrigatória pendente sem direito a ogiva'); assert.match(apply(s, p, { t: 'place', t0: s.terr.findIndex((t) => t.o === p), n: 1 }, rng) || '', /obrigatório trocar/); }
      const before = a.t === 'nuke' ? { a: s.terr[a.to].a, o: s.terr[a.to].o, v: G.tradeValue(s.trades), hand: s.players[p].cards.length } : null;
      assert.equal(apply(s, who, a, rng), null, `seed ${seed}: jogada de bot recusada ${JSON.stringify(a)}`);
      assert.equal(G.invariant(s), null);
      for (const e of s.ev) {
        if (e.t === 'trade') hist[e.p].push('normal');
        if (e.t === 'nuke') hist[e.p].push('nuke');
        if (fog0 && s.fog && e.t === 'attack') assert.notEqual(e.to, fog0.t, 'ataque a território sob névoa');
        if (e.t === 'attack') assert.notEqual(key0, nukedThisTurn, 'atacou no turno em que lançou a ogiva');
        if (e.t === 'turn' && s.fog) { fogTurns++; assert.notEqual(s.fog.by, e.p, 'névoa não se dissipou na volta de quem lançou'); }
      }
      if (a.t === 'nuke') {
        launched++; nukedThisTurn = key0;
        assert.equal(fog0, null, 'ogiva com névoa já no mapa');
        const lost = Math.min(2 * before.v, Math.floor(before.a / 2));
        assert.equal(s.terr[a.to].a, before.a - lost, 'dano errado'); assert(s.terr[a.to].a >= Math.ceil(before.a / 2), 'perdeu mais da metade'); assert.equal(s.terr[a.to].o, before.o, 'ogiva mudou o dono');
        const auto = s.ev.filter((e) => e.t === 'trade');
        assert.equal(s.trades, trades0 + 1 + auto.length, 'ogiva não ocupou degrau da escada');
        assert.equal(G.poolTotal(s) - auto.reduce((k, e) => k + e.v, 0), pool0 + Math.floor(before.v / 2), 'quem lança recebe metade da troca');
        assert.deepEqual(s.fog, { t: a.to, by: p }); assert(s.noAttack); assert.equal(s.turn, p, 'o turno continua');
        assert(!s.pacts.some((x) => x.a === p || x.b === p), 'pactos de quem lançou continuaram');
      }
    }
    for (const h of hist) h.forEach((x, i) => { if (x === 'nuke') assert(i > 0 && h[i - 1] === 'normal', 'ogiva na primeira troca ou em duas trocas seguidas: ' + h); });
    if (s.phase === 'over') games++;
  }
  assert(games >= 190, 'partidas com ogiva não terminam: ' + games); assert(launched > 0, 'bots nunca lançam'); assert(fogTurns > 0);
  // efeito controlado
  { const rng = rngFrom(11), s = newGame(seats(3, 'local'), rng, { nukes: true });
    while (s.round === 0) apply(s, s.turn, botAction(s), rng);
    const p = s.turn, hand = s.deck.filter((c) => c < TERR.length).slice(0, 9); const tri = G.findTrade(hand);
    s.deck = s.deck.filter((c) => !tri.includes(c)); s.players[p].cards = tri.slice();
    const tg = s.terr.findIndex((t) => t.o !== p), mine = s.terr.findIndex((t) => t.o === p);
    assert.match(apply(s, p, { t: 'nuke', cards: tri, to: tg }, rng), /primeira troca/);
    s.players[p].lastTrade = 'normal';
    assert.match(apply(s, p, { t: 'nuke', cards: tri, to: mine }, rng), /inimigo/);
    assert.match(apply(s, p, { t: 'nuke', cards: [tri[0], tri[0], tri[1]], to: tg }, rng), /trinca/);
    // teto: metade do alvo
    { const c = JSON.parse(JSON.stringify(s)); c.terr[tg].a = 7; assert.equal(apply(c, p, { t: 'nuke', cards: tri, to: tg }, rng), null); assert.equal(c.terr[tg].a, 4, 'com 7 exércitos o alvo perde 3'); }
    { const c = JSON.parse(JSON.stringify(s)); c.terr[tg].a = 1; assert.equal(apply(c, p, { t: 'nuke', cards: tri, to: tg }, rng), null); assert.equal(c.terr[tg].a, 1); }
    s.terr[tg].a = 30; const v = G.tradeValue(s.trades), free = s.pool.free;
    assert.equal(apply(s, p, { t: 'place', t0: mine, n: 1 }, rng), null); // pode reforçar antes de lançar
    assert.equal(apply(s, p, { t: 'nuke', cards: tri, to: tg }, rng), null);
    assert.equal(s.terr[tg].a, 30 - 2 * v); assert.equal(s.pool.free, free - 1 + Math.floor(v / 2)); assert.equal(G.tradeValue(s.trades), G.tradeValue(1));
    const owner = s.terr[tg].o;
    while (s.step === 'reinforce') apply(s, p, botAction(s, { noNuke: true }), rng);
    assert.equal(s.step, 'move', 'depois da ogiva o turno pula o ataque');
    assert.match(apply(s, p, { t: 'attack', from: mine, to: tg }, rng) || '', /atacar|ogiva/);
    apply(s, p, { t: 'endTurn' }, rng);
    while (s.turn !== owner && s.phase === 'play') { while (s.step === 'reinforce') apply(s, s.turn, botAction(s, { noNuke: true }), rng); if (s.step === 'attack') apply(s, s.turn, { t: 'endAttack' }, rng); apply(s, s.turn, { t: 'endTurn' }, rng); }
    // o dono joga normalmente: reforça lá e pode atacar a partir de lá; ninguém pode atacá-lo
    assert.equal(apply(s, owner, { t: 'place', t0: tg, n: 1 }, rng), null, 'o dono deveria poder reforçar o território atingido');
    const en = TERR[tg].adj.find((j) => s.terr[j].o !== owner);
    if (en != null) { assert.equal(G.attackBlock(s, tg, en), null, 'o dono deveria poder atacar a partir dele'); assert.match(G.attackBlock(s, en, tg), /Névoa/); }
    assert.equal(G.moveBlock(s, tg, TERR[tg].adj[0]), null);
    for (let i = 0; i < 600 && s.fog && s.phase === 'play'; i++) { apply(s, s.turn, botAction(s, { noNuke: true }), rng); if (!s.fog && s.phase === 'play') assert.equal(s.turn, p, 'névoa sumiu fora da vez de quem lançou'); }
    assert(s.phase !== 'play' || s.fog === null); }
  // jogadas ao acaso com tudo ligado
  { const kinds = ['place', 'attack', 'occupy', 'endAttack', 'move', 'endTurn', 'trade', 'nuke', 'nuke', 'pactOffer', 'pactReply', 'pactBreak'];
    let ok = 0, nk = 0;
    for (let seed = 1; seed <= 60; seed++) { const rng = rngFrom(12000 + seed), n = 3 + (seed % 4), R = (k) => Math.floor(rng() * k);
      const s = newGame(seats(n), rng, { events: true, pacts: true, nukes: true });
      for (let step = 0; step < 1500 && s.phase === 'play'; step++) { const smart = rng() < 0.6, p = smart || rng() < 0.7 ? s.turn : R(n);
        const hand = s.players[s.turn].cards, tri = G.findTrade(hand);
        const a = s.offer && rng() < 0.5 ? G.botPactReply(s) : smart ? botAction(s) : { t: kinds[R(kinds.length)], t0: R(44), from: R(44), to: R(44), with: R(n), n: R(30), accept: rng() < 0.5, cards: tri && rng() < 0.8 ? tri : [R(44), R(44), R(44)] };
        const who = a.t === 'pactReply' && s.offer && rng() < 0.8 ? s.offer.to : p, before = JSON.stringify(s), fog0 = s.fog ? s.fog.t : null;
        const err = apply(s, who, a, rng);
        if (err) { assert.equal(JSON.stringify(s), before); continue; }
        ok++; if (a.t === 'nuke') nk++;
        assert.equal(G.invariant(s), null, `seed ${seed}: ${G.invariant(s)} após ${JSON.stringify(a)}`);
        for (const x of s.players.keys()) assert(s.pacts.filter((q) => q.a === x || q.b === x).length <= 1, 'jogador com dois pactos');
        if (fog0 != null && s.fog) for (const e of s.ev) assert(!(e.t === 'attack' && e.to === fog0), 'território sob névoa foi atacado'); } }
    console.log(`ok — ogiva: ${games}/200 partidas terminadas, ${launched} lançamentos de bots, ${choice} trocas obrigatórias com escolha, e ${ok} jogadas ao acaso (${nk} ogivas) sem quebrar regras`); }
}

// Pactos: um por jogador, espera para renovar, multa proporcional; metas e distribuição por número de jogadores
{
  const G = await import('../js/game.js');
  const seats = (n) => Array.from({ length: n }, (_, i) => ({ name: 'N' + i, color: i, ctrl: 'local' }));
  const rng = rngFrom(21), s = newGame(seats(4), rng, { pacts: true });
  while (s.round === 0) apply(s, s.turn, botAction(s, { noPact: true }), rng);
  const p = s.turn, q = (p + 1) % 4, r = (p + 2) % 4;
  assert.equal(apply(s, p, { t: 'pactOffer', to: q }, rng), null); assert.equal(apply(s, q, { t: 'pactReply', accept: true }, rng), null);
  assert.equal(s.pacts[0].until, s.round + 2, 'pacto de 2 rodadas');
  assert.match(G.pactBlock(s, p, r), /um por vez/); assert.match(G.pactBlock(s, r, q), /já tem um pacto/);
  // romper: metade do reforço (mínimo 3), só antes de reforçar
  while (!(s.turn === p && s.step === 'reinforce' && s.round >= 2)) apply(s, s.turn, botAction(s, { noPact: true }), rng);
  if (s.pacts.length) {
    const pool = G.poolTotal(s), want = Math.min(pool, Math.max(3, Math.ceil(pool / 2)));
    { const c = JSON.parse(JSON.stringify(s)); apply(c, p, { t: 'place', t0: c.terr.findIndex((t) => t.o === p), n: 1 }, rng); if (c.step === 'reinforce') assert.match(apply(c, p, { t: 'pactBreak', with: q }, rng), /antes de colocar/); }
    assert.equal(apply(s, p, { t: 'pactBreak', with: q }, rng), null); assert.equal(G.poolTotal(s), pool - want, 'multa errada');
    assert.match(G.pactBlock(s, p, q), /acabaram de ter um pacto/);
  }
  // metas de território por número de jogadores
  assert.equal(G.countGoal(2, 1), G.BAL.goal[2]); assert.equal(G.countGoal(5, 1), G.GOAL); assert.equal(G.countGoal(3, 2), G.BAL.goal2[3]);
  assert.match(G.objectiveText({ k: 'count', min: 1 }, 2), new RegExp(String(G.BAL.goal[2])));
  // distribuição inicial: quem joga depois recebe mais
  for (const n of [2, 3, 4, 6]) { const g = newGame(seats(n), rngFrom(n)); const pools = []; while (g.round === 0) { if (pools.length === g.turn) pools.push(G.poolTotal(g)); apply(g, g.turn, botAction(g), rngFrom(1)); }
    for (let i = 1; i < n; i++) assert(pools[i] - pools[0] >= (G.BAL.seat[n] || 0) * i - 1, `distribuição inicial sem compensação (${n} jogadores): ${pools}`); }
  console.log('ok — pactos (um por jogador, espera, multa proporcional), metas e distribuição inicial por número de jogadores');
}
