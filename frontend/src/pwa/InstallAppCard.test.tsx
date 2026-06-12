import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, waitFor, act } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { InstallAppCard } from './InstallAppCard'

function setMatchMedia(standalone: boolean) {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches: query.includes('standalone') ? standalone : false,
    media: query,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
    onchange: null,
  }))
}

function setUserAgent(ua: string) {
  Object.defineProperty(navigator, 'userAgent', { value: ua, configurable: true })
}

describe('<InstallAppCard />', () => {
  beforeEach(() => {
    setMatchMedia(false)
    setUserAgent('Mozilla/5.0 (Linux; Android 14)')
    Object.defineProperty(navigator, 'standalone', { value: undefined, configurable: true })
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('não renderiza nada quando já está instalado (standalone)', () => {
    setMatchMedia(true)
    const { container } = render(<InstallAppCard />)
    expect(container).toBeEmptyDOMElement()
  })

  it('mostra instruções do iOS quando não há prompt nativo', () => {
    setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari')
    render(<InstallAppCard />)
    expect(screen.getByText(/Compartilhar/i)).toBeInTheDocument()
    expect(screen.getByText(/Adicionar à Tela de Início/i)).toBeInTheDocument()
  })

  it('mostra o botão de instalar e dispara o prompt nativo', async () => {
    render(<InstallAppCard />)

    const prompt = vi.fn().mockResolvedValue(undefined)
    const event = Object.assign(new Event('beforeinstallprompt'), {
      prompt,
      userChoice: Promise.resolve({ outcome: 'accepted' as const }),
    })
    act(() => {
      window.dispatchEvent(event)
    })

    const button = await screen.findByTestId('install-pwa')
    await userEvent.click(button)

    await waitFor(() => expect(prompt).toHaveBeenCalledOnce())
  })
})
