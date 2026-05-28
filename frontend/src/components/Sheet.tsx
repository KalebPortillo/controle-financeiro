import { useEffect, type ReactNode } from 'react'

// Drawer lateral direito (detail sheet do design). Backdrop + fecha no Esc.
// Sombra só aqui (é overlay) — cards não têm sombra.
export function Sheet({
  open,
  onClose,
  children,
  width = 440,
}: {
  open: boolean
  onClose: () => void
  children: ReactNode
  width?: number
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    if (open) window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  return (
    <>
      <div
        className={`fixed inset-0 z-40 bg-black/40 transition-opacity ${
          open ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
        onClick={onClose}
        aria-hidden
      />
      <aside
        role="dialog"
        aria-hidden={!open}
        className="fixed top-0 right-0 z-50 h-full bg-card border-l border-border shadow-[var(--shadow-popover)] transition-transform duration-200 overflow-y-auto"
        style={{
          width,
          maxWidth: '100vw',
          transform: open ? 'translateX(0)' : `translateX(${width}px)`,
        }}
      >
        {open && children}
      </aside>
    </>
  )
}
