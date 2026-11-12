import { TERR, CONTINENTS, SEA, MAP_W, MAP_H } from './map.js';
import {
  COLORS, SYMBOLS, OBJECTIVES, objectiveText, newGame, apply, viewFor, botAction, owned,
  poolTotal, validTrade, bestTrade, tradeValue, cardSymbol, cardName, mustTrade, handSize,
  EVENTS, eventText, attackBlock, isSea, pactOf, botPactReply, PACT_ROUNDS, PACT_PENALTY,
} from './game.js';
import { createInvite, joinInvite, initCert, myFingerprint, armSpare, useSpare } from './net.js';
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
  sel: null, target: null, n: 1, nKey: '', info: null, // n: quantidade no seletor − / +
  lastRoll: 0, lastViewer: null, botTimer: null,
  cfg: { secs: 120, events: false, pacts: false }, // tempo por turno em segundos (0 = livre) e regras opcionais
  spare: null, autoOn: false, offerKey: null, offerOpen: false, // convidado: conexão reserva; proposta de pacto em aberto
  tEnd: null, tLimit: 0, // relógio local do turno
  evN: null, peek: null, peekKey: '', turnKey: null, pausedAt: null, lastSec: null,
};
const VERSION = '23'; // manter igual ao sufixo do cache em sw.js
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
  applyLayout();
  if (id === 'game') requestAnimationFrame(fitView);
}
// Jogo sempre deitado: na partida, se o celular estiver em pé, o palco gira 90° (o jogador vira o aparelho).
// Com o aparelho deitado de verdade nada gira. Dá para desligar no menu.
const rotated = () => document.body.classList.contains('rot');
function applyLayout() {
  const inGame = !$('#game').hidden, portrait = innerHeight > innerWidth;
  const rot = inGame && portrait && store.get('forceLand') !== false;
  const st = $('#stage').style;
  document.body.classList.toggle('rot', rot);
  if (rot) { st.left = innerWidth + 'px'; st.width = innerHeight + 'px'; st.height = innerWidth + 'px'; }
  else st.left = st.width = st.height = '';
  document.body.classList.toggle('land', rot || (!portrait && innerHeight <= 520));
}
// posição do toque no sistema de coordenadas do palco (que pode estar girado)
const pt = (e) => (rotated() ? { x: e.clientY, y: innerWidth - e.clientX } : { x: e.clientX, y: e.clientY });
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
      const known = seatOfLink(link);
      if (known >= 0) { // qualquer mensagem prova que o convidado está vivo
        const st = app.seats[known]; st.seen = Date.now();
        if (st.lag) { st.lag = false; app.game ? renderGame() : renderLobby(); }
      }
      if (msg.t === 'pong') return;
      if (msg.t === 'sync') return sync(); // o convidado percebeu que está defasado e pediu o estado de novo
      if (msg.t === 'hello') {
        if (known >= 0) return sync(); // "olá" repetido (o convidado insiste até ouvir resposta): só reenvia o estado
        const name = String(msg.name || 'Convidado').slice(0, 14);
        const gid = String(msg.gid || '').slice(0, 40), fp = String(msg.fp || '').slice(0, 80);
        // quem já tinha assento (mesmo aparelho) volta para ele, inclusive no meio da partida
        let si = targetSeat;
        if (si == null && gid) { const k = app.seats.findIndex((s) => s.gid === gid && s.ctrl !== 'local'); if (k >= 0) si = k; }
        if (si != null && app.seats[si]) {
          const st = app.seats[si];
          if (st.link && st.link !== link) { const old = st.link; st.link = null; old.close(); }
          st.link = link; st.ctrl = 'remote'; st.seen = Date.now(); st.lag = false; if (gid) st.gid = gid; if (fp) st.fp = fp;
          const pi = playerOfSeat(si);
          if (pi >= 0) app.game.players[pi].ctrl = 'remote';
          toast(`${st.name} ${app.game ? 'voltou à partida' : 'conectou'}.`);
        } else if (!app.game && app.seats.length < 6) {
          app.seats.push({ name, color: freeColor(), ctrl: 'remote', link, gid, fp, seen: Date.now() });
          toast(`${name} conectou.`);
        } else return link.send({ t: 'err', m: app.game ? 'A partida já começou. Peça ao anfitrião o QR do seu jogador (menu ☰).' : 'A sala está cheia.' });
        if ($('#qrbox')) closeModal(); // fecha só a janela do convite; quem voltou sozinho não interrompe nada
        sync();
        armSpareFor(app.seats[seatOfLink(link)]);
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
      const st = app.seats[si];
      st.link = null;
      toast(`${st.name} desconectou.`);
      if (!app.game) { // na sala o lugar some; a conexão reserva fica uns minutos à espera de ele voltar sozinho
        app.seats.splice(si, 1);
        const sp = st.spare; st.spare = null;
        if (sp) setTimeout(() => !sp.link.open && sp.cancel(), 180000);
      }
      sync();
    },
  };
}

// Conexão reserva: enquanto o convidado está ligado, o anfitrião deixa pronta uma segunda conexão, já "respondida"
// com credenciais combinadas pelo canal atual. Se o convidado cair (tela bloqueada, página recarregada, Wi-Fi piscou),
// ele abre essa reserva sozinho, sem QR. Se não der (rede mudou, anfitrião reiniciou), o QR continua valendo.
async function armSpareFor(st) {
  if (!st || !st.fp || !st.link || st.arming) return;
  st.arming = true; st.spareAt = Date.now();
  let sp = null;
  try { sp = await armSpare(st.fp, hostHandlers(null)); } catch {}
  st.arming = false;
  if (!sp) return;
  if (!st.link || !app.seats.includes(st)) return sp.cancel();
  const old = st.spare;
  st.spare = sp;
  if (old && old.link !== st.link) old.cancel();
  st.link.send({ t: 'spare', code: sp.code, gu: sp.gu, gp: sp.gp });
}
const dropSpare = (st) => { const sp = st.spare; st.spare = null; if (sp && sp.link !== st.link) sp.cancel(); };

async function hostInvite(targetSeat = null) {
  modal('<h3>Preparando convite…</h3><p>Se o navegador pedir, permita a câmera: ela lê o QR de resposta e ajuda os aparelhos a se encontrarem na rede local.</p>');
  const camStream = await openCamera();
  if (app.game && !app.pausedAt) { app.pausedAt = Date.now(); sync(); } // relógio do turno pausa durante o pareamento
  let inv, stop = () => {};
  try { inv = await createInvite(hostHandlers(targetSeat)); }
  catch (e) { stopStream(camStream); app.pausedAt = null; closeModal(); return toast(e.message === 'sem-rede' ? 'Sem rede local: conecte-se a um Wi-Fi ou ao hotspot de alguém e tente de novo.' : 'Seu navegador não conseguiu criar a conexão.', 5000); }
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
  app.game = newGame(app.seats.map((s) => ({ name: s.name, color: s.color, ctrl: s.ctrl })), undefined, { events: !!app.cfg.events, pacts: !!app.cfg.pacts });
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
    else s.link.send({ t: 'lobby', seats: pub, you: si, secs: app.cfg.secs, events: !!app.cfg.events, pacts: !!app.cfg.pacts });
  });
  if (g) {
    store.set('save3', { seats: app.seats.map(({ link, seen, lag, spare, spareAt, arming, ...s }) => s), game: g });
    app.view = viewFor(g, viewer());
    renderGame(); scheduleBot();
  } else renderLobby();
}
// Batimento: o anfitrião pergunta a cada 3 s; quem fica 9 s calado é marcado como "sem resposta",
// sem derrubar a conexão (ela pode voltar sozinha). O convidado faz o mesmo em relação ao anfitrião.
setInterval(() => {
  if (app.role === 'host') {
    let changed = false;
    for (const s of app.seats) {
      if (!s.link) continue;
      s.link.send({ t: 'ping', n: app.game ? app.game.n : null });
      if (!s.lag && Date.now() - (s.seen || 0) > 9000) { s.lag = true; changed = true; }
      if (!s.lag && s.fp && Date.now() - (s.spareAt || 0) > 300000) armSpareFor(s); // renova a reserva de tempos em tempos
    }
    if (changed) app.game ? renderGame() : renderLobby();
  } else if (app.role === 'guest' && app.link && app.heard && !app.hostLag && Date.now() - app.heard > 9000) {
    app.hostLag = true;
    autoLoop(true);
    if (app.view) renderGame();
  }
}, 3000);
// Ao voltar para o app (tela desbloqueada, troca de aba), confere o estado na hora.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') return;
  if (app.role === 'guest' && app.link) app.link.send({ t: 'sync' });
  if (app.role === 'guest' && (!app.link || app.hostLag)) autoLoop(true);
  else if (app.role === 'host' && (app.game || app.seats.length)) sync();
});
function scheduleBot() {
  clearTimeout(app.botTimer);
  const g = app.game;
  if (!g || g.phase !== 'play') return;
  if (g.offer && g.players[g.offer.to].ctrl === 'bot') { // bot responde à proposta de pacto, mesmo fora da vez dele
    app.botTimer = setTimeout(() => { if (g.offer) apply(g, g.offer.to, botPactReply(g)); sync(); }, 900);
    return;
  }
  if (g.players[g.turn].ctrl !== 'bot') return;
  app.botTimer = setTimeout(() => { apply(g, g.turn, botAction(g)); sync(); }, g.step === 'attack' ? 1150 : 700); // devagar o bastante para dar tempo de ver cada jogada
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
    if (app.role === 'host') return link.close();
    if (app.link && app.link !== link) { const old = app.link; app.link = null; old.close(); } // a conexão nova substitui a que travou
    app.role = 'guest'; app.link = link; app.heard = 0; app.hostLag = false;
    store.set('guest', true);
    // A primeira mensagem pode se perder se chegar antes de o canal abrir do outro lado:
    // repete o "olá" até ouvir qualquer resposta do anfitrião.
    const hello = () => link.send({ t: 'hello', name: myName(), gid: guestId(), fp: myFingerprint() });
    hello();
    let tries = 0;
    const iv = setInterval(() => { if (app.link !== link || app.heard || ++tries > 40) return clearInterval(iv); hello(); }, 500);
    if ($('#qrbox') || $('#scanbox')) closeModal();
    toast(app.view ? 'Reconectado!' : 'Conectado!');
  },
  onmessage(msg, link) {
    if (app.link !== link) return;
    app.heard = Date.now();
    if (app.hostLag) { app.hostLag = false; if (app.view) renderGame(); }
    if (msg.t === 'ping') { // responde e confere se o estado local é o mais recente
      link.send({ t: 'pong' });
      if (app.view && msg.n != null && msg.n !== app.view.n) link.send({ t: 'sync' });
      return;
    }
    if (msg.t === 'spare') { app.spare = { code: msg.code, gu: msg.gu, gp: msg.gp }; store.set('spare', app.spare); return; }
    if (msg.t === 'lobby') { app.lobby = msg; app.view = null; app.winShown = false; $('#win').hidden = true; show('lobby'); renderLobby(); }
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
    const sp = app.spare || store.get('spare');
    toast(sp ? 'Conexão perdida. Tentando voltar sozinho…' : 'Conexão perdida. Peça um novo QR ao anfitrião (menu ☰ → reconectar).', sp ? 3000 : 6000);
    if (app.view) renderGame(); else { show('home'); }
    autoLoop(true);
  },
};
// Volta sozinho pela conexão reserva. Tenta algumas vezes; se não der, fica o caminho do QR.
const certReady = initCert().catch(() => null);
let autoBusy = false, autoTimer = null, autoTries = 0;
async function tryAuto() {
  const sp = app.spare || store.get('spare');
  if (autoBusy || !sp) return false;
  autoBusy = true;
  let u = null;
  try {
    await certReady;
    u = await useSpare(sp, guestHandlers);
    const ok = await u.opened(6000);
    if (!ok) u.cancel();
    return ok;
  } catch { u && u.cancel(); return false; } finally { autoBusy = false; }
}
function autoLoop(reset) {
  if (reset) { if (app.autoOn) return; autoTries = 0; }
  clearTimeout(autoTimer);
  const need = app.role !== 'host' && (app.role === 'guest' || store.get('guest')) && (app.spare || store.get('spare')) && (!app.link || app.hostLag);
  if (!need || autoTries >= 12) { app.autoOn = false; if (app.view) renderGame(); return; }
  app.autoOn = true; autoTries++;
  tryAuto().then((ok) => {
    if (ok) { app.autoOn = false; return; }
    autoTimer = setTimeout(autoLoop, 4000);
    if (app.view) renderGame();
  });
}
async function guestJoin(raw) {
  const code = extractCode(raw);
  if (!/^1~o/.test(code)) return toast('Esse não é um QR de convite.');
  modal('<h3>Preparando resposta…</h3><p>Se o navegador pedir, permita a câmera: sem ela a conexão na rede local pode não abrir.</p>');
  const camStream = await openCamera();
  let j;
  await certReady;
  try { j = await joinInvite(code, guestHandlers); }
  catch (e) { closeModal(); return toast(e.message === 'sem-rede' ? 'Sem rede local: conecte-se ao mesmo Wi-Fi ou hotspot do anfitrião e tente de novo.' : 'Convite inválido ou expirado.', 5000); }
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
       <div class="setting">Regras extras<span class="chips"><button class="chip${app.cfg.events ? ' on' : ''}" data-opt="events" aria-pressed="${!!app.cfg.events}">Eventos de rodada</button><button class="chip${app.cfg.pacts ? ' on' : ''}" data-opt="pacts" aria-pressed="${!!app.cfg.pacts}">Pactos</button></span></div>
       <div class="row"><button class="btn" data-do="invite" ${full ? 'disabled' : ''}>Convidar por QR</button></div>
       <div class="row"><button class="btn small" data-do="addLocal" ${full ? 'disabled' : ''}>+ Jogador neste aparelho</button><button class="btn small" data-do="addBot" ${full ? 'disabled' : ''}>+ Bot</button></div>
       <button class="btn primary" data-do="begin" ${seats.length < 2 ? 'disabled' : ''}>Iniciar partida (${seats.length} jogadores)</button>
       <button class="btn ghost" data-do="leave">Sair</button>`
    : `<p class="tag">Tempo por turno: ${app.lobby.secs ? app.lobby.secs / 60 + ' min' : 'livre'}.${app.lobby.events || app.lobby.pacts ? ` Regras extras: ${[app.lobby.events && 'eventos de rodada', app.lobby.pacts && 'pactos'].filter(Boolean).join(' e ')}.` : ''} Aguardando o anfitrião iniciar…</p><button class="btn ghost" data-do="leave">Sair</button>`;
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
let aimLayer = null;
(function buildMap() {
  const aura = el('g', {}, svg), depth = el('g', {}, svg), land = el('g', {}, svg), moat = el('g', {}, svg), routes = el('g', {}, svg), labels = el('g', {}, svg), aim = el('g', { class: 'aimlayer' }, svg), hits = el('g', {}, svg);
  aimLayer = aim;
  // ligações por mar: um traço de costa a costa, por cima da terra, para ficar sempre visível
  const link = (x1, y1, x2, y2) => { el('line', { class: 'sea-case', x1, y1, x2, y2 }, routes); el('line', { class: 'sea-route', x1, y1, x2, y2 }, routes); };
  SEA.forEach(([, , x1, y1, x2, y2, wrap]) => {
    if (wrap) { link(x1, y1, -PAD, y1); link(x2, y2, MAP_W + PAD, y2); } // dá a volta no mapa: um trecho até cada borda
    else link(x1, y1, x2, y2);
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
function boxOf() { const b = rotated() ? { left: 0, top: 0 } : $('#mapwrap').getBoundingClientRect(); return { left: b.left, top: b.top, width: svg.clientWidth, height: svg.clientHeight }; }
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
  const q = pt(e);
  ptrs.set(e.pointerId, { x: q.x, y: q.y });
  if (ptrs.size === 1) gesture = { sx: q.x, sy: q.y, moved: false, id: e.pointerId };
  else if (gesture) gesture.moved = true;
});
svg.addEventListener('pointermove', (e) => {
  const p = ptrs.get(e.pointerId);
  if (!p) return;
  const prev = [...ptrs.values()].map((q) => ({ ...q }));
  const q = pt(e);
  p.x = q.x; p.y = q.y;
  const cur = [...ptrs.values()];
  const r = boxOf();
  if (cur.length === 1) {
    if (gesture && !gesture.moved && Math.hypot(q.x - gesture.sx, q.y - gesture.sy) < 8) return;
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
  const r = boxOf(), q = pt(e), mx = q.x - r.left, my = q.y - r.top;
  const wx = cam.x + mx / cam.z, wy = cam.y + my / cam.z;
  cam.z *= e.deltaY < 0 ? 1.15 : 1 / 1.15; applyCam();
  cam.x = wx - mx / cam.z; cam.y = wy - my / cam.z; applyCam();
}, { passive: false });
addEventListener('resize', () => { applyLayout(); if (!$('#game').hidden) applyCam(); });
$('#fit').onclick = () => fitView(true);

/* ---------- alertas, efeitos e relógio ---------- */
const buzz = (p) => { try { navigator.vibrate && navigator.vibrate(p); } catch {} };
// Alerta grande no meio da tela; some sozinho em 1 s. Alertas do próprio jogador (urgentes)
// passam na frente dos demais, para "Sua vez!" nunca ficar preso atrás de avisos de outros.
const flashQ = [];
let flashCur = null, flashTimer = null;
// mini = aviso discreto no topo, para o que os outros fazem: não cobre o mapa.
function flash(text, color, sub = '', ms = 1000, urgent = false, mini = false) {
  const f = { text, color, sub, ms, urgent, mini };
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
  box.classList.toggle('mini', f.mini);
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
// Destaque passageiro dos territórios envolvidos na jogada de outro jogador (o resto do mapa esmaece).
function spotlight(ids, ms = 1000) {
  app.spot = { set: new Set(ids), until: Date.now() + ms };
  clearTimeout(app.spotTimer);
  app.spotTimer = setTimeout(() => { app.spot = null; renderGame(); }, ms + 30);
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
  if (first) app.roundSeen = v.round;
  app.evN = v.n;
  const col = (p) => COLORS[v.players[p].color].c, nm = (p) => v.players[p].name;
  const mine = (p) => (app.role === 'guest' ? p === app.me : v.players[p].ctrl === 'local');
  for (const e of v.ev || []) {
    if (first && e.t !== 'turn') continue;
    if (e.t === 'turn') {
      if (v.phase !== 'play') continue;
      if (v.round === 1 && app.roundSeen === 0) flash('Rodada 2', '#e2b04a', 'A partir de agora os ataques estão liberados', 1400, true);
      app.roundSeen = v.round;
      if (mine(e.p)) { flash('Sua vez!', col(e.p), v.round === 0 ? 'Distribua seus exércitos' : PHASE_ALERT.reinforce[1], 1000, true); buzz([120, 60, 120]); play('turn'); }
      else { flash(`Vez de ${nm(e.p)}`, col(e.p), '', 900, false, true); play('other'); }
    } else if (e.t === 'phase') {
      if (mine(e.p)) { flash(PHASE_ALERT[e.step][0], col(e.p), PHASE_ALERT[e.step][1], 1000, true); buzz(40); play('phase'); }
    } else if (e.t === 'place') { fxPulse(e.to, col(e.p)); fxFloat(e.to, '+' + e.k, '#fff'); play('place'); if (!mine(e.p)) spotlight([e.to]); }
    else if (e.t === 'trade') {
      if (mine(e.p)) flash(`+${e.v} exércitos`, col(e.p), e.auto ? 'Troca automática de cartas' : 'Troca de cartas', 1000, true);
      else { flash(`${nm(e.p)} trocou cartas: +${e.v}`, col(e.p), '', 1000, false, true); if ((e.bonus || []).length) spotlight(e.bonus); }
      (e.bonus || []).forEach((t) => { fxPulse(t, col(e.p)); fxFloat(t, '+2', '#fff'); });
      play('trade');
    }
    else if (e.t === 'move') { fxArrow(e.from, e.to, col(e.p)); fxFloat(e.to, '+' + e.k, '#fff'); play('move'); if (!mine(e.p)) spotlight([e.from, e.to]); }
    else if (e.t === 'attack') {
      fxArrow(e.from, e.to, col(e.p));
      if (e.la) fxFloat(e.from, '−' + e.la, '#ff8a7a');
      if (e.ld) fxFloat(e.to, '−' + e.ld, '#ff8a7a');
      shake(e.won);
      if (!mine(e.p)) spotlight([e.from, e.to], 1200);
      const involved = mine(e.p) || mine(e.def);
      play('dice'); play(!e.won ? 'attack' : mine(e.def) && !mine(e.p) ? 'lost' : 'conquer');
      if (e.won) {
        fxPulse(e.to, col(e.p), true);
        if (involved) buzz([80, 40, 160]);
        if (mine(e.p)) flash('Conquistou!', col(e.p), TERR[e.to].n, 1000, true);
        else if (mine(e.def)) flash(`${nm(e.p)} tomou ${TERR[e.to].n}`, col(e.p), '', 1200, false, true); // aviso discreto: o mapa fica livre para ver o que acontece
      } else if (involved) buzz(70);
    } else if (e.t === 'card') { if (mine(e.p)) { flash('Carta recebida', col(e.p), 'Toque no ícone de cartas para ver'); play('card'); } }
    else if (e.t === 'dead') { flash(`${nm(e.p)} eliminado`, col(e.by), `por ${nm(e.by)}`); if (mine(e.p)) buzz([200, 80, 200]); play('dead'); }
    else if (e.t === 'timeout') { flash(mine(e.p) ? 'Tempo esgotado!' : `Tempo de ${nm(e.p)} esgotou`, '#e06a5a', '', 1000, mine(e.p), !mine(e.p)); play('timeout'); }
    else if (e.t === 'win') { play('win'); buzz([150, 80, 150, 80, 300, 80, 400]); }
    else if (e.t === 'event') { flash(EVENTS[e.k].n, '#e2b04a', eventText(e), 2400, true); play('phase'); }
    else if (e.t === 'pactAsk') { if (!mine(e.b)) flash(mine(e.a) ? `Proposta enviada a ${nm(e.b)}` : `${nm(e.a)} propôs um pacto a ${nm(e.b)}`, col(e.a), '', 1100, false, true); }
    else if (e.t === 'pact') {
      const inv = mine(e.a) || mine(e.b);
      flash(inv ? 'Pacto firmado' : `Pacto: ${nm(e.a)} e ${nm(e.b)}`, col(e.a), inv ? `${nm(e.a)} e ${nm(e.b)} · até o fim da rodada ${e.until + 1}` : '', inv ? 1500 : 1300, inv, !inv);
      if (inv) buzz(60); play('trade');
    } else if (e.t === 'pactNo') { if (mine(e.a)) flash('Pacto recusado', col(e.b), `${nm(e.b)} não aceitou`, 1200, true); else if (!mine(e.b)) flash(`${nm(e.b)} recusou o pacto de ${nm(e.a)}`, col(e.b), '', 1100, false, true); }
    else if (e.t === 'pactBreak') {
      const inv = mine(e.a) || mine(e.b);
      flash(mine(e.b) && !mine(e.a) ? `${nm(e.a)} rompeu o pacto com você!` : inv ? 'Pacto rompido' : `${nm(e.a)} rompeu o pacto com ${nm(e.b)}`, col(e.a), inv ? `${nm(e.a)} perdeu ${e.lost} exército${e.lost === 1 ? '' : 's'} do reforço` : '', 1600, inv, !inv);
      if (mine(e.b) && !mine(e.a)) buzz([160, 60, 160]); play('lost');
    } else if (e.t === 'pactEnd') { if (mine(e.a) || mine(e.b)) flash('Pacto encerrado', '#e2b04a', `${nm(e.a)} e ${nm(e.b)} podem se atacar de novo`, 1500, false, true); }
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
// Anel de jogada: o aro de fora é o relógio do turno; o centro mostra o tempo (ou, sem relógio, os territórios de quem joga).
const RING_C = 2 * Math.PI * 45;
function updateRing() {
  const el = $('#ring'), v = app.view;
  if (el.hidden || !el.firstChild || !v) return null;
  const time = el.querySelector('.time'), rt = el.querySelector('.rt'), rs = el.querySelector('.rs');
  if (!(app.tEnd && app.tLimit)) { // sem relógio (turno livre, bot ou pareamento em curso)
    time.setAttribute('stroke-dasharray', `0 ${RING_C}`);
    rt.textContent = owned(v, v.turn); rs.textContent = 'terr.';
    el.classList.remove('low');
    return null;
  }
  const left = app.tEnd - Date.now(), secs = Math.max(0, Math.ceil(left / 1000));
  time.setAttribute('stroke-dasharray', `${(Math.max(0, Math.min(1, left / app.tLimit)) * RING_C).toFixed(1)} ${RING_C}`);
  rt.textContent = secs >= 60 ? `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}` : secs;
  rs.textContent = secs >= 60 ? '' : 'seg';
  el.classList.toggle('low', secs <= 10);
  return secs;
}
setInterval(() => {
  const v = app.view;
  const on = v && v.phase === 'play' && !$('#game').hidden;
  const secs = on ? updateRing() : null;
  if (secs == null) { app.lastSec = null; return; }
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
// Jogada em nome de um jogador específico (resposta a pacto, que acontece fora da vez).
function actAs(p, a) {
  if (app.role === 'guest') return app.link ? app.link.send({ t: 'act', a }) : toast('Sem conexão com o anfitrião.');
  const err = apply(app.game, p, a);
  if (err) toast(err);
  sync();
}
const seaShut = (v, a, b) => !!(v.event && v.event.k === 'sea' && isSea(a, b));
function tapTerritory(t) {
  const v = app.view;
  if (!v) return;
  app.info = t;
  const me = v.turn, T = v.terr, mine = T[t].o === me, adj = (a, b) => TERR[a].adj.includes(b);
  if (canAct() && !v.occupy) {
    if (v.step === 'reinforce') {
      if (!mine) app.sel = null;
      else if (mustTrade(v)) toast('Com 5 cartas é obrigatório trocar antes.');
      else if (v.pool.free + (v.pool.cont[TERR[t].c] || 0) < 1) { app.sel = null; toast('Os exércitos restantes são bônus de outro continente.'); }
      else if (app.sel === t) app.n++; // tocar de novo no mesmo território soma 1
      else app.sel = t;
      app.target = null;
    } else if (v.step === 'attack') {
      if (mine) {
        if (T[t].a < 2) { app.sel = app.target = null; toast('É preciso 2 ou mais exércitos para atacar daqui.'); }
        else if (app.target != null && adj(t, app.target)) app.sel = t; // troca a origem e mantém o alvo
        else { app.sel = t; app.target = null; }
      } else if (app.target === t && app.sel != null) return actions.attack(); // tocar de novo no alvo ataca
      else if (app.sel != null && adj(app.sel, t) && !attackBlock(v, app.sel, t)) app.target = t;
      else if (app.sel != null && adj(app.sel, t)) { app.target = null; toast(attackBlock(v, app.sel, t), 4200); }
      else { // tocou direto no inimigo: a origem passa a ser o vizinho seu com mais exércitos
        const near = TERR[t].adj.filter((j) => T[j].o === me && T[j].a >= 2).sort((a, b) => T[b].a - T[a].a);
        const from = near.filter((j) => !attackBlock(v, j, t))[0];
        if (from == null && near.length) { app.target = null; toast(attackBlock(v, near[0], t), 4200); }
        else if (from == null) { app.target = null; toast('Nenhum território seu com 2 ou mais exércitos faz fronteira com esse.'); }
        else { app.sel = from; app.target = t; }
      }
    } else if (v.step === 'move') {
      if (mine && app.sel != null && t !== app.sel && adj(app.sel, t) && seaShut(v, app.sel, t)) { app.target = null; toast('Mar revolto: as ligações por mar estão fechadas nesta rodada.', 3600); }
      else if (mine && app.sel != null && t !== app.sel && adj(app.sel, t)) app.target = t;
      else if (!mine || t === app.sel) app.sel = app.target = null;
      else if (v.movable[t] > 0) { app.sel = t; app.target = null; }
      else { app.sel = app.target = null; toast('Nenhum exército disponível para mover daqui.'); }
    }
  }
  renderGame();
}
// Faixa do seletor − / + conforme o que o jogador está fazendo; null quando não há quantidade a escolher.
function stepRange(v) {
  const T = v.terr, s = app.sel, t = app.target;
  if (v.occupy) return [0, v.occupy.max];
  if (s == null || T[s].o !== v.turn) return null;
  if (v.step === 'reinforce') { const hi = v.pool.free + (v.pool.cont[TERR[s].c] || 0); return hi > 0 ? [1, hi] : null; }
  if (t == null) return null;
  if (v.step === 'attack') { // na tempestade, quem ataca o continente atingido rola no máximo 2 dados
    const cap = v.event && v.event.k === 'storm' && TERR[t].c === v.event.c ? 2 : 3;
    return T[s].a > 1 ? [1, Math.min(cap, T[s].a - 1)] : null;
  }
  const hi = Math.min(v.movable[s] || 0, T[s].a - 1);
  return hi > 0 ? [1, hi] : null;
}

const STEP = { reinforce: 'Reforço', attack: 'Ataque', move: 'Remanejamento' };
const ICON = {
  goal: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/></svg>',
  cards: '<svg viewBox="0 0 24 24"><rect x="4" y="6" width="11" height="15" rx="2"/><path d="M9 3h9a2 2 0 0 1 2 2v13"/></svg>',
  menu: '<svg viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  extras: '<svg viewBox="0 0 24 24"><path d="M13 3 5 13.5h6L10 21l8-10.5h-6z"/></svg>',
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
  if (v.step === 'attack' && app.target != null && T[app.target].o === v.turn) app.sel = app.target = null;
  if (v.step === 'move' && app.target != null && T[app.target].o !== v.turn) app.target = null;
  if (v.step === 'attack' && app.sel != null && T[app.sel].a < 2) app.sel = app.target = null;
  if (v.step === 'attack' && app.sel != null && app.target != null && attackBlock(v, app.sel, app.target)) app.target = null;

  processEvents(v);
  // proposta de pacto para um jogador deste aparelho: pergunta na hora; some se a proposta vencer
  const of = v.phase === 'play' ? v.offer || null : null;
  const ofKey = of ? `${v.round}:${v.turn}:${of.from}:${of.to}` : null;
  if (ofKey !== app.offerKey) {
    if (app.offerOpen) closeModal();
    app.offerKey = ofKey;
    if (of && offerIsMine(v)) showOffer(v);
  }
  // fim de jogo: tela de vitória (uma vez por partida) e, no mapa, só o domínio do vencedor aceso
  if (v.phase !== 'over') { app.winShown = false; $('#win').hidden = true; }
  else if (!app.winShown) { app.winShown = true; showWin(v); }
  // quem só assiste vê o que o jogador da vez está mirando
  const okT = (x) => Number.isInteger(x) && x >= 0 && x < TERR.length;
  const pk = !can && app.peek && app.peek.n === v.n && okT(app.peek.sel) ? app.peek : null;

  // mapa
  const targets = new Set();
  if (can && app.sel != null) {
    TERR[app.sel].adj.forEach((j) => {
      if (v.step === 'attack' && T[j].o !== v.turn && !attackBlock(v, app.sel, j)) targets.add(j);
      if (v.step === 'move' && T[j].o === v.turn && v.movable[app.sel] > 0 && !seaShut(v, app.sel, j)) targets.add(j);
    });
  }
  // no reforço, quando só restam bônus de continente, apaga onde não dá para colocar
  const bonusOnly = can && v.step === 'reinforce' && v.pool.free === 0 && !mustTrade(v);
  const spot = !can && app.spot && app.spot.until > Date.now() ? app.spot.set : null, front = [];
  nodes.forEach((nd, i) => {
    nd.poly.setAttribute('fill', COLORS[v.players[T[i].o].color].c);
    nd.num.textContent = T[i].a;
    const hl = app.target != null ? i === app.target : targets.has(i);
    // quem joga: esmaece o que não é origem nem alvo possível; quem assiste: esmaece tudo menos
    // o que o jogador da vez selecionou (ou, sem seleção, os territórios da última jogada)
    const dim = can ? (app.sel != null && v.step !== 'reinforce' ? i !== app.sel && !targets.has(i) : bonusOnly && !(T[i].o === v.turn && v.pool.cont[TERR[i].c] > 0))
      : v.phase === 'over' ? T[i].o !== v.winner : pk ? i !== pk.sel && i !== pk.target : spot ? !spot.has(i) : false;
    const ps = pk ? (i === pk.sel ? ' sel' : i === pk.target ? ' tgt' : '') : spot && spot.has(i) ? ' lit' : '';
    nd.poly.setAttribute('class', 'terr' + (i === app.sel ? ' sel' : '') + (hl ? ' tgt' : '') + (dim ? ' dim' : '') + ps);
    if (i === app.sel || hl || ps) front.push(nd.poly);
  });
  front.forEach((p) => p.parentNode.appendChild(p)); // destacados por cima dos vizinhos, para o contorno aparecer inteiro

  // linhas até onde dá para atacar ou mover (e, para quem assiste, a mira do jogador da vez)
  aimLayer.replaceChildren();
  const aimTo = (a, b, cls, color) => {
    if (Math.abs(TERR[a].x - TERR[b].x) > MAP_W / 2) return;
    const ln = el('line', { class: 'aim ' + cls, x1: TERR[a].x, y1: TERR[a].y, x2: TERR[b].x, y2: TERR[b].y }, aimLayer);
    if (color) ln.setAttribute('stroke', color);
  };
  if (can && app.sel != null && v.step !== 'reinforce' && !v.occupy) (app.target != null ? [app.target] : [...targets]).forEach((j) => aimTo(app.sel, j, app.target != null ? 'one' : ''));
  if (pk && okT(pk.target)) aimTo(pk.sel, pk.target, 'one', COLORS[cur.color].c);

  // seletor − / +: valor inicial quando muda o que está sendo escolhido, sempre dentro da faixa
  const rng = can ? stepRange(v) : null, nKey = `${v.step}:${v.occupy ? 'o' + v.occupy.to : ''}:${app.sel}:${app.target}`;
  if (rng) {
    if (nKey !== app.nKey) app.n = v.occupy || v.step === 'attack' ? rng[1] : 1;
    app.n = Math.max(rng[0], Math.min(rng[1], app.n));
  }
  app.nKey = nKey;
  const stepper = (unit) => `<div class="step"><button data-step="-1" aria-label="Menos"${app.n <= rng[0] ? ' disabled' : ''}>−</button><b>${app.n}${unit ? `<small>${unit}</small>` : ''}</b><button data-step="1" aria-label="Mais"${app.n >= rng[1] ? ' disabled' : ''}>+</button></div>`;

  // topo
  const meP = v.players[vw], extras = !!(v.opts && (v.opts.events || v.opts.pacts));
  $('#hud').innerHTML = `<div class="turn"><span class="dot" style="background:${COLORS[cur.color].c}"></span>
    <span><b>${esc(cur.name)}</b><span class="phase">${v.phase === 'over' ? 'Fim de jogo' : `${STEP[v.step]} · rodada ${v.round + 1}`}</span></span></div>
    <button class="icon" data-do="objective" aria-label="Objetivo">${ICON.goal}</button>
    <button class="icon" data-do="cards" aria-label="Cartas">${ICON.cards}<span>${handSize(meP)}</span></button>
    ${extras ? `<button class="icon${of && offerIsMine(v) ? ' call' : ''}" data-do="extras" aria-label="${[v.opts.events && 'Evento da rodada', v.opts.pacts && 'Pactos'].filter(Boolean).join(' e ')}">${ICON.extras}${v.opts.pacts && v.pacts.length ? `<span>${v.pacts.length}</span>` : ''}</button>` : ''}
    <button class="icon" data-do="menu" aria-label="Menu">${ICON.menu}</button>`;

  // anel de jogada: uma fatia por jogador, na ordem em que jogam (sentido horário a partir do topo,
  // onde começa a de quem joga agora, marcada por uma seta no meio dela); todas com a mesma espessura, e o comprimento segue o número de territórios
  const seq = [];
  for (let k = 0; k < v.players.length; k++) { const i = (v.turn + k) % v.players.length; if (v.players[i].alive) seq.push(i); }
  const ring = $('#ring');
  ring.hidden = v.phase !== 'play';
  if (!ring.hidden) {
    const C = 2 * Math.PI * 31, gap = seq.length > 1 ? 2.5 : 0, counts = seq.map((i) => owned(v, i));
    let lens = counts.map((c) => Math.max(8, (c / TERR.length) * C));
    const sum = lens.reduce((x, y) => x + y, 0);
    lens = lens.map((l) => (l * C) / sum);
    let off = 0, segs = '';
    seq.forEach((i, k) => {
      const L = lens[k];
      segs += `<circle class="seg" r="31" stroke="${COLORS[v.players[i].color].c}" stroke-dasharray="${(L - gap).toFixed(1)} ${C.toFixed(1)}" stroke-dashoffset="${(-off).toFixed(1)}"/>`;
      off += L;
    });
    ring.setAttribute('aria-label', 'Ordem de jogada: ' + seq.map((i, k) => `${v.players[i].name}${k ? '' : ' (jogando)'}, ${counts[k]} territórios`).join('; '));
    ring.innerHTML = `<svg viewBox="-50 -50 100 100"><circle class="disc" r="50"/><g transform="rotate(-90)"><circle class="track" r="45"/><circle class="time" r="45"/>${segs}</g><path class="start" transform="rotate(${(((lens[0] - gap) / 2 / C) * 360).toFixed(1)})" d="M-4 -42h8l-4 6z"/><text class="rt" y="2"></text><text class="rs" y="14"></text></svg>`;
    updateRing();
  }

  // evento da rodada sempre à vista, ao lado do anel (toque abre a explicação)
  const chip = $('#evchip');
  chip.hidden = !(v.event && v.phase === 'play');
  if (!chip.hidden) { chip.innerHTML = `${ICON.extras}<span>${EVENTS[v.event.k].n}${v.event.c != null ? ' · ' + CONTINENTS[v.event.c].n : ''}</span>`; chip.setAttribute('aria-label', `Evento da rodada: ${EVENTS[v.event.k].n}. ${eventText(v.event)}`); }

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
  const info = app.info != null ? `${TERR[app.info].n} · ${CONTINENTS[TERR[app.info].c].n} · ${esc(v.players[T[app.info].o].name)} · ${T[app.info].a} exérc.`
    : v.event && v.phase === 'play' ? `<b class="evt">${EVENTS[v.event.k].n}</b> · ${esc(eventText(v.event))}` : esc(v.log[v.log.length - 1] || '');
  let msg = '', btns = '', warn = '';
  if (v.phase === 'over') {
    const w = v.players[v.winner];
    msg = `<b style="color:${COLORS[w.color].c}">${esc(w.name)}</b> venceu! ${w.obj != null ? esc(objectiveText(OBJECTIVES[w.obj])) : ''}`;
    btns = app.role === 'host' ? '<button class="btn small primary" data-do="again">Nova partida</button>' : '';
  } else if (!can) {
    const nm = `<b style="color:${COLORS[cur.color].c}">${esc(cur.name)}</b>`;
    const doing = v.step === 'reinforce' ? `está reforçando${pk ? ' ' + TERR[pk.sel].n : ''} (${poolTotal(v)} a colocar)`
      : v.step === 'move' ? (pk ? `vai mover tropas de ${TERR[pk.sel].n}` : 'está remanejando tropas')
      : pk && okT(pk.target) ? `mira ${TERR[pk.target].n} a partir de ${TERR[pk.sel].n}` : pk ? `prepara um ataque de ${TERR[pk.sel].n}` : 'está na fase de ataque';
    msg = app.role === 'guest' && !app.link ? `<span class="off">Sem conexão.</span> ${app.autoOn ? 'Tentando voltar sozinho…' : 'Peça um novo QR ao anfitrião.'}` : `${nm} ${doing}${cur.ctrl === 'bot' ? ' (bot)' : ''}`;
    if (app.role === 'guest' && !app.link) btns = '<button class="btn small primary" data-do="join">Reconectar (ler QR)</button>';
  } else if (v.step === 'reinforce') {
    const extra = Object.entries(v.pool.cont).map(([c, n]) => `+${n} em ${CONTINENTS[c].n}`).join(', ');
    const left = `<b>${v.pool.free}</b> livre${v.pool.free === 1 ? '' : 's'}${extra ? ` (${extra})` : ''}`;
    msg = mustTrade(v) ? 'Você tem 5 ou mais cartas: troque antes de reforçar.' : rng ? `Reforçar <b>${TERR[app.sel].n}</b> · ${left}` : `Toque num território seu para reforçar · ${left}`;
    const tr = Array.isArray(meP.cards) ? bestTrade(meP.cards, T, v.turn) : null;
    btns = (rng ? stepper() + '<button class="btn small" data-do="max">Máx</button><button class="btn small primary" data-do="place">Colocar</button>' : '')
      + (tr ? `<button class="btn small${rng ? '' : ' primary'}" data-do="autoTrade">Trocar +${tradeValue(v.trades)}</button>` : '');
  } else if (v.occupy) {
    msg = `Conquistou <b>${TERR[v.occupy.to].n}</b>! Um exército já entrou; levar mais quantos?`;
    btns = stepper() + '<button class="btn small primary" data-do="occupyOk">Mover</button>';
  } else if (v.step === 'attack') {
    if (rng) {
      msg = `${TERR[app.sel].n} (${T[app.sel].a}) ⚔ ${TERR[app.target].n} (${T[app.target].a}) · toque de novo no alvo para atacar`;
      btns = stepper(app.n === 1 ? 'dado' : 'dados') + '<button class="btn small primary" data-do="attack">Atacar</button><button class="btn small" data-do="blitz">Auto</button><button class="btn small ghost" data-do="endAttack">Encerrar</button>';
    } else {
      msg = app.sel != null ? 'Toque num inimigo ligado pelas linhas.' : 'Toque no inimigo que quer atacar (ou num território seu para escolher a origem).';
      btns = '<button class="btn small" data-do="endAttack">Encerrar ataques</button>';
    }
  } else if (rng) {
    msg = `Mover de <b>${TERR[app.sel].n}</b> para <b>${TERR[app.target].n}</b>`;
    btns = stepper() + '<button class="btn small" data-do="max">Máx</button><button class="btn small primary" data-do="moveOk">Mover</button><button class="btn small ghost" data-do="endTurn">Encerrar</button>';
  } else {
    msg = app.sel != null ? `Mover de ${TERR[app.sel].n} (até ${v.movable[app.sel] || 0}): toque no destino ligado pelas linhas.` : 'Remaneje: toque na origem e depois num vizinho seu.';
    btns = '<button class="btn small primary" data-do="endTurn">Encerrar turno</button>';
  }
  if (app.role === 'host' && v.phase === 'play') {
    const off = app.seats.filter((s) => s.ctrl === 'remote' && (!s.link || s.lag));
    if (off.length) warn = `<div class="actions"><button class="btn small warn" data-do="invite">Reconectar ${esc(off.length === 1 ? off[0].name : off.length + ' jogadores')} (${off.some((s) => !s.link) ? 'offline' : 'sem resposta'})</button></div>`;
  } else if (app.role === 'guest' && app.link && app.hostLag && v.phase === 'play') {
    warn = '<div class="actions"><button class="btn small warn" data-do="join">Anfitrião sem resposta · reconectar</button></div>';
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

// Tela de vitória: ocupa a tela toda, na cor do vencedor, com o objetivo cumprido e a classificação final.
function showWin(v) {
  const w = v.players[v.winner], col = COLORS[w.color].c;
  const mine = app.role === 'guest' ? v.winner === app.me : w.ctrl === 'local';
  const rank = v.players.map((p, i) => ({ p, i, n: owned(v, i) })).sort((a, b) => (b.i === v.winner) - (a.i === v.winner) || b.n - a.n);
  const pieces = Array.from({ length: 70 }, (_, k) => {
    const c = [col, '#e2b04a', '#f1e6cf', col][k % 4], x = (k * 37) % 100, d = 2.4 + ((k * 13) % 20) / 10, dl = -((k * 29) % 40) / 10, sz = 6 + (k % 4) * 2;
    return `<i style="left:${x}%;width:${sz}px;height:${sz * 1.6}px;background:${c};animation-duration:${d}s;animation-delay:${dl}s"></i>`;
  }).join('');
  $('#win').innerHTML = `<div class="confetti" aria-hidden="true">${pieces}</div>
    <div class="wincard" style="--c:${col}">
      <svg class="cup" viewBox="0 0 64 64" aria-hidden="true"><path d="M20 10h24v14a12 12 0 0 1-24 0z"/><path d="M20 14h-8v4a8 8 0 0 0 8 8M44 14h8v4a8 8 0 0 1-8 8M32 36v10M22 54h20M26 46h12v8H26z"/></svg>
      <p class="wl">${mine ? 'Você venceu!' : 'Vitória de'}</p>
      <h2>${esc(w.name)}</h2>
      <p class="wobj"><b>${v.winBy === 'last' ? 'Último exército em jogo · o objetivo era' : 'Objetivo cumprido'}</b>${w.obj != null ? esc(objectiveText(OBJECTIVES[w.obj]).replace(/ Se for o seu.*$/, '')) : ''}</p>
      <ol class="rank">${rank.map(({ p, i, n }) => `<li${i === v.winner ? ' class="first"' : ''}><span class="dot" style="background:${COLORS[p.color].c}"></span><span class="who">${esc(p.name)}</span><span>${p.alive ? n + ' territórios' : 'eliminado'}</span></li>`).join('')}</ol>
      <div class="row"><button class="btn" data-do="winMap">Ver o mapa</button>${app.role === 'host' ? '<button class="btn primary" data-do="again">Nova partida</button>' : ''}</div>
    </div>`;
  $('#win').hidden = false;
}
// Regras opcionais: evento da rodada e pactos (propor, responder, romper).
const offerIsMine = (v) => !!v.offer && (app.role === 'guest' ? v.offer.to === app.me : v.players[v.offer.to].ctrl === 'local');
function showOffer(v) {
  const of = v.offer, a = v.players[of.from], b = v.players[of.to];
  modal(`<h3>Proposta de pacto</h3>
    <p style="color:var(--ink);font-size:16px"><b style="color:${COLORS[a.color].c}">${esc(a.name)}</b> propõe um pacto de não agressão a <b style="color:${COLORS[b.color].c}">${esc(b.name)}</b>.</p>
    <p>Até o fim da rodada ${v.round + PACT_ROUNDS + 1} nenhum dos dois ataca o outro. Quem quiser romper antes só pode no início do próprio turno e perde ${PACT_PENALTY} exércitos do reforço.</p>
    <div class="row"><button class="btn primary" data-m="yes">Aceitar</button><button class="btn" data-m="no">Recusar</button></div>`, () => { app.offerOpen = false; });
  app.offerOpen = true;
  $('#modal .sheet').onclick = (e) => {
    const m = e.target.dataset.m;
    if (m !== 'yes' && m !== 'no') return;
    closeModal(); actAs(of.to, { t: 'pactReply', accept: m === 'yes' });
  };
  buzz([60, 40, 60]); play('turn');
}
function showExtras() {
  const v = app.view, me = app.role === 'guest' ? app.me : viewer();
  const myTurn = canAct() && v.turn === me, alive = v.players.filter((p) => p.alive).length;
  const tag = (i) => `<b style="color:${COLORS[v.players[i].color].c}">${esc(v.players[i].name)}</b>`;
  let h = '';
  if (v.opts.events) {
    h += `<h3>Evento da rodada</h3>${v.event ? `<p style="color:var(--ink);font-size:16px"><b class="evt">${EVENTS[v.event.k].n}</b> · ${esc(eventText(v.event))}</p>` : '<p>Nenhum ainda. O primeiro é sorteado na rodada 2.</p>'}
      <p>A cada rodada sai um evento novo, que vale para todos até a rodada acabar.</p>`;
  }
  if (v.opts.pacts) {
    h += `<h3>Pactos</h3><p>Dois jogadores combinam não se atacar por ${PACT_ROUNDS} rodadas. Proponha na sua vez (uma proposta por turno). Romper antes só no início do seu turno, e custa ${PACT_PENALTY} exércitos do reforço.</p>`;
    h += `<ul class="plist">${v.pacts.map((x) => {
      const mineP = x.a === me || x.b === me, other = x.a === me ? x.b : x.a;
      return `<li><span class="who">${tag(x.a)} e ${tag(x.b)} · até o fim da rodada ${x.until + 1}</span>${mineP && myTurn && v.step === 'reinforce' ? `<button class="btn small warn" data-break="${other}">Romper</button>` : ''}</li>`;
    }).join('') || '<li><span class="who">Nenhum pacto em vigor.</span></li>'}</ul>`;
    if (offerIsMine(v)) h += `<button class="btn primary" data-m="answer">Responder à proposta de ${esc(v.players[v.offer.from].name)}</button>`;
    else if (v.offer) h += `<p>${tag(v.offer.from)} aguarda a resposta de ${tag(v.offer.to)}.</p>`;
    if (myTurn) {
      const used = v.players[me].offered === v.round + ':' + v.turn;
      const cand = v.players.map((p, i) => i).filter((i) => i !== me && v.players[i].alive && !pactOf(v, me, i));
      h += alive <= 2 ? '<p>Com só dois jogadores em jogo não há pactos.</p>'
        : used ? '<p>Você já fez a proposta deste turno.</p>'
        : `<div class="row wrap">${cand.map((i) => `<button class="btn small" data-offer="${i}"${v.offer ? ' disabled' : ''}><span class="dot" style="background:${COLORS[v.players[i].color].c}"></span>Propor a ${esc(v.players[i].name)}</button>`).join('')}</div>`;
    } else h += '<p>Você propõe ou rompe pactos na sua vez.</p>';
  }
  modal(h + '<button class="btn" data-m="close">Fechar</button>');
  $('#modal .sheet').onclick = (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    const d = b.dataset;
    if (d.m === 'answer') return showOffer(app.view);
    if (d.offer != null) { closeModal(); act({ t: 'pactOffer', to: +d.offer }); }
    if (d.break != null) {
      const w = +d.break;
      modal(`<h3>Romper o pacto?</h3><p>Você perde ${PACT_PENALTY} exércitos do reforço deste turno (ou o que restar dele) e volta a poder atacar ${tag(w)}. Todos ficam sabendo.</p>
        <div class="row"><button class="btn warn" data-m="sure">Romper</button><button class="btn" data-m="close">Manter</button></div>`);
      $('#modal .sheet').onclick = (ev) => { if (ev.target.dataset.m === 'sure') { closeModal(); act({ t: 'pactBreak', with: w }); } };
    }
  };
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
    const offline = host && p.ctrl === 'remote' && (!seat.link || seat.lag);
    return `<li><span class="dot" style="background:${COLORS[p.color].c}"></span><span class="who">${p.alive ? '' : '☠ '}<b>${esc(p.name)}</b> · ${owned(v, i)} terr. · ${handSize(p)} cartas${p.ctrl === 'bot' ? ' · bot' : ''}${offline ? ` · <span class="off">${seat.link ? 'sem resposta' : 'offline'}</span>` : ''}</span>
      ${host && p.ctrl === 'remote' && p.alive ? `<button class="btn small" data-re="${p.seat}">QR</button>` : ''}${offline && p.alive ? `<button class="btn small" data-bot="${i}">Virar bot</button>` : ''}</li>`;
  }).join('')}</ul>
  <div class="log">${v.log.slice().reverse().map(esc).join('<br>')}</div>
  ${host && v.players.some((p) => p.ctrl === 'remote' || app.seats[p.seat].gid) ? '<button class="btn small" data-do="invite">Reconectar por QR</button>' : ''}
  <div class="row"><button class="btn small" data-do="land">Tela deitada: ${store.get('forceLand') !== false ? 'sempre' : 'automática'}</button><button class="btn small" data-do="sound">Som: ${soundOn() ? 'ligado' : 'desligado'}</button></div>
  <div class="row"><button class="btn small" data-do="rules">Regras</button><button class="btn small" data-do="quit">Sair</button><button class="btn small primary" data-m="close">Voltar</button></div>`);
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
  <li><b>Ataque:</b> a partir da 2ª rodada, ataque vizinhos com até 3 dados (precisa deixar 1 exército para trás); use − e + para escolher quantos. A defesa rola até 3. Compare do maior para o menor; empate é da defesa. “Auto” repete o ataque com o máximo de dados até conquistar ou não poder mais.</li>
  <li><b>Conquista:</b> ao zerar a defesa você ocupa o território com 1 a 3 exércitos e, no fim do turno, ganha uma carta.</li>
  <li><b>Cartas:</b> troque 3 iguais ou 3 diferentes por exércitos (4, 6, 8, 10, 12, 15, depois +5 a cada troca). Com 5 cartas a troca é obrigatória e o jogo faz sozinho no início do turno, escolhendo a melhor trinca. Com menos, o botão “Trocar cartas” aparece no reforço.</li>
  <li><b>Remanejamento:</b> ao final, mova exércitos entre territórios vizinhos seus; cada exército anda uma vez por turno.</li>
  <li><b>Rotas marítimas:</b> linhas pontilhadas também são fronteiras. O Alasca liga com o Extremo Oriente pela borda do mapa.</li></ul>
  <h3>Regras extras (opcionais)</h3>
  <ul><li><b>Eventos de rodada:</b> da 2ª rodada em diante, cada rodada sorteia um evento que vale para todos: ${Object.values(EVENTS).map((x) => x.n).join(', ')}. O raio no painel mostra o evento em vigor.</li>
  <li><b>Pactos:</b> na sua vez, proponha a outro jogador um pacto de não agressão de ${PACT_ROUNDS} rodadas. Enquanto valer, um não ataca o outro. Para romper antes, só no início do seu turno e ao custo de ${PACT_PENALTY} exércitos do reforço. Com dois jogadores em jogo os pactos acabam.</li></ul>
  <h3>Conexão</h3>
  <p>Os aparelhos falam direto entre si, sem servidor e sem internet: basta estarem no mesmo Wi-Fi ou no hotspot de um dos celulares. Permita a câmera quando o navegador pedir. Se alguém cair, o jogo tenta voltar sozinho em alguns segundos. Se não conseguir, o anfitrião toca em “Reconectar” e o jogador lê o novo QR em “Reconectar à partida”: ele volta para o mesmo lugar.</p>
  <button class="btn" data-m="close">Fechar</button>`);
}

/* ---------- eventos globais ---------- */
function leave() {
  clearTimeout(app.botTimer);
  if (app.role === 'host') app.seats.forEach((s) => { dropSpare(s); s.link && s.link.close(); });
  clearTimeout(autoTimer); app.autoOn = false;
  if (app.role === 'guest') { store.del('guest'); store.del('spare'); app.spare = null; }
  if (app.link) { const l = app.link; app.link = null; l.close(); }
  app.winShown = false; $('#win').hidden = true;
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
    if (!app.game.opts) Object.assign(app.game, { opts: { events: false, pacts: false }, event: null, pacts: [], offer: null }); // partida salva antes das regras opcionais
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
  again() { store.del('save3'); app.game = null; app.view = null; app.winShown = false; $('#win').hidden = true; show('lobby'); sync(); },
  objective: showObjective,
  extras: showExtras,
  land() { store.set('forceLand', store.get('forceLand') === false); applyLayout(); applyCam(); showMenu(); },
  winMap() { $('#win').hidden = true; },
  sound() { setSound(!soundOn()); store.set('sound', soundOn()); if (soundOn()) { unlock(); play('turn'); } showMenu(); },
  cards: showCards,
  autoTrade() { const v = app.view, me = v.players[v.turn]; const tr = Array.isArray(me.cards) && bestTrade(me.cards, v.terr, v.turn); if (tr) act({ t: 'trade', cards: tr }); },
  menu: showMenu,
  attack: () => act({ t: 'attack', from: app.sel, to: app.target, dice: app.n }),
  max() { const r = stepRange(app.view); if (r) { app.n = r[1]; renderGame(); } },
  place() { const n = app.n; app.n = 1; act({ t: 'place', t0: app.sel, n }); },
  occupyOk: () => act({ t: 'occupy', n: app.n }),
  moveOk() { const m = { t: 'move', from: app.sel, to: app.target, n: app.n }; app.target = null; act(m); },
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
  if (d.step) { const r = stepRange(app.view); if (r) { app.n = Math.max(r[0], Math.min(r[1], app.n + +d.step)); renderGame(); } return; }
  if (d.secs != null) { app.cfg.secs = +d.secs; store.set('cfg', app.cfg); return sync(); }
  if (d.opt === 'events' || d.opt === 'pacts') { if (app.role !== 'host' || app.game) return; app.cfg[d.opt] = !app.cfg[d.opt]; store.set('cfg', app.cfg); return sync(); }
  if (d.kick != null) { const s = app.seats.splice(+d.kick, 1)[0]; dropSpare(s); s.link && s.link.close(); return sync(); }
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
if (store.get('guest') && store.get('spare')) { toast('Procurando a partida em andamento…', 3500); autoLoop(true); } // recarregou a página: tenta voltar sem QR
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
