import { TERR, CONTINENTS, SEA, MAP_W, MAP_H } from './map.js';
import {
  COLORS, SYMBOLS, OBJECTIVES, objectiveText, newGame, apply, viewFor, botAction, owned,
  poolTotal, validTrade, bestTrade, tradeValue, cardSymbol, cardName, mustTrade, handSize,
} from './game.js';
import { createInvite, joinInvite } from './net.js';
import { play, unlock, soundOn, setSound } from './sound.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const store = {
  get(k) { try { return JSON.parse(localStorage.getItem('estandarte.' + k)); } catch { return null; } },
  set(k, v) { try { localStorage.setItem('estandarte.' + k, JSON.stringify(v)); } catch {} },
  del(k) { try { localStorage.removeItem('estandarte.' + k); } catch {} },
};

const app = {
  role: null,      // 'host' | 'guest'
  seats: [],       // anfitrião: [{name,color,ctrl,link}]
  game: null,      // anfitrião: estado completo
  view: null,      // o que este aparelho enxerga
  me: null,        // convidado: meu índice de jogador
  link: null,      // convidado: conexão com o anfitrião
  lobby: null,     // convidado: lista de assentos recebida
  sel: null, target: null, qty: 1, info: null,
  lastRoll: 0, lastViewer: null, botTimer: null,
  cfg: { secs: 120 },   // tempo por turno em segundos (0 = livre)
  tEnd: null, tLimit: 0, // relógio local do turno
  evN: null, peek: null, peekKey: '', turnKey: null, pausedAt: null, lastSec: null,
};
const VERSION = '12'; // manter igual ao sufixo do cache em sw.js
if (new URLSearchParams(location.search).has('debug')) window.__app = app;

/* ---------- utilidades de interface ---------- */
let toastTimer;
function toast(msg, ms = 2600) {
  const t = $('#toast');
  t.textContent = msg; t.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => (t.hidden = true), ms);
}
let modalCleanup = null;
function modal(html, onClose) {
  closeModal();
  $('#modal .sheet').onclick = null;
  $('#modal .sheet').innerHTML = html;
  $('#modal').hidden = false;
  modalCleanup = onClose || null;
}
function closeModal() {
  if (modalCleanup) { const f = modalCleanup; modalCleanup = null; f(); }
  $('#modal').hidden = true; $('#modal .sheet').innerHTML = '';
}
function show(id) {
  for (const s of document.querySelectorAll('.screen')) s.hidden = s.id !== id;
  if (id === 'game') requestAnimationFrame(fitView);
}
const myName = () => ($('#name').value.trim() || 'Jogador').slice(0, 14);

function drawQr(text) {
  const qr = qrcode(0, 'L'); qr.addData(text); qr.make();
  const n = qr.getModuleCount(), q = 3, cell = 6;
  const c = document.createElement('canvas');
  c.width = c.height = (n + 2 * q) * cell;
  const g = c.getContext('2d');
  g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); g.fillStyle = '#000';
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (qr.isDark(y, x)) g.fillRect((x + q) * cell, (y + q) * cell, cell, cell);
  return c;
}
const inviteUrl = (code) => `${location.origin}${location.pathname}#j=${encodeURIComponent(code)}`;
function extractCode(text) {
  text = String(text || '').trim();
  const m = text.match(/#j=([^\s]+)/);
  if (m) { try { return decodeURIComponent(m[1]); } catch { return m[1]; } }
  return text;
}

// Pedir a câmera antes de criar a conexão tem um segundo efeito: com a permissão concedida,
// o navegador informa o IP local real em vez de um nome mDNS, que outros aparelhos da rede
// (principalmente Android) muitas vezes não conseguem resolver.
const stopStream = (s) => s && s.getTracks().forEach((t) => t.stop());
async function openCamera() {
  try { return await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false }); } catch { return null; }
}
const guestId = () => {
  let id = store.get('gid');
  if (!id) { id = Math.random().toString(36).slice(2) + Date.now().toString(36); store.set('gid', id); }
  return id;
};

// Abre a câmera dentro de `box` e chama onCode a cada QR lido. Retorna função para parar.
// Se `shared` for passado, usa esse stream e não o encerra ao parar.
function startScanner(box, onCode, shared) {
  let stream, raf, stopped = false;
  const video = document.createElement('video');
  video.setAttribute('playsinline', ''); video.muted = true;
  box.replaceChildren(video);
  const canvas = document.createElement('canvas'), g = canvas.getContext('2d', { willReadFrequently: true });
  const tick = () => {
    if (stopped) return;
    if (video.readyState >= 2 && video.videoWidth) {
      const s = Math.min(1, 640 / video.videoWidth);
      canvas.width = video.videoWidth * s; canvas.height = video.videoHeight * s;
      g.drawImage(video, 0, 0, canvas.width, canvas.height);
      const img = g.getImageData(0, 0, canvas.width, canvas.height);
      const r = jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' });
      if (r && r.data && onCode(r.data) !== false) return;
    }
    raf = requestAnimationFrame(tick);
  };
  const live = shared && shared.getTracks().some((t) => t.readyState === 'live');
  (live ? Promise.resolve(shared) : openCamera()).then((s) => {
    if (!s) { box.innerHTML = '<p>Não foi possível abrir a câmera. Use o campo de código abaixo.</p>'; return; }
    stream = s;
    if (stopped) { if (!live) stopStream(s); return; }
    video.srcObject = s; video.play().catch(() => {}); tick();
  });
  return () => { stopped = true; cancelAnimationFrame(raf); if (!live) stopStream(stream); };
}

async function copyText(text) {
  try { await navigator.clipboard.writeText(text); toast('Copiado.'); } catch { toast('Não foi possível copiar; selecione o texto manualmente.'); }
}

/* ---------- anfitrião ---------- */
const freeColor = () => COLORS.findIndex((_, i) => !app.seats.some((s) => s.color === i));
function hostStart() {
  app.role = 'host'; app.game = null;
  app.seats = [{ name: myName(), color: 0, ctrl: 'local' }];
  show('lobby'); renderLobby();
}
function seatOfLink(link) { return app.seats.findIndex((s) => s.link === link); }
function playerOfSeat(si) { return app.game ? app.game.players.findIndex((p) => p.seat === si) : -1; }

function hostHandlers(targetSeat) {
  return {
    onopen() {},
    onmessage(msg, link) {
      if (msg.t === 'hello') {
        const name = String(msg.name || 'Convidado').slice(0, 14);
        const gid = String(msg.gid || '').slice(0, 40);
        // quem já tinha assento (mesmo aparelho) volta para ele, inclusive no meio da partida
        let si = targetSeat;
        if (si == null && gid) { const k = app.seats.findIndex((s) => s.gid === gid && s.ctrl !== 'local'); if (k >= 0) si = k; }
        if (si != null && app.seats[si]) {
          const st = app.seats[si];
          if (st.link && st.link !== link) { const old = st.link; st.link = null; old.close(); }
          st.link = link; st.ctrl = 'remote'; if (gid) st.gid = gid;
          const pi = playerOfSeat(si);
          if (pi >= 0) app.game.players[pi].ctrl = 'remote';
          toast(`${st.name} ${app.game ? 'voltou à partida' : 'conectou'}.`);
        } else if (!app.game && app.seats.length < 6) {
          app.seats.push({ name, color: freeColor(), ctrl: 'remote', link, gid });
          toast(`${name} conectou.`);
        } else return link.send({ t: 'err', m: app.game ? 'A partida já começou. Peça ao anfitrião o QR do seu jogador (menu ☰).' : 'A sala está cheia.' });
        closeModal();
        sync();
      } else if (msg.t === 'peek' && app.game) {
        if (playerOfSeat(seatOfLink(link)) !== app.game.turn) return;
        app.peek = { n: msg.n | 0, sel: msg.sel, target: msg.target };
        app.seats.forEach((s) => s.link && s.link !== link && s.link.send({ t: 'peek', ...app.peek }));
        renderGame();
      } else if (msg.t === 'act' && app.game) {
        const pi = playerOfSeat(seatOfLink(link));
        if (pi < 0) return;
        const err = apply(app.game, pi, msg.a);
        if (err) link.send({ t: 'err', m: err });
        sync();
      }
    },
    onclose(link) {
      const si = seatOfLink(link);
      if (si < 0) return;
      app.seats[si].link = null;
      toast(`${app.seats[si].name} desconectou.`);
      if (!app.game) app.seats.splice(si, 1);
      sync();
    },
  };
}

async function hostInvite(targetSeat = null) {
  modal('<h3>Preparando convite…</h3><p>Se o navegador pedir, permita a câmera: ela lê o QR de resposta e ajuda os aparelhos a se encontrarem na rede local.</p>');
  const camStream = await openCamera();
  if (app.game && !app.pausedAt) { app.pausedAt = Date.now(); sync(); } // relógio do turno pausa durante o pareamento
  let inv, stop = () => {};
  try { inv = await createInvite(hostHandlers(targetSeat)); }
  catch (e) { stopStream(camStream); app.pausedAt = null; closeModal(); return toast('Seu navegador não conseguiu criar a conexão.'); }
  const url = inviteUrl(inv.code);
  const accept = (raw) => {
    const code = extractCode(raw);
    if (!/^1~a/.test(code)) { toast('Esse não é o QR de resposta do convidado.'); return false; }
    stop(); stop = () => {};
    $('#scanbox').innerHTML = '<p>Conectando…</p>';
    inv.accept(code).catch(() => toast('Resposta inválida.'));
    setTimeout(() => {
      if (!inv.link.open && $('#scanbox')) $('#scanbox').innerHTML = '<p class="off">Não conectou. Confiram se os aparelhos estão na mesma rede Wi-Fi (ou no hotspot de um deles) e gerem um novo convite.</p>';
    }, 15000);
  };
  modal(`<h3>${targetSeat != null ? 'Reconectar ' + esc(app.seats[targetSeat].name) : app.game ? 'Reconectar jogador' : 'Convidar jogador'}</h3>
    <ol><li>O convidado abre o jogo, toca em “${app.game ? 'Reconectar à partida' : 'Entrar em partida'}” e lê este QR (a câmera do celular também serve).</li>
    <li>O celular dele mostra um QR de resposta: aponte a câmera deste aparelho para ele${camStream ? '. A leitura é automática' : ''}.</li></ol>
    <div class="qr" id="qrbox"></div>
    <div id="scanbox" class="scan-mini"></div>
    <div class="row"><button class="btn small" data-m="copy">Copiar link</button>${camStream ? '' : '<button class="btn small primary" data-m="scan">Abrir câmera</button>'}</div>
    <label class="field">Ou cole o código de resposta<textarea id="paste" rows="2"></textarea></label>
    <div class="row"><button class="btn small" data-m="ok">Usar código colado</button><button class="btn small ghost" data-m="close">Cancelar</button></div>`,
  () => {
    stop(); stopStream(camStream);
    if (!inv.link.open) setTimeout(() => !inv.link.open && inv.cancel(), 20000);
    if (app.pausedAt) { if (app.game && app.game.tEnd) app.game.tEnd += Date.now() - app.pausedAt; app.pausedAt = null; sync(); }
  });
  $('#qrbox').append(drawQr(url));
  if (camStream) stop = startScanner($('#scanbox'), accept, camStream);
  $('#modal .sheet').onclick = (e) => {
    const m = e.target.dataset.m;
    if (m === 'copy') copyText(url);
    if (m === 'scan') stop = startScanner($('#scanbox'), accept, camStream);
    if (m === 'ok') accept($('#paste').value);
    if (m === 'close') { inv.cancel(); closeModal(); }
  };
}

function hostBegin() {
  app.game = newGame(app.seats.map((s) => ({ name: s.name, color: s.color, ctrl: s.ctrl })));
  app.game.limit = app.cfg.secs;
  app.sel = app.target = null; app.lastViewer = null; app.turnKey = null; app.evN = null;
  show('game'); sync();
}

// Propaga o estado: salva, envia a cada convidado a visão dele e redesenha.
function sync() {
  if (app.role !== 'host') return;
  const g = app.game;
  const pub = app.seats.map((s) => ({ name: s.name, color: s.color, ctrl: s.ctrl, on: s.ctrl !== 'remote' || !!s.link }));
  let left = null;
  if (g) { // relógio do turno: reinicia quando o turno muda; bots não têm relógio
    const key = g.round + ':' + g.turn;
    if (key !== app.turnKey) { app.turnKey = key; g.tEnd = g.limit ? Date.now() + g.limit * 1000 : null; }
    if (g.tEnd && g.phase === 'play' && g.players[g.turn].ctrl !== 'bot' && !app.pausedAt) left = Math.max(0, g.tEnd - Date.now());
    app.tEnd = left == null ? null : Date.now() + left; app.tLimit = (g.limit || 0) * 1000;
  }
  app.seats.forEach((s, si) => {
    if (!s.link) return;
    if (g) { const pi = playerOfSeat(si); s.link.send({ t: 'state', s: viewFor(g, pi), you: pi, left, limit: g.limit || 0 }); }
    else s.link.send({ t: 'lobby', seats: pub, you: si, secs: app.cfg.secs });
  });
  if (g) {
    store.set('save3', { seats: app.seats.map(({ link, ...s }) => s), game: g });
    app.view = viewFor(g, viewer());
    renderGame(); scheduleBot();
  } else renderLobby();
}
function scheduleBot() {
  clearTimeout(app.botTimer);
  const g = app.game;
  if (!g || g.phase !== 'play' || g.players[g.turn].ctrl !== 'bot') return;
  app.botTimer = setTimeout(() => { apply(g, g.turn, botAction(g)); sync(); }, g.step === 'attack' ? 900 : 450);
}
function viewer() {
  if (app.role === 'guest') return app.me;
  const g = app.game;
  if (g.players[g.turn].ctrl === 'local') return g.turn;
  if (app.lastViewer != null && g.players[app.lastViewer].ctrl === 'local') return app.lastViewer;
  const i = g.players.findIndex((p) => p.ctrl === 'local' && p.alive);
  return i >= 0 ? i : g.players.findIndex((p) => p.ctrl === 'local');
}

/* ---------- convidado ---------- */
const guestHandlers = {
  onopen(link) {
    app.role = 'guest'; app.link = link;
    link.send({ t: 'hello', name: myName(), gid: guestId() });
    store.set('guest', true);
    closeModal(); toast('Conectado!');
  },
  onmessage(msg) {
    if (msg.t === 'lobby') { app.lobby = msg; app.view = null; show('lobby'); renderLobby(); }
    else if (msg.t === 'state') {
      app.view = msg.s; app.me = msg.you;
      app.tEnd = msg.left == null ? null : Date.now() + msg.left; app.tLimit = (msg.limit || 0) * 1000;
      if ($('#game').hidden) show('game');
      renderGame();
    } else if (msg.t === 'peek') { app.peek = msg; renderGame(); }
    else if (msg.t === 'err') toast(msg.m);
  },
  onclose(link) {
    if (app.link !== link) return;
    app.link = null;
    toast('Conexão perdida. Peça um novo QR ao anfitrião (menu ☰ → reconectar).', 6000);
    if (app.view) renderGame(); else { show('home'); }
  },
};
async function guestJoin(raw) {
  const code = extractCode(raw);
  if (!/^1~o/.test(code)) return toast('Esse não é um QR de convite.');
  modal('<h3>Preparando resposta…</h3><p>Se o navegador pedir, permita a câmera: sem ela a conexão na rede local pode não abrir.</p>');
  const camStream = await openCamera();
  let j;
  try { j = await joinInvite(code, guestHandlers); }
  catch (e) { closeModal(); return toast('Convite inválido ou expirado.'); }
  finally { stopStream(camStream); }
  if (app.link) { const old = app.link; app.link = null; old.close(); }
  modal(`<h3>Mostre este QR ao anfitrião</h3><p>No celular dele: “Ler resposta”. A conexão abre sozinha em seguida.</p>
    <div class="qr" id="qrbox"></div>
    <div class="row"><button class="btn small" data-m="copy">Copiar código</button><button class="btn small ghost" data-m="close">Cancelar</button></div>`);
  $('#qrbox').append(drawQr(j.code));
  $('#modal .sheet').onclick = (e) => {
    if (e.target.dataset.m === 'copy') copyText(j.code);
    if (e.target.dataset.m === 'close') { j.cancel(); closeModal(); }
  };
}
function guestScan() {
  let stop = () => {};
  modal(`<h3>${store.get('guest') ? 'Reconectar à partida' : 'Entrar em partida'}</h3><p>Aponte para o QR na tela do anfitrião${store.get('guest') ? ' (ele gera um novo em ☰ → Reconectar por QR)' : ''}.</p><div id="scanbox"></div>
    <label class="field">Ou cole o link/código do convite<textarea id="paste" rows="2"></textarea></label>
    <div class="row"><button class="btn small" data-m="ok">Usar código colado</button><button class="btn small ghost" data-m="close">Cancelar</button></div>`,
  () => stop());
  const go = (raw) => {
    if (!/^1~o/.test(extractCode(raw))) return false;
    stop(); stop = () => {}; guestJoin(raw);
  };
  stop = startScanner($('#scanbox'), go);
  $('#modal .sheet').onclick = (e) => {
    if (e.target.dataset.m === 'ok') { if (go($('#paste').value) === false) toast('Código de convite inválido.'); }
    if (e.target.dataset.m === 'close') closeModal();
  };
}

/* ---------- sala ---------- */
function renderLobby() {
  const host = app.role === 'host';
  const seats = host ? app.seats.map((s) => ({ ...s, on: s.ctrl !== 'remote' || !!s.link })) : app.lobby.seats;
  const kind = { local: 'neste aparelho', remote: 'outro aparelho', bot: 'bot' };
  $('#seats').innerHTML = seats.map((s, i) => `<li>
    <button class="dot" style="background:${COLORS[s.color].c}" ${host ? `data-color="${i}"` : 'disabled'} aria-label="Trocar cor"></button>
    <span class="who"><b>${esc(s.name)}</b>${!host && i === app.lobby.you ? ' (você)' : ''}<small>${COLORS[s.color].n} · ${kind[s.ctrl]}</small></span>
    ${host && i > 0 ? `<button class="btn small ghost" data-kick="${i}" aria-label="Remover">✕</button>` : ''}</li>`).join('');
  const full = seats.length >= 6;
  $('#lobbyActions').innerHTML = host
    ? `<div class="setting">Tempo por turno<span class="chips">${[[0, 'Livre'], [60, '1 min'], [120, '2 min'], [180, '3 min']].map(([v, l]) => `<button class="chip${app.cfg.secs === v ? ' on' : ''}" data-secs="${v}">${l}</button>`).join('')}</span></div>
       <div class="row"><button class="btn" data-do="invite" ${full ? 'disabled' : ''}>Convidar por QR</button></div>
       <div class="row"><button class="btn small" data-do="addLocal" ${full ? 'disabled' : ''}>+ Jogador neste aparelho</button><button class="btn small" data-do="addBot" ${full ? 'disabled' : ''}>+ Bot</button></div>
       <button class="btn primary" data-do="begin" ${seats.length < 2 ? 'disabled' : ''}>Iniciar partida (${seats.length} jogadores)</button>
       <button class="btn ghost" data-do="leave">Sair</button>`
    : `<p class="tag">Tempo por turno: ${app.lobby.secs ? app.lobby.secs / 60 + ' min' : 'livre'}. Aguardando o anfitrião iniciar…</p><button class="btn ghost" data-do="leave">Sair</button>`;
}

/* ---------- mapa ---------- */
const SVGNS = 'http://www.w3.org/2000/svg';
const svg = $('#map');
const el = (tag, attrs, parent) => {
  const e = document.createElementNS(SVGNS, tag);
  for (const k in attrs) e.setAttribute(k, attrs[k]);
  parent && parent.append(e);
  return e;
};
const PAD = 30;
const nodes = [];
(function buildMap() {
  const aura = el('g', {}, svg), routes = el('g', {}, svg), depth = el('g', {}, svg), land = el('g', {}, svg), moat = el('g', {}, svg), labels = el('g', {}, svg), hits = el('g', {}, svg);
  SEA.forEach(([a, b, wrap]) => {
    const A = TERR[a], B = TERR[b];
    if (wrap) { // rota que dá a volta no mapa: um trecho até cada borda
      const [l, r] = A.x < B.x ? [A, B] : [B, A];
      el('line', { class: 'sea-route', x1: l.x, y1: l.y, x2: -PAD, y2: l.y }, routes);
      el('line', { class: 'sea-route', x1: r.x, y1: r.y, x2: MAP_W + PAD, y2: r.y }, routes);
    } else el('line', { class: 'sea-route', x1: A.x, y1: A.y, x2: B.x, y2: B.y }, routes);
  });
  TERR.forEach((t, i) => {
    const col = CONTINENTS[t.c].color;
    const poly = el('path', { class: 'terr', d: t.d, 'data-t': i, 'fill-rule': 'evenodd' }, land);
    // marcador (exércitos + nome) num grupo próprio, para poder manter o tamanho na tela ao afastar o zoom
    const g = el('g', { class: 'mark' }, hits);
    el('text', { class: 'tname', x: 0, y: 24 }, g).textContent = t.n;
    const badge = el('circle', { class: 'badge', cx: 0, cy: 0, r: 12.5 }, g);
    const num = el('text', { class: 'num', x: 0, y: 0.5 }, g);
    el('circle', { class: 'hit', cx: 0, cy: 0, r: 19, 'data-t': i }, g);
    nodes.push({ poly, num, badge, g });
  });
  CONTINENTS.forEach((c, ci) => {
    el('text', { class: 'cname', x: c.x, y: c.y, fill: c.color }, labels).textContent = `${c.n} +${c.bonus}`;
    // Continente como "ilha": por baixo da terra, uma faixa na cor do continente que aparece só no mar;
    // por cima, um canal escuro no contorno externo, que separa a terra da faixa e um continente do outro.
    el('path', { class: 'aura', d: c.d, stroke: c.color }, aura);
    el('path', { class: 'auracut', d: c.d }, aura);
    el('path', { class: 'moat', d: c.d }, moat);
    el('path', { class: 'depth', d: c.d, 'fill-rule': 'evenodd' }, depth); // "espessura" do tabuleiro, deslocada para baixo
  });
})();
let markK = 0;
function scaleMarks() {
  // ao afastar o zoom os marcadores crescem (até um limite) para continuarem legíveis e tocáveis
  const k = Math.round(Math.min(2.2, Math.max(1, 10.5 / (12.5 * cam.z))) * 50) / 50;
  svg.classList.toggle('far', cam.z < 0.5);
  // contornos de continente com espessura limitada em pixels: ao aproximar o zoom eles não engrossam
  // nem cobrem ilhas e territórios estreitos
  const u = (units, px) => Math.min(units, px / cam.z).toFixed(2);
  const cut = +u(8, 9);
  svg.style.setProperty('--moat', u(3.2, 4));
  svg.style.setProperty('--cut', cut);
  svg.style.setProperty('--aura', (cut + +u(5.5, 6)).toFixed(2));
  svg.style.setProperty('--depth', u(3, 3.5) + 'px');
  if (k === markK) return;
  markK = k;
  nodes.forEach((nd, i) => nd.g.setAttribute('transform', `translate(${TERR[i].x} ${TERR[i].y}) scale(${k})`));
}

// Pan e zoom por viewBox, mantendo a proporção do contêiner.
const cam = { x: 0, y: 0, z: 1 };
// Caixa do mapa sem a inclinação em perspectiva (o retângulo transformado não serve para as contas de zoom).
function boxOf() { const b = $('#mapwrap').getBoundingClientRect(); return { left: b.left, top: b.top, width: svg.clientWidth, height: svg.clientHeight }; }
function limits() {
  const r = boxOf();
  const contain = Math.min(r.width / (MAP_W + 2 * PAD), r.height / (MAP_H + 2 * PAD));
  const cover = Math.max(r.width / MAP_W, r.height / MAP_H);
  return { r, contain, cover, max: Math.max(cover * 2.2, 1.4) };
}
function applyCam() {
  const { r, contain, max } = limits();
  if (!r.width) return;
  cam.z = Math.min(max, Math.max(contain, cam.z));
  const w = r.width / cam.z, h = r.height / cam.z;
  const clamp = (v, size, total) => (size >= total + 2 * PAD ? (total - size) / 2 : Math.min(total + PAD - size, Math.max(-PAD, v)));
  cam.x = clamp(cam.x, w, MAP_W); cam.y = clamp(cam.y, h, MAP_H);
  svg.setAttribute('viewBox', `${cam.x} ${cam.y} ${w} ${h}`);
  scaleMarks();
}
let camReady = false;
function fitView(toggle) {
  const { r, contain, cover } = limits();
  if (!r.width) return;
  const mid = Math.min(cover, contain * 2.4);
  if (toggle === true) cam.z = Math.abs(cam.z - contain) < 0.01 ? mid : contain;
  else if (camReady) return applyCam();
  else cam.z = mid;
  camReady = true;
  cam.x = (MAP_W - r.width / cam.z) / 2; cam.y = (MAP_H - r.height / cam.z) / 2;
  applyCam();
}
const ptrs = new Map();
let gesture = null;
svg.addEventListener('pointerdown', (e) => {
  ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (ptrs.size === 1) gesture = { sx: e.clientX, sy: e.clientY, moved: false, id: e.pointerId };
  else if (gesture) gesture.moved = true;
});
svg.addEventListener('pointermove', (e) => {
  const p = ptrs.get(e.pointerId);
  if (!p) return;
  const prev = [...ptrs.values()].map((q) => ({ ...q }));
  p.x = e.clientX; p.y = e.clientY;
  const cur = [...ptrs.values()];
  const r = boxOf();
  if (cur.length === 1) {
    if (gesture && !gesture.moved && Math.hypot(e.clientX - gesture.sx, e.clientY - gesture.sy) < 8) return;
    if (gesture) gesture.moved = true;
    cam.x -= (cur[0].x - prev[0].x) / cam.z; cam.y -= (cur[0].y - prev[0].y) / cam.z;
  } else if (cur.length === 2) {
    const d0 = Math.hypot(prev[0].x - prev[1].x, prev[0].y - prev[1].y), d1 = Math.hypot(cur[0].x - cur[1].x, cur[0].y - cur[1].y);
    const mx = (cur[0].x + cur[1].x) / 2 - r.left, my = (cur[0].y + cur[1].y) / 2 - r.top;
    const pmx = (prev[0].x + prev[1].x) / 2 - r.left, pmy = (prev[0].y + prev[1].y) / 2 - r.top;
    const wx = cam.x + pmx / cam.z, wy = cam.y + pmy / cam.z;
    const { contain, max } = limits();
    cam.z = Math.min(max, Math.max(contain, cam.z * (d1 / (d0 || 1))));
    cam.x = wx - mx / cam.z; cam.y = wy - my / cam.z;
  }
  applyCam();
});
const endPtr = (e) => {
  const had = ptrs.delete(e.pointerId);
  if (had && e.type === 'pointerup' && gesture && gesture.id === e.pointerId && !gesture.moved && ptrs.size === 0) {
    const hit = document.elementFromPoint(e.clientX, e.clientY);
    let t = hit && hit.dataset && hit.dataset.t != null ? +hit.dataset.t : null;
    if (t == null) { // toque no mar: aceita o território cujo marcador está a até 24px do dedo
      let best = 24; // medido na tela, para valer também com o mapa em perspectiva
      nodes.forEach((nd, i) => { const b = nd.badge.getBoundingClientRect(), d = Math.hypot(b.left + b.width / 2 - e.clientX, b.top + b.height / 2 - e.clientY); if (d < best) { best = d; t = i; } });
    }
    if (t != null) tapTerritory(t);
    else { app.sel = app.target = null; renderGame(); }
  }
  if (ptrs.size === 0) gesture = null;
};
svg.addEventListener('pointerup', endPtr); svg.addEventListener('pointercancel', endPtr); svg.addEventListener('pointerleave', endPtr);
svg.addEventListener('wheel', (e) => {
  e.preventDefault();
  const r = boxOf(), mx = e.clientX - r.left, my = e.clientY - r.top;
  const wx = cam.x + mx / cam.z, wy = cam.y + my / cam.z;
  cam.z *= e.deltaY < 0 ? 1.15 : 1 / 1.15; applyCam();
  cam.x = wx - mx / cam.z; cam.y = wy - my / cam.z; applyCam();
}, { passive: false });
addEventListener('resize', () => { if (!$('#game').hidden) applyCam(); });
$('#fit').onclick = () => fitView(true);

/* ---------- alertas, efeitos e relógio ---------- */
const buzz = (p) => { try { navigator.vibrate && navigator.vibrate(p); } catch {} };
// Alerta grande no meio da tela; some sozinho em 1 s. Alertas do próprio jogador (urgentes)
// passam na frente dos demais, para "Sua vez!" nunca ficar preso atrás de avisos de outros.
const flashQ = [];
let flashCur = null, flashTimer = null;
function flash(text, color, sub = '', ms = 1000, urgent = false) {
  const f = { text, color, sub, ms, urgent };
  if (urgent) { for (let i = flashQ.length - 1; i >= 0; i--) if (!flashQ[i].urgent) flashQ.splice(i, 1); }
  else { const i = flashQ.findIndex((q) => !q.urgent); if (i >= 0) flashQ.splice(i, 1); }
  flashQ.push(f);
  if (flashQ.length > 3) flashQ.shift();
  if (!flashCur || (urgent && !flashCur.urgent)) nextFlash();
}
function nextFlash() {
  clearTimeout(flashTimer);
  const f = flashQ.shift(), box = $('#flash');
  flashCur = f || null;
  if (!f) { box.hidden = true; return; }
  box.querySelector('b').textContent = f.text; box.querySelector('small').textContent = f.sub;
  box.style.setProperty('--c', f.color || '#f1e6cf'); box.style.animationDuration = f.ms + 'ms';
  box.hidden = false; box.classList.remove('go'); void box.offsetWidth; box.classList.add('go');
  flashTimer = setTimeout(nextFlash, f.ms);
}
const fx = el('g', { class: 'fx' }, svg);
const later = (node, ms) => setTimeout(() => node.remove(), ms);
function fxFloat(t, text, color, dy = 0) {
  const n = el('text', { class: 'fx-float', x: TERR[t].x, y: TERR[t].y - 18 + dy, fill: color }, fx);
  n.textContent = text; later(n, 1400);
}
function fxPulse(t, color, big) { later(el('circle', { class: 'fx-pulse' + (big ? ' big' : ''), cx: TERR[t].x, cy: TERR[t].y, r: 13, stroke: color }, fx), 1300); }
function fxArrow(a, b, color) {
  const A = TERR[a], B = TERR[b];
  if (Math.abs(A.x - B.x) < MAP_W / 2) later(el('line', { class: 'fx-arrow', x1: A.x, y1: A.y, x2: B.x, y2: B.y, stroke: color }, fx), 1100);
  later(el('circle', { class: 'fx-dot', cx: B.x, cy: B.y, r: 7, fill: color, stroke: '#fff', 'stroke-width': 2 }, fx), 1100);
}
function shake(big) { svg.classList.remove('shake', 'shake2'); void svg.getBoundingClientRect(); svg.classList.add(big ? 'shake2' : 'shake'); }

const PHASE_ALERT = {
  reinforce: ['Reforço', 'Reforce seus territórios'],
  attack: ['Ataque!', 'Toque num território seu e num vizinho inimigo'],
  move: ['Remanejamento', 'Mova tropas ou encerre o turno'],
};
// Transforma os eventos da última ação em animações, vibração e alertas.
function processEvents(v) {
  if (app.evN === v.n) return;
  const first = app.evN == null;
  app.evN = v.n;
  const col = (p) => COLORS[v.players[p].color].c, nm = (p) => v.players[p].name;
  const mine = (p) => (app.role === 'guest' ? p === app.me : v.players[p].ctrl === 'local');
  for (const e of v.ev || []) {
    if (first && e.t !== 'turn') continue;
    if (e.t === 'turn') {
      if (v.phase !== 'play') continue;
      if (mine(e.p)) { flash('Sua vez!', col(e.p), v.round === 0 ? 'Distribua seus exércitos' : PHASE_ALERT.reinforce[1], 1000, true); buzz([120, 60, 120]); play('turn'); }
      else { flash(`Vez de ${nm(e.p)}`, col(e.p)); play('other'); }
    } else if (e.t === 'phase') {
      if (mine(e.p)) { flash(PHASE_ALERT[e.step][0], col(e.p), PHASE_ALERT[e.step][1], 1000, true); buzz(40); play('phase'); }
    } else if (e.t === 'place') { fxPulse(e.to, col(e.p)); fxFloat(e.to, '+' + e.k, '#fff'); play('place'); }
    else if (e.t === 'trade') {
      flash(mine(e.p) ? `+${e.v} exércitos` : `${nm(e.p)} trocou cartas`, col(e.p), mine(e.p) ? (e.auto ? 'Troca automática de cartas' : 'Troca de cartas') : `+${e.v} exércitos`, 1000, mine(e.p));
      (e.bonus || []).forEach((t) => { fxPulse(t, col(e.p)); fxFloat(t, '+2', '#fff'); });
      play('trade');
    }
    else if (e.t === 'move') { fxArrow(e.from, e.to, col(e.p)); fxFloat(e.to, '+' + e.k, '#fff'); play('move'); }
    else if (e.t === 'attack') {
      fxArrow(e.from, e.to, col(e.p));
      if (e.la) fxFloat(e.from, '−' + e.la, '#ff8a7a');
      if (e.ld) fxFloat(e.to, '−' + e.ld, '#ff8a7a');
      shake(e.won);
      const involved = mine(e.p) || mine(e.def);
      play('dice'); play(!e.won ? 'attack' : mine(e.def) && !mine(e.p) ? 'lost' : 'conquer');
      if (e.won) {
        fxPulse(e.to, col(e.p), true);
        if (involved) buzz([80, 40, 160]);
        if (mine(e.p)) flash('Conquistou!', col(e.p), TERR[e.to].n, 1000, true);
        else if (mine(e.def)) flash('Território perdido', col(e.p), `${nm(e.p)} tomou ${TERR[e.to].n}`, 1000, true);
        else flash(`${nm(e.p)} conquistou`, col(e.p), TERR[e.to].n);
      } else if (involved) buzz(70);
    } else if (e.t === 'card') { if (mine(e.p)) { flash('Carta recebida', col(e.p), 'Toque no ícone de cartas para ver'); play('card'); } }
    else if (e.t === 'dead') { flash(`${nm(e.p)} eliminado`, col(e.by), `por ${nm(e.by)}`); if (mine(e.p)) buzz([200, 80, 200]); play('dead'); }
    else if (e.t === 'timeout') { flash(mine(e.p) ? 'Tempo esgotado!' : `Tempo de ${nm(e.p)} esgotou`, '#e06a5a', '', 1000, mine(e.p)); play('timeout'); }
    else if (e.t === 'win') { play('win'); flash(`${nm(e.p)} venceu!`, col(e.p), '', 2500, true); buzz([150, 80, 150, 80, 300]); }
  }
}

// Tempo esgotado: o anfitrião termina o turno pelo jogador (reforços automáticos, sem ataques).
function forceEnd() {
  const g = app.game, p = g.turn, key = g.round + ':' + g.turn;
  const same = () => g.phase === 'play' && g.round + ':' + g.turn === key;
  for (let i = 0; i < 80 && same() && g.step === 'reinforce'; i++) if (apply(g, g.turn, botAction(g))) break;
  if (same() && g.occupy) apply(g, g.turn, { t: 'occupy', n: 0 });
  if (same() && g.step === 'attack') apply(g, g.turn, { t: 'endAttack' });
  if (same() && g.step === 'move') apply(g, g.turn, { t: 'endTurn' });
  g.ev.unshift({ t: 'timeout', p });
  g.log.push(`O tempo de ${g.players[p].name} esgotou.`);
  app.sel = app.target = null;
  sync();
}
setInterval(() => {
  const v = app.view, bar = $('#timer');
  const on = v && v.phase === 'play' && app.tEnd && app.tLimit && !$('#game').hidden;
  bar.hidden = !on;
  if (!on) { app.lastSec = null; return; }
  const left = app.tEnd - Date.now(), secs = Math.max(0, Math.ceil(left / 1000));
  bar.querySelector('i').style.transform = `scaleX(${Math.max(0, Math.min(1, left / app.tLimit))})`;
  bar.querySelector('b').textContent = secs >= 60 ? `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}` : secs + ' s';
  bar.classList.toggle('low', secs <= 10);
  if (secs !== app.lastSec) {
    if (canAct() && app.lastSec != null) {
      if (secs === 10) { flash('10 segundos!', '#e06a5a', 'O turno vai encerrar sozinho', 1000, true); buzz([60, 40, 60]); play('warn'); }
      else if (secs <= 5 && secs > 0) { buzz(35); play('tick'); }
    }
    app.lastSec = secs;
  }
  if (app.role === 'host' && !app.pausedAt && app.game && app.game.tEnd && Date.now() > app.game.tEnd + 250 && app.game.players[app.game.turn].ctrl !== 'bot') forceEnd();
}, 250);

/* ---------- partida ---------- */
const canAct = () => {
  const v = app.view;
  if (!v || v.phase !== 'play') return false;
  if (app.role === 'guest') return v.turn === app.me && !!app.link;
  return v.players[v.turn].ctrl === 'local';
};
function act(a) {
  if (app.role === 'guest') return app.link ? app.link.send({ t: 'act', a }) : toast('Sem conexão com o anfitrião.');
  const err = apply(app.game, app.game.turn, a);
  if (err) toast(err);
  sync();
}
function tapTerritory(t) {
  const v = app.view;
  if (!v) return;
  app.info = t;
  const me = v.turn, T = v.terr, mine = T[t].o === me, adj = (a, b) => TERR[a].adj.includes(b);
  const n = app.qty === 'all' ? 9999 : app.qty;
  if (canAct()) {
    if (v.step === 'reinforce') {
      if (mine) { if (mustTrade(v)) toast('Com 5 cartas é obrigatório trocar antes.'); else return act({ t: 'place', t0: t, n }); }
    } else if (v.step === 'attack' && !v.occupy) {
      if (mine) { app.sel = T[t].a >= 2 ? t : null; app.target = null; if (T[t].a < 2) toast('É preciso 2 ou mais exércitos para atacar daqui.'); }
      else if (app.sel != null && adj(app.sel, t)) app.target = t;
      else { app.target = null; if (app.sel != null) toast('Esse território não faz fronteira com o selecionado.'); }
    } else if (v.step === 'move') {
      if (mine && app.sel != null && adj(app.sel, t)) return act({ t: 'move', from: app.sel, to: t, n });
      if (!mine || t === app.sel) app.sel = null;
      else if (v.movable[t] > 0) app.sel = t;
      else { app.sel = null; toast('Nenhum exército disponível para mover daqui.'); }
    }
  }
  renderGame();
}

const STEP = { reinforce: 'Reforço', attack: 'Ataque', move: 'Remanejamento' };
const ICON = {
  goal: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/></svg>',
  cards: '<svg viewBox="0 0 24 24"><rect x="4" y="6" width="11" height="15" rx="2"/><path d="M9 3h9a2 2 0 0 1 2 2v13"/></svg>',
  menu: '<svg viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
};
function renderGame() {
  const v = app.view;
  if (!v) return;
  const T = v.terr, cur = v.players[v.turn], can = canAct();
  const vw = app.role === 'guest' ? app.me : viewer();

  // passagem do aparelho entre jogadores locais
  if (app.role === 'host' && v.phase === 'play' && cur.ctrl === 'local' && app.lastViewer !== v.turn) {
    const locals = v.players.filter((p) => p.ctrl === 'local').length;
    const first = app.lastViewer == null;
    app.lastViewer = v.turn;
    if (locals > 1 && !first) modal(`<h3>Passe o aparelho</h3><p>Agora é a vez de <b style="color:${COLORS[cur.color].c}">${esc(cur.name)}</b>.</p><button class="btn primary" data-m="close">Estou com o aparelho</button>`);
  }
  // valida seleção
  if (!can || (app.sel != null && T[app.sel].o !== v.turn)) app.sel = app.target = null;
  if (app.target != null && T[app.target].o === v.turn) app.sel = app.target = null;
  if (v.step === 'attack' && app.sel != null && T[app.sel].a < 2) app.sel = app.target = null;

  processEvents(v);
  // quem só assiste vê o que o jogador da vez está mirando
  const okT = (x) => Number.isInteger(x) && x >= 0 && x < TERR.length;
  const pk = !can && app.peek && app.peek.n === v.n && okT(app.peek.sel) ? app.peek : null;

  // mapa
  const targets = new Set();
  if (can && app.sel != null) {
    TERR[app.sel].adj.forEach((j) => {
      if (v.step === 'attack' && T[j].o !== v.turn) targets.add(j);
      if (v.step === 'move' && T[j].o === v.turn && v.movable[app.sel] > 0) targets.add(j);
    });
  }
  // no reforço, quando só restam bônus de continente, apaga onde não dá para colocar
  const bonusOnly = can && v.step === 'reinforce' && v.pool.free === 0 && !mustTrade(v);
  nodes.forEach((nd, i) => {
    nd.poly.setAttribute('fill', COLORS[v.players[T[i].o].color].c);
    nd.num.textContent = T[i].a;
    const hl = app.target != null ? i === app.target : targets.has(i);
    const dim = app.sel != null ? i !== app.sel && !targets.has(i) : bonusOnly && !(T[i].o === v.turn && v.pool.cont[TERR[i].c] > 0);
    const ps = pk && (i === pk.sel ? ' psel' : i === pk.target ? ' tgt' : '');
    nd.poly.setAttribute('class', 'terr' + (i === app.sel ? ' sel' : '') + (hl ? ' tgt' : '') + (dim ? ' dim' : '') + (ps || ''));
  });

  // topo
  const meP = v.players[vw];
  $('#hud').innerHTML = `<div class="turn"><span class="dot" style="background:${COLORS[cur.color].c}"></span>
    <span><b>${esc(cur.name)}</b><span class="phase">${v.phase === 'over' ? 'Fim de jogo' : `${STEP[v.step]} · rodada ${v.round + 1}`}</span></span></div>
    <button class="icon" data-do="objective" aria-label="Objetivo">${ICON.goal}</button>
    <button class="icon" data-do="cards" aria-label="Cartas">${ICON.cards}<span>${handSize(meP)}</span></button>
    <button class="icon" data-do="menu" aria-label="Menu">${ICON.menu}</button>`;

  // dados
  if (v.roll && v.roll.n !== app.lastRoll) {
    app.lastRoll = v.roll.n;
    const r = v.roll, pairs = Math.min(r.att.length, r.def.length);
    const die = (x, cls, lost) => `<span class="die ${cls}${lost ? ' lost' : ''}">${x}</span>`;
    const d = $('#dice');
    d.innerHTML = `<span>${r.att.map((x, i) => die(x, 'a', i < pairs && x <= r.def[i])).join('')}</span><span>×</span><span>${r.def.map((x, i) => die(x, 'd', i < pairs && r.att[i] > x)).join('')}</span>`;
    d.hidden = false; clearTimeout(d._t); d._t = setTimeout(() => (d.hidden = true), 2600);
  }

  // rodapé
  const info = app.info != null ? `${TERR[app.info].n} · ${CONTINENTS[TERR[app.info].c].n} · ${esc(v.players[T[app.info].o].name)} · ${T[app.info].a} exérc.` : (v.log[v.log.length - 1] || '');
  const chips = `<div class="chips">${[1, 5, 'all'].map((q) => `<button class="chip${app.qty === q ? ' on' : ''}" data-qty="${q}">${q === 'all' ? 'Tudo' : '×' + q}</button>`).join('')}</div>`;
  let msg = '', btns = '', warn = '';
  if (v.phase === 'over') {
    const w = v.players[v.winner];
    msg = `<b style="color:${COLORS[w.color].c}">${esc(w.name)}</b> venceu! ${w.obj != null ? esc(objectiveText(OBJECTIVES[w.obj])) : ''}`;
    btns = app.role === 'host' ? '<button class="btn small primary" data-do="again">Nova partida</button>' : '';
  } else if (!can) {
    const nm = `<b style="color:${COLORS[cur.color].c}">${esc(cur.name)}</b>`;
    const doing = v.step === 'reinforce' ? `está reforçando (${poolTotal(v)} a colocar)`
      : v.step === 'move' ? (pk ? `vai mover tropas de ${TERR[pk.sel].n}` : 'está remanejando tropas')
      : pk && okT(pk.target) ? `mira ${TERR[pk.target].n} a partir de ${TERR[pk.sel].n}` : pk ? `prepara um ataque de ${TERR[pk.sel].n}` : 'está na fase de ataque';
    msg = app.role === 'guest' && !app.link ? '<span class="off">Sem conexão.</span> Peça um novo QR ao anfitrião.' : `${nm} ${doing}${cur.ctrl === 'bot' ? ' (bot)' : ''}`;
    if (app.role === 'guest' && !app.link) btns = '<button class="btn small primary" data-do="join">Reconectar (ler QR)</button>';
  } else if (v.step === 'reinforce') {
    const extra = Object.entries(v.pool.cont).map(([c, n]) => `+${n} em ${CONTINENTS[c].n}`).join(', ');
    msg = mustTrade(v) ? 'Você tem 5 ou mais cartas: troque antes de reforçar.' : `Toque em territórios seus para reforçar: <b>${v.pool.free}</b> livre${v.pool.free === 1 ? '' : 's'}${extra ? ` (${extra})` : ''}.`;
    const tr = Array.isArray(meP.cards) ? bestTrade(meP.cards, T, v.turn) : null;
    btns = chips + (tr ? `<button class="btn small primary" data-do="autoTrade">Trocar cartas +${tradeValue(v.trades)}</button>` : '');
  } else if (v.occupy) {
    msg = `Conquistou ${TERR[v.occupy.to].n}! Levar mais exércitos?`;
    btns = Array.from({ length: v.occupy.max + 1 }, (_, i) => `<button class="btn small${i === v.occupy.max ? ' primary' : ''}" data-occupy="${i}">+${i}</button>`).join('');
  } else if (v.step === 'attack') {
    if (app.sel != null && app.target != null) {
      msg = `${TERR[app.sel].n} (${T[app.sel].a}) ⚔ ${TERR[app.target].n} (${T[app.target].a})`;
      btns = '<button class="btn small primary" data-do="attack">Atacar</button><button class="btn small" data-do="blitz">Até o fim</button>';
    } else msg = app.sel != null ? 'Agora toque num vizinho inimigo (tracejado).' : 'Toque num território seu para atacar a partir dele.';
    btns += '<button class="btn small" data-do="endAttack">Encerrar ataques</button>';
    if (app.sel != null && app.target != null) btns = btns.replace('Encerrar ataques', 'Encerrar');
  } else {
    msg = app.sel != null ? `Mover de ${TERR[app.sel].n} (até ${v.movable[app.sel] || 0}): toque no destino.` : 'Remaneje: toque na origem e depois num vizinho seu.';
    btns = chips + '<button class="btn small primary" data-do="endTurn">Encerrar turno</button>';
  }
  if (app.role === 'host' && v.phase === 'play') {
    const off = app.seats.filter((s) => s.ctrl === 'remote' && !s.link);
    if (off.length) warn = `<div class="actions"><button class="btn small warn" data-do="invite">Reconectar ${esc(off.length === 1 ? off[0].name : off.length + ' jogadores')} (offline)</button></div>`;
  }
  if (can) { // compartilha a seleção atual com quem está assistindo
    const key = `${v.n}:${app.sel}:${app.target}`;
    if (key !== app.peekKey) {
      app.peekKey = key;
      const m = { t: 'peek', n: v.n, sel: app.sel, target: app.target };
      if (app.role === 'guest') app.link && app.link.send(m); else app.seats.forEach((s) => s.link && s.link.send(m));
    }
  }
  const you = `<span class="you"><span class="dot" style="background:${COLORS[meP.color].c}"></span><span>Você: ${esc(meP.name)}</span></span>`;
  $('#bar').innerHTML = `<div class="msg">${msg}</div>${btns ? `<div class="actions">${btns}</div>` : ''}${warn}<div class="foot"><span class="info">${info}</span>${you}</div>`;
}

function showObjective() {
  const v = app.view, me = v.players[app.role === 'guest' ? app.me : viewer()];
  modal(`<h3>Objetivo de ${esc(me.name)}</h3><p style="color:var(--ink);font-size:16px">${me.obj != null ? esc(objectiveText(OBJECTIVES[me.obj])) : '—'}</p>
    <p>Mantenha em segredo. Territórios: ${owned(v, v.players.indexOf(me))} de ${TERR.length}.</p><button class="btn" data-m="close">Fechar</button>`);
}
function showCards() {
  const v = app.view, pi = app.role === 'guest' ? app.me : viewer(), me = v.players[pi];
  const hand = Array.isArray(me.cards) ? me.cards : [];
  const picked = new Set();
  const canTrade = canAct() && v.turn === pi && v.step === 'reinforce';
  const draw = () => {
    const ok = canTrade && validTrade([...picked]);
    $('#modal .sheet').innerHTML = `<h3>Cartas (${hand.length})</h3>
      <p>Troque 3 símbolos iguais ou 3 diferentes (★ vale qualquer um) no início do seu turno. Próxima troca vale <b>${tradeValue(v.trades)}</b> exércitos; cartas de territórios seus dão +2 neles. Com 5 cartas a troca é automática.</p>
      <div class="cards">${hand.map((c) => `<button class="card${picked.has(c) ? ' on' : ''}" data-card="${c}"><b>${SYMBOLS[cardSymbol(c)]}</b>${esc(cardName(c))}</button>`).join('') || '<p>Nenhuma carta ainda. Conquiste um território no turno para ganhar uma.</p>'}</div>
      <div class="row"><button class="btn primary" data-m="trade" ${ok ? '' : 'disabled'}>Trocar selecionadas</button><button class="btn" data-m="close">Fechar</button></div>`;
  };
  modal('');
  draw();
  $('#modal .sheet').onclick = (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.card != null) { const c = +b.dataset.card; picked.has(c) ? picked.delete(c) : picked.size < 3 && picked.add(c); draw(); }
    if (b.dataset.m === 'trade') { closeModal(); act({ t: 'trade', cards: [...picked] }); }
  };
}
function showMenu() {
  const v = app.view, host = app.role === 'host';
  modal(`<h3>Jogadores</h3><ul class="plist">${v.players.map((p, i) => {
    const seat = host ? app.seats[p.seat] : null;
    const offline = host && p.ctrl === 'remote' && !seat.link;
    return `<li><span class="dot" style="background:${COLORS[p.color].c}"></span><span class="who">${p.alive ? '' : '☠ '}<b>${esc(p.name)}</b> · ${owned(v, i)} terr. · ${handSize(p)} cartas${p.ctrl === 'bot' ? ' · bot' : ''}${offline ? ' · <span class="off">offline</span>' : ''}</span>
      ${host && p.ctrl === 'remote' && p.alive ? `<button class="btn small" data-re="${p.seat}">QR</button>` : ''}${offline && p.alive ? `<button class="btn small" data-bot="${i}">Virar bot</button>` : ''}</li>`;
  }).join('')}</ul>
  <div class="log">${v.log.slice().reverse().map(esc).join('<br>')}</div>
  ${host && v.players.some((p) => p.ctrl === 'remote' || app.seats[p.seat].gid) ? '<button class="btn small" data-do="invite">Reconectar por QR</button>' : ''}
  <div class="row"><button class="btn small" data-do="sound">Som: ${soundOn() ? 'ligado' : 'desligado'}</button><button class="btn small" data-do="rules">Regras</button><button class="btn small" data-do="quit">Sair</button><button class="btn small primary" data-m="close">Voltar</button></div>`);
  $('#modal .sheet').onclick = (e) => {
    const d = e.target.dataset;
    if (d.re != null) hostInvite(+d.re);
    if (d.bot != null) { app.game.players[+d.bot].ctrl = 'bot'; app.seats[app.game.players[+d.bot].seat].ctrl = 'bot'; closeModal(); sync(); }
  };
}
function showRules() {
  modal(`<h3>Como jogar</h3>
  <ul><li><b>Objetivo:</b> cada jogador recebe um objetivo secreto (🎯). Quem cumprir primeiro vence.</li>
  <li><b>Reforço:</b> no início do turno você recebe metade dos seus territórios em exércitos (mínimo 3), mais o bônus de cada continente inteiro que dominar (o bônus só pode ser colocado no próprio continente).</li>
  <li><b>Ataque:</b> a partir da 2ª rodada, ataque vizinhos com até 3 dados (precisa deixar 1 exército para trás). A defesa rola até 3. Compare do maior para o menor; empate é da defesa.</li>
  <li><b>Conquista:</b> ao zerar a defesa você ocupa o território com 1 a 3 exércitos e, no fim do turno, ganha uma carta.</li>
  <li><b>Cartas:</b> troque 3 iguais ou 3 diferentes por exércitos (4, 6, 8, 10, 12, 15, depois +5 a cada troca). Com 5 cartas a troca é obrigatória e o jogo faz sozinho no início do turno, escolhendo a melhor trinca. Com menos, o botão “Trocar cartas” aparece no reforço.</li>
  <li><b>Remanejamento:</b> ao final, mova exércitos entre territórios vizinhos seus; cada exército anda uma vez por turno.</li>
  <li><b>Rotas marítimas:</b> linhas pontilhadas também são fronteiras. O Alasca liga com o Extremo Oriente pela borda do mapa.</li></ul>
  <h3>Conexão</h3>
  <p>Os aparelhos falam direto entre si, sem servidor e sem internet: basta estarem no mesmo Wi-Fi ou no hotspot de um dos celulares. Permita a câmera quando o navegador pedir. Se alguém cair, o anfitrião toca em “Reconectar” e o jogador lê o novo QR em “Reconectar à partida”: ele volta para o mesmo lugar.</p>
  <button class="btn" data-m="close">Fechar</button>`);
}

/* ---------- eventos globais ---------- */
function leave() {
  clearTimeout(app.botTimer);
  if (app.role === 'host') app.seats.forEach((s) => s.link && s.link.close());
  if (app.link) { const l = app.link; app.link = null; l.close(); }
  if (app.role === 'guest') store.del('guest');
  Object.assign(app, { role: null, seats: [], game: null, view: null, me: null, lobby: null, sel: null, target: null, info: null, lastViewer: null });
  refreshHome();
  closeModal(); show('home');
}
const actions = {
  host: hostStart,
  join: guestScan,
  rejoin: guestScan,
  rules: showRules,
  resume() {
    const sv = store.get('save3');
    if (!sv) return;
    app.role = 'host'; app.seats = sv.seats; app.game = sv.game; app.lastViewer = null; app.turnKey = null; app.evN = null;
    if (!app.game.ev) app.game.ev = [];
    show('game'); sync();
    if (app.seats.some((s) => s.ctrl === 'remote')) toast('Reconecte os convidados pelo menu ☰ (botão QR).', 5000);
  },
  invite: () => hostInvite(),
  addBot() { const n = app.seats.filter((s) => s.ctrl === 'bot').length + 1; app.seats.push({ name: 'Bot ' + n, color: freeColor(), ctrl: 'bot' }); sync(); },
  addLocal() {
    modal(`<h3>Jogador neste aparelho</h3><label class="field">Nome<input id="lname" maxlength="14"></label>
      <div class="row"><button class="btn primary" data-m="add">Adicionar</button><button class="btn" data-m="close">Cancelar</button></div>`);
    $('#modal .sheet').onclick = (e) => {
      if (e.target.dataset.m !== 'add') return;
      app.seats.push({ name: ($('#lname').value.trim() || 'Jogador ' + (app.seats.length + 1)).slice(0, 14), color: freeColor(), ctrl: 'local' });
      closeModal(); sync();
    };
  },
  begin: hostBegin,
  leave,
  quit() {
    modal(`<h3>Sair da partida?</h3><p>${app.role === 'host' ? 'A partida fica salva neste aparelho e pode ser retomada na tela inicial.' : 'Você poderá voltar lendo um novo QR do anfitrião.'}</p>
      <div class="row"><button class="btn primary" data-do="leave">Sair</button><button class="btn" data-m="close">Ficar</button></div>`);
  },
  again() { store.del('save3'); app.game = null; app.view = null; show('lobby'); sync(); },
  objective: showObjective,
  sound() { setSound(!soundOn()); store.set('sound', soundOn()); if (soundOn()) { unlock(); play('turn'); } showMenu(); },
  cards: showCards,
  autoTrade() { const v = app.view, me = v.players[v.turn]; const tr = Array.isArray(me.cards) && bestTrade(me.cards, v.terr, v.turn); if (tr) act({ t: 'trade', cards: tr }); },
  menu: showMenu,
  attack: () => act({ t: 'attack', from: app.sel, to: app.target }),
  blitz: () => act({ t: 'attack', from: app.sel, to: app.target, blitz: true }),
  endAttack: () => { app.sel = app.target = null; act({ t: 'endAttack' }); },
  endTurn: () => { app.sel = app.target = null; act({ t: 'endTurn' }); },
};
document.addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) { if (e.target.id === 'modal') closeModal(); return; }
  const d = b.dataset;
  if (d.m === 'close') return closeModal();
  if (d.do && actions[d.do]) return actions[d.do]();
  if (d.qty) { app.qty = d.qty === 'all' ? 'all' : +d.qty; return renderGame(); }
  if (d.secs != null) { app.cfg.secs = +d.secs; store.set('cfg', app.cfg); return sync(); }
  if (d.occupy != null) return act({ t: 'occupy', n: +d.occupy });
  if (d.kick != null) { const s = app.seats.splice(+d.kick, 1)[0]; s.link && s.link.close(); return sync(); }
  if (d.color != null) {
    const s = app.seats[+d.color];
    for (let k = 1; k <= COLORS.length; k++) { const c = (s.color + k) % COLORS.length; if (!app.seats.some((x) => x.color === c)) { s.color = c; break; } }
    return sync();
  }
});

/* ---------- inicialização ---------- */
$('#name').value = store.get('name') || '';
if (store.get('sound') === false) setSound(false);
// o navegador só libera áudio depois de um toque do usuário
for (const ev of ['pointerdown', 'keydown']) document.addEventListener(ev, unlock, { passive: true });
$('#ver').textContent = 'versão ' + VERSION;
// estilos alternativos do destaque de continente, para comparar: ?estilo=2 ou ?estilo=3
const estilo = new URLSearchParams(location.search).get('estilo');
if (estilo === '2' || estilo === '3') svg.classList.add('st' + estilo);
if (store.get('cfg')) Object.assign(app.cfg, store.get('cfg'));
$('#name').addEventListener('input', () => store.set('name', $('#name').value));
function refreshHome() {
  $('#resume').hidden = !store.get('save3');
  $('#rejoin').hidden = !store.get('guest');
}
refreshHome();

let wake = null;
async function keepAwake() {
  try { if ('wakeLock' in navigator && document.visibilityState === 'visible') wake = await navigator.wakeLock.request('screen'); } catch {}
}
document.addEventListener('visibilitychange', keepAwake);
document.addEventListener('click', () => !wake && keepAwake(), { once: true });

if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost')) {
  const hadCtl = !!navigator.serviceWorker.controller;
  navigator.serviceWorker.register('sw.js').then((r) => r.update()).catch(() => {});
  navigator.serviceWorker.ready.then(() => caches.has('estandarte-v' + VERSION)).then((ok) => { $('#offline').hidden = !ok; }).catch(() => {});
  // versão nova instalada: recarrega sozinho, desde que ninguém esteja no meio de uma partida
  navigator.serviceWorker.addEventListener('controllerchange', () => { if (hadCtl && !$('#home').hidden && $('#modal').hidden) location.reload(); });
}

function fromHash() {
  if (!location.hash.startsWith('#j=')) return;
  const raw = location.href;
  history.replaceState(null, '', location.pathname + location.search);
  modal(`<h3>Entrar na partida</h3><label class="field">Seu nome<input id="jname" maxlength="14" value="${esc(store.get('name') || '')}"></label>
    <p>Ao entrar, o navegador vai pedir a câmera. Permita: é o que faz a conexão funcionar na rede local.</p>
    <button class="btn primary" data-m="go">Entrar</button>`);
  $('#modal .sheet').onclick = (e) => {
    if (e.target.dataset.m !== 'go') return;
    $('#name').value = $('#jname').value.trim(); store.set('name', $('#name').value);
    guestJoin(raw);
  };
}
addEventListener('hashchange', fromHash);
fromHash();
