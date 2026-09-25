const V='pos-v3',A=['/','/index.html','/config.js','/manifest.json','/logo.png','https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js'];
self.oninstall=e=>e.waitUntil(caches.open(V).then(c=>Promise.all(A.map(u=>c.add(u).catch(()=>0)))).then(()=>skipWaiting()));
self.onactivate=e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!=V).map(x=>caches.delete(x)))).then(()=>clients.claim()));
self.onfetch=e=>{const r=e.request,u=new URL(r.url);if(r.method!='GET'||(u.origin!=location.origin&&!u.host.includes('jsdelivr')))return;e.respondWith(fetch(r).then(x=>{if(x.ok){const y=x.clone();caches.open(V).then(c=>c.put(r,y))}return x}).catch(()=>caches.match(r).then(m=>m||caches.match('/index.html'))))};
