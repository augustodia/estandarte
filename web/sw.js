// Kill-switch Service Worker para substituir e remover o antigo Estandarte em cache (/sw.js).
self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((k) => caches.delete(k)));
      } catch (_) {}
      try {
        await self.registration.unregister();
      } catch (_) {}
      try {
        const clients = await self.clients.matchAll({
          type: 'window',
          includeUncontrolled: true,
        });
        for (const client of clients) {
          if (client.url && 'navigate' in client) {
            client.navigate(client.url);
          }
        }
      } catch (_) {}
    })()
  );
});
