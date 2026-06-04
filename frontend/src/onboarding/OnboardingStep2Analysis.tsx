import { useSkipAnalysis } from './useOnboarding'
import { AnalysisProgress } from './AnalysisProgress'

const ANALYSIS_STEPS = [
  'Lendo suas transações',
  'Identificando padrões de gasto',
  'Agrupando por tema',
  'Montando sugestões de tags',
]

/**
 * Passo 2 do onboarding (RF22) — análise inicial da IA.
 * Status backend: "analyzing". Fica em polling até a análise terminar
 * (AnalyzeJob termina → status vira "tagging" → frontend avança sozinho).
 *
 * "Pular análise" chama advance(to: tagging) imediatamente. O AnalyzeJob
 * pode ainda estar rodando em background; quando terminar, grava no catálogo
 * suggested_tags (não-destrutivo) — as sugestões aparecem depois na página
 * de Tags e no inbox.
 */
export function OnboardingStep2Analysis() {
  const skip = useSkipAnalysis()

  return (
    <div
      className="flex flex-col items-center text-center py-12 space-y-5"
      data-testid="onboarding-step-2"
    >
      <div className="space-y-1">
        <h1 className="text-xl font-semibold tracking-tight">Analisando seus gastos</h1>
        <p className="text-xs text-muted-foreground max-w-xs">
          Identificando padrões para sugerir tags e categorias. Pode deixar essa
          tela aberta — a gente avança sozinho quando terminar.
        </p>
      </div>

      <AnalysisProgress steps={ANALYSIS_STEPS} />

      <button
        type="button"
        onClick={() => skip.mutate()}
        disabled={skip.isPending}
        className="text-xs text-muted-foreground hover:text-foreground underline"
        data-testid="skip-analysis"
      >
        {skip.isPending ? 'Aguarde…' : 'Pular análise e continuar'}
      </button>
    </div>
  )
}
