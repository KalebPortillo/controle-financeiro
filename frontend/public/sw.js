/*
 * Service worker mínimo — existe pra (1) tornar o app instalável como PWA no
 * mobile e (2) dar uma casca offline básica. NÃO cacheia a API: dados
 * financeiros têm que ser sempre frescos. Estratégia network-first com fallback
 * pra cache só pra navegações e assets estáticos same-origin.
 */
const CACHE = 'cf-shell-v1'

// Caminhos que o SW nunca deve interceptar/cachear — sempre vão direto à rede.
const BYPASS = [/^\/api\//, /^\/cable/, /^\/up$/]

self.addEventListener('install', () => self.skipWaiting())

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys()
      await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
      await self.clients.claim()
    })(),
  )
})

self.addEventListener('fetch', (event) => {
  const { request } = event
  if (request.method !== 'GET') return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return
  if (BYPASS.some((re) => re.test(url.pathname))) return

  const isNavigation = request.mode === 'navigate'
  const isAsset = /\.(?:js|css|woff2?|png|svg|webmanifest|ico|jpg|jpeg|webp)$/.test(url.pathname)
  if (!isNavigation && !isAsset) return

  event.respondWith(
    (async () => {
      try {
        const res = await fetch(request)
        // Guarda uma cópia fresca pra servir offline depois.
        if (res && res.ok && res.type === 'basic') {
          const cache = await caches.open(CACHE)
          cache.put(isNavigation ? '/' : request, res.clone())
        }
        return res
      } catch {
        const cache = await caches.open(CACHE)
        const cached = await cache.match(isNavigation ? '/' : request)
        if (cached) return cached
        throw new Error('offline e sem cache')
      }
    })(),
  )
})
