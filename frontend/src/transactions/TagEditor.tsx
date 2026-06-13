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

  // Posiciona o portal junto do input. Usa o visualViewport (que encolhe com o
  // teclado no mobile) pra medir o espaço visível. Estratégia: PREFERE abrir
  // embaixo e só vira pra cima quando realmente não cabe embaixo. O browser do
  // iOS rola o input pra dentro da vista DEPOIS do focus, então além dos eventos
  // de scroll/resize a gente recalcula em timeouts curtos pra assentar.
  useEffect(() => {
    if (!open) return
    const vv = window.visualViewport
    const place = () => {
      const el = inputRef.current
      if (!el) return
      const r = el.getBoundingClientRect()
      const GAP = 4
      const DESIRED = 224 // altura máx. desejada do dropdown
      const viewTop = vv?.offsetTop ?? 0
      const viewBottom = viewTop + (vv?.height ?? window.innerHeight)
      const spaceBelow = viewBottom - r.bottom - GAP
      const spaceAbove = r.top - viewTop - GAP
      // Embaixo é o padrão; vira pra cima só se não cabe um mínimo embaixo E há
      // mais espaço acima (caso desktop com o campo perto do fim do drawer).
      const below = spaceBelow >= 120 || spaceBelow >= spaceAbove
      const maxHeight = Math.max(96, Math.min(DESIRED, Math.floor(below ? spaceBelow : spaceAbove)))
      setCoords(
        below
          ? { left: r.left, width: r.width, maxHeight, top: Math.round(r.bottom + GAP) }
          : { left: r.left, width: r.width, maxHeight, bottom: Math.round(window.innerHeight - r.top + GAP) },
      )
    }
    place()
    const t1 = setTimeout(place, 150)
    const t2 = setTimeout(place, 350)
    window.addEventListener('scroll', place, true)
    window.addEventListener('resize', place)
    vv?.addEventListener('resize', place)
    vv?.addEventListener('scroll', place)
    return () => {
      clearTimeout(t1)
      clearTimeout(t2)
      window.removeEventListener('scroll', place, true)
      window.removeEventListener('resize', place)
      vv?.removeEventListener('resize', place)
      vv?.removeEventListener('scroll', place)
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
