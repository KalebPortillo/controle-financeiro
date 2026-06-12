import { useEffect, useState } from 'react'

// O evento `beforeinstallprompt` não está nos tipos padrão do DOM.
interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

function detectStandalone(): boolean {
  if (typeof window === 'undefined') return false
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    // iOS Safari usa uma flag não-padrão.
    (navigator as unknown as { standalone?: boolean }).standalone === true
  )
}

function detectIOS(): boolean {
  if (typeof navigator === 'undefined') return false
  const ua = navigator.userAgent
  const iOSDevice = /iPad|iPhone|iPod/.test(ua)
  // iPadOS 13+ se reporta como Mac; detecta pelo touch.
  const iPadOS = ua.includes('Macintosh') && 'ontouchend' in document
  return iOSDevice || iPadOS
}

/**
 * Estado de instalabilidade do PWA. Em Android/desktop Chrome captura o
 * `beforeinstallprompt` e expõe `promptInstall()`. No iOS não há prompt
 * programático — o componente cai nas instruções manuais (`isIOS`).
 */
export function useInstallPrompt() {
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null)
  const [installed, setInstalled] = useState(detectStandalone())

  useEffect(() => {
    const onBeforeInstall = (e: Event) => {
      e.preventDefault() // segura o mini-infobar pra disparar via nosso botão
      setDeferred(e as BeforeInstallPromptEvent)
    }
    const onInstalled = () => {
      setInstalled(true)
      setDeferred(null)
    }
    window.addEventListener('beforeinstallprompt', onBeforeInstall)
    window.addEventListener('appinstalled', onInstalled)
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstall)
      window.removeEventListener('appinstalled', onInstalled)
    }
  }, [])

  async function promptInstall() {
    if (!deferred) return
    await deferred.prompt()
    await deferred.userChoice
    setDeferred(null) // o evento só pode ser usado uma vez
  }

  return {
    isStandalone: installed,
    isIOS: detectIOS(),
    canPrompt: deferred !== null,
    promptInstall,
  }
}
