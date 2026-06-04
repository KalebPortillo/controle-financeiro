import { useState, type FormEvent } from 'react'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { ApiError } from '../api/client'
import {
  useTags,
  useCreateTag,
  useUpdateTag,
  useMergeTag,
  useDeleteTag,
  type Tag,
} from './useTags'
import { SuggestedTagsList } from './SuggestedTagsList'

// Paleta de cores pras tags (swatches). Acento + semânticos do design.
const SWATCHES = ['#7C3AED', '#15803D', '#B45309', '#B91C1C', '#2563EB', '#0891B2', '#737373']

/**
 * Gestão de tags (RF5.4) — listar com uso, criar, editar nome+cor, mesclar e
 * excluir. Vive dentro do AppLayout. Tags planas; categorias (RF6) virão depois.
 */
export function TagsPage() {
  const { data: tags, isLoading } = useTags()
  const createTag = useCreateTag()
  const [newName, setNewName] = useState('')
  const [error, setError] = useState<string | null>(null)

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault()
    const name = newName.trim()
    if (!name) return
    setError(null)
    try {
      await createTag.mutateAsync(name)
      setNewName('')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Erro ao criar tag')
    }
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <section className="space-y-1">
        <h1 className="font-sans text-2xl font-semibold tracking-tight">Tags</h1>
        <p className="text-sm text-muted-foreground">
          Planas e múltiplas por gasto. Use mesclar para unir duplicadas.
        </p>
      </section>

      <form onSubmit={handleCreate} className="flex gap-2 items-stretch">
        <Input
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          placeholder="Nova tag…"
          data-testid="new-tag-name"
        />
        <Button type="submit" disabled={createTag.isPending || !newName.trim()} data-testid="new-tag-submit">
          {createTag.isPending ? 'Criando…' : 'Criar'}
        </Button>
      </form>
      {error && <p className="text-xs text-destructive" role="alert">{error}</p>}

      <div className="border border-border rounded-lg overflow-hidden">
        {isLoading && <p className="text-xs text-muted-foreground px-4 py-3">Carregando…</p>}
        {!isLoading && (tags?.length ?? 0) === 0 && (
          <p className="text-sm text-muted-foreground px-4 py-3" data-testid="tags-empty">
            Nenhuma tag ainda.
          </p>
        )}
        {tags?.map((tag) => (
          <TagRow key={tag.id} tag={tag} allTags={tags} />
        ))}
      </div>

      <SuggestedTagsList />
    </div>
  )
}

function TagRow({ tag, allTags }: { tag: Tag; allTags: Tag[] }) {
  const update = useUpdateTag()
  const merge = useMergeTag()
  const del = useDeleteTag()

  const [mode, setMode] = useState<'view' | 'edit' | 'merge'>('view')
  const [name, setName] = useState(tag.name)
  const [color, setColor] = useState(tag.color ?? SWATCHES[0])
  const [mergeInto, setMergeInto] = useState('')
  const [error, setError] = useState<string | null>(null)

  const busy = update.isPending || merge.isPending || del.isPending
  const others = allTags.filter((t) => t.id !== tag.id)

  const saveEdit = async () => {
    await update.mutateAsync({ id: tag.id, name: name.trim() || tag.name, color })
    setMode('view')
  }

  const doMerge = async () => {
    if (!mergeInto) return
    await merge.mutateAsync({ id: tag.id, intoTagId: mergeInto })
    // a linha some (origem apagada); nada a fazer
  }

  const doDelete = async () => {
    setError(null)
    try {
      await del.mutateAsync(tag.id)
    } catch (err) {
      if (err instanceof ApiError && err.code === 'tag_in_use') {
        setError('Tag em uso. Use "mesclar" para movê-la antes de excluir.')
      } else {
        setError(err instanceof ApiError ? err.message : 'Erro ao excluir')
      }
    }
  }

  return (
    <div className="px-4 py-3 border-b border-border last:border-b-0 space-y-2" data-testid={`tag-row-${tag.id}`}>
      <div className="flex items-center gap-3">
        <span className="h-2.5 w-2.5 rounded-full shrink-0" style={{ background: tag.color || 'var(--muted-foreground)' }} />
        <span className="text-sm font-medium flex-1 min-w-0 truncate">{tag.name}</span>
        <span className="text-[11px] text-muted-foreground">{tag.usage_count} uso{tag.usage_count === 1 ? '' : 's'}</span>
        {mode === 'view' && (
          <div className="flex gap-1">
            <Button variant="ghost" size="sm" onClick={() => setMode('edit')} disabled={busy} data-testid={`tag-edit-${tag.id}`}>
              Editar
            </Button>
            {others.length > 0 && (
              <Button variant="ghost" size="sm" onClick={() => setMode('merge')} disabled={busy} data-testid={`tag-merge-${tag.id}`}>
                Mesclar
              </Button>
            )}
            <Button variant="ghost" size="sm" onClick={doDelete} disabled={busy} data-testid={`tag-delete-${tag.id}`}>
              Excluir
            </Button>
          </div>
        )}
      </div>

      {error && <p className="text-xs text-destructive" role="alert">{error}</p>}

      {mode === 'edit' && (
        <div className="flex flex-wrap items-center gap-2 pl-5">
          <Input value={name} onChange={(e) => setName(e.target.value)} className="max-w-48" data-testid={`tag-name-${tag.id}`} />
          <div className="flex gap-1">
            {SWATCHES.map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => setColor(c)}
                aria-label={`cor ${c}`}
                data-testid={`swatch-${tag.id}-${c}`}
                className={`h-5 w-5 rounded-full ${color === c ? 'ring-2 ring-offset-1 ring-ring' : ''}`}
                style={{ background: c }}
              />
            ))}
          </div>
          <Button size="sm" onClick={saveEdit} disabled={busy} data-testid={`tag-save-${tag.id}`}>Salvar</Button>
          <Button size="sm" variant="ghost" onClick={() => setMode('view')} disabled={busy}>Cancelar</Button>
        </div>
      )}

      {mode === 'merge' && (
        <div className="flex flex-wrap items-center gap-2 pl-5">
          <span className="text-xs text-muted-foreground">Mesclar em:</span>
          <select
            value={mergeInto}
            onChange={(e) => setMergeInto(e.target.value)}
            data-testid={`merge-select-${tag.id}`}
            className="h-9 rounded-md border border-input bg-background px-2 text-sm"
          >
            <option value="">escolher…</option>
            {others.map((t) => (
              <option key={t.id} value={t.id}>{t.name}</option>
            ))}
          </select>
          <Button size="sm" onClick={doMerge} disabled={busy || !mergeInto} data-testid={`merge-confirm-${tag.id}`}>Mesclar</Button>
          <Button size="sm" variant="ghost" onClick={() => setMode('view')} disabled={busy}>Cancelar</Button>
        </div>
      )}
    </div>
  )
}
