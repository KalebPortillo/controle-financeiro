/**
 * Registra o service worker (`/public/sw.js`) que torna o app instalável como
 * PWA no celular. Só em produção: em dev o Vite cuida do HMR e um SW cacheando
 * atrapalharia; nos E2E (vite preview) idem. O SW em si nunca cacheia a API.
 */
export function registerServiceWorker() {
  if (!import.meta.env.PROD) return
  if (!('serviceWorker' in navigator)) return

  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {
      // Falha de registro não pode derrubar o app — PWA é progressive enhancement.
    })
  })
}
