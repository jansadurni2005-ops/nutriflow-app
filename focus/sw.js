// FOCUS OS service worker: funciona sin conexión y recibe las actualizaciones al volver a tener red.
var CACHE = 'focusos-v8';
var ASSETS = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png', './apple-touch-icon.png'];

self.addEventListener('install', function (e) {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(function (c) { return c.addAll(ASSETS).catch(function () {}); }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k.indexOf('focusos-') === 0 && k !== CACHE; })
        .map(function (k) { return caches.delete(k); }));
    }).then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var url;
  try { url = new URL(req.url); } catch (err) { return; }
  if (url.origin !== self.location.origin) return;
  // Red primero para la página (actualizaciones inmediatas); caché si no hay conexión.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req, { cache: 'no-store' }).then(function (r) {
        var cp = r.clone(); caches.open(CACHE).then(function (c) { c.put('./index.html', cp); }); return r;
      }).catch(function () { return caches.match('./index.html'); })
    );
    return;
  }
  e.respondWith(caches.match(req).then(function (r) {
    return r || fetch(req).then(function (rr) {
      if (rr && rr.status === 200) { var cp = rr.clone(); caches.open(CACHE).then(function (c) { c.put(req, cp); }); }
      return rr;
    });
  }));
});

// Al tocar una notificación, abrir (o enfocar) la app.
self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then(function (list) {
    for (var i = 0; i < list.length; i++) { if ('focus' in list[i]) return list[i].focus(); }
    return self.clients.openWindow('./');
  }));
});
