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
  if (s.fog && (s.fog.t === from || s.fog.t === to)) return fogText(s);
  return null;
}
const fogText = (s) => `Névoa nuclear: ${TERR[s.fog.t].n} está isolado até a névoa se dissipar.`;
// Motivo pelo qual não dá para mover tropas de from para to agora; null se pode.
export function moveBlock(s, from, to) {
  if (s.event && s.event.k === 'sea' && isSea(from, to)) return 'Mar revolto: as ligações por mar estão fechadas nesta rodada.';
  if (s.fog && (s.fog.t === from || s.fog.t === to)) return fogText(s);
  return null;
}
// ---- regra opcional: ogiva nuclear ----
// Lançada no lugar de uma troca de cartas, como primeira ação do turno: o jogador entrega a trinca e o turno dele acaba ali,
// sem reforço, ataque nem remanejamento.
// O alvo perde o dobro do que a troca valeria (sobra ao menos 1) e fica sob névoa até a vez voltar a quem lançou:
// isolado (sem ataques, reforços ou movimentos) e com o bônus do continente suspenso. Uma névoa por vez no mapa.
export const NUKE_MULT = 2;
export const nukeDamage = (s) => NUKE_MULT * tradeValue(s.trades);
// Motivo pelo qual p não pode lançar agora (em to, se informado); null se pode.
export function nukeBlock(s, p, to) {
  if (!s.opts || !s.opts.nukes) return 'Esta partida não tem ogiva.';
  if (s.phase !== 'play' || s.turn !== p || s.step !== 'reinforce') return 'A ogiva só pode ser lançada no início do seu turno, no lugar de uma troca de cartas.';
  if (s.placed) return 'A ogiva custa o turno inteiro: só pode ser lançada antes de colocar qualquer reforço.';
  if (s.fog) return 'Já há uma névoa nuclear no mapa. Só depois que ela se dissipar.';
  const last = s.players[p].lastTrade;
  if (last !== 'normal') return last === 'nuke' ? 'Depois de uma ogiva, a sua próxima troca precisa ser normal.' : 'A sua primeira troca precisa ser normal.';
  if (to == null) return null;
  const d = Number.isInteger(to) ? s.terr[to] : null;
  if (!d || d.o === p) return 'Escolha um território inimigo como alvo.';
  if (pactOf(s, p, d.o)) return `Você tem um pacto com ${s.players[d.o].name}. Rompa o pacto antes de lançar contra ele.`;
  if (s.event && s.event.k === 'ceasefire' && TERR[to].c === s.event.c) return `Cessar-fogo: ${CONTINENTS[s.event.c].n} não pode ser atacada nesta rodada.`;
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
// opts: { events, pacts, nukes } ligam as regras opcionais; sem elas o jogo é o clássico.
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
    opts: { events: !!opts.events, pacts: !!opts.pacts, nukes: !!opts.nukes }, event: null, pacts: [], offer: null, fog: null, noAttack: false,
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
  s.noAttack = false; s.placed = false;
  // a névoa dura até a vez voltar a quem lançou (ou até ele sair do jogo)
  if (s.fog && (s.fog.by === p || !s.players[s.fog.by].alive)) { s.ev.push({ t: 'fogEnd', to: s.fog.t }); log(s, `A névoa sobre ${TERR[s.fog.t].n} se dissipou.`); s.fog = null; }
  let base = Math.max(3, Math.floor(owned(s, p) / 2));
  if (s.event && s.event.k === 'recruit') base += 2;
  if (s.event && s.event.k === 'shortage') base = Math.max(3, base - 2);
  s.pool = { free: base, cont: {} };
  CONTINENTS.forEach((c, i) => { if (ownsContinent(s, p, i) && !(s.fog && TERR[s.fog.t].c === i)) s.pool.cont[i] = c.bonus; }); // continente sob névoa não paga bônus
  s.ev.push({ t: 'turn', p });
  if (s.fog && s.terr[s.fog.t].o === p && owned(s, p) === 1) { // o único território do jogador está isolado: não há onde reforçar
    s.pool = { free: 0, cont: {} }; s.step = 'attack';
    log(s, `Vez de ${pname(s, p)}: sob a névoa, sem reforços neste turno.`);
    return;
  }
  // com 5 cartas ou mais a troca é obrigatória: o jogo faz sozinho, com a melhor trinca.
  // Quem pode lançar a ogiva escolhe antes: a troca fica obrigatória, mas não automática.
  if (nukeBlock(s, p)) for (let tr; s.players[p].cards.length >= 5 && (tr = bestTrade(s.players[p].cards, s.terr, p));) doTrade(s, p, tr, true);
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
  pl.lastTrade = 'normal';
  const gets = cards.filter((c) => c < NT && T[c].o === p && !(s.fog && s.fog.t === c)); // território sob névoa não recebe o +2
  const bonus = gets.length;
  gets.forEach((c) => { T[c].a += 2; });
  s.ev.push({ t: 'trade', p, v, auto: !!auto, bonus: gets });
  log(s, `${pl.name} trocou cartas por ${v} exércitos${auto ? ' (troca automática)' : ''}${bonus ? ` e +2 em ${bonus} território${bonus > 1 ? 's' : ''}` : ''}.`);
}
// Trinca para pagar a ogiva: o contrário da melhor troca, poupa cartas de territórios do jogador e coringas.
export function nukeTrade(hand, terr, p) {
  let best = null, top = -1;
  for (let a = 0; a < hand.length; a++)
    for (let b = a + 1; b < hand.length; b++)
      for (let c = b + 1; c < hand.length; c++) {
        const tr = [hand[a], hand[b], hand[c]];
        if (!validTrade(tr)) continue;
        const sc = tr.reduce((k, x) => k + (x >= NT ? 0 : terr[x].o === p ? 1 : 10), 0);
        if (sc > top) { top = sc; best = tr; }
      }
  return best;
}
// Fim do reforço: segue para o ataque, ou direto para o remanejamento se o jogador lançou a ogiva neste turno.
function endReinforce(s, p) {
  if (!s.noAttack) { s.step = 'attack'; s.ev.push({ t: 'phase', p, step: 'attack' }); return; }
  s.step = 'move'; s.roll = null; s.occupy = null;
  s.ev.push({ t: 'phase', p, step: 'move' });
  s.movable = {};
  s.terr.forEach((t, i) => { if (t.o === p && t.a > 1) s.movable[i] = t.a - 1; });
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
    if (s.fog && (!s.opts.nukes || !s.terr[s.fog.t] || !s.players[s.fog.by])) return 'névoa inválida';
    if (s.noAttack && (s.step === 'attack' || s.occupy)) return 'ataque em turno de ogiva';
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
      if (s.fog && s.fog.t === a.t0) return fogText(s);
      let n = Math.max(1, a.n | 0);
      const c = TERR[a.t0].c;
      let placed = 0;
      const fromCont = Math.min(n, s.pool.cont[c] || 0);
      if (fromCont) { s.pool.cont[c] -= fromCont; if (!s.pool.cont[c]) delete s.pool.cont[c]; placed += fromCont; n -= fromCont; }
      const fromFree = Math.min(n, s.pool.free);
      s.pool.free -= fromFree; placed += fromFree;
      if (!placed) return 'Os exércitos restantes são bônus de outro continente.';
      t.a += placed; s.placed = true;
      s.ev.push({ t: 'place', p, to: a.t0, k: placed });
      if (poolTotal(s) === 0) {
        if (s.round === 0) { log(s, `${pl.name} posicionou seus exércitos.`); nextTurn(s, rng); }
        else endReinforce(s, p);
      }
      checkWin(s, p);
      return null;
    }
    case 'attack': {
      if (s.round === 0) return 'Na primeira rodada não há ataques: só distribuição de exércitos.';
      if (s.step !== 'attack' || s.occupy) return 'Não é possível atacar agora.';
      if (s.noAttack) return 'Você lançou a ogiva neste turno: sem ataques.';
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
      } while (a.blitz && d.a > 0 && f.a > Math.max(1, a.keep | 0)); // keep: o ataque em sequência para ao sobrar esse tanto na origem
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
      const mb = moveBlock(s, a.from, a.to);
      if (mb) return mb;
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
      if (poolTotal(s) === 0) endReinforce(s, p);
      return null;
    }
    case 'nuke': {
      const why = nukeBlock(s, p, a.to);
      if (why) return why;
      if (!Array.isArray(a.cards) || !validTrade(a.cards) || !a.cards.every((c) => pl.cards.includes(c))) return 'Para lançar é preciso entregar uma trinca de cartas válida.';
      pl.cards = pl.cards.filter((c) => !a.cards.includes(c));
      s.discard.push(...a.cards);
      const d = T[a.to], def = d.o, v = tradeValue(s.trades), lost = Math.min(d.a - 1, NUKE_MULT * v);
      s.trades++; // ocupa um degrau da escada de trocas
      d.a -= lost;
      pl.lastTrade = 'nuke';
      s.fog = { t: a.to, by: p };
      s.ev.push({ t: 'nuke', p, to: a.to, def, lost, v });
      log(s, `${pl.name} lançou a ogiva sobre ${TERR[a.to].n} (${pname(s, def)}): ${lost} exército${lost === 1 ? '' : 's'} destruído${lost === 1 ? '' : 's'}.`);
      for (const x of s.pacts.filter((q) => q.a === p || q.b === p)) { s.ev.push({ t: 'pactVoid', a: x.a, b: x.b }); log(s, `O pacto entre ${pname(s, x.a)} e ${pname(s, x.b)} acabou com o lançamento.`); }
      s.pacts = s.pacts.filter((q) => q.a !== p && q.b !== p);
      // a ogiva custa o turno: o reforço que restava se perde e a vez passa (cartas que sobrarem ficam para a próxima vez)
      s.pool = { free: 0, cont: {} };
      nextTurn(s, rng);
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

// ---------------------------------------------------------------- bots
// Chance de o atacante conquistar, com a exércitos na origem contra d na defesa (regras deste jogo: até 3 dados de cada
// lado, empate é da defesa, 1 exército fica para trás). Tabela exata, calculada uma vez por programação dinâmica.
let ODDS = null, WIN = null;
function battleOdds() { // ODDS[nA][nD] = lista de [perdaAtaque, perdaDefesa, probabilidade]
  ODDS = {};
  const rolls = (n) => { let out = [[]]; for (let k = 0; k < n; k++) out = out.flatMap((r) => [1, 2, 3, 4, 5, 6].map((x) => [...r, x])); return out.map((r) => r.sort((a, b) => b - a)); };
  for (let nA = 1; nA <= 3; nA++) { ODDS[nA] = {}; for (let nD = 1; nD <= 3; nD++) {
    const acc = {}, A = rolls(nA), D = rolls(nD);
    for (const x of A) for (const y of D) { let la = 0; const m = Math.min(nA, nD); for (let i = 0; i < m; i++) if (x[i] <= y[i]) la++; acc[la] = (acc[la] || 0) + 1; }
    ODDS[nA][nD] = Object.entries(acc).map(([la, c]) => [+la, Math.min(nA, nD) - la, c / (A.length * D.length)]);
  } }
}
const WMAX = 48;
export function winChance(a, d) {
  if (a < 2) return 0;
  if (d < 1) return 1;
  if (a > WMAX || d > WMAX) { const k = WMAX / Math.max(a, d); a = Math.max(2, Math.round(a * k)); d = Math.max(1, Math.round(d * k)); } // pilhas enormes: mesma proporção
  if (!WIN) {
    battleOdds();
    WIN = Array.from({ length: WMAX + 1 }, () => new Float64Array(WMAX + 1));
    for (let x = 0; x <= WMAX; x++) WIN[x][0] = 1;
    for (let y = 1; y <= WMAX; y++) for (let x = 2; x <= WMAX; x++) {
      let pr = 0;
      for (const [la, ld, q] of ODDS[Math.min(3, x - 1)][Math.min(3, y)]) pr += q * (x - la < 2 ? 0 : WIN[x - la][y - ld]);
      WIN[x][y] = pr;
    }
  }
  return WIN[a][d];
}
const CSIZE = CONTINENTS.map((_, c) => TERR.filter((t) => t.c === c).length);

// Leitura do tabuleiro do ponto de vista do jogador p: o que vale a pena conquistar e onde há perigo.
function botView(s, p) {
  const T = s.terr, pl = s.players[p], N = s.players.length;
  const terrs = Array(N).fill(0), arm = Array(N).fill(0);
  const mineIn = CONTINENTS.map(() => 0), owner = CONTINENTS.map(() => null); // owner[c]: dono único do continente, ou -1
  T.forEach((t, i) => { terrs[t.o]++; arm[t.o] += t.a; const c = TERR[i].c; if (t.o === p) mineIn[c]++; owner[c] = owner[c] === null ? t.o : owner[c] === t.o ? t.o : -1; });
  const alive = s.players.map((q, i) => i).filter((i) => s.players[i].alive);
  const power = (q) => terrs[q] * 2 + arm[q];
  const leader = alive.filter((q) => q !== p).sort((a, b) => power(b) - power(a))[0];
  let obj = OBJECTIVES[pl.obj] || { k: 'count' }, killTarget = -1;
  if (obj.k === 'kill') { // objetivo de eliminar alguém; se não dá mais, vira contagem de territórios (como na regra)
    killTarget = s.players.findIndex((q, i) => i !== p && q.alive && q.color === obj.color);
    if (killTarget < 0) obj = { k: 'count' };
  }
  // quanto cada continente interessa: os do objetivo acima de tudo; senão, os que já estão quase na mão e rendem mais por território
  const focus = CONTINENTS.map((ct, c) => {
    const share = mineIn[c] / CSIZE[c];
    let f = share * share * 1.6 + (ct.bonus / CSIZE[c]) * 0.35;
    if (obj.k === 'cont' && obj.c.includes(c)) f += 1.4;
    return f;
  });
  const enemiesOf = (i) => TERR[i].adj.filter((j) => T[j].o !== p);
  const threat = (i) => { let m = 0; for (const j of TERR[i].adj) if (T[j].o !== p && !pactOf(s, p, T[j].o) && T[j].a > 1) m = Math.max(m, T[j].a - 1); return m; };
  // valor de tomar o território j
  const value = (j) => {
    const q = T[j].o, c = TERR[j].c, missing = CSIZE[c] - mineIn[c];
    let v = 1 + focus[c] * 2;
    if (missing <= 2) v += CONTINENTS[c].bonus * (missing === 1 ? 1.6 : 0.7); // fecha (ou quase) um continente
    if (owner[c] === q) v += CONTINENTS[c].bonus * 1.2; // tira o bônus de quem tem o continente inteiro
    if (q === killTarget) v += 3;
    if (terrs[q] <= 2) v += 2.5 + 1.5 * (typeof s.players[q].cards === 'number' ? s.players[q].cards : s.players[q].cards.length); // eliminar rende as cartas dele
    if (q === leader && power(q) > power(p) * 1.25) v += 1.2; // segura quem está disparando na frente
    if (obj.k === 'count') v += 0.8;
    if (!pl.conquered) v += 1.5; // a primeira conquista do turno vale uma carta
    return v;
  };
  return { T, pl, terrs, arm, mineIn, owner, alive, power, leader, killTarget, focus, enemiesOf, threat, value, obj };
}
// Ajuste da chance de vitória pelos eventos da rodada.
const eventOdds = (s, to, pw) => {
  const e = s.event;
  if (!e) return pw;
  if (e.k === 'fort') return pw * 0.78;
  if (e.k === 'charge') return Math.min(1, pw * 1.15 + 0.03);
  if (e.k === 'storm' && TERR[to].c === e.c) return pw * 0.8;
  return pw;
};

// Resposta de um bot a uma proposta de pacto: recusa quem está liderando com folga, quem é o alvo do seu objetivo e quem
// ocupa o continente que ele precisa; aceita de quem é uma ameaça real na fronteira.
export function botPactReply(s) {
  const me = s.offer.to, q = s.offer.from, V = botView(s, me), T = s.terr;
  let no = q === V.killTarget || (V.leader === q && V.power(q) > V.power(me) * 1.3);
  if (!no && V.obj.k === 'cont') { let need = 0, his = 0; T.forEach((t, i) => { if (V.obj.c.includes(TERR[i].c) && t.o !== me) { need++; if (t.o === q) his++; } }); if (need && his / need > 0.5) no = true; }
  let border = 0;
  T.forEach((t, i) => { if (t.o === me && TERR[i].adj.some((j) => T[j].o === q)) border++; });
  return { t: 'pactReply', accept: !no && border > 0 };
}
// Bot: lê o objetivo e o tabuleiro, defende os continentes que tem, distribui os reforços por frentes (em vez de uma pilha só),
// ataca quando a chance compensa o que há a ganhar e para antes de se esvaziar.
// o.noNuke: nunca lança a ogiva (usado quando o jogo joga por um humano cujo tempo acabou). o.noPact: não propõe pactos.
export function botAction(s, o = {}) {
  const p = s.turn, T = s.terr, pl = s.players[p];
  const V = botView(s, p), { enemiesOf, threat, value } = V;
  if (s.occupy) { // leva mais gente se a origem ficou sem inimigos por perto ou se o conquistado está mais exposto
    const { from, to, max } = s.occupy;
    const tf = threat(from), tt = threat(to);
    return { t: 'occupy', n: !enemiesOf(from).length ? max : !enemiesOf(to).length ? 0 : tt >= tf || T[from].a - max > tf ? max : 0 };
  }
  if (s.step === 'reinforce') {
    const tr = bestTrade(pl.cards, T, p);
    if (tr && !o.noNuke && !nukeBlock(s, p)) { // ogiva só quando compensa: a maior pilha do adversário mais forte, se perder bem mais do que a troca e o reforço dariam
      const tg = T.map((t, i) => i).filter((i) => T[i].o === V.leader && !nukeBlock(s, p, i)).sort((a, b) => T[b].a - T[a].a)[0];
      if (tg != null && V.power(V.leader) >= V.power(p) && Math.min(T[tg].a - 1, nukeDamage(s)) >= 1.5 * (tradeValue(s.trades) + poolTotal(s))) return { t: 'nuke', cards: nukeTrade(pl.cards, T, p), to: tg };
    }
    if (tr && (pl.cards.length >= 5 || poolTotal(s) > 0)) return { t: 'trade', cards: tr };
    // pacto: de vez em quando, com o vizinho que mais ameaça e que não é o alvo nem o líder
    if (s.opts && s.opts.pacts && !o.noPact && !s.placed && !s.offer && s.round >= 1 && (s.round + p) % 3 === 0 && V.alive.length > 2
      && pl.offered !== s.round + ':' + s.turn && !s.pacts.some((x) => x.a === p || x.b === p)) {
      const press = {};
      T.forEach((t, i) => { if (t.o === p) for (const j of TERR[i].adj) { const q = T[j].o; if (q !== p) press[q] = (press[q] || 0) + T[j].a; } });
      const q = Object.keys(press).map(Number).filter((q) => q !== V.killTarget && q !== V.leader).sort((a, b) => press[b] - press[a])[0];
      if (q != null && press[q] >= V.arm[p] * 0.25) return { t: 'pactOffer', to: q };
    }
    const mine = T.map((t, i) => i).filter((i) => T[i].o === p && !(s.fog && s.fog.t === i));
    const front = (list) => { const b = list.filter((i) => enemiesOf(i).length); return b.length ? b : list; };
    // 1) bônus de continente: só pode ir no próprio continente; vai para a fronteira mais ameaçada dele
    for (const k of Object.keys(s.pool.cont)) {
      const c = +k, cand = front(mine.filter((i) => TERR[i].c === c)).sort((a, b) => threat(b) - T[b].a - (threat(a) - T[a].a));
      if (cand.length) return { t: 'place', t0: cand[0], n: s.pool.cont[c] };
    }
    const free = s.pool.free, border = front(mine);
    // 2) defesa: fronteira de um continente que já é dele e está fraca diante do vizinho mais forte recebe até metade do que resta
    let worst = null;
    for (const i of border) {
      if (V.owner[TERR[i].c] !== p) continue;
      const lack = Math.ceil(threat(i) * 0.55) - T[i].a;
      if (lack > 0 && (!worst || lack > worst.lack)) worst = { i, lack };
    }
    if (worst && free >= 2) return { t: 'place', t0: worst.i, n: Math.min(worst.lack, Math.ceil(free / 2)) };
    // 3) ataque: em parcelas, cada uma onde mais aumenta a chance de uma conquista que vale a pena (várias frentes, não uma pilha só)
    const chunk = Math.min(free, Math.max(3, Math.ceil(free / 4)));
    let best = null;
    for (const i of border) {
      let g = 0;
      for (const j of enemiesOf(i)) {
        if (s.round > 0 && attackBlock(s, i, j)) continue;
        const gain = value(j) * (winChance(T[i].a + chunk, T[j].a) - winChance(T[i].a, T[j].a)) + value(j) * 0.02 * chunk;
        if (gain > g) g = gain;
      }
      g += Math.max(0, threat(i) - T[i].a) * 0.01; // desempate: onde há mais perigo
      if (!best || g > best.g) best = { i, g };
    }
    return { t: 'place', t0: best.i, n: chunk };
  }
  if (s.step === 'attack') {
    let best = null;
    T.forEach((t, i) => {
      if (t.o !== p || t.a < 2) return;
      for (const j of enemiesOf(i)) {
        if (attackBlock(s, i, j)) continue; // respeita eventos, pactos e névoa
        const pw = eventOdds(s, j, winChance(t.a, T[j].a)), q = T[j].o, c = TERR[j].c;
        const decisive = V.terrs[q] === 1 || CSIZE[c] - V.mineIn[c] === 1 || (V.owner[c] === q && CONTINENTS[c].bonus >= 3);
        const need = !pl.conquered && T[j].a <= 2 ? 0.5 : decisive ? 0.5 : 0.66; // sem carta ainda, ou jogada que muda o jogo: aceita mais risco
        if (pw < need) continue;
        // não abre a guarda de um continente próprio por pouco
        const guard = V.owner[TERR[i].c] === p ? Math.ceil(threat(i) * 0.4) : 0;
        if (t.a - T[j].a < guard && !decisive) continue;
        const sc = value(j) * pw - T[j].a * 0.12;
        if (!best || sc > best.sc) best = { sc, from: i, to: j, keep: Math.max(1, Math.min(t.a - 2, Math.max(guard, Math.floor(T[j].a * 0.7)))) };
      }
    });
    return best ? { t: 'attack', from: best.from, to: best.to, blitz: true, keep: best.keep } : { t: 'endAttack' };
  }
  // remanejamento: leva exércitos do interior em direção à fronteira mais próxima (e, entre as próximas, à mais ameaçada)
  const dist = T.map((t, i) => (t.o === p && enemiesOf(i).length ? 0 : Infinity));
  for (let d = 0, changed = true; changed; d++) {
    changed = false;
    T.forEach((t, i) => {
      if (t.o === p && dist[i] === Infinity && TERR[i].adj.some((j) => dist[j] === d)) { dist[i] = d + 1; changed = true; }
    });
  }
  for (const k of Object.keys(s.movable || {})) {
    const i = +k, n = Math.min(s.movable[i], T[i].a - 1);
    if (n < 1 || dist[i] === 0) continue;
    const j = TERR[i].adj.filter((x) => T[x].o === p && dist[x] < dist[i] && !moveBlock(s, i, x)).sort((a, b) => dist[a] - dist[b] || threat(b) - T[b].a - (threat(a) - T[a].a))[0];
    if (j !== undefined) return { t: 'move', from: i, to: j, n };
  }
  return { t: 'endTurn' };
}
