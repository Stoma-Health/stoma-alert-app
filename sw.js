// Stoma Alert — prototype service worker (network-first so updates show immediately)
const CACHE = 'stoma-alert-app-v46';
const SHELL = ['./','./index.html','./manifest.webmanifest','./icons/icon-192.png','./icons/apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});
// Never cache Supabase/API or the JS CDN; network-first for everything else, cache as offline fallback.
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.hostname.endsWith('supabase.co') || url.hostname.includes('esm.sh') || url.hostname.includes('opencv.org')) return;
  e.respondWith(
    fetch(e.request).then(res => {
      if (res.ok && url.origin === self.location.origin) {
        const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy));
      }
      return res;
    }).catch(() => caches.match(e.request).then(hit => hit || caches.match('./index.html')))
  );
});
