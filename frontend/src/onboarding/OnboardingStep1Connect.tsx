import { useEffect, useState } from 'react'
import { Link } from 'react-router'
import { Building2, Upload, CheckCircle2 } from 'lucide-react'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { ConnectBankButton } from '../bank/ConnectBankButton'
import {
  HISTORY_PERIOD_OPTIONS,
  resolveHistorySince,
  useBankConnectionsList,
  type HistoryPeriod,
  type BankConnection,
} from '../bank/useBankConnections'
import { useStartOnboarding, useStartAnalysis, type OnboardingState } from './useOnboarding'

/**
 * Passo 1 do onboarding (RF22.5.1–5.4) — conectar fonte de dados.
 *
 * F2: a tela PERMANECE após conectar uma conta — o usuário pode conectar mais
 * contas (ou importar CSV no futuro) e só então clicar "Continuar para análise",
 * que avança connecting→analyzing e dispara a análise IA (o sync não a inicia
 * mais automaticamente).
 */
export function OnboardingStep1Connect({ state }: { state: OnboardingState }) {
  const start = useStartOnboarding()
  const startAnalysis = useStartAnalysis()
  const { data: connections } = useBankConnectionsList()
  // RF1.7 — período do histórico inicial. Default: últimos 3 meses.
  const [period, setPeriod] = useState<HistoryPeriod>('3m')
  const [customDate, setCustomDate] = useState('')
  const historySince = resolveHistorySince(period, customDate)

  // Marca como connecting na primeira vez que o usuário chega aqui.
  // Idempotente do lado do backend.
  useEffect(() => {
    if (state.status === 'not_started') {
      start.mutate()
    }
  }, [state.status, start])

  const connected = connections?.connections ?? []
  const hasConnection = connected.length > 0

  return (
    <div className="space-y-6" data-testid="onboarding-step-1">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Conectar sua conta</h1>
        <p className="text-sm text-muted-foreground">
          A gente vai buscar seus gastos pra pré-categorizar tudo com IA antes
          de você revisar.
        </p>
      </div>

      <HistoryPeriodPicker
        period={period}
        customDate={customDate}
        onPeriodChange={setPeriod}
        onCustomDateChange={setCustomDate}
      />

      <div className="space-y-3">
        <ConnectBankCard historySince={historySince} connections={connected} />
        <ImportCsvCard />
      </div>

      <div className="flex items-center justify-end border-t border-border pt-4">
        <Button
          onClick={() => startAnalysis.mutate()}
          disabled={!hasConnection || startAnalysis.isPending}
          data-testid="continue-to-analysis"
        >
          {startAnalysis.isPending ? 'Continuando…' : 'Continuar para análise'}
        </Button>
      </div>
    </div>
  )
}

function HistoryPeriodPicker({
  period,
  customDate,
  onPeriodChange,
  onCustomDateChange,
}: {
  period: HistoryPeriod
  customDate: string
  onPeriodChange: (p: HistoryPeriod) => void
  onCustomDateChange: (d: string) => void
}) {
  return (
    <fieldset className="border border-border rounded-md p-4 space-y-3">
      <legend className="px-1 text-sm font-medium">Importar gastos de quando?</legend>
      <div className="flex flex-col gap-1.5" role="radiogroup" aria-label="Período do histórico">
        {HISTORY_PERIOD_OPTIONS.map((opt) => (
          <label
            key={opt.value}
            className="flex items-center gap-2.5 text-sm cursor-pointer"
          >
            <input
              type="radio"
              name="history-period"
              value={opt.value}
              checked={period === opt.value}
              onChange={() => onPeriodChange(opt.value)}
              className="h-4 w-4 accent-accent"
            />
            <span>{opt.label}</span>
          </label>
        ))}
      </div>

      {period === 'custom' && (
        <div className="pt-1">
          <Input
            type="date"
            value={customDate}
            onChange={(e) => onCustomDateChange(e.target.value)}
            data-testid="custom-history-date"
            aria-label="Data de início personalizada"
            className="max-w-44"
          />
        </div>
      )}
    </fieldset>
  )
}

function ConnectBankCard({
  historySince,
  connections,
}: {
  historySince: string
  connections: BankConnection[]
}) {
  const hasConnection = connections.length > 0
  return (
    <div className="border border-border rounded-md p-4">
      <div className="flex items-start gap-3">
        <div className="h-9 w-9 rounded-md bg-accent/10 text-accent flex items-center justify-center shrink-0">
          <Building2 size={18} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium">Conectar banco via Pluggy</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Conexão segura. Suportamos os principais bancos brasileiros.
          </p>

          {/* Contas já conectadas — dentro do próprio card de conexão. */}
          {hasConnection && (
            <ul className="mt-3 space-y-1.5" data-testid="connected-list">
              {connections.map((c) => (
                <li key={c.id} className="flex items-center gap-2 text-sm">
                  <CheckCircle2 size={15} className="text-success shrink-0" />
                  <span className="truncate">
                    {c.accounts.length > 0
                      ? c.accounts.map((a) => a.institution_label || a.name).join(', ')
                      : 'Conta conectada'}
                  </span>
                </li>
              ))}
            </ul>
          )}

          <div className="mt-3">
            <ConnectBankButton
              historySince={historySince}
              variant={hasConnection ? 'outline' : 'primary'}
              label={hasConnection ? 'Conectar outro banco' : 'Conectar banco'}
            />
          </div>
        </div>
      </div>
    </div>
  )
}

function ImportCsvCard() {
  return (
    <Link
      to="/importar"
      className="block border border-border rounded-md p-4 hover:bg-muted/50 transition-colors"
      data-testid="onboarding-import-card"
    >
      <div className="flex items-start gap-3">
        <div className="h-9 w-9 rounded-md bg-accent/10 text-accent flex items-center justify-center shrink-0">
          <Upload size={18} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium">Importar arquivo</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Suba um extrato CSV exportado do seu banco.
          </p>
        </div>
      </div>
    </Link>
  )
}

