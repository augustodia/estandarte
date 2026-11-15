// Partidas online: um servidor na internet faz o papel do celular anfitrião (guarda a partida, aplica as regras e
// joga pelos bots). Aqui fica só a conexão; as mensagens são as mesmas do jogo pela rede local.

// Endereço do servidor publicado no Render. Para testar um servidor no computador ou na rede de casa: abra o jogo
// com ?server=ws://localhost:8080 (fica guardado neste aparelho; ?server= vazio volta ao padrão). Outros endereços
// são ignorados. Se mudar este endereço, mude também o connect-src da Content-Security-Policy em index.html.
export const DEFAULT_SERVER = 'wss://estandarte-backend.onrender.com';

const KEY = 'estandarte.server';
// Só aceita trocar o servidor por um de teste no próprio computador ou na rede de casa. Sem isso, um link
// malicioso (…?server=wss://site-do-golpista) faria o jogo conversar com outro servidor e guardar isso no aparelho.
export function allowedServer(v) {
  try {
    const u = new URL(String(v).replace(/^http/, 'ws'));
    if (u.protocol !== 'ws:' && u.protocol !== 'wss:') return false;
    if (u.origin === new URL(DEFAULT_SERVER).origin) return true;
    const h = u.hostname;
    return h === 'localhost' || h === '127.0.0.1' || h === '[::1]' || h.endsWith('.local') ||
      /^10\./.test(h) || /^192\.168\./.test(h) || /^172\.(1[6-9]|2\d|3[01])\./.test(h);
  } catch { return false; }
}
export function serverUrl() {
  const q = new URLSearchParams(location.search);
  if (q.has('server')) {
    const v = q.get('server').trim();
    try { if (!v) localStorage.removeItem(KEY); else if (allowedServer(v)) localStorage.setItem(KEY, v); } catch {}
  }
  let s = DEFAULT_SERVER;
  try { const saved = localStorage.getItem(KEY); if (saved && allowedServer(saved)) s = saved; } catch {}
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

// Lista de salas públicas: { lobby: [...], play: [...], maxWatchers }. Com o servidor dormindo a resposta pode levar
// até um minuto (o Render segura o pedido enquanto ele acorda).
export async function listRooms(server, ms = 75000) {
  const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), ms);
  try {
    const r = await fetch(server.replace(/^ws/, 'http') + '/rooms', { cache: 'no-store', signal: ctl.signal });
    if (!r.ok) throw new Error('http ' + r.status);
    return await r.json();
  } finally { clearTimeout(t); }
}
