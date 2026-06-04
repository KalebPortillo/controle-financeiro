import { useEffect, useState, type FormEvent } from 'react'
import { X } from 'lucide-react'
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
import { useSuggestedCategories } from '../transactions/useSuggestedCategories'
import { SuggestedCategoriesList } from '../transactions/SuggestedCategoriesList'
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
// Quanto tempo no máximo mostrar "montando categorias" antes de desistir da
// espera e deixar o usuário seguir manualmente (a 2ª análise pode falhar/demorar).
const ANALYSIS_WAIT_MS = 45_000

export function OnboardingStep3Categories({ state }: { state: OnboardingState }) {
  const { data: categories, isLoading: loadingCats } = useCategories()
  const { data: suggestions } = useSuggestedCategories({
    // Faz polling enquanto a 2ª análise pode não ter terminado (sem sugestões).
    pollWhileEmpty: true,
  })
  const createCategory = useCreateCategory()
  const advance = useAdvanceOnboarding()
  const [newName, setNewName] = useState('')
  const [error, setError] = useState<string | null>(null)

  // Janela de espera pela 2ª análise: depois dela, paramos de mostrar o
  // progresso (o usuário segue manual). Some assim que sugestões chegam.
  const [waitedTooLong, setWaitedTooLong] = useState(false)
  useEffect(() => {
    const id = setTimeout(() => setWaitedTooLong(true), ANALYSIS_WAIT_MS)
    return () => clearTimeout(id)
  }, [])

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
  // Ainda esperando a 2ª análise: em categorizing, sem sugestões e sem nada
  // aceito ainda, dentro da janela de espera. Mostra a barra de progresso
  // (dentro da seção de sugeridas) em vez de uma lista vazia silenciosa.
  const awaitingAnalysis =
    state.status === 'categorizing' &&
    pending.length === 0 &&
    accepted.length === 0 &&
    !waitedTooLong

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

      {accepted.length > 0 && (
        <div className="border border-border rounded-lg overflow-hidden">
          {accepted.map((cat) => (
            <AcceptedCategoryRow key={cat.id} category={cat} />
          ))}
        </div>
      )}

      {awaitingAnalysis ? (
        <div
          className="flex flex-col items-center text-center py-8 space-y-4"
          data-testid="categories-analysis-progress"
        >
          <div className="space-y-1">
            <p className="text-sm font-medium">Montando suas categorias</p>
            <p className="text-xs text-muted-foreground max-w-xs">
              Agrupando as tags que você aceitou em categorias amplas.
            </p>
          </div>
          <AnalysisProgress steps={ANALYSIS_STEPS} />
        </div>
      ) : (
        <SuggestedCategoriesList suggestions={pending} />
      )}

      {!loadingCats && !awaitingAnalysis && accepted.length === 0 && pending.length === 0 && (
        <p className="text-sm text-muted-foreground" data-testid="categories-empty">
          Nenhuma categoria ainda. Crie a sua acima ou conclua e gerencie depois.
        </p>
      )}

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

