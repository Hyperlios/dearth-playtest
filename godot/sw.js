'use strict';
// v6 replaces the v5 cache-dependent offline interceptor with network-only requests.
// No offline shell and no cache dependency in the request path.
// Leave verified resource caches and IndexedDB game saves untouched.
self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  await self.clients.claim();
})()));
self.addEventListener('message', event => {
  if (event.data === 'dearth-worker-version') event.ports[0]?.postMessage('network-only-v6');
});
// Network-only handler keeps a functional registration on Safari. It never opens
// Cache Storage, so a stuck cache backend cannot block HTML/scripts/manifests.
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || /\/(pack|wasm)-\d+\.bin(?:\?|$)/.test(event.request.url)) return;
  event.respondWith(fetch(event.request));
});
