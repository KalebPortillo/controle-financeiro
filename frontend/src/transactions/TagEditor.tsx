import { useMemo, useRef, useState } from 'react'
import { useTags, useCreateTag } from './useTags'
import type { InboxTag } from './useInbox'

/**
 * Editor de tags (RF5) — dropdown-search. Mostra as tags atuais (com X pra
 * remover) e um input que, ao focar, abre um dropdown com as tags disponíveis.
 * Digitar filtra; o botão "+ criar" aparece sempre que há texto e nenhuma tag
 * tem nome idêntico (mesmo havendo matches por substring). onChange recebe a
 * lista final de tag_ids, que o pai persiste.
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
  const blurTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const currentIds = current.map((t) => t.id)

  // Disponíveis (não selecionadas), filtradas pelo texto. Vazio = todas.
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

  // Fecha no blur com pequeno atraso pra permitir o clique numa opção.
  const onBlur = () => {
    blurTimer.current = setTimeout(() => setOpen(false), 120)
  }
  const keepOpen = () => {
    if (blurTimer.current) clearTimeout(blurTimer.current)
  }

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

      <div className="relative">
        <input
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

        {open && (suggestions.length > 0 || canCreate) && (
          <ul
            onMouseDown={keepOpen}
            className="absolute z-20 mt-1 w-full max-h-56 overflow-y-auto rounded-md border border-border bg-popover shadow-[var(--shadow-popover)] py-1"
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
        )}
      </div>
    </div>
  )
}
