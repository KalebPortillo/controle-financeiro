import { useEffect } from 'react'
import { useNavigate } from 'react-router'
import { OnboardingShell } from './OnboardingShell'
import { OnboardingStep1Connect } from './OnboardingStep1Connect'
import { OnboardingStep2Analysis } from './OnboardingStep2Analysis'
import { OnboardingStep2Tags } from './OnboardingStep2Tags'
import { useOnboarding } from './useOnboarding'

export function OnboardingPage() {
  const { data, isLoading, isError } = useOnboarding()
  const navigate = useNavigate()

  useEffect(() => {
    if (data?.status === 'completed' || data?.status === 'skipped') {
      navigate('/inbox', { replace: true })
    }
  }, [data?.status, navigate])

  if (isLoading) {
    return (
      <div
        role="status"
        className="min-h-screen flex items-center justify-center text-xs text-muted-foreground"
      >
        Carregando…
      </div>
    )
  }

  if (isError || !data) {
    return (
      <main className="min-h-screen flex items-center justify-center px-4">
        <div className="text-center space-y-2">
          <p className="text-sm font-medium">Não foi possível carregar o onboarding</p>
          <p className="text-xs text-muted-foreground">Verifique sua conexão e recarregue.</p>
        </div>
      </main>
    )
  }

  const step = !data.current_step || data.current_step < 1 ? 1 : data.current_step

  return (
    <OnboardingShell currentStep={step}>
      {step === 1 && <OnboardingStep1Connect state={data} />}
      {step === 2 && <OnboardingStep2Analysis />}
      {step === 3 && <OnboardingStep2Tags />}
    </OnboardingShell>
  )
}
