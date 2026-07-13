import { CalendarClock } from 'lucide-react'
import { Money } from '../components/Money'
import { formatDayMonth } from './display'
import { useInstallmentGroup, type InstallmentParcel } from './useInbox'

// RF9.4.4 — no consolidado cada parcela é uma linha no seu mês, então o detalhe
// de uma parcela não mostrava as demais. Esta seção busca o grupo inteiro e lista
// TODAS as parcelas (número, data, valor, status), destacando a parcela atual.
const STATUS_LABEL: Record<string, string> = {
  pending: 'pendente',
  consolidated: 'consolidado',
  rejected: 'rejeitado',
}

export function InstallmentScheduleSection({
  groupId,
  currentId,
}: {
  groupId: string
  currentId: string
}) {
  const { data, isLoading } = useInstallmentGroup(groupId, true)

  return (
    <div className="mt-2 pt-3.5 border-t border-border" data-testid="installment-schedule">
      <div className="flex items-center justify-between gap-2 mb-2">
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <CalendarClock size={13} />
          <span>Parcelamento{data?.installment_total ? ` · ${data.installment_total}x` : ''}</span>
        </div>
        {data && <Money cents={-data.total_amount_cents} className="text-xs" />}
      </div>

      {isLoading && <p className="text-[11px] text-muted-foreground">Carregando parcelas…</p>}

      {data?.parcels && (
        <div className="space-y-0.5">
          {data.parcels.map((p) => (
            <ParcelRow key={p.id} parcel={p} current={p.id === currentId} />
          ))}
        </div>
      )}
    </div>
  )
}

function ParcelRow({ parcel: p, current }: { parcel: InstallmentParcel; current: boolean }) {
  return (
    <div
      data-testid={`parcel-${p.id}`}
      className={`flex items-center justify-between gap-2 px-2 py-1.5 rounded-md text-sm ${
        current ? 'bg-muted' : ''
      }`}
    >
      <div className="flex items-center gap-2 min-w-0">
        <span className="tabular-nums text-muted-foreground w-10 shrink-0">
          {p.installment_number}/{p.installment_total}
        </span>
        <span className="tabular-nums text-muted-foreground text-[11px]">
          {formatDayMonth(p.occurred_at)}
        </span>
        {current && <span className="text-[10px] text-muted-foreground">· esta parcela</span>}
      </div>
      <div className="flex items-center gap-2 shrink-0">
        <span className="text-[10px] text-muted-foreground">{STATUS_LABEL[p.status] ?? p.status}</span>
        <Money cents={-p.amount_cents} className="text-sm" />
      </div>
    </div>
  )
}
