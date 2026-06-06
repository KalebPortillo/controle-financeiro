import { useSkipAnalysis, useOnboarding } from './useOnboarding'
import { AnalysisProgress } from './AnalysisProgress'
import { Alert } from '../components/Alert'
import { Button } from '../components/Button'

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
 * Se a IA falha (ex.: limite/serviço indisponível), o backend registra o erro
 * (camada de feedback) e a tela mostra um card amigável com "Continuar
 * manualmente" — sem spinner infinito. Recuperando, o polling avança sozinho.
 *
 * "Pular análise" / "Continuar manualmente" chamam advance(to: tagging). O
 * AnalyzeJob pode ainda estar rodando; quando terminar, grava no catálogo
 * suggested_tags (não-destrutivo) — as sugestões aparecem depois.
 */
export function OnboardingStep2Analysis() {
  const skip = useSkipAnalysis()
  const { data } = useOnboarding()
  const error = data?.analysis_error ?? null

  return (
    <div
      className="flex flex-col items-center text-center py-12 space-y-5"
      data-testid="onboarding-step-2"
    >
      <div className="space-y-1">
        <h1 className="text-xl font-semibold tracking-tight">
          {error ? 'Não consegui analisar agora' : 'Analisando seus gastos'}
        </h1>
        <p className="text-xs text-muted-foreground max-w-xs">
          {error
            ? 'A análise por IA está indisponível no momento. Você pode continuar e organizar manualmente.'
            : 'Identificando padrões para sugerir tags e categorias. Pode deixar essa tela aberta — a gente avança sozinho quando terminar.'}
        </p>
      </div>

      {error ? (
        <Alert
          variant="warning"
          title="Análise por IA indisponível"
          testid="analysis-error"
          className="max-w-sm text-left"
          action={
            <Button
              size="sm"
              onClick={() => skip.mutate()}
              disabled={skip.isPending}
              data-testid="continue-manually"
            >
              {skip.isPending ? 'Aguarde…' : 'Continuar e organizar manualmente'}
            </Button>
          }
        >
          {error.message} As sugestões aparecem depois, quando o serviço voltar.
        </Alert>
      ) : (
        <>
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
        </>
      )}
    </div>
  )
}
