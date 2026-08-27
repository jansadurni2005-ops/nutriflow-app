// NutriFlow service worker — offline app shell + always-fresh HTML/data
var CACHE='nutriflow-v4';
var ASSETS=['./','./index.html','./manifest.json','./icon-192.png','./icon-512.png'];

self.addEventListener('install',function(e){
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(function(c){return c.addAll(ASSETS).catch(function(){});}));
});

self.addEventListener('activate',function(e){
  e.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.filter(function(k){return k!==CACHE;}).map(function(k){return caches.delete(k);}));
    }).then(function(){return self.clients.claim();})
  );
});

self.addEventListener('fetch',function(e){
  var req=e.request;
  if(req.method!=='GET')return;
  var url;
  try{url=new URL(req.url);}catch(err){return;}
  // Never touch Supabase / API calls — data must always be live
  if(url.hostname.indexOf('supabase')>=0||url.hostname.indexOf('pollinations')>=0)return;
  // Network-first for the app page so updates always land; cached copy only offline
  if(req.mode==='navigate'||url.pathname.indexOf('index.html')>=0||url.pathname.charAt(url.pathname.length-1)==='/'){
    e.respondWith(
      fetch(req,{cache:'no-store'}).then(function(r){var cp=r.clone();caches.open(CACHE).then(function(c){c.put('./index.html',cp);});return r;})
        .catch(function(){return caches.match('./index.html');})
    );
    return;
  }
  // Cache-first for static assets (icons, manifest)
  e.respondWith(
    caches.match(req).then(function(r){
      return r||fetch(req).then(function(rr){
        if(rr&&rr.status===200){var cp=rr.clone();caches.open(CACHE).then(function(c){c.put(req,cp);});}
        return rr;
      }).catch(function(){return r;});
    })
  );
});
