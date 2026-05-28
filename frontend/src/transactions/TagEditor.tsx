import { useMemo, useState } from 'react'
import { useTags, useCreateTag } from './useTags'
import type { InboxTag } from './useInbox'

/**
 * Edita as tags de uma transação na inbox (RF5). Mostra as tags atuais (com X
 * pra remover), e um input com autocomplete das tags existentes + opção de
 * criar uma nova. Cada mudança chama onChange com a lista final de tag_ids,
 * que o pai persiste via PATCH tag_ids.
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

  const currentIds = current.map((t) => t.id)

  const suggestions = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return []
    return (allTags ?? [])
      .filter((t) => !currentIds.includes(t.id) && t.name.toLowerCase().includes(q))
      .slice(0, 6)
  }, [allTags, query, currentIds])

  const exactExists = (allTags ?? []).some(
    (t) => t.name.toLowerCase() === query.trim().toLowerCase()
  )

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

  return (
    <div className="space-y-1" data-testid={`tag-editor-${transactionId}`}>
      <div className="flex flex-wrap gap-1 items-center">
        {current.map((t) => (
          <span
            key={t.id}
            className="inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5 text-[11px] text-foreground"
            data-testid={`tag-chip-${t.id}`}
          >
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
          placeholder="Adicionar tag…"
          disabled={disabled}
          data-testid={`tag-input-${transactionId}`}
          className="h-7 w-full rounded-md border border-input bg-background px-2 text-xs text-foreground placeholder:text-muted-foreground focus:border-ring focus:outline-2 focus:outline-ring/30"
        />
        {query.trim() && (
          <ul className="mt-1 flex flex-wrap gap-1">
            {suggestions.map((t) => (
              <li key={t.id}>
                <button
                  type="button"
                  onClick={() => addTag(t.id)}
                  disabled={disabled}
                  className="rounded-full border border-input px-2 py-0.5 text-[11px] hover:bg-muted"
                  data-testid={`tag-suggest-${t.id}`}
                >
                  {t.name}
                </button>
              </li>
            ))}
            {!exactExists && (
              <li>
                <button
                  type="button"
                  onClick={createAndAdd}
                  disabled={disabled || createTag.isPending}
                  className="rounded-full border border-dashed border-input px-2 py-0.5 text-[11px] hover:bg-muted"
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
