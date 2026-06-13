import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useTags, useCreateTag } from './useTags'
import type { InboxTag } from './useInbox'

/**
 * Editor de tags (RF5) — dropdown-search. Mostra as tags atuais (com X pra
 * remover) e um input que, ao focar, abre um dropdown com as tags disponíveis.
 * Digitar filtra; o botão "+ criar" aparece sempre que há texto e nenhuma tag
 * tem nome idêntico (mesmo havendo matches por substring). onChange recebe a
 * lista final de tag_ids, que o pai persiste.
 *
 * O dropdown é renderizado num portal com posição fixed pra não ser cortado por
 * ancestrais com overflow (lista de categorias, body do detail sheet, etc).
 */
export function TagEditor({
  transactionId,
  current,
  onChange,
  disabled,
}: {
  transactionId: string
  current: InboxTag[]
  onChange: (tagIds: string[]) => void
  disabled?: boolean
}) {
  const { data: allTags } = useTags()
  const createTag = useCreateTag()
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  const [coords, setCoords] = useState<
    { left: number; width: number; maxHeight: number; top?: number; bottom?: number } | null
  >(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const blurTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const currentIds = current.map((t) => t.id)

  const suggestions = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (allTags ?? [])
      .filter((t) => !currentIds.includes(t.id))
      .filter((t) => q === '' || t.name.toLowerCase().includes(q))
      .slice(0, 50)
  }, [allTags, query, currentIds])

  // "+ criar" some só quando já existe tag com nome idêntico (case-insensitive).
  const exactExists = (allTags ?? []).some(
    (t) => t.name.toLowerCase() === query.trim().toLowerCase()
  )
  const canCreate = query.trim() !== '' && !exactExists

  // Posiciona o portal junto do input e acompanha scroll/resize. Usa o
  // visualViewport (que encolhe com o teclado no mobile) pra decidir o espaço
  // disponível e VIRA pra cima quando não cabe embaixo — senão a lista abre
  // atrás do teclado, fora da vista.
  useEffect(() => {
    if (!open) return
    const vv = window.visualViewport
    const reposition = () => {
      const el = inputRef.current
      if (!el) return
      const r = el.getBoundingClientRect()
      const GAP = 4
      const DESIRED = 224 // altura máx. desejada do dropdown
      const viewTop = vv?.offsetTop ?? 0
      const viewBottom = (vv?.offsetTop ?? 0) + (vv?.height ?? window.innerHeight)
      const spaceBelow = viewBottom - r.bottom - GAP
      const spaceAbove = r.top - viewTop - GAP
      const flipUp = spaceBelow < Math.min(DESIRED, 160) && spaceAbove > spaceBelow
      const maxHeight = Math.max(112, Math.min(DESIRED, flipUp ? spaceAbove : spaceBelow))
      setCoords(
        flipUp
          ? { left: r.left, width: r.width, maxHeight, bottom: window.innerHeight - r.top + GAP }
          : { left: r.left, width: r.width, maxHeight, top: r.bottom + GAP },
      )
    }
    reposition()
    window.addEventListener('scroll', reposition, true)
    window.addEventListener('resize', reposition)
    vv?.addEventListener('resize', reposition)
    vv?.addEventListener('scroll', reposition)
    return () => {
      window.removeEventListener('scroll', reposition, true)
      window.removeEventListener('resize', reposition)
      vv?.removeEventListener('resize', reposition)
      vv?.removeEventListener('scroll', reposition)
    }
  }, [open])

  const addTag = (id: string) => {
    onChange([...currentIds, id])
    setQuery('')
  }

  const removeTag = (id: string) => {
    onChange(currentIds.filter((x) => x !== id))
  }

  const createAndAdd = async () => {
    const name = query.trim()
    if (!name) return
    const tag = await createTag.mutateAsync(name)
    onChange([...currentIds, tag.id])
    setQuery('')
  }

  const onBlur = () => {
    blurTimer.current = setTimeout(() => setOpen(false), 120)
  }
  const keepOpen = () => {
    if (blurTimer.current) clearTimeout(blurTimer.current)
  }

  const dropdown = open && coords && (suggestions.length > 0 || canCreate) && (
    <ul
      onMouseDown={keepOpen}
      style={{
        position: 'fixed',
        left: coords.left,
        width: coords.width,
        maxHeight: coords.maxHeight,
        ...(coords.top != null ? { top: coords.top } : { bottom: coords.bottom }),
      }}
      className="z-50 overflow-y-auto rounded-md border border-border bg-popover shadow-[var(--shadow-popover)] py-1"
      data-testid={`tag-dropdown-${transactionId}`}
    >
      {suggestions.map((t) => (
        <li key={t.id}>
          <button
            type="button"
            onClick={() => addTag(t.id)}
            disabled={disabled}
            className="flex w-full items-center gap-2 px-2.5 py-1.5 text-xs text-left hover:bg-muted"
            data-testid={`tag-suggest-${t.id}`}
          >
            <span className="h-1.5 w-1.5 rounded-full shrink-0" style={{ background: t.color || 'var(--muted-foreground)' }} />
            {t.name}
            <span className="ml-auto text-[10px] text-muted-foreground">{t.usage_count}</span>
          </button>
        </li>
      ))}
      {canCreate && (
        <li className={suggestions.length > 0 ? 'border-t border-border' : ''}>
          <button
            type="button"
            onClick={createAndAdd}
            disabled={disabled || createTag.isPending}
            className="flex w-full items-center gap-1.5 px-2.5 py-1.5 text-xs text-left text-accent hover:bg-muted"
            data-testid="tag-create"
          >
            + criar "{query.trim()}"
          </button>
        </li>
      )}
    </ul>
  )

  return (
    <div className="space-y-1" data-testid={`tag-editor-${transactionId}`}>
      <div className="flex flex-wrap gap-1 items-center">
        {current.map((t) => (
          <span
            key={t.id}
            className="inline-flex items-center gap-1 rounded-sm bg-muted px-2 py-0.5 text-[11px] text-foreground"
            data-testid={`tag-chip-${t.id}`}
          >
            <span className="h-1.5 w-1.5 rounded-full" style={{ background: t.color || 'var(--muted-foreground)' }} />
            {t.name}
            <button
              type="button"
              onClick={() => removeTag(t.id)}
              disabled={disabled}
              className="text-muted-foreground hover:text-destructive"
              aria-label={`Remover ${t.name}`}
              data-testid={`tag-remove-${t.id}`}
            >
              ×
            </button>
          </span>
        ))}
      </div>

      <input
        ref={inputRef}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onFocus={() => setOpen(true)}
        onBlur={onBlur}
        onKeyDown={(e) => e.key === 'Escape' && setOpen(false)}
        placeholder="Adicionar tag…"
        disabled={disabled}
        data-testid={`tag-input-${transactionId}`}
        className="h-7 w-full rounded-md border border-input bg-background px-2 text-xs text-foreground placeholder:text-muted-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
      />

      {dropdown && createPortal(dropdown, document.body)}
    </div>
  )
}
