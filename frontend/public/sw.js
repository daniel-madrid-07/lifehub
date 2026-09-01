// Service worker de Life Hub: Web Push + cacheo para carga instantánea y offline.
// Estrategia:
//  - Navegaciones (HTML): network-first con fallback a la copia cacheada. Así
//    online siempre sirve el index nuevo (evita la pantalla en blanco por JS
//    borrado) y offline abre el último guardado.
//  - Assets con hash (/assets/*, iconos): cache-first (el nombre cambia en cada
//    build, así que cachear para siempre es seguro).
//  - /api/* y push: nunca se cachean.
const CACHE = "lifehub-v1"
const SHELL = "/"

self.addEventListener("install", (event) => {
  self.skipWaiting()
  event.waitUntil(caches.open(CACHE).then((c) => c.add(SHELL)).catch(() => {}))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys()
      await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
      await self.clients.claim()
    })(),
  )
})

self.addEventListener("fetch", (event) => {
  const req = event.request
  if (req.method !== "GET") return
  const url = new URL(req.url)
  if (url.origin !== self.location.origin) return
  if (url.pathname.startsWith("/api/")) return // datos: siempre a la red

  // Navegaciones / documentos: network-first.
  if (req.mode === "navigate" || req.destination === "document") {
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(req)
          const cache = await caches.open(CACHE)
          cache.put(SHELL, fresh.clone())
          return fresh
        } catch {
          return (await caches.match(SHELL)) || Response.error()
        }
      })(),
    )
    return
  }

  // Resto (assets con hash, iconos, fuentes): cache-first.
  event.respondWith(
    (async () => {
      const cached = await caches.match(req)
      if (cached) return cached
      try {
        const fresh = await fetch(req)
        if (fresh.ok) {
          const cache = await caches.open(CACHE)
          cache.put(req, fresh.clone())
        }
        return fresh
      } catch {
        return cached || Response.error()
      }
    })(),
  )
})

self.addEventListener("push", (event) => {
  let data = { title: "Life Hub", body: "", url: "/" }
  try {
    if (event.data) data = { ...data, ...event.data.json() }
  } catch {
    if (event.data) data.body = event.data.text()
  }
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: "/icon-192.png",
      badge: "/icon-192.png",
      data: { url: data.url || "/" },
    }),
  )
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const url = (event.notification.data && event.notification.data.url) || "/"
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if ("focus" in client) return client.focus()
      }
      return self.clients.openWindow(url)
    }),
  )
})
