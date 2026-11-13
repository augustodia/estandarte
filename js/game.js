// Motor de regras: funções puras sobre um estado serializável.
// O anfitrião é a autoridade: aplica ações e distribui visões filtradas.
import { TERR, CONTINENTS, SEA } from './map.js';

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
// ---- regras opcionais: eventos de rodada e pactos ----
const SEA_LINK = new Set(SEA.flatMap(([a, b]) => [a + '-' + b, b + '-' + a]));
export const isSea = (a, b) => SEA_LINK.has(a + '-' + b);
// Eventos: sorteados de vez em quando no início de uma rodada (a partir da 2ª), valendo para todos até ela acabar.
export const EVENTS = {
  storm: { n: 'Tempestade', d: (c) => `Quem ataca territórios de ${CONTINENTS[c].n} rola no máximo 2 dados.`, cont: true },
  ceasefire: { n: 'Cessar-fogo', d: (c) => `Nenhum território de ${CONTINENTS[c].n} pode ser atacado nesta rodada.`, cont: true },
  sea: { n: 'Mar revolto', d: () => 'As ligações por mar estão fechadas: sem ataques nem movimentos por elas.' },
  recruit: { n: 'Recrutamento', d: () => 'Todos recebem 2 exércitos a mais no reforço.' },
  shortage: { n: 'Escassez', d: () => 'Todos recebem 2 exércitos a menos no reforço (mínimo 3).' },
  fort: { n: 'Trincheiras', d: () => 'A defesa soma 1 ao seu maior dado (até 6).' },
  charge: { n: 'Ofensiva', d: () => 'O ataque soma 1 ao seu maior dado (até 6).' },
};
export const eventText = (e) => (e ? EVENTS[e.k].d(e.c) : '');
export const PACT_ROUNDS = 3, PACT_PENALTY = 3;
export const EVENT_CHANCE = 0.45;
export const pactOf = (s, a, b) => (s.pacts || []).find((x) => (x.a === a && x.b === b) || (x.a === b && x.b === a)) || null;
// Motivo pelo qual from não pode atacar to agora por causa de evento ou pacto; null se pode.
export function attackBlock(s, from, to) {
  const e = s.event, def = s.terr[to].o;
  if (e && e.k === 'sea' && isSea(from, to)) return 'Mar revolto: as ligações por mar estão fechadas nesta rodada.';
  if (e && e.k === 'ceasefire' && TERR[to].c === e.c) return `Cessar-fogo: ${CONTINENTS[e.c].n} não pode ser atacada nesta rodada.`;
  const pact = pactOf(s, s.terr[from].o, def);
  if (pact) return `Você tem um pacto com ${s.players[def].name} até o fim da rodada ${pact.until + 1}. Para atacar, rompa o pacto no início do seu turno.`;
  return null;
}
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
// opts: { events, pacts } ligam as regras opcionais; sem elas o jogo é o clássico.
export function newGame(seats, rng = Math.random, opts = {}) {
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
    ev: [], // eventos da última ação, para animações e alertas em todos os aparelhos
    opts: { events: !!opts.events, pacts: !!opts.pacts }, event: null, pacts: [], offer: null,
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
  let base = Math.max(3, Math.floor(owned(s, p) / 2));
  if (s.event && s.event.k === 'recruit') base += 2;
  if (s.event && s.event.k === 'shortage') base = Math.max(3, base - 2);
  s.pool = { free: base, cont: {} };
  CONTINENTS.forEach((c, i) => { if (ownsContinent(s, p, i)) s.pool.cont[i] = c.bonus; });
  s.ev.push({ t: 'turn', p });
  // com 5 cartas ou mais a troca é obrigatória: o jogo faz sozinho, com a melhor trinca
  for (let tr; s.players[p].cards.length >= 5 && (tr = bestTrade(s.players[p].cards, s.terr, p));) doTrade(s, p, tr, true);
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
  s.winBy = objectiveMet(s, p) ? 'goal' : 'last'; // cumpriu o objetivo, ou só sobrou ele
  s.ev.push({ t: 'win', p });
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
// Melhor trinca para trocar: prioriza cartas de territórios do jogador (+2 cada) e poupa coringas.
export function bestTrade(hand, terr, p) {
  let best = null, top = -1;
  for (let a = 0; a < hand.length; a++)
    for (let b = a + 1; b < hand.length; b++)
      for (let c = b + 1; c < hand.length; c++) {
        const tr = [hand[a], hand[b], hand[c]];
        if (!validTrade(tr)) continue;
        const sc = tr.reduce((k, x) => k + (x >= NT ? 0 : 1 + (terr[x].o === p ? 10 : 0)), 0);
        if (sc > top) { top = sc; best = tr; }
      }
  return best;
}
function doTrade(s, p, cards, auto) {
  const pl = s.players[p], T = s.terr;
  pl.cards = pl.cards.filter((c) => !cards.includes(c));
  s.discard.push(...cards);
  const v = tradeValue(s.trades++);
  s.pool.free += v;
  let bonus = 0;
  cards.forEach((c) => { if (c < NT && T[c].o === p) { T[c].a += 2; bonus++; } });
  s.ev.push({ t: 'trade', p, v, auto: !!auto, bonus: cards.filter((c) => c < NT && T[c].o === p) });
  log(s, `${pl.name} trocou cartas por ${v} exércitos${auto ? ' (troca automática)' : ''}${bonus ? ` e +2 em ${bonus} território${bonus > 1 ? 's' : ''}` : ''}.`);
}
export const mustTrade = (s) => s.step === 'reinforce' && s.players[s.turn].cards.length >= 5;

function nextTurn(s, rng) {
  const pl = s.players[s.turn];
  if (pl.conquered) {
    if (!s.deck.length) { s.deck = shuffle(s.discard, rng); s.discard = []; }
    if (s.deck.length) { pl.cards.push(s.deck.pop()); s.ev.push({ t: 'card', p: s.turn }); log(s, `${pl.name} recebeu uma carta.`); }
  }
  let t = s.turn;
  const round0 = s.round;
  do {
    t = (t + 1) % s.players.length;
    if (t === 0) s.round++;
  } while (!s.players[t].alive);
  s.turn = t;
  s.offer = null; // proposta de pacto sem resposta vence com o turno de quem propôs
  if (s.round !== round0) newRound(s, rng);
  startTurn(s);
}

function newRound(s, rng) {
  // pactos vencidos
  for (const x of s.pacts.filter((q) => s.round > q.until)) { s.ev.push({ t: 'pactEnd', a: x.a, b: x.b }); log(s, `O pacto entre ${pname(s, x.a)} e ${pname(s, x.b)} terminou.`); }
  s.pacts = s.pacts.filter((q) => s.round <= q.until);
  if (!s.opts.events) return;
  // Eventos espaçados e imprevisíveis: depois de um evento vem sempre ao menos uma rodada calma;
  // em rodada calma a chance de sair um é de 45%, e nunca passam mais de 3 calmas seguidas.
  const calm = s.calm || 0;
  if (s.event || (calm < 3 && rng() >= EVENT_CHANCE)) {
    if (s.event) { s.ev.push({ t: 'eventEnd', k: s.event.k }); log(s, `O evento ${EVENTS[s.event.k].n} terminou.`); }
    s.calm = s.event ? 1 : calm + 1; s.event = null;
    return;
  }
  const keys = Object.keys(EVENTS).filter((k) => k !== s.lastEvent); // nunca repete o último que saiu
  const k = keys[Math.floor(rng() * keys.length)];
  s.calm = 0; s.lastEvent = k;
  s.event = EVENTS[k].cont ? { k, c: Math.floor(rng() * CONTINENTS.length) } : { k };
  s.ev.push({ t: 'event', k, c: s.event.c });
  log(s, `Evento da rodada ${s.round + 1}: ${EVENTS[k].n}. ${eventText(s.event)}`);
}
// pactos deixam de existir para quem foi eliminado, e todos acabam quando sobram só dois jogadores
function prunePacts(s) {
  const alive = s.players.filter((q) => q.alive).length;
  s.pacts = s.pacts.filter((x) => alive > 2 && s.players[x.a].alive && s.players[x.b].alive);
  if (s.offer && (alive <= 2 || !s.players[s.offer.from].alive || !s.players[s.offer.to].alive)) s.offer = null;
}
const rollDice = (n, rng) => Array.from({ length: n }, () => 1 + Math.floor(rng() * 6)).sort((a, b) => b - a);

// Regras que precisam valer depois de qualquer jogada. Devolve a descrição do problema, ou null.
export function invariant(s) {
  const alive = s.players.filter((q) => q.alive).length;
  if (!['play', 'over'].includes(s.phase)) return 'fase inválida';
  if (!['reinforce', 'attack', 'move'].includes(s.step)) return 'etapa inválida';
  for (const t of s.terr) {
    if (!Number.isInteger(t.a) || t.a < 1) return 'território sem exército';
    if (!s.players[t.o] || !s.players[t.o].alive) return 'território de jogador eliminado';
  }
  for (let i = 0; i < s.players.length; i++) if (s.players[i].alive !== s.terr.some((t) => t.o === i)) return 'jogador vivo sem território (ou o contrário)';
  const cards = s.deck.length + s.discard.length + s.players.reduce((k, q) => k + q.cards.length, 0);
  if (cards !== NT + 2 || new Set([...s.deck, ...s.discard, ...s.players.flatMap((q) => q.cards)]).size !== NT + 2) return 'cartas duplicadas ou perdidas';
  if (s.pool.free < 0 || Object.values(s.pool.cont).some((v) => v < 0)) return 'reforço negativo';
  if (s.phase === 'play') {
    if (!s.players[s.turn] || !s.players[s.turn].alive) return 'vez de jogador eliminado';
    if (alive < 2) return 'partida deveria ter terminado';
    if (s.round === 0 && (s.step !== 'reinforce' || s.occupy || s.roll)) return 'ataque ou movimento na primeira rodada';
    if (s.step !== 'reinforce' && poolTotal(s) > 0) return 'saiu do reforço com exércitos por colocar';
    if ((s.pacts || []).some((x) => x.a === x.b || !s.players[x.a].alive || !s.players[x.b].alive) || (!s.opts.pacts && (s.pacts.length || s.offer))) return 'pacto inválido';
    if (!s.opts.events && s.event) return 'evento em partida sem eventos';
    if (s.occupy && (s.step !== 'attack' || s.terr[s.occupy.from].o !== s.turn || s.terr[s.occupy.to].o !== s.turn || s.terr[s.occupy.from].a - s.occupy.max < 1)) return 'ocupação inconsistente';
  }
  return null;
}

// Aplica a ação do jogador p. Retorna null se ok, ou mensagem de erro.
// É transacional: uma jogada recusada, ou que deixaria o jogo num estado que quebra as regras,
// não muda nada no estado.
export function apply(s, p, a, rng = Math.random) {
  const snap = JSON.stringify(s);
  let err;
  try { err = applyAction(s, p, a || {}, rng) || invariant(s); } catch (e) { err = 'Jogada inválida.'; }
  if (err) { for (const k of Object.keys(s)) delete s[k]; Object.assign(s, JSON.parse(snap)); }
  return err || null;
}
function applyAction(s, p, a, rng) {
  if (s.phase !== 'play') return 'A partida não está em andamento.';
  if (a.t === 'pactReply') { // única jogada que se faz fora da vez: responder a uma proposta de pacto
    if (!s.offer || s.offer.to !== p) return 'Não há proposta de pacto para você.';
    const from = s.offer.from;
    s.n++; s.ev = []; s.offer = null;
    if (a.accept) {
      const until = s.round + PACT_ROUNDS;
      s.pacts.push({ a: from, b: p, until });
      s.ev.push({ t: 'pact', a: from, b: p, until });
      log(s, `Pacto entre ${pname(s, from)} e ${pname(s, p)} até o fim da rodada ${until + 1}.`);
    } else { s.ev.push({ t: 'pactNo', a: from, b: p }); log(s, `${pname(s, p)} recusou o pacto de ${pname(s, from)}.`); }
    return null;
  }
  if (p !== s.turn) return 'Não é a sua vez.';
  const pl = s.players[p];
  const T = s.terr;
  s.n++;
  s.ev = [];
  switch (a.t) {
    case 'trade': {
      if (s.step !== 'reinforce') return 'Trocas só no início do turno.';
      if (!Array.isArray(a.cards) || !validTrade(a.cards) || !a.cards.every((c) => pl.cards.includes(c))) return 'Troca inválida.';
      doTrade(s, p, a.cards, false);
      return null;
    }
    case 'place': {
      if (s.step !== 'reinforce') return 'Fora da fase de reforço.';
      if (mustTrade(s)) return 'Com 5 cartas é obrigatório trocar antes.';
      const t = Number.isInteger(a.t0) ? T[a.t0] : null;
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
      s.ev.push({ t: 'place', p, to: a.t0, k: placed });
      if (poolTotal(s) === 0) {
        if (s.round === 0) { log(s, `${pl.name} posicionou seus exércitos.`); nextTurn(s, rng); }
        else { s.step = 'attack'; s.ev.push({ t: 'phase', p, step: 'attack' }); }
      }
      checkWin(s, p);
      return null;
    }
    case 'attack': {
      if (s.round === 0) return 'Na primeira rodada não há ataques: só distribuição de exércitos.';
      if (s.step !== 'attack' || s.occupy) return 'Não é possível atacar agora.';
      if (!Number.isInteger(a.from) || !Number.isInteger(a.to)) return 'Ataque inválido.';
      const f = T[a.from], d = T[a.to];
      if (!f || !d || f.o !== p || d.o === p || !TERR[a.from].adj.includes(a.to)) return 'Ataque inválido.';
      if (f.a < 2) return 'É preciso ter ao menos 2 exércitos para atacar.';
      const blocked = attackBlock(s, a.from, a.to);
      if (blocked) return blocked;
      const defender = d.o, storm = s.event && s.event.k === 'storm' && TERR[a.to].c === s.event.c;
      let last, tla = 0, tld = 0;
      do {
        const maxA = Math.min(storm ? 2 : 3, f.a - 1), nA = a.blitz ? maxA : Math.max(1, Math.min(maxA, a.dice | 0 || maxA)); // dados escolhidos pelo atacante
        const att = rollDice(nA, rng), def = rollDice(Math.min(3, d.a), rng);
        if (s.event && s.event.k === 'charge') att[0] = Math.min(6, att[0] + 1);
        if (s.event && s.event.k === 'fort') def[0] = Math.min(6, def[0] + 1);
        let la = 0, ld = 0;
        for (let i = 0; i < Math.min(att.length, def.length); i++) att[i] > def[i] ? ld++ : la++;
        f.a -= la; d.a -= ld; tla += la; tld += ld;
        last = { from: a.from, to: a.to, att, def, la, ld, by: p, n: s.n };
      } while (a.blitz && d.a > 0 && f.a > 1);
      s.roll = last;
      const ev = { t: 'attack', p, from: a.from, to: a.to, la: tla, ld: tld, def: defender, won: d.a === 0 };
      s.ev.push(ev);
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
          s.ev.push({ t: 'dead', p: defender, by: p });
          prunePacts(s);
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
      if (n) s.ev.push({ t: 'move', p, from: s.occupy.from, to: s.occupy.to, k: n });
      s.occupy = null;
      checkWin(s, p);
      return null;
    }
    case 'endAttack': {
      if (s.step !== 'attack') return 'Fora da fase de ataque.';
      s.occupy = null; s.step = 'move'; s.roll = null;
      s.ev.push({ t: 'phase', p, step: 'move' });
      s.movable = {};
      T.forEach((t, i) => { if (t.o === p && t.a > 1) s.movable[i] = t.a - 1; });
      return null;
    }
    case 'move': {
      if (s.step !== 'move') return 'Fora da fase de remanejamento.';
      if (!Number.isInteger(a.from) || !Number.isInteger(a.to)) return 'Movimento inválido.';
      const f = T[a.from], d = T[a.to];
      if (!f || !d || f.o !== p || d.o !== p || !TERR[a.from].adj.includes(a.to)) return 'Movimento inválido.';
      if (s.event && s.event.k === 'sea' && isSea(a.from, a.to)) return 'Mar revolto: as ligações por mar estão fechadas nesta rodada.';
      const n = Math.min(Math.max(1, a.n | 0), s.movable[a.from] || 0, f.a - 1);
      if (n < 1) return 'Sem exércitos disponíveis para mover daqui.';
      f.a -= n; d.a += n; s.movable[a.from] -= n;
      s.ev.push({ t: 'move', p, from: a.from, to: a.to, k: n });
      checkWin(s, p);
      return null;
    }
    case 'pactOffer': {
      if (!s.opts.pacts) return 'Esta partida não tem pactos.';
      const q = s.players[a.to];
      if (!Number.isInteger(a.to) || !q || !q.alive || a.to === p) return 'Jogador inválido.';
      if (s.players.filter((x) => x.alive).length <= 2) return 'Com só dois jogadores não há pactos.';
      if (pactOf(s, p, a.to)) return 'Vocês já têm um pacto.';
      if (s.offer) return 'Já há uma proposta aguardando resposta.';
      if (pl.offered === s.round + ':' + s.turn) return 'Só uma proposta de pacto por turno.';
      pl.offered = s.round + ':' + s.turn;
      s.offer = { from: p, to: a.to };
      s.ev.push({ t: 'pactAsk', a: p, b: a.to });
      return null;
    }
    case 'pactBreak': {
      const pact = Number.isInteger(a.with) ? pactOf(s, p, a.with) : null;
      if (!pact) return 'Não há pacto com esse jogador.';
      if (s.step !== 'reinforce') return 'O pacto só pode ser rompido no início do seu turno, antes de terminar o reforço.';
      const lost = Math.min(PACT_PENALTY, s.pool.free);
      s.pool.free -= lost;
      s.pacts = s.pacts.filter((x) => x !== pact);
      s.ev.push({ t: 'pactBreak', a: p, b: a.with, lost });
      log(s, `${pl.name} rompeu o pacto com ${pname(s, a.with)} e perdeu ${lost} exército${lost === 1 ? '' : 's'} do reforço.`);
      if (poolTotal(s) === 0) { s.step = 'attack'; s.ev.push({ t: 'phase', p, step: 'attack' }); }
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

// Resposta de um bot a uma proposta de pacto: aceita se quem propõe tem mais territórios que ele.
export const botPactReply = (s) => ({ t: 'pactReply', accept: owned(s, s.offer.from) >= owned(s, s.offer.to) });
// Bot simples: concentra reforços onde tem mais vantagem, ataca com vantagem e leva tropas do interior para a fronteira.
export function botAction(s) {
  const p = s.turn, T = s.terr, pl = s.players[p];
  const enemies = (i) => TERR[i].adj.filter((j) => T[j].o !== p);
  if (s.occupy) return { t: 'occupy', n: s.occupy.max };
  if (s.step === 'reinforce') {
    const tr = bestTrade(pl.cards, T, p);
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
        if (attackBlock(s, i, j)) return; // respeita eventos e pactos
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
    const j = TERR[i].adj.find((x) => T[x].o === p && dist[x] < dist[i] && !(s.event && s.event.k === 'sea' && isSea(i, x)));
    if (j !== undefined) return { t: 'move', from: i, to: j, n };
  }
  return { t: 'endTurn' };
}
