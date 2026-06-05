/**
 * Cliente HTTP minimalista pra API Rails.
 *
 * Convenções (espelham contratos-api.md v1.1):
 *   - sempre `credentials: 'include'` — sessão é cookie HTTP-only assinado.
 *   - `Accept: application/json` + `Content-Type: application/json` no body.
 *   - 4xx/5xx viram exceção (`ApiError`) com `{ code, message, status, details }`
 *     já parseado. 401 vira `UnauthorizedError` (subclasse) pra useSession
 *     diferenciar "não logado" de "falha real".
 */

export type ApiErrorPayload = {
  code: string
  message: string
  details?: Array<{ field?: string; code?: string; message?: string }>
}

export class ApiError extends Error {
  status: number
  code: string
  details?: ApiErrorPayload['details']

  constructor(status: number, payload: ApiErrorPayload) {
    super(payload.message)
    this.name = 'ApiError'
    this.status = status
    this.code = payload.code
    this.details = payload.details
  }
}

export class UnauthorizedError extends ApiError {
  constructor() {
    super(401, { code: 'unauthenticated', message: 'Sign in required.' })
    this.name = 'UnauthorizedError'
  }
}

type RequestOptions = {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE'
  body?: unknown
  signal?: AbortSignal
}

export async function apiFetch<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const method = opts.method ?? 'GET'
  const headers: Record<string, string> = { Accept: 'application/json' }
  let body: string | FormData | undefined
  if (opts.body instanceof FormData) {
    // multipart (RF20 upload) — o browser seta o Content-Type com boundary.
    body = opts.body
  } else if (opts.body !== undefined) {
    headers['Content-Type'] = 'application/json'
    body = JSON.stringify(opts.body)
  }

  const res = await fetch(path, {
    method,
    headers,
    body,
    credentials: 'include',
    signal: opts.signal,
  })

  if (res.status === 204) return undefined as T

  if (!res.ok) {
    // 401 sempre vira UnauthorizedError mesmo sem body — backend pode
    // (em teoria) responder vazio.
    if (res.status === 401) throw new UnauthorizedError()

    let payload: ApiErrorPayload
    try {
      const parsed = (await res.json()) as { error?: ApiErrorPayload }
      payload = parsed.error ?? { code: 'unknown', message: `HTTP ${res.status}` }
    } catch {
      payload = { code: 'unknown', message: `HTTP ${res.status}` }
    }
    throw new ApiError(res.status, payload)
  }

  return (await res.json()) as T
}
