import { Loader2 } from 'lucide-react'
import { useSkipAnalysis } from './useOnboarding'

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
      className="flex flex-col items-center text-center py-12 space-y-4"
      data-testid="onboarding-step-2"
    >
      <Loader2 className="animate-spin text-accent" size={32} />
      <div className="space-y-1">
        <p className="text-sm font-medium">Analisando seus gastos com IA…</p>
        <p className="text-xs text-muted-foreground max-w-xs">
          Pode levar até 1 minuto. Pode deixar essa tela aberta — a gente avança
          automaticamente quando terminar.
        </p>
      </div>
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
