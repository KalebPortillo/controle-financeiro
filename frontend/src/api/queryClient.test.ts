import { describe, it, expect, vi, beforeEach } from 'vitest'
import { ApiError, UnauthorizedError } from './client'

const toastError = vi.fn()
vi.mock('sonner', () => ({ toast: { error: (...a: unknown[]) => toastError(...a) } }))

// Importado depois do mock pra que `notifyMutationError` use o toast mockado.
import { notifyMutationError } from './queryClient'

describe('notifyMutationError', () => {
  beforeEach(() => toastError.mockClear())

  it('shows a toast for a failed mutation', () => {
    notifyMutationError(new ApiError(500, { code: 'unknown', message: 'x' }))
    expect(toastError).toHaveBeenCalledOnce()
    expect(toastError).toHaveBeenCalledWith('Erro no servidor', expect.objectContaining({ description: expect.any(String) }))
  })

  it('stays silent when the mutation opts out via meta.silent', () => {
    notifyMutationError(new ApiError(500, { code: 'unknown', message: 'x' }), { meta: { silent: true } })
    expect(toastError).not.toHaveBeenCalled()
  })

  it('stays silent for 401 (auth flow handles it)', () => {
    notifyMutationError(new UnauthorizedError())
    expect(toastError).not.toHaveBeenCalled()
  })
})
