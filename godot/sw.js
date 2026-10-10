'use strict';
// Only this game's directory and caches. Never touches /userfs IndexedDB saves.
const SHELL = 'dearth-web-shell-v5';
const FILES = ['./', 'index.html', 'loader.js?v=5', 'godot.js', 'assets.json',
  'godot.audio.worklet.js', 'godot.audio.position.worklet.js',
  'mobile.pck?v=4', 'mobile-src/boot.gd?v=4', 'mobile-src/boot.tscn?v=4'];
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(SHELL);
  await cache.addAll(FILES.map(path => new Request(new URL(path, self.registration.scope), {cache:'reload'})));
  await self.skipWaiting();
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const name of await caches.keys()) {
    if (name.startsWith('dearth-web-shell-') && name !== SHELL) await caches.delete(name);
  }
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || !request.url.startsWith(self.registration.scope)) return;
  // Binary chunks use the loader's checksum-verified, bounded cache instead.
  if (/\/(pack|wasm)-\d+\.bin(?:\?|$)/.test(request.url)) return;
  event.respondWith((async () => {
    const cache = await caches.open(SHELL);
    const cached = await cache.match(request.mode === 'navigate' ? new URL('index.html', self.registration.scope).href : request);
    // Navigation stays fresh online; known shell requests retain HTTP update checks.
    try {
      const response = await fetch(request);
      if (response.ok) return response;
      if (cached) return cached;
      return response;
    } catch (error) {
      if (cached) return cached;
      throw error;
    }
  })());
});
