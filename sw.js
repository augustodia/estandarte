// Cache offline: cada versão é baixada por inteiro e servida só do próprio cache,
// para nunca misturar arquivos de versões diferentes. Suba o número a cada publicação.
const CACHE = 'estandarte-v34';
const ASSETS = ['./', 'index.html', 'css/style.css', 'js/main.js', 'js/game.js', 'js/map.js', 'js/net.js', 'js/sound.js', 'js/smoke.js',
  'vendor/qrcode.js', 'vendor/jsQR.js', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/icon-maskable-512.png', 'icons/apple-touch-icon.png'];
self.addEventListener('install', (e) => e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS.map((u) => new Request(u, { cache: 'reload' })))).then(() => self.skipWaiting())));
self.addEventListener('activate', (e) => e.waitUntil(
  caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  e.respondWith(caches.open(CACHE).then(async (c) => {
    const hit = await c.match(e.request, { ignoreSearch: true });
    return hit || fetch(e.request);
  }));
});
