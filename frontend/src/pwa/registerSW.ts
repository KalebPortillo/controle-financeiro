/**
 * Registra o service worker (`/public/sw.js`) que torna o app instalável como
 * PWA no celular. Só em produção: em dev o Vite cuida do HMR e um SW cacheando
 * atrapalharia; nos E2E (vite preview) idem. O SW em si nunca cacheia a API.
 */
// Injetado pelo Vite (define) — muda a cada build.
declare const __SW_BUILD__: string

export function registerServiceWorker() {
  if (!import.meta.env.PROD) return
  if (!('serviceWorker' in navigator)) return

  window.addEventListener('load', () => {
    // A query de versão faz a URL do SW mudar a cada deploy: o Cloudflare (que
    // cacheia .js no edge) trata como recurso novo e busca fresco, então o SW
    // sempre atualiza. O arquivo é o mesmo; muda só a URL.
    navigator.serviceWorker.register(`/sw.js?v=${__SW_BUILD__}`).catch(() => {
      // Falha de registro não pode derrubar o app — PWA é progressive enhancement.
    })
  })
}
