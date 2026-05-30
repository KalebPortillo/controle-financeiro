import { useMemo, useState } from 'react'
import { Plus, X } from 'lucide-react'
import { Button } from '../components/Button'
import { TagChip } from '../components/TagChip'
import { useTags } from '../transactions/useTags'
import {
  useAcceptOnboardingCategories,
  type OnboardingState,
  type SuggestedCategory,
} from './useOnboarding'

const PAGE_SIZE = 10

type RowState = {
  selected: boolean
  editedName: string
  tagIds: string[]
  dismissed: boolean
}

type ManualCategory = { name: string; tagIds: string[] }

export function OnboardingStep3Categories({ state }: { state: OnboardingState }) {
  const accept = useAcceptOnboardingCategories()
  const { data: tags } = useTags()

  const nameToId = useMemo(() => {
    const map: Record<string, string> = {}
    ;(tags ?? []).forEach((t) => { map[t.name] = t.id })
    return map
  }, [tags])

  const idToName = useMemo(() => {
    const map: Record<string, string> = {}
    ;(tags ?? []).forEach((t) => { map[t.id] = t.name })
    return map
  }, [tags])

  const allSuggestions = state.suggested_categories

  // Base rows derived from server suggestions + resolved tag IDs (no effect needed).
  const baseRows = useMemo(() => initRows(allSuggestions, nameToId), [allSuggestions, nameToId])

  // User edits on top of the base (check/uncheck, rename, add/remove tags, dismiss).
  const [patches, setPatches] = useState<Record<string, Partial<RowState>>>({})
  const rows = useMemo(() => {
    const result: Record<string, RowState> = {}
    for (const [k, v] of Object.entries(baseRows)) {
      result[k] = patches[k] ? { ...v, ...patches[k] } : v
    }
    return result
  }, [baseRows, patches])

  const [shown, setShown] = useState(() => Math.min(PAGE_SIZE, allSuggestions.length))
  const [manualCategories, setManualCategories] = useState<ManualCategory[]>([])
  const [manualName, setManualName] = useState('')

  const applyPatch = (name: string, patch: Partial<RowState>) =>
    setPatches((prev) => ({ ...prev, [name]: { ...prev[name], ...patch } }))

  const visible = allSuggestions.slice(0, shown).filter((c) => !rows[c.name]?.dismissed)
  const hasMore = shown < allSuggestions.length

  const selectedCount =
    Object.values(rows).filter((r) => r.selected && !r.dismissed).length + manualCategories.length

  const onConclude = async () => {
    const accepted = [
      ...Object.entries(rows)
        .filter(([, r]) => r.selected && !r.dismissed && r.editedName.trim() !== '')
        .map(([, r]) => ({ name: r.editedName.trim(), tag_ids: r.tagIds })),
      ...manualCategories
        .filter((c) => c.name.trim() !== '')
        .map((c) => ({ name: c.name.trim(), tag_ids: c.tagIds })),
    ]
    await accept.mutateAsync({ accepted })
  }

  const onSkipStep = async () => {
    await accept.mutateAsync({ accepted: [] })
  }

  const addManual = () => {
    const name = manualName.trim()
    if (!name) return
    setManualCategories((prev) => [...prev, { name, tagIds: [] }])
    setManualName('')
  }

  return (
    <div className="space-y-6" data-testid="onboarding-step-3">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Suas categorias</h1>
        <p className="text-sm text-muted-foreground">
          Categorias agrupam tags pra relatórios e orçamentos. Edite como quiser.
        </p>
      </div>

      <ul className="space-y-2" data-testid="category-suggestions">
        {visible.map((cat) => (
          <CategoryRow
            key={cat.name}
            cat={cat}
            state={rows[cat.name]}
            idToName={idToName}
            allTags={tags ?? []}
            onChange={(patch) => applyPatch(cat.name, patch)}
          />
        ))}
        {visible.length === 0 && (
          <li className="text-sm text-muted-foreground text-center py-4">
            Nenhuma sugestão para mostrar.
          </li>
        )}
      </ul>

      {hasMore && (
        <Button
          variant="outline"
          size="sm"
          onClick={() => setShown((s) => Math.min(s + PAGE_SIZE, allSuggestions.length))}
          data-testid="show-more-categories"
        >
          <Plus size={14} /> Mostrar mais sugestões
        </Button>
      )}

      <div className="border-t border-border pt-4 space-y-2">
        <div className="flex items-center gap-2">
          <input
            value={manualName}
            onChange={(e) => setManualName(e.target.value)}
            placeholder="Adicionar categoria manual"
            data-testid="manual-category-input"
            className="flex-1 h-9 rounded-md border border-input bg-background px-3 text-sm focus:border-ring focus:outline-2 focus:outline-ring/30"
            onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addManual())}
          />
          <Button variant="outline" size="sm" onClick={addManual} disabled={!manualName.trim()}>
            Adicionar
          </Button>
        </div>
        {manualCategories.length > 0 && (
          <ul className="space-y-1.5">
            {manualCategories.map((c, i) => (
              <li key={`${c.name}-${i}`} className="text-[12px] flex items-center gap-2">
                <span className="font-medium">{c.name}</span>
                <button
                  type="button"
                  onClick={() => setManualCategories((prev) => prev.filter((_, idx) => idx !== i))}
                  className="text-muted-foreground hover:text-destructive"
                  aria-label={`Remover ${c.name}`}
                >
                  <X size={11} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex items-center justify-between pt-2">
        <button
          type="button"
          onClick={onSkipStep}
          disabled={accept.isPending}
          className="text-xs text-muted-foreground hover:text-foreground underline"
          data-testid="skip-categories-step"
        >
          Pular este passo
        </button>
        <Button
          variant="primary"
          size="sm"
          onClick={onConclude}
          disabled={accept.isPending}
          data-testid="conclude-onboarding"
        >
          {accept.isPending ? 'Aplicando…' : `Concluir (${selectedCount})`}
        </Button>
      </div>
    </div>
  )
}

function initRows(
  suggestions: SuggestedCategory[],
  nameToId: Record<string, string>
): Record<string, RowState> {
  const rows: Record<string, RowState> = {}
  suggestions.forEach((c, idx) => {
    const tagIds = c.tag_names.map((n) => nameToId[n]).filter(Boolean)
    rows[c.name] = { selected: idx < 5, editedName: c.name, tagIds, dismissed: false }
  })
  return rows
}

function CategoryRow({
  cat, state, idToName, allTags, onChange,
}: {
  cat: SuggestedCategory
  state: RowState | undefined
  idToName: Record<string, string>
  allTags: { id: string; name: string; color: string | null; icon: string | null; usage_count: number }[]
  onChange: (patch: Partial<RowState>) => void
}) {
  const s = state || { selected: false, editedName: cat.name, tagIds: [], dismissed: false }
  const [addingTag, setAddingTag] = useState(false)
  const availableTags = allTags.filter((t) => !s.tagIds.includes(t.id))

  return (
    <li className="border border-border rounded-md p-3 flex items-start gap-3">
      <input
        type="checkbox"
        checked={s.selected}
        onChange={(e) => onChange({ selected: e.target.checked })}
        className="mt-1 h-4 w-4 accent-accent"
        aria-label={`Aceitar ${cat.name}`}
        data-testid={`category-checkbox-${cat.name}`}
      />
      <div className="flex-1 min-w-0 space-y-2">
        <input
          value={s.editedName}
          onChange={(e) => onChange({ editedName: e.target.value })}
          className="w-full bg-transparent text-sm font-medium border-0 p-0 focus:outline-none focus:bg-muted/30 rounded px-1"
          data-testid={`category-name-${cat.name}`}
        />
        <div className="flex flex-wrap gap-1.5 items-center">
          {s.tagIds.map((id) => {
            const allTag = allTags.find((t) => t.id === id)
            return (
              <span
                key={id}
                className="inline-flex items-center gap-1 rounded-sm bg-muted px-2 py-0.5 text-[12px]"
              >
                <TagChip name={idToName[id] || '?'} color={allTag?.color ?? null} />
                <button
                  type="button"
                  onClick={() => onChange({ tagIds: s.tagIds.filter((x) => x !== id) })}
                  className="text-muted-foreground hover:text-destructive"
                  aria-label="Remover tag"
                >
                  <X size={11} />
                </button>
              </span>
            )
          })}
          {availableTags.length > 0 && !addingTag && (
            <button
              type="button"
              onClick={() => setAddingTag(true)}
              className="text-[12px] text-accent hover:underline"
            >
              + tag
            </button>
          )}
          {addingTag && (
            <select
              onChange={(e) => {
                const id = e.target.value
                if (id) onChange({ tagIds: [...s.tagIds, id] })
                setAddingTag(false)
              }}
              onBlur={() => setAddingTag(false)}
              className="text-xs border border-border rounded px-1 py-0.5 bg-background"
              defaultValue=""
              autoFocus
            >
              <option value="" disabled>escolha…</option>
              {availableTags.map((t) => (
                <option key={t.id} value={t.id}>{t.name}</option>
              ))}
            </select>
          )}
        </div>
      </div>
      <button
        type="button"
        onClick={() => onChange({ dismissed: true })}
        className="text-muted-foreground hover:text-destructive shrink-0"
        aria-label={`Recusar ${cat.name}`}
        data-testid={`category-dismiss-${cat.name}`}
      >
        <X size={14} />
      </button>
    </li>
  )
}
