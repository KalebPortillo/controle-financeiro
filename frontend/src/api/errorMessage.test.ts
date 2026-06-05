import { describe, it, expect } from 'vitest'
import { errorFeedback } from './errorMessage'
import { ApiError, UnauthorizedError } from './client'

describe('errorFeedback', () => {
  it('ignores 401 (auth flow handles it)', () => {
    expect(errorFeedback(new UnauthorizedError())).toBeNull()
  })

  it('maps a network failure (fetch threw) to a connection message', () => {
    const fb = errorFeedback(new TypeError('Failed to fetch'))
    expect(fb?.title).toMatch(/conex/i)
  })

  it('maps 429 to a rate-limit message', () => {
    const fb = errorFeedback(new ApiError(429, { code: 'rate_limited', message: 'slow down' }))
    expect(fb?.title).toMatch(/limite/i)
  })

  it('maps 5xx to a server error message', () => {
    const fb = errorFeedback(new ApiError(503, { code: 'unknown', message: 'HTTP 503' }))
    expect(fb?.title).toMatch(/servidor/i)
  })

  it('uses the backend message for 422 validation errors', () => {
    const fb = errorFeedback(new ApiError(422, { code: 'validation_failed', message: 'Nome obrigatório' }))
    expect(fb?.description).toBe('Nome obrigatório')
  })

  it('maps 403 to a permission message', () => {
    const fb = errorFeedback(new ApiError(403, { code: 'forbidden', message: 'no' }))
    expect(fb?.title).toMatch(/permiss/i)
  })

  it('falls back to a generic message for unknown errors', () => {
    const fb = errorFeedback(new Error('boom'))
    expect(fb?.title).toBeTruthy()
  })
})
