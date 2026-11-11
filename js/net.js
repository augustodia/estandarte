// WebRTC sem servidor de sinalização: a oferta e a resposta viajam em QR codes.
// Para caber num QR legível, só os campos essenciais do SDP são transmitidos
// e o SDP é reconstruído do outro lado a partir de um modelo fixo.

const ICE = [{ urls: 'stun:stun.l.google.com:19302' }];
const GATHER_MS = 2500;
const MAX_CANDS = 5;

const b64u = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

export function packSdp(desc) {
  const sdp = desc.sdp;
  const get = (re) => (sdp.match(re) || [])[1];
  const fp = get(/a=fingerprint:sha-256 ([0-9A-Fa-f:]+)/);
  const ufrag = get(/a=ice-ufrag:(\S+)/), pwd = get(/a=ice-pwd:(\S+)/);
  if (!fp || !ufrag || !pwd) throw new Error('SDP sem os campos esperados');
  const setup = { actpass: 'p', active: 'a', passive: 's' }[get(/a=setup:(\w+)/)] || 'p';
  const cands = [];
  for (const m of sdp.matchAll(/a=candidate:\S+ 1 (\w+) \d+ (\S+) (\d+) typ (\w+)/g)) {
    const [, proto, ip, port, typ] = m;
    if (proto.toLowerCase() !== 'udp' || (typ !== 'host' && typ !== 'srflx')) continue;
    if (/^fe80:/i.test(ip)) continue;
    const v6 = ip.includes(':'), mdns = ip.endsWith('.local');
    const rank = typ === 'host' ? (mdns ? 2 : v6 ? 3 : 0) : v6 ? 4 : 1;
    const c = `${typ[0]},${ip},${port}`;
    if (!cands.some((x) => x.c === c)) cands.push({ rank, c });
  }
  cands.sort((a, b) => a.rank - b.rank);
  const fpB = b64u(fp.split(':').map((h) => parseInt(h, 16)));
  return ['1', desc.type[0] + setup, ufrag, pwd, fpB, cands.slice(0, MAX_CANDS).map((x) => x.c).join(';')].join('~');
}

export function unpackSdp(code) {
  const [v, ts, ufrag, pwd, fpB, cs] = code.trim().split('~');
  if (v !== '1' || !fpB) throw new Error('Código inválido');
  const type = ts[0] === 'o' ? 'offer' : 'answer';
  const setup = { p: 'actpass', a: 'active', s: 'passive' }[ts[1]];
  const fp = [...unb64u(fpB)].map((b) => b.toString(16).padStart(2, '0').toUpperCase()).join(':');
  const lines = [
    'v=0', 'o=- 4611731400430051336 2 IN IP4 127.0.0.1', 's=-', 't=0 0', 'a=group:BUNDLE 0',
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel', 'c=IN IP4 0.0.0.0',
    `a=ice-ufrag:${ufrag}`, `a=ice-pwd:${pwd}`, `a=fingerprint:sha-256 ${fp}`, `a=setup:${setup}`,
    'a=mid:0', 'a=sctp-port:5000', 'a=max-message-size:262144',
  ];
  (cs ? cs.split(';') : []).forEach((c, i) => {
    const [t, ip, port] = c.split(',');
    lines.push(t === 'h'
      ? `a=candidate:${i + 1} 1 udp ${2122260223 - i} ${ip} ${port} typ host`
      : `a=candidate:${i + 1} 1 udp ${1686052607 - i} ${ip} ${port} typ srflx raddr 0.0.0.0 rport 0`);
  });
  lines.push('a=end-of-candidates');
  return { type, sdp: lines.join('\r\n') + '\r\n' };
}

function gathered(pc) {
  return new Promise((res) => {
    if (pc.iceGatheringState === 'complete') return res();
    const done = () => { clearTimeout(timer); res(); };
    const timer = setTimeout(done, GATHER_MS);
    pc.addEventListener('icegatheringstatechange', () => pc.iceGatheringState === 'complete' && done());
  });
}

// Envolve um RTCDataChannel com mensagens JSON e eventos de abertura/fechamento.
function wrap(pc, dc, h) {
  const link = {
    open: false,
    send(msg) { if (dc.readyState === 'open') dc.send(JSON.stringify(msg)); },
    close() { try { dc.close(); pc.close(); } catch {} },
  };
  let closed = false;
  const down = () => { if (closed) return; closed = true; link.open = false; h.onclose && h.onclose(link); };
  const up = () => { if (link.open || closed) return; link.open = true; h.onopen && h.onopen(link); };
  dc.onopen = up;
  if (dc.readyState === 'open') queueMicrotask(up);
  dc.onmessage = (e) => { try { h.onmessage && h.onmessage(JSON.parse(e.data), link); } catch (err) { console.error(err); } };
  dc.onclose = down;
  pc.addEventListener('connectionstatechange', () => ['failed', 'closed'].includes(pc.connectionState) && down());
  return link;
}

// Anfitrião: cria um convite. Retorna { code, accept(answerCode), cancel() }.
export async function createInvite(handlers) {
  const pc = new RTCPeerConnection({ iceServers: ICE });
  const dc = pc.createDataChannel('jogo', { ordered: true });
  const link = wrap(pc, dc, handlers);
  await pc.setLocalDescription(await pc.createOffer());
  await gathered(pc);
  return {
    code: packSdp(pc.localDescription),
    link,
    accept: (answerCode) => pc.setRemoteDescription(unpackSdp(answerCode)),
    cancel: () => link.close(),
  };
}

// Convidado: recebe o código do convite e devolve { code (resposta), link }.
export async function joinInvite(offerCode, handlers) {
  const offer = unpackSdp(offerCode);
  if (offer.type !== 'offer') throw new Error('Este código não é um convite.');
  const pc = new RTCPeerConnection({ iceServers: ICE });
  const out = { link: null };
  pc.ondatachannel = (e) => { out.link = wrap(pc, e.channel, handlers); };
  await pc.setRemoteDescription(offer);
  await pc.setLocalDescription(await pc.createAnswer());
  await gathered(pc);
  out.code = packSdp(pc.localDescription);
  out.cancel = () => pc.close();
  return out;
}
