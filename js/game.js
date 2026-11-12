// Motor de regras: funções puras sobre um estado serializável.
// O anfitrião é a autoridade: aplica ações e distribui visões filtradas.
import { TERR, CONTINENTS } from './map.js';

export const COLORS = [
  { n: 'Carmim', c: '#d64545' },
  { n: 'Cobalto', c: '#3f7fe0' },
  { n: 'Musgo', c: '#3f9d58' },
  { n: 'Âmbar', c: '#e2a72e' },
  { n: 'Violeta', c: '#9a5fd0' },
  { n: 'Grafite', c: '#8b96a3' },
];
export const SYMBOLS = ['●', '■', '▲', '★']; // 3 = coringa
const NT = TERR.length;
const WILD = [NT, NT + 1];
export const GOAL = Math.round(NT * 0.57), GOAL2 = Math.round(NT * 0.43);
const TRADE_TABLE = [4, 6, 8, 10, 12, 15];
export const tradeValue = (n) => (n < TRADE_TABLE.length ? TRADE_TABLE[n] : 15 + 5 * (n - 5));
export const cardSymbol = (c) => (c >= NT ? 3 : c % 3);
export const cardName = (c) => (c >= NT ? 'Coringa' : TERR[c].n);

// Continentes ordenados por tamanho, para montar objetivos equilibrados.
const bySize = CONTINENTS.map((_, i) => i).sort(
  (a, b) => TERR.filter((t) => t.c === a).length - TERR.filter((t) => t.c === b).length
);
const S = (i) => bySize[i];
export const OBJECTIVES = [
  { k: 'cont', c: [S(5), S(0)] },
  { k: 'cont', c: [S(5), S(1)] },
  { k: 'cont', c: [S(4), S(3)] },
  { k: 'cont', c: [S(4), S(2)] },
  { k: 'cont', c: [S(3), S(1)], extra: 1 },
  { k: 'cont', c: [S(2), S(0)], extra: 1 },
  { k: 'count', n: GOAL, min: 1 },
  { k: 'count', n: GOAL2, min: 2 },
  ...COLORS.map((_, i) => ({ k: 'kill', color: i })),
];
export function objectiveText(o) {
  if (!o) return '';
  if (o.k === 'cont') {
    const names = o.c.map((c) => CONTINENTS[c].n).join(' e ');
    return `Dominar por inteiro ${names}${o.extra ? ' e mais um continente à sua escolha' : ''}.`;
  }
  if (o.k === 'count')
    return o.min > 1
      ? `Dominar ${o.n} territórios, com pelo menos ${o.min} exércitos em cada um.`
      : `Dominar ${o.n} territórios.`;
  return `Eliminar o exército ${COLORS[o.color].n}. Se for o seu, não estiver em jogo ou outro jogador o eliminar, seu objetivo passa a ser dominar ${GOAL} territórios.`;
}

const shuffle = (a, rng) => {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};
const log = (s, msg) => {
  s.log.push(msg);
  if (s.log.length > 25) s.log.shift();
};
const pname = (s, i) => s.players[i].name;

// seats: [{name, color, ctrl}]
export function newGame(seats, rng = Math.random) {
  const n = seats.length;
  const pool = OBJECTIVES.map((_, i) => i).filter((i) => {
    const o = OBJECTIVES[i];
    return o.k !== 'kill' || (n >= 3 && seats.some((p) => p.color === o.color));
  });
  shuffle(pool, rng);
  const order = shuffle(seats.map((_, i) => i), rng);
  const players = order.map((si, i) => ({
    name: seats[si].name, color: seats[si].color, ctrl: seats[si].ctrl, seat: si,
    alive: true, cards: [], obj: pool[i], killedBy: null, conquered: false,
  }));
  const ids = shuffle(TERR.map((_, i) => i), rng);
  const terr = new Array(NT);
  ids.forEach((t, k) => (terr[t] = { o: k % n, a: 1 }));
  const s = {
    phase: 'play', players, terr, turn: 0, round: 0, step: 'reinforce',
    pool: { free: 0, cont: {} }, deck: shuffle([...TERR.map((_, i) => i), ...WILD], rng),
    discard: [], trades: 0, occupy: null, movable: null, roll: null, log: [], winner: null, n: 0,
  };
  startTurn(s);
  return s;
}

export const owned = (s, p) => s.terr.reduce((k, t) => k + (t.o === p), 0);
export const ownsContinent = (s, p, c) => TERR.every((t, i) => t.c !== c || s.terr[i].o === p);
export const poolTotal = (s) => s.pool.free + Object.values(s.pool.cont).reduce((a, b) => a + b, 0);

function startTurn(s) {
  const p = s.turn;
  s.step = 'reinforce';
  s.occupy = null; s.movable = null; s.roll = null;
  s.players[p].conquered = false;
  s.pool = { free: Math.max(3, Math.floor(owned(s, p) / 2)), cont: {} };
  CONTINENTS.forEach((c, i) => { if (ownsContinent(s, p, i)) s.pool.cont[i] = c.bonus; });
  log(s, `Vez de ${pname(s, p)}: ${poolTotal(s)} exércitos a distribuir.`);
  checkWin(s, p);
}

function objectiveMet(s, p) {
  const pl = s.players[p];
  let o = OBJECTIVES[pl.obj];
  if (o.k === 'kill') {
    const target = s.players.findIndex((q) => q.color === o.color);
    if (target >= 0 && target !== p) {
      if (s.players[target].alive) return false;
      if (s.players[target].killedBy === p) return true;
    }
    o = { k: 'count', n: GOAL, min: 1 };
  }
  if (o.k === 'count') return s.terr.filter((t) => t.o === p && t.a >= o.min).length >= o.n;
  if (!o.c.every((c) => ownsContinent(s, p, c))) return false;
  return !o.extra || CONTINENTS.filter((_, i) => ownsContinent(s, p, i)).length >= o.c.length + 1;
}
function checkWin(s, p) {
  const alive = s.players.filter((q) => q.alive);
  if (alive.length === 1) p = s.players.indexOf(alive[0]);
  else if (!objectiveMet(s, p)) return false;
  s.phase = 'over'; s.winner = p;
  log(s, `${pname(s, p)} venceu a partida!`);
  return true;
}

export function validTrade(cards) {
  if (cards.length !== 3 || new Set(cards).size !== 3) return false;
  const sy = cards.map(cardSymbol).filter((x) => x !== 3);
  const u = new Set(sy).size;
  return sy.length < 3 || u === 1 || u === 3;
}
export function findTrade(hand) {
  for (let a = 0; a < hand.length; a++)
    for (let b = a + 1; b < hand.length; b++)
      for (let c = b + 1; c < hand.length; c++)
        if (validTrade([hand[a], hand[b], hand[c]])) return [hand[a], hand[b], hand[c]];
  return null;
}
export const mustTrade = (s) => s.step === 'reinforce' && s.players[s.turn].cards.length >= 5;

function nextTurn(s, rng) {
  const pl = s.players[s.turn];
  if (pl.conquered) {
    if (!s.deck.length) { s.deck = shuffle(s.discard, rng); s.discard = []; }
    if (s.deck.length) { pl.cards.push(s.deck.pop()); log(s, `${pl.name} recebeu uma carta.`); }
  }
  let t = s.turn;
  do {
    t = (t + 1) % s.players.length;
    if (t === 0) s.round++;
  } while (!s.players[t].alive);
  s.turn = t;
  startTurn(s);
}

const rollDice = (n, rng) => Array.from({ length: n }, () => 1 + Math.floor(rng() * 6)).sort((a, b) => b - a);

// Aplica a ação do jogador p. Retorna null se ok, ou mensagem de erro.
export function apply(s, p, a, rng = Math.random) {
  if (s.phase !== 'play') return 'A partida não está em andamento.';
  if (p !== s.turn) return 'Não é a sua vez.';
  const pl = s.players[p];
  const T = s.terr;
  s.n++;
  switch (a.t) {
    case 'trade': {
      if (s.step !== 'reinforce') return 'Trocas só no início do turno.';
      if (!validTrade(a.cards) || !a.cards.every((c) => pl.cards.includes(c))) return 'Troca inválida.';
      pl.cards = pl.cards.filter((c) => !a.cards.includes(c));
      s.discard.push(...a.cards);
      const v = tradeValue(s.trades++);
      s.pool.free += v;
      let bonus = 0;
      a.cards.forEach((c) => { if (c < NT && T[c].o === p) { T[c].a += 2; bonus++; } });
      log(s, `${pl.name} trocou cartas por ${v} exércitos${bonus ? ` (+2 em ${bonus} território${bonus > 1 ? 's' : ''} das cartas)` : ''}.`);
      return null;
    }
    case 'place': {
      if (s.step !== 'reinforce') return 'Fora da fase de reforço.';
      if (mustTrade(s)) return 'Com 5 cartas é obrigatório trocar antes.';
      const t = T[a.t0];
      if (!t || t.o !== p) return 'Território inválido.';
      let n = Math.max(1, a.n | 0);
      const c = TERR[a.t0].c;
      let placed = 0;
      const fromCont = Math.min(n, s.pool.cont[c] || 0);
      if (fromCont) { s.pool.cont[c] -= fromCont; if (!s.pool.cont[c]) delete s.pool.cont[c]; placed += fromCont; n -= fromCont; }
      const fromFree = Math.min(n, s.pool.free);
      s.pool.free -= fromFree; placed += fromFree;
      if (!placed) return 'Os exércitos restantes são bônus de outro continente.';
      t.a += placed;
      if (poolTotal(s) === 0) {
        if (s.round === 0) { log(s, `${pl.name} posicionou seus exércitos.`); nextTurn(s, rng); }
        else s.step = 'attack';
      }
      checkWin(s, p);
      return null;
    }
    case 'attack': {
      if (s.step !== 'attack' || s.occupy) return 'Não é possível atacar agora.';
      const f = T[a.from], d = T[a.to];
      if (!f || !d || f.o !== p || d.o === p || !TERR[a.from].adj.includes(a.to)) return 'Ataque inválido.';
      if (f.a < 2) return 'É preciso ter ao menos 2 exércitos para atacar.';
      const defender = d.o;
      let last;
      do {
        const att = rollDice(Math.min(3, f.a - 1), rng), def = rollDice(Math.min(3, d.a), rng);
        let la = 0, ld = 0;
        for (let i = 0; i < Math.min(att.length, def.length); i++) att[i] > def[i] ? ld++ : la++;
        f.a -= la; d.a -= ld;
        last = { from: a.from, to: a.to, att, def, la, ld, by: p, n: s.n };
      } while (a.blitz && d.a > 0 && f.a > 1);
      s.roll = last;
      if (d.a === 0) {
        const max = Math.min(3, f.a - 1);
        d.o = p; d.a = 1; f.a -= 1; pl.conquered = true;
        s.roll.won = true;
        log(s, `${pl.name} conquistou ${TERR[a.to].n} de ${pname(s, defender)}.`);
        if (max > 1) s.occupy = { from: a.from, to: a.to, max: max - 1 };
        if (owned(s, defender) === 0) {
          const dp = s.players[defender];
          dp.alive = false; dp.killedBy = p;
          pl.cards.push(...dp.cards); dp.cards = [];
          log(s, `${dp.name} foi eliminado por ${pl.name}.`);
        }
        checkWin(s, p);
      } else log(s, `${pl.name} atacou ${TERR[a.to].n} (${last.att.join(' ')} × ${last.def.join(' ')}).`);
      return null;
    }
    case 'occupy': {
      if (!s.occupy) return 'Nada a ocupar.';
      const n = Math.max(0, Math.min(s.occupy.max, a.n | 0));
      T[s.occupy.from].a -= n; T[s.occupy.to].a += n;
      s.occupy = null;
      checkWin(s, p);
      return null;
    }
    case 'endAttack': {
      if (s.step !== 'attack') return 'Fora da fase de ataque.';
      s.occupy = null; s.step = 'move'; s.roll = null;
      s.movable = {};
      T.forEach((t, i) => { if (t.o === p && t.a > 1) s.movable[i] = t.a - 1; });
      return null;
    }
    case 'move': {
      if (s.step !== 'move') return 'Fora da fase de remanejamento.';
      const f = T[a.from], d = T[a.to];
      if (!f || !d || f.o !== p || d.o !== p || !TERR[a.from].adj.includes(a.to)) return 'Movimento inválido.';
      const n = Math.min(Math.max(1, a.n | 0), s.movable[a.from] || 0, f.a - 1);
      if (n < 1) return 'Sem exércitos disponíveis para mover daqui.';
      f.a -= n; d.a += n; s.movable[a.from] -= n;
      checkWin(s, p);
      return null;
    }
    case 'endTurn': {
      if (s.step === 'reinforce') return 'Distribua seus exércitos primeiro.';
      nextTurn(s, rng);
      return null;
    }
  }
  return 'Ação desconhecida.';
}

// Visão que um jogador pode ver: esconde mãos, objetivos alheios e o baralho.
export function viewFor(s, p) {
  const over = s.phase === 'over';
  return {
    ...s,
    deck: s.deck.length, discard: s.discard.length,
    players: s.players.map((q, i) => (i === p || over ? q : { ...q, cards: q.cards.length, obj: null })),
  };
}
export const handSize = (q) => (Array.isArray(q.cards) ? q.cards.length : q.cards);

// Bot simples: concentra reforços onde tem mais vantagem, ataca com vantagem e leva tropas do interior para a fronteira.
export function botAction(s) {
  const p = s.turn, T = s.terr, pl = s.players[p];
  const enemies = (i) => TERR[i].adj.filter((j) => T[j].o !== p);
  if (s.occupy) return { t: 'occupy', n: s.occupy.max };
  if (s.step === 'reinforce') {
    const tr = findTrade(pl.cards);
    if (tr && (pl.cards.length >= 5 || poolTotal(s) > 0)) return { t: 'trade', cards: tr };
    const mine = T.map((t, i) => i).filter((i) => T[i].o === p);
    const contIds = Object.keys(s.pool.cont).map(Number);
    let cand = mine.filter((i) => s.pool.free > 0 || contIds.includes(TERR[i].c));
    const border = cand.filter((i) => enemies(i).length);
    if (border.length) cand = border;
    const edge = (i) => (enemies(i).length ? T[i].a - Math.min(...enemies(i).map((j) => T[j].a)) : -1e9);
    cand.sort((a, b) => edge(b) - edge(a));
    return { t: 'place', t0: cand[0], n: poolTotal(s) };
  }
  if (s.step === 'attack') {
    let best = null;
    T.forEach((t, i) => {
      if (t.o !== p || t.a < 3) return;
      enemies(i).forEach((j) => {
        const adv = t.a - T[j].a;
        if (adv >= 1 && (!best || adv > best.adv)) best = { adv, from: i, to: j };
      });
    });
    return best ? { t: 'attack', from: best.from, to: best.to, blitz: true } : { t: 'endAttack' };
  }
  // remanejamento: leva exércitos do interior em direção à fronteira mais próxima
  const dist = T.map((t, i) => (t.o === p && enemies(i).length ? 0 : Infinity));
  for (let d = 0, changed = true; changed; d++) {
    changed = false;
    T.forEach((t, i) => {
      if (t.o === p && dist[i] === Infinity && TERR[i].adj.some((j) => dist[j] === d)) { dist[i] = d + 1; changed = true; }
    });
  }
  for (const k of Object.keys(s.movable || {})) {
    const i = +k, n = Math.min(s.movable[i], T[i].a - 1);
    if (n < 1 || dist[i] === 0) continue;
    const j = TERR[i].adj.find((x) => T[x].o === p && dist[x] < dist[i]);
    if (j !== undefined) return { t: 'move', from: i, to: j, n };
  }
  return { t: 'endTurn' };
}
