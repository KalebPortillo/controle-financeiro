import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { OnboardingStep3Categories } from './OnboardingStep3Categories'

const saveCategories = vi.fn().mockResolvedValue(undefined)

vi.mock('./useOnboarding', () => ({
  useOnboarding: () => ({
    state: { discovered_categories: ['Casa', 'Lazer'] },
    saveCategories,
  }),
}))

describe('OnboardingStep3Categories', () => {
  beforeEach(() => {
    saveCategories.mockClear()
  })

  it('seeds the discovered categories as initial chips', () => {
    render(<OnboardingStep3Categories onComplete={() => {}} />)
    expect(screen.getByText('Crie categorias')).toBeInTheDocument()
    expect(screen.getByText('Casa')).toBeInTheDocument()
    expect(screen.getByText('Lazer')).toBeInTheDocument()
  })

  it('adds a category when typing and clicking add', () => {
    render(<OnboardingStep3Categories onComplete={() => {}} />)
    const input = screen.getByPlaceholderText('Nome da categoria')
    fireEvent.change(input, { target: { value: 'Saúde' } })
    fireEvent.click(screen.getByLabelText('Adicionar categoria'))
    expect(screen.getByText('Saúde')).toBeInTheDocument()
  })

  it('removes a category when clicking the x', () => {
    render(<OnboardingStep3Categories onComplete={() => {}} />)
    fireEvent.click(screen.getByLabelText('Remover Casa'))
    expect(screen.queryByText('Casa')).not.toBeInTheDocument()
  })

  it('saves categories and completes when clicking conclude', async () => {
    const onComplete = vi.fn()
    render(<OnboardingStep3Categories onComplete={onComplete} />)
    fireEvent.click(screen.getByRole('button', { name: /concluir/i }))
    await waitFor(() => expect(saveCategories).toHaveBeenCalledWith(['Casa', 'Lazer']))
    expect(onComplete).toHaveBeenCalled()
  })
})
