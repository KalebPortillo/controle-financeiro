import { useState, type FormEvent } from 'react'
import { Check, X, Sparkles } from 'lucide-react'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { TagChip } from '../components/TagChip'
import { ApiError } from '../api/client'
import {
  useCategories,
  useCreateCategory,
  useDeleteCategory,
  type Category,
} from '../transactions/useCategories'
import {
  useSuggestedCategories,
  useAcceptSuggestedCategory,
  useDismissSuggestedCategory,
  type SuggestedCategory,
} from '../transactions/useSuggestedCategories'
import { AnalysisProgress } from './AnalysisProgress'
import { useAdvanceOnboarding, type OnboardingState } from './useOnboarding'

const ANALYSIS_STEPS = [
  'Lendo suas tags',
  'Agrupando por afinidade',
  'Montando categorias',
]

/**
 * Passo 4 do onboarding (RF22) — categorias. Mesmo modelo das tags:
 * - lista de categorias ACEITAS (reais) no topo, com criar na hora + excluir;
 * - lista de categorias SUGERIDAS pela IA abaixo (a 2ª análise as gera a partir
 *   das tags aceitas; aceitar = vira real + associa as tags, recusar).
 * Enquanto a 2ª análise roda (sem aceitas e sem sugestões ainda), mostra o
 * progresso. "Concluir" avança categorizing→completed.
 */
export function OnboardingStep3Categories({ state }: { state: OnboardingState }) {
  const { data: categories, isLoading: loadingCats } = useCategories()
  const { data: suggestions, isLoading: loadingSugg } = useSuggestedCategories({
    // Faz polling enquanto a 2ª análise pode não ter terminado (sem sugestões).
    pollWhileEmpty: true,
  })
  const createCategory = useCreateCategory()
  const advance = useAdvanceOnboarding()
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

  const accepted = categories ?? []
  const pending = suggestions ?? []
  // Tela de espera: nada aceito, nada sugerido ainda e ainda carregando/buscando.
  const waiting =
    accepted.length === 0 && pending.length === 0 && (loadingSugg || loadingCats) &&
    state.status === 'categorizing'

  if (waiting) {
    return (
      <div
        className="flex flex-col items-center text-center py-12 space-y-5"
        data-testid="onboarding-step-categories"
      >
        <div className="space-y-1">
          <h1 className="text-xl font-semibold tracking-tight">Montando suas categorias</h1>
          <p className="text-xs text-muted-foreground max-w-xs">
            Agrupando as tags que você aceitou em categorias amplas.
          </p>
        </div>
        <AnalysisProgress steps={ANALYSIS_STEPS} />
      </div>
    )
  }

  return (
    <div className="space-y-6" data-testid="onboarding-step-categories">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Suas categorias</h1>
        <p className="text-sm text-muted-foreground">
          Categorias agrupam tags para relatórios e orçamentos. Aceite as sugestões
          da IA ou crie as suas.
        </p>
      </div>

      <form onSubmit={handleCreate} className="flex gap-2 items-stretch">
        <Input
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          placeholder="Nova categoria…"
          data-testid="new-category-name"
        />
        <Button type="submit" disabled={createCategory.isPending || !newName.trim()} data-testid="new-category-submit">
          {createCategory.isPending ? 'Criando…' : 'Adicionar'}
        </Button>
      </form>
      {error && <p className="text-xs text-destructive" role="alert">{error}</p>}

      <div className="border border-border rounded-lg overflow-hidden">
        {!loadingCats && accepted.length === 0 && (
          <p className="text-sm text-muted-foreground px-4 py-3" data-testid="accepted-categories-empty">
            Nenhuma categoria aceita ainda. Aceite uma sugestão abaixo ou crie a sua.
          </p>
        )}
        {accepted.map((cat) => (
          <AcceptedCategoryRow key={cat.id} category={cat} />
        ))}
      </div>

      <SuggestedCategoriesList suggestions={pending} />

      <div className="flex items-center justify-end border-t border-border pt-4">
        <Button
          onClick={() => advance.mutate()}
          disabled={advance.isPending}
          data-testid="conclude-onboarding"
        >
          {advance.isPending ? 'Concluindo…' : 'Concluir'}
        </Button>
      </div>
    </div>
  )
}

function AcceptedCategoryRow({ category }: { category: Category }) {
  const del = useDeleteCategory()
  return (
    <div
      className="px-4 py-3 border-b border-border last:border-b-0 flex items-center gap-3"
      data-testid={`accepted-category-${category.id}`}
    >
      <div className="flex-1 min-w-0">
        <span className="text-sm font-medium">{category.name}</span>
        {category.tags.length > 0 && (
          <div className="flex flex-wrap gap-1 mt-1">
            {category.tags.map((t) => (
              <TagChip key={t.id} name={t.name} color={t.color} />
            ))}
          </div>
        )}
      </div>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => del.mutate(category.id)}
        disabled={del.isPending}
        aria-label={`Remover ${category.name}`}
        data-testid={`remove-category-${category.id}`}
      >
        <X size={14} />
      </Button>
    </div>
  )
}

function SuggestedCategoriesList({ suggestions }: { suggestions: SuggestedCategory[] }) {
  if (suggestions.length === 0) return null
  return (
    <section className="space-y-2" data-testid="suggested-categories-section">
      <div className="flex items-center gap-1.5">
        <Sparkles size={14} className="text-accent" />
        <h2 className="text-sm font-medium">Sugeridas pela IA</h2>
      </div>
      <p className="text-xs text-muted-foreground">
        A IA agrupou suas tags aceitas. Aceite para virar uma categoria de verdade.
      </p>
      <div className="border border-border rounded-lg overflow-hidden">
        {suggestions.map((s) => (
          <SuggestedCategoryRow key={s.id} suggestion={s} />
        ))}
      </div>
    </section>
  )
}

function SuggestedCategoryRow({ suggestion }: { suggestion: SuggestedCategory }) {
  const accept = useAcceptSuggestedCategory()
  const dismiss = useDismissSuggestedCategory()
  const busy = accept.isPending || dismiss.isPending

  return (
    <div
      className="px-4 py-3 border-b border-border last:border-b-0 flex items-center gap-3"
      data-testid={`suggested-category-${suggestion.id}`}
    >
      <div className="flex-1 min-w-0">
        <span className="text-sm font-medium">{suggestion.name}</span>
        {suggestion.tag_names.length > 0 && (
          <p className="text-[11px] text-muted-foreground mt-0.5 truncate">
            {suggestion.tag_names.join(', ')}
          </p>
        )}
      </div>
      <Button
        variant="outline"
        size="sm"
        onClick={() => accept.mutate(suggestion.id)}
        disabled={busy}
        data-testid={`accept-suggested-category-${suggestion.id}`}
      >
        <Check size={14} /> Aceitar
      </Button>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => dismiss.mutate(suggestion.id)}
        disabled={busy}
        aria-label={`Recusar ${suggestion.name}`}
        data-testid={`dismiss-suggested-category-${suggestion.id}`}
      >
        <X size={14} />
      </Button>
    </div>
  )
}
