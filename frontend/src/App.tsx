import { useEffect, useState } from 'react'
import { Wallet, Loader2, CircleCheck, CircleAlert } from 'lucide-react'

type Health = {
  status: string
  version: string
  ruby: string
  rails: string
  time: string
}

function App() {
  const [health, setHealth] = useState<Health | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch('/api/v1/health')
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<Health>
      })
      .then(setHealth)
      .catch((err: Error) => setError(err.message))
  }, [])

  const triggerJsError = () => {
    throw new Error(`Test JS error — Sentry probe (${new Date().toISOString()})`)
  }

  return (
    <main className="min-h-screen bg-white text-neutral-900 flex flex-col items-center justify-center p-8 font-sans">
      <div className="max-w-md w-full space-y-6">
        <header className="flex items-center gap-3">
          <Wallet className="w-7 h-7 text-neutral-900" strokeWidth={1.75} />
          <h1 className="text-2xl font-bold tracking-tight">Controle Financeiro</h1>
        </header>

        <p className="text-sm text-neutral-500 leading-relaxed">
          Pre-MVP smoke test. Backend Rails 8 + frontend Vite/React, expostos via
          Cloudflare Tunnel. Próximo: começar TDD do RF16 (auth + workspace).
        </p>

        <section className="rounded-md border border-neutral-200 p-4 space-y-3">
          <div className="flex items-center gap-2">
            {health?.status === 'ok' ? (
              <CircleCheck className="w-4 h-4 text-green-600" strokeWidth={2} />
            ) : error ? (
              <CircleAlert className="w-4 h-4 text-red-600" strokeWidth={2} />
            ) : (
              <Loader2 className="w-4 h-4 text-neutral-400 animate-spin" strokeWidth={2} />
            )}
            <span className="text-sm font-semibold">Backend health</span>
          </div>
          {health && (
            <dl className="text-xs font-mono text-neutral-700 space-y-1">
              <div className="flex gap-2">
                <dt className="text-neutral-400 w-16">status:</dt>
                <dd>{health.status}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-neutral-400 w-16">rails:</dt>
                <dd>{health.rails}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-neutral-400 w-16">ruby:</dt>
                <dd>{health.ruby}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-neutral-400 w-16">time:</dt>
                <dd>{health.time}</dd>
              </div>
            </dl>
          )}
          {error && <p className="text-xs text-red-600">{error}</p>}
        </section>

        <button
          type="button"
          onClick={triggerJsError}
          className="text-xs text-neutral-400 hover:text-neutral-700 underline cursor-pointer"
        >
          Trigger test error (Sentry probe)
        </button>
      </div>
    </main>
  )
}

export default App
