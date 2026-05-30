import { useMemo, useState } from 'react'
import { Plus, X } from 'lucide-react'
import { Button } from '../components/Button'
import { useAcceptOnboardingTags, useSkipOnboarding, type OnboardingState, type SuggestedTag } from './useOnboarding'

const PAGE_SIZE = 10

type RowState = {
  selected: boolean
  editedName: string
  dismissed: boolean
}

export function OnboardingStep2Tags({ state }: { state: OnboardingState }) {
  const accept = useAcceptOnboardingTags()
  const skip = useSkipOnboarding()

  const allSuggestions = state.suggested_tags

  const baseRows = useMemo(() => initRows(allSuggestions), [allSuggestions])
  const [patches, setPatches] = useState<Record<string, Partial<RowState>>>({})
  const rows = useMemo(() => {
    const result: Record<string, RowState> = {}
    for (const [k, v] of Object.entries(baseRows)) {
      result[k] = patches[k] ? { ...v, ...patches[k] } : v
    }
    return result
  }, [baseRows, patches])

  const applyPatch = (name: string, patch: Partial<RowState>) =>
    setPatches((prev) => ({ ...prev, [name]: { ...prev[name], ...patch } }))

  const [shown, setShown] = useState(() => Math.min(PAGE_SIZE, allSuggestions.length))
  const [manualName, setManualName] = useState('')
  const [manualNames, setManualNames] = useState<string[]>([])

  const visible = useMemo(() => allSuggestions.slice(0, shown), [allSuggestions, shown])
  const visibleAfterDismiss = visible.filter((t) => !rows[t.name]?.dismissed)
  const hasMore = shown < allSuggestions.length

  const selectedCount =
    Object.values(rows).filter((r) => r.selected && !r.dismissed).length + manualNames.length

  const onContinue = async () => {
    const accepted = [
      ...Object.entries(rows)
        .filter(([, r]) => r.selected && !r.dismissed && r.editedName.trim() !== '')
        .map(([, r]) => ({ name: r.editedName.trim() })),
      ...manualNames.map((name) => ({ name: name.trim() })).filter((t) => t.name !== ''),
    ]
    await accept.mutateAsync({ accepted })
  }

  const onSkipStep = async () => {
    await accept.mutateAsync({ accepted: [] })
  }

  const addManual = () => {
    const name = manualName.trim()
    if (!name) return
    setManualNames((prev) => [...prev, name])
    setManualName('')
  }

  return (
    <div className="space-y-6" data-testid="onboarding-step-2">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Suas tags iniciais</h1>
        <p className="text-sm text-muted-foreground">
          A IA sugeriu essas tags com base nos seus gastos. Aceite, edite ou recuse.
        </p>
      </div>

      <ul className="space-y-2" data-testid="tag-suggestions">
        {visibleAfterDismiss.map((tag) => (
          <SuggestionRow
            key={tag.name}
            tag={tag}
            state={rows[tag.name]}
            onChange={(patch) => applyPatch(tag.name, patch)}
          />
        ))}
        {visibleAfterDismiss.length === 0 && (
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
          data-testid="show-more-tags"
        >
          <Plus size={14} /> Mostrar mais sugestões
        </Button>
      )}

      <div className="border-t border-border pt-4 space-y-2">
        <div className="flex items-center gap-2">
          <input
            value={manualName}
            onChange={(e) => setManualName(e.target.value)}
            placeholder="Adicionar tag manual"
            data-testid="manual-tag-input"
            className="flex-1 h-9 rounded-md border border-input bg-background px-3 text-sm focus:border-ring focus:outline-2 focus:outline-ring/30"
            onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addManual())}
          />
          <Button variant="outline" size="sm" onClick={addManual} disabled={!manualName.trim()}>
            Adicionar
          </Button>
        </div>
        {manualNames.length > 0 && (
          <ul className="flex flex-wrap gap-1.5" data-testid="manual-tag-list">
            {manualNames.map((name, i) => (
              <li key={`${name}-${i}`} className="inline-flex items-center gap-1 rounded-sm bg-muted px-2 py-0.5 text-[12px]">
                {name}
                <button
                  type="button"
                  onClick={() => setManualNames((prev) => prev.filter((_, idx) => idx !== i))}
                  className="text-muted-foreground hover:text-destructive"
                  aria-label={`Remover ${name}`}
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
          data-testid="skip-tags-step"
        >
          Pular este passo
        </button>
        <Button
          variant="primary"
          size="sm"
          onClick={onContinue}
          disabled={accept.isPending || skip.isPending || selectedCount === 0}
          data-testid="continue-tags"
        >
          {accept.isPending ? 'Salvando…' : `Continuar (${selectedCount})`}
        </Button>
      </div>
    </div>
  )
}

function initRows(suggestions: SuggestedTag[]): Record<string, RowState> {
  const rows: Record<string, RowState> = {}
  suggestions.forEach((t, idx) => {
    rows[t.name] = { selected: idx < 5, editedName: t.name, dismissed: false }
  })
  return rows
}

function SuggestionRow({
  tag, state, onChange,
}: {
  tag: SuggestedTag
  state: RowState | undefined
  onChange: (patch: Partial<RowState>) => void
}) {
  const s = state || { selected: false, editedName: tag.name, dismissed: false }
  return (
    <li className="border border-border rounded-md p-3 flex items-start gap-3">
      <input
        type="checkbox"
        checked={s.selected}
        onChange={(e) => onChange({ selected: e.target.checked })}
        className="mt-1 h-4 w-4 accent-accent"
        data-testid={`tag-checkbox-${tag.name}`}
        aria-label={`Aceitar ${tag.name}`}
      />
      <div className="flex-1 min-w-0">
        <input
          value={s.editedName}
          onChange={(e) => onChange({ editedName: e.target.value })}
          className="w-full bg-transparent text-sm font-medium border-0 p-0 focus:outline-none focus:bg-muted/30 rounded px-1"
          data-testid={`tag-name-${tag.name}`}
        />
        {tag.rationale && (
          <p className="text-[11px] text-muted-foreground mt-0.5">
            {tag.rationale}
            {tag.coverage !== undefined && tag.coverage > 0 && ` · ${tag.coverage} transações`}
          </p>
        )}
      </div>
      <button
        type="button"
        onClick={() => onChange({ dismissed: true })}
        className="text-muted-foreground hover:text-destructive shrink-0"
        aria-label={`Recusar ${tag.name}`}
        data-testid={`tag-dismiss-${tag.name}`}
      >
        <X size={14} />
      </button>
    </li>
  )
}
