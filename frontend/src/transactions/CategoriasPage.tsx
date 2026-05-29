import { useState, type FormEvent } from 'react'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { TagChip } from '../components/TagChip'
import { ApiError } from '../api/client'
import { TagEditor } from './TagEditor'
import { useTags } from './useTags'
import type { InboxTag } from './useInbox'
import {
  useCategories,
  useCreateCategory,
  useUpdateCategory,
  useMergeCategory,
  useDeleteCategory,
  type Category,
} from './useCategories'

const SWATCHES = ['#7C3AED', '#15803D', '#B45309', '#B91C1C', '#2563EB', '#0891B2', '#737373']

/**
 * Gestão de categorias (RF6) — agregam tags pra relatórios/orçamentos (que vêm
 * depois). Listar, criar, editar nome+cor, associar tags, mesclar, excluir.
 */
export function CategoriasPage() {
  const { data: categories, isLoading } = useCategories()
  const createCategory = useCreateCategory()
  const [newName, setNewName] = useState('')
  const [error, setError] = useState<string | null>(null)

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault()
    const name = newName.trim()
    if (!name) return
    setError(null)
    try {
      await createCategory.mutateAsync({ name })
      setNewName('')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Erro ao criar categoria')
    }
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <section className="space-y-1">
        <h1 className="font-sans text-2xl font-semibold tracking-tight">Categorias</h1>
        <p className="text-sm text-muted-foreground">
          Agrupam tags para relatórios e orçamentos. Uma tag pode estar em várias.
        </p>
      </section>

      <form onSubmit={handleCreate} className="flex gap-2 items-stretch">
        <Input
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          placeholder="Nova categoria…"
          data-testid="new-category-name"
        />
        <Button type="submit" disabled={createCategory.isPending || !newName.trim()} data-testid="new-category-submit">
          {createCategory.isPending ? 'Criando…' : 'Criar'}
        </Button>
      </form>
      {error && <p className="text-xs text-destructive" role="alert">{error}</p>}

      <div className="border border-border rounded-lg overflow-hidden">
        {isLoading && <p className="text-xs text-muted-foreground px-4 py-3">Carregando…</p>}
        {!isLoading && (categories?.length ?? 0) === 0 && (
          <p className="text-sm text-muted-foreground px-4 py-3" data-testid="categories-empty">
            Nenhuma categoria ainda.
          </p>
        )}
        {categories?.map((cat) => (
          <CategoryRow key={cat.id} category={cat} allCategories={categories} />
        ))}
      </div>
    </div>
  )
}

function CategoryRow({ category, allCategories }: { category: Category; allCategories: Category[] }) {
  const { data: allTags } = useTags()
  const update = useUpdateCategory()
  const merge = useMergeCategory()
  const del = useDeleteCategory()

  const [mode, setMode] = useState<'view' | 'edit' | 'merge'>('view')
  const [name, setName] = useState(category.name)
  const [color, setColor] = useState(category.color ?? SWATCHES[0])
  const [tags, setTags] = useState<InboxTag[]>(category.tags)
  const [mergeInto, setMergeInto] = useState('')

  const busy = update.isPending || merge.isPending || del.isPending
  const others = allCategories.filter((c) => c.id !== category.id)

  const onTagsChange = (ids: string[]) => {
    const map = new Map((allTags ?? []).map((t) => [t.id, t]))
    setTags(ids.flatMap((id) => {
      const t = map.get(id)
      return t ? [{ id: t.id, name: t.name, color: t.color, icon: t.icon }] : []
    }))
  }

  const saveEdit = async () => {
    await update.mutateAsync({ id: category.id, name: name.trim() || category.name, color, tag_ids: tags.map((t) => t.id) })
    setMode('view')
  }

  const doMerge = async () => {
    if (!mergeInto) return
    await merge.mutateAsync({ id: category.id, intoCategoryId: mergeInto })
  }

  return (
    <div className="px-4 py-3 border-b border-border last:border-b-0 space-y-2" data-testid={`category-row-${category.id}`}>
      <div className="flex items-center gap-3">
        <span className="h-2.5 w-2.5 rounded-full shrink-0" style={{ background: category.color || 'var(--muted-foreground)' }} />
        <span className="text-sm font-medium shrink-0">{category.name}</span>
        <div className="flex items-center gap-1 flex-1 min-w-0 overflow-hidden">
          {category.tags.slice(0, 3).map((t) => (
            <TagChip key={t.id} name={t.name} color={t.color} />
          ))}
          {category.tags.length > 3 && (
            <span className="text-[11px] text-muted-foreground">+{category.tags.length - 3}</span>
          )}
        </div>
        {mode === 'view' && (
          <div className="flex gap-1 shrink-0">
            <Button variant="ghost" size="sm" onClick={() => setMode('edit')} disabled={busy} data-testid={`category-edit-${category.id}`}>
              Editar
            </Button>
            {others.length > 0 && (
              <Button variant="ghost" size="sm" onClick={() => setMode('merge')} disabled={busy} data-testid={`category-merge-${category.id}`}>
                Mesclar
              </Button>
            )}
            <Button variant="ghost" size="sm" onClick={() => del.mutate(category.id)} disabled={busy} data-testid={`category-delete-${category.id}`}>
              Excluir
            </Button>
          </div>
        )}
      </div>

      {mode === 'edit' && (
        <div className="space-y-2 pl-5">
          <div className="flex flex-wrap items-center gap-2">
            <Input value={name} onChange={(e) => setName(e.target.value)} className="max-w-48" data-testid={`category-name-${category.id}`} />
            <div className="flex gap-1">
              {SWATCHES.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setColor(c)}
                  aria-label={`cor ${c}`}
                  data-testid={`cat-swatch-${category.id}-${c}`}
                  className={`h-5 w-5 rounded-full ${color === c ? 'ring-2 ring-offset-1 ring-ring' : ''}`}
                  style={{ background: c }}
                />
              ))}
            </div>
          </div>
          <div>
            <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground mb-1">Tags</div>
            <TagEditor transactionId={`cat-${category.id}`} current={tags} onChange={onTagsChange} disabled={busy} />
          </div>
          <div className="flex gap-2">
            <Button size="sm" onClick={saveEdit} disabled={busy} data-testid={`category-save-${category.id}`}>Salvar</Button>
            <Button size="sm" variant="ghost" onClick={() => setMode('view')} disabled={busy}>Cancelar</Button>
          </div>
        </div>
      )}

      {mode === 'merge' && (
        <div className="flex flex-wrap items-center gap-2 pl-5">
          <span className="text-xs text-muted-foreground">Mesclar em:</span>
          <select
            value={mergeInto}
            onChange={(e) => setMergeInto(e.target.value)}
            data-testid={`cat-merge-select-${category.id}`}
            className="h-9 rounded-md border border-input bg-background px-2 text-sm"
          >
            <option value="">escolher…</option>
            {others.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
          <Button size="sm" onClick={doMerge} disabled={busy || !mergeInto} data-testid={`cat-merge-confirm-${category.id}`}>Mesclar</Button>
          <Button size="sm" variant="ghost" onClick={() => setMode('view')} disabled={busy}>Cancelar</Button>
        </div>
      )}
    </div>
  )
}
