import { describe, it, expect, beforeEach, vi } from 'vitest'
import { apiFetch, ApiError, UnauthorizedError } from './client'

function mockFetch(response: Partial<Response> & { jsonBody?: unknown }) {
  const fetchMock = vi.fn().mockResolvedValue({
    ok: response.status ? response.status < 400 : true,
    status: response.status ?? 200,
    json: async () => response.jsonBody,
  } as Response)
  globalThis.fetch = fetchMock as unknown as typeof fetch
  return fetchMock
}

describe('apiFetch', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  it('sends credentials: include and parses JSON on success', async () => {
    const fetchMock = mockFetch({ status: 200, jsonBody: { user: { id: 'u1' } } })
    const data = await apiFetch<{ user: { id: string } }>('/api/v1/sessions/current')
    expect(data.user.id).toBe('u1')
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/sessions/current',
      expect.objectContaining({ credentials: 'include' })
    )
  })

  it('serializes body and sets Content-Type when body present', async () => {
    const fetchMock = mockFetch({ status: 201, jsonBody: { ok: true } })
    await apiFetch('/api/v1/workspaces', { method: 'POST', body: { name: 'X' } })
    const call = fetchMock.mock.calls[0][1] as RequestInit
    expect(call.method).toBe('POST')
    expect(call.body).toBe(JSON.stringify({ name: 'X' }))
    const headers = call.headers as Record<string, string>
    expect(headers['Content-Type']).toBe('application/json')
  })

  it('returns undefined on 204 No Content', async () => {
    mockFetch({ status: 204, jsonBody: undefined })
    const result = await apiFetch('/api/v1/sessions/current', { method: 'DELETE' })
    expect(result).toBeUndefined()
  })

  it('throws UnauthorizedError on 401', async () => {
    mockFetch({ status: 401, jsonBody: { error: { code: 'unauthenticated', message: 'no' } } })
    await expect(apiFetch('/api/v1/sessions/current')).rejects.toBeInstanceOf(UnauthorizedError)
  })

  it('throws ApiError with parsed code/message on 422', async () => {
    mockFetch({
      status: 422,
      jsonBody: { error: { code: 'validation_failed', message: 'Name is invalid' } },
    })
    try {
      await apiFetch('/api/v1/workspaces', { method: 'POST', body: { name: '' } })
      expect.fail('should have thrown')
    } catch (e) {
      expect(e).toBeInstanceOf(ApiError)
      const err = e as ApiError
      expect(err.status).toBe(422)
      expect(err.code).toBe('validation_failed')
      expect(err.message).toBe('Name is invalid')
    }
  })
})
