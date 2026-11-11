import { TERR, CONTINENTS, SEA, MAP_W, MAP_H } from './map.js';
import {
  COLORS, SYMBOLS, OBJECTIVES, objectiveText, newGame, apply, viewFor, botAction, owned,
  poolTotal, validTrade, tradeValue, cardSymbol, cardName, mustTrade, handSize,
} from './game.js';
import { createInvite, joinInvite } from './net.js';

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
};
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

// Abre a câmera dentro de `box` e chama onCode a cada QR lido. Retorna função para parar.
function startScanner(box, onCode) {
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
  (navigator.mediaDevices?.getUserMedia
    ? navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false })
    : Promise.reject(new Error('sem câmera')))
    .then((s) => { stream = s; if (stopped) return s.getTracks().forEach((t) => t.stop()); video.srcObject = s; video.play(); tick(); })
    .catch(() => { box.innerHTML = '<p>Não foi possível abrir a câmera. Use o campo de código abaixo.</p>'; });
  return () => { stopped = true; cancelAnimationFrame(raf); stream && stream.getTracks().forEach((t) => t.stop()); };
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
        if (targetSeat != null && app.seats[targetSeat]) {
          const st = app.seats[targetSeat];
          if (st.link && st.link !== link) st.link.close();
          st.link = link; st.ctrl = 'remote';
          const pi = playerOfSeat(targetSeat);
          if (pi >= 0) app.game.players[pi].ctrl = 'remote';
        } else if (!app.game && app.seats.length < 6) {
          app.seats.push({ name, color: freeColor(), ctrl: 'remote', link });
        } else return link.send({ t: 'err', m: 'A sala está cheia ou a partida já começou.' });
        closeModal(); toast(`${name} conectou.`);
        sync();
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
  modal('<h3>Preparando convite…</h3>');
  let inv, stop = () => {};
  try { inv = await createInvite(hostHandlers(targetSeat)); }
  catch (e) { closeModal(); return toast('Seu navegador não conseguiu criar a conexão.'); }
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
  modal(`<h3>${targetSeat != null ? 'Reconectar ' + esc(app.seats[targetSeat].name) : 'Convidar jogador'}</h3>
    <ol><li>O convidado aponta a câmera para este QR (ou usa “Entrar em partida”).</li>
    <li>O celular dele mostra um QR de resposta: leia-o aqui.</li></ol>
    <div class="qr" id="qrbox"></div>
    <div class="row"><button class="btn small" data-m="copy">Copiar link</button><button class="btn small primary" data-m="scan">Ler resposta</button></div>
    <div id="scanbox"></div>
    <label class="field">Ou cole o código de resposta<textarea id="paste" rows="2"></textarea></label>
    <div class="row"><button class="btn small" data-m="ok">Usar código colado</button><button class="btn small ghost" data-m="close">Cancelar</button></div>`,
  () => { stop(); if (!inv.link.open) setTimeout(() => !inv.link.open && inv.cancel(), 20000); });
  $('#qrbox').append(drawQr(url));
  $('#modal .sheet').onclick = (e) => {
    const m = e.target.dataset.m;
    if (m === 'copy') copyText(url);
    if (m === 'scan') { $('#qrbox').hidden = true; stop = startScanner($('#scanbox'), accept); }
    if (m === 'ok') accept($('#paste').value);
    if (m === 'close') { inv.cancel(); closeModal(); }
  };
}

function hostBegin() {
  app.game = newGame(app.seats.map((s) => ({ name: s.name, color: s.color, ctrl: s.ctrl })));
  app.sel = app.target = null; app.lastViewer = null;
  show('game'); sync();
}

// Propaga o estado: salva, envia a cada convidado a visão dele e redesenha.
function sync() {
  if (app.role !== 'host') return;
  const g = app.game;
  const pub = app.seats.map((s) => ({ name: s.name, color: s.color, ctrl: s.ctrl, on: s.ctrl !== 'remote' || !!s.link }));
  app.seats.forEach((s, si) => {
    if (!s.link) return;
    if (g) { const pi = playerOfSeat(si); s.link.send({ t: 'state', s: viewFor(g, pi), you: pi }); }
    else s.link.send({ t: 'lobby', seats: pub, you: si });
  });
  if (g) {
    store.set('save', { seats: app.seats.map(({ link, ...s }) => s), game: g });
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
    link.send({ t: 'hello', name: myName() });
    closeModal(); toast('Conectado!');
  },
  onmessage(msg) {
    if (msg.t === 'lobby') { app.lobby = msg; app.view = null; show('lobby'); renderLobby(); }
    else if (msg.t === 'state') { app.view = msg.s; app.me = msg.you; if ($('#game').hidden) show('game'); renderGame(); }
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
  modal('<h3>Preparando resposta…</h3>');
  let j;
  try { j = await joinInvite(code, guestHandlers); }
  catch (e) { closeModal(); return toast('Convite inválido ou expirado.'); }
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
  modal(`<h3>Entrar em partida</h3><p>Aponte para o QR de convite na tela do anfitrião.</p><div id="scanbox"></div>
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
    ? `<div class="row"><button class="btn" data-do="invite" ${full ? 'disabled' : ''}>Convidar por QR</button></div>
       <div class="row"><button class="btn small" data-do="addLocal" ${full ? 'disabled' : ''}>+ Jogador neste aparelho</button><button class="btn small" data-do="addBot" ${full ? 'disabled' : ''}>+ Bot</button></div>
       <button class="btn primary" data-do="begin" ${seats.length < 2 ? 'disabled' : ''}>Iniciar partida (${seats.length} jogadores)</button>
       <button class="btn ghost" data-do="leave">Sair</button>`
    : `<p class="tag">Aguardando o anfitrião iniciar…</p><button class="btn ghost" data-do="leave">Sair</button>`;
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
const nodes = [];
(function buildMap() {
  const halo = el('g', {}, svg), routes = el('g', {}, svg), land = el('g', {}, svg), labels = el('g', {}, svg);
  SEA.forEach(([a, b]) => el('line', { class: 'sea-route', x1: TERR[a].x, y1: TERR[a].y, x2: TERR[b].x, y2: TERR[b].y }, routes));
  TERR.forEach((t, i) => {
    const col = CONTINENTS[t.c].color;
    el('polygon', { class: 'halo', points: t.p, fill: col, stroke: col }, halo);
    const poly = el('polygon', { class: 'terr', points: t.p, 'data-t': i }, land);
    el('text', { class: 'tname', x: t.x, y: t.y + 30 }, labels).textContent = t.n;
    el('circle', { class: 'badge', cx: t.x, cy: t.y - 2, r: 16 }, labels);
    const num = el('text', { class: 'num', x: t.x, y: t.y - 1 }, labels);
    nodes.push({ poly, num });
  });
  // rótulo do continente acima do território mais ao norte
  CONTINENTS.forEach((c, ci) => {
    let top = null;
    TERR.forEach((t) => {
      if (t.c !== ci) return;
      const y = Math.min(...t.p.split(' ').map((q) => +q.split(',')[1]));
      if (!top || y < top.y) top = { x: t.x, y };
    });
    el('text', { class: 'cname', x: top.x, y: Math.max(24, top.y - 14), fill: c.color }, labels).textContent = `${c.n} +${c.bonus}`;
  });
})();

// Pan e zoom por viewBox, mantendo a proporção do contêiner.
const cam = { x: 0, y: 0, z: 1 };
const PAD = 30;
function limits() {
  const r = svg.getBoundingClientRect();
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
}
let camReady = false;
function fitView(toggle) {
  const { r, contain, cover } = limits();
  if (!r.width) return;
  const mid = Math.min(cover, contain * 1.7);
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
  const r = svg.getBoundingClientRect();
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
    if (hit && hit.dataset && hit.dataset.t != null) tapTerritory(+hit.dataset.t);
    else { app.sel = app.target = null; renderGame(); }
  }
  if (ptrs.size === 0) gesture = null;
};
svg.addEventListener('pointerup', endPtr); svg.addEventListener('pointercancel', endPtr); svg.addEventListener('pointerleave', endPtr);
svg.addEventListener('wheel', (e) => {
  e.preventDefault();
  const r = svg.getBoundingClientRect(), mx = e.clientX - r.left, my = e.clientY - r.top;
  const wx = cam.x + mx / cam.z, wy = cam.y + my / cam.z;
  cam.z *= e.deltaY < 0 ? 1.15 : 1 / 1.15; applyCam();
  cam.x = wx - mx / cam.z; cam.y = wy - my / cam.z; applyCam();
}, { passive: false });
addEventListener('resize', () => { if (!$('#game').hidden) applyCam(); });
$('#fit').onclick = () => fitView(true);

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
    nd.poly.setAttribute('class', 'terr' + (i === app.sel ? ' sel' : '') + (hl ? ' tgt' : '') + (dim ? ' dim' : ''));
  });

  // topo
  const meP = v.players[vw];
  $('#hud').innerHTML = `<div class="turn"><span class="dot" style="background:${COLORS[cur.color].c}"></span>
    <span><b>${esc(cur.name)}</b><span class="phase">${v.phase === 'over' ? 'Fim de jogo' : `${STEP[v.step]} · rodada ${v.round + 1}`}</span></span></div>
    <button class="icon" data-do="objective" aria-label="Objetivo">🎯</button>
    <button class="icon" data-do="cards" aria-label="Cartas">🂠 ${handSize(meP)}</button>
    <button class="icon" data-do="menu" aria-label="Menu">☰</button>`;

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
  let msg = '', btns = '';
  if (v.phase === 'over') {
    const w = v.players[v.winner];
    msg = `<b style="color:${COLORS[w.color].c}">${esc(w.name)}</b> venceu! ${w.obj != null ? esc(objectiveText(OBJECTIVES[w.obj])) : ''}`;
    btns = app.role === 'host' ? '<button class="btn small primary" data-do="again">Nova partida</button>' : '';
  } else if (!can) {
    msg = app.role === 'guest' && !app.link ? '<span class="off">Sem conexão.</span> Peça um novo QR ao anfitrião.' : `Aguardando ${esc(cur.name)}…`;
    if (app.role === 'guest' && !app.link) btns = '<button class="btn small primary" data-do="join">Ler QR de reconexão</button>';
  } else if (v.step === 'reinforce') {
    const extra = Object.entries(v.pool.cont).map(([c, n]) => `+${n} em ${CONTINENTS[c].n}`).join(', ');
    msg = mustTrade(v) ? 'Você tem 5 ou mais cartas: troque antes de reforçar.' : `Toque em territórios seus para reforçar: <b>${v.pool.free}</b> livre${v.pool.free === 1 ? '' : 's'}${extra ? ` (${extra})` : ''}.`;
    btns = chips + (mustTrade(v) ? '<button class="btn small primary" data-do="cards">Trocar cartas</button>' : '');
  } else if (v.occupy) {
    msg = `Conquistou ${TERR[v.occupy.to].n}! Levar mais exércitos?`;
    btns = Array.from({ length: v.occupy.max + 1 }, (_, i) => `<button class="btn small${i === v.occupy.max ? ' primary' : ''}" data-occupy="${i}">+${i}</button>`).join('');
  } else if (v.step === 'attack') {
    if (app.sel != null && app.target != null) {
      msg = `${TERR[app.sel].n} (${T[app.sel].a}) ⚔ ${TERR[app.target].n} (${T[app.target].a})`;
      btns = '<button class="btn small primary" data-do="attack">Atacar</button><button class="btn small" data-do="blitz">Até o fim</button>';
    } else msg = app.sel != null ? 'Agora toque num vizinho inimigo (tracejado).' : 'Toque num território seu para atacar a partir dele.';
    btns += '<button class="btn small" data-do="endAttack">Encerrar ataques</button>';
  } else {
    msg = app.sel != null ? `Mover de ${TERR[app.sel].n} (até ${v.movable[app.sel] || 0}): toque no destino.` : 'Remaneje: toque na origem e depois num vizinho seu.';
    btns = chips + '<button class="btn small primary" data-do="endTurn">Encerrar turno</button>';
  }
  const you = `<span class="you"><span class="dot" style="background:${COLORS[meP.color].c}"></span>Você: ${esc(meP.name)}</span>`;
  $('#bar').innerHTML = `<div class="msg">${msg}</div><div class="row">${btns}</div><div class="foot"><span class="info">${info}</span>${you}</div>`;
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
      <p>Troque 3 símbolos iguais ou 3 diferentes (★ vale qualquer um) no início do seu turno. Próxima troca vale <b>${tradeValue(v.trades)}</b> exércitos; cartas de territórios seus dão +2 neles.</p>
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
  <div class="row"><button class="btn small" data-do="rules">Regras</button><button class="btn small" data-do="quit">Sair da partida</button><button class="btn small primary" data-m="close">Voltar</button></div>`);
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
  <li><b>Cartas:</b> troque 3 iguais ou 3 diferentes por exércitos (4, 6, 8, 10, 12, 15, depois +5 a cada troca). Com 5 cartas a troca é obrigatória.</li>
  <li><b>Remanejamento:</b> ao final, mova exércitos entre territórios vizinhos seus; cada exército anda uma vez por turno.</li>
  <li><b>Rotas marítimas:</b> linhas pontilhadas também são fronteiras.</li></ul>
  <h3>Conexão</h3>
  <p>Os aparelhos falam direto entre si (WebRTC). Funciona melhor com todos no mesmo Wi-Fi ou no hotspot de um dos celulares. Mantenha a tela ligada; se alguém cair, o anfitrião gera um novo QR em ☰.</p>
  <button class="btn" data-m="close">Fechar</button>`);
}

/* ---------- eventos globais ---------- */
function leave() {
  clearTimeout(app.botTimer);
  if (app.role === 'host') app.seats.forEach((s) => s.link && s.link.close());
  if (app.link) { const l = app.link; app.link = null; l.close(); }
  Object.assign(app, { role: null, seats: [], game: null, view: null, me: null, lobby: null, sel: null, target: null, info: null, lastViewer: null });
  $('#resume').hidden = !store.get('save');
  closeModal(); show('home');
}
const actions = {
  host: hostStart,
  join: guestScan,
  rules: showRules,
  resume() {
    const sv = store.get('save');
    if (!sv) return;
    app.role = 'host'; app.seats = sv.seats; app.game = sv.game; app.lastViewer = null;
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
  again() { store.del('save'); app.game = null; app.view = null; show('lobby'); sync(); },
  objective: showObjective,
  cards: showCards,
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
$('#name').addEventListener('input', () => store.set('name', $('#name').value));
$('#resume').hidden = !store.get('save');

let wake = null;
async function keepAwake() {
  try { if ('wakeLock' in navigator && document.visibilityState === 'visible') wake = await navigator.wakeLock.request('screen'); } catch {}
}
document.addEventListener('visibilitychange', keepAwake);
document.addEventListener('click', () => !wake && keepAwake(), { once: true });

if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});

function fromHash() {
  if (!location.hash.startsWith('#j=')) return;
  const raw = location.href;
  history.replaceState(null, '', location.pathname + location.search);
  if (!store.get('name')) {
    modal(`<h3>Entrar na partida</h3><label class="field">Seu nome<input id="jname" maxlength="14"></label><button class="btn primary" data-m="go">Entrar</button>`);
    $('#modal .sheet').onclick = (e) => {
      if (e.target.dataset.m !== 'go') return;
      $('#name').value = $('#jname').value.trim(); store.set('name', $('#name').value);
      guestJoin(raw);
    };
  } else guestJoin(raw);
}
addEventListener('hashchange', fromHash);
fromHash();
