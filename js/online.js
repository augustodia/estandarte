// Partidas online: um servidor na internet faz o papel do celular anfitrião (guarda a partida, aplica as regras e
// joga pelos bots). Aqui fica só a conexão; as mensagens são as mesmas do jogo pela rede local.

// Endereço do servidor publicado no Render. Para testar outro: abra o jogo com ?server=ws://localhost:8080
// (fica guardado neste aparelho; ?server= vazio volta ao padrão).
export const DEFAULT_SERVER = 'wss://estandarte-backend.onrender.com';

const KEY = 'estandarte.server';
export function serverUrl() {
  const q = new URLSearchParams(location.search);
  if (q.has('server')) {
    const v = q.get('server').trim();
    try { v ? localStorage.setItem(KEY, v) : localStorage.removeItem(KEY); } catch {}
  }
  let s = DEFAULT_SERVER;
  try { s = localStorage.getItem(KEY) || DEFAULT_SERVER; } catch {}
  return s.replace(/^http/, 'ws').replace(/\/+$/, '');
}

// Código da sala a partir do que a pessoa digitou ou colou (o código ou o link inteiro).
export function roomCode(raw) {
  const s = String(raw || '').trim();
  const m = s.match(/[?&]sala=([A-Za-z0-9]{5})/) || s.match(/^([A-Za-z0-9]{5})$/);
  return m ? m[1].toUpperCase() : null;
}

// Abre a conexão. O servidor gratuito "dorme" quando ninguém joga e leva até um minuto para acordar: enquanto isso
// a conexão é tentada de novo a cada poucos segundos (h.onwait avisa quanto tempo passou) e desiste depois de ~100 s
// (h.onfail). Aberta, funciona como os links da rede local: h.onopen(link), h.onmessage(msg, link), h.onclose(link).
export function connectOnline(server, query, h) {
  const started = Date.now();
  let ws = null, stopped = false, tries = 0, timer = null;
  const link = {
    open: false,
    send(m) { if (link.open) try { ws.send(JSON.stringify(m)); } catch {} },
    close() { stopped = true; clearTimeout(timer); link.open = false; if (ws) try { ws.close(); } catch {} },
  };
  const http = server.replace(/^ws/, 'http');
  const wake = () => fetch(http + '/healthz', { mode: 'no-cors', cache: 'no-store' }).catch(() => {});
  const attempt = () => {
    if (stopped) return;
    tries++;
    let w;
    try { w = new WebSocket(server + '/ws?' + query); } catch { h.onfail && h.onfail(); return; }
    ws = w;
    let opened = false;
    w.onopen = () => { if (stopped) { w.close(); return; } opened = true; link.open = true; h.onopen(link); };
    w.onmessage = (e) => { let m; try { m = JSON.parse(e.data); } catch { return; } if (m && typeof m.t === 'string') h.onmessage(m, link); };
    w.onclose = () => {
      if (opened) { link.open = false; h.onclose(link); return; }
      if (stopped) return;
      if (Date.now() - started > 100000) { h.onfail && h.onfail(); return; }
      h.onwait && h.onwait(Math.round((Date.now() - started) / 1000), tries);
      if (tries % 4 === 1) wake();
      timer = setTimeout(attempt, Math.min(4000, 800 * tries));
    };
  };
  wake();
  attempt();
  return link;
}
