import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { OnboardingStep2Tags } from './OnboardingStep2Tags'

const saveTags = vi.fn().mockResolvedValue(undefined)

vi.mock('./useOnboarding', () => ({
  useOnboarding: () => ({
    state: { discovered_tags: ['Mercado', 'Transporte'] },
    saveTags,
  }),
}))

describe('OnboardingStep2Tags', () => {
  beforeEach(() => {
    saveTags.mockClear()
  })

  it('seeds the discovered tags as initial chips', () => {
    render(<OnboardingStep2Tags onAdvance={() => {}} />)
    expect(screen.getByText('Adicione tags')).toBeInTheDocument()
    expect(screen.getByText('Mercado')).toBeInTheDocument()
    expect(screen.getByText('Transporte')).toBeInTheDocument()
  })

  it('adds a tag when typing and clicking add', () => {
    render(<OnboardingStep2Tags onAdvance={() => {}} />)
    const input = screen.getByPlaceholderText('Nome da tag')
    fireEvent.change(input, { target: { value: 'Lazer' } })
    fireEvent.click(screen.getByLabelText('Adicionar tag'))
    expect(screen.getByText('Lazer')).toBeInTheDocument()
  })

  it('removes a tag when clicking the x', () => {
    render(<OnboardingStep2Tags onAdvance={() => {}} />)
    fireEvent.click(screen.getByLabelText('Remover Mercado'))
    expect(screen.queryByText('Mercado')).not.toBeInTheDocument()
  })

  it('saves tags and advances when clicking continue', async () => {
    const onAdvance = vi.fn()
    render(<OnboardingStep2Tags onAdvance={onAdvance} />)
    fireEvent.click(screen.getByRole('button', { name: /continuar/i }))
    await waitFor(() => expect(saveTags).toHaveBeenCalledWith(['Mercado', 'Transporte']))
    expect(onAdvance).toHaveBeenCalled()
  })
})
