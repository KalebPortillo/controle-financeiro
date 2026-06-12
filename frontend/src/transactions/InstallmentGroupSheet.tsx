import { useState, type ReactNode } from 'react'
import { X, Tag as TagIcon, Layers, Check, ChevronRight } from 'lucide-react'
import { Sheet } from '../components/Sheet'
import { Button } from '../components/Button'
import { Money } from '../components/Money'
import { Input } from '../components/Input'
import { TagEditor } from './TagEditor'
import { AccountTag } from './AccountTag'
import { InstallmentBadge } from './InstallmentBadge'
import { useUpdateInstallmentGroup, type InboxTransaction } from './useInbox'
import type { InboxItem } from './inboxItems'

type InstallmentItem = Extract<InboxItem, { kind: 'installment' }>

function formatDate(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${d}/${m}`
}
function signed(direction: string, cents: number): number {
  return direction === 'debit' ? -cents : cents
}
const STATUS_LABEL: Record<string, string> = {
  pending: 'pendente', consolidated: 'consolidado', rejected: 'rejeitado', split: 'dividido',
}

/**
 * Detalhe de um parcelamento (RF9.4) — abre ao clicar no item agregado do inbox.
 * Mobile-first: Sheet de tela cheia com o total, edição de título/tags (vale pra
 * todas as parcelas) e a LISTA das parcelas presentes (cada uma abre seu detalhe).
 * No inbox, rodapé com aceitar/rejeitar todas de uma vez.
 */
export function InstallmentGroupSheet({
  item, open, onClose, mode = 'inbox', onOpenParcel, onAcceptGroup, onRejectGroup,
}: {
  item: InstallmentItem | null
  open: boolean
  onClose: () => void
  mode?: 'inbox' | 'consolidated'
  onOpenParcel: (t: InboxTransaction) => void
  onAcceptGroup: () => void
  onRejectGroup: () => void
}) {
  return (
    <Sheet open={open} onClose={onClose} width={460}>
      {item && (
        <Inner
          key={item.groupId}
          item={item}
          mode={mode}
          onClose={onClose}
          onOpenParcel={onOpenParcel}
          onAcceptGroup={onAcceptGroup}
          onRejectGroup={onRejectGroup}
        />
      )}
    </Sheet>
  )
}

function Inner({
  item, mode, onClose, onOpenParcel, onAcceptGroup, onRejectGroup,
}: {
  item: InstallmentItem
  mode: 'inbox' | 'consolidated'
  onClose: () => void
  onOpenParcel: (t: InboxTransaction) => void
  onAcceptGroup: () => void
  onRejectGroup: () => void
}) {
  const { representative: rep, parcels, total, groupId } = item
  const [title, setTitle] = useState(rep.improved_title ?? '')
  const updateGroup = useUpdateInstallmentGroup()

  const saveTitle = () => {
    const v = title.trim()
    if (v !== (rep.improved_title ?? '')) updateGroup.mutate({ group_id: groupId, improved_title: v })
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-5 pt-5 pb-4 border-b border-border">
        <div className="flex items-start gap-2.5">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 mb-1">
              <Layers size={13} className="text-muted-foreground shrink-0" />
              <span className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
                Parcelamento · {rep.installment_total}x
              </span>
            </div>
            <div className="font-display text-lg font-semibold tracking-tight truncate">
              {rep.improved_title || rep.original_description}
            </div>
          </div>
          <button
            onClick={onClose}
            aria-label="Fechar"
            className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground shrink-0"
          >
            <X size={16} />
          </button>
        </div>
        <div className="mt-3 flex items-baseline gap-2">
          <Money cents={signed(rep.direction, total)} signed className="text-3xl font-medium" />
          <span className="text-xs text-muted-foreground">
            {parcels.length} {parcels.length === 1 ? 'parcela' : 'parcelas'} no inbox
          </span>
        </div>
      </div>

      {/* Body */}
      <div className="flex-1 overflow-y-auto px-5 py-5 flex flex-col gap-3.5">
        <FieldLabel>Título</FieldLabel>
        <Input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onBlur={saveTitle}
          data-testid={`group-sheet-title-${groupId}`}
        />

        <FieldLabel icon={<TagIcon size={12} />}>Tags</FieldLabel>
        <TagEditor
          transactionId={rep.id}
          current={rep.tags}
          disabled={updateGroup.isPending}
          onChange={(tagIds) => updateGroup.mutate({ group_id: groupId, tag_ids: tagIds })}
        />
        <p className="text-[11px] text-muted-foreground -mt-1.5">
          Título e tags valem para as {rep.installment_total} parcelas.
        </p>

        <FieldLabel>Conta</FieldLabel>
        <div className="h-9 px-3 flex items-center rounded-md bg-muted text-muted-foreground text-sm">
          <AccountTag kind={rep.account_kind} institutionLabel={rep.institution_label} accountName={rep.account_name} />
        </div>

        <FieldLabel>Parcelas no inbox ({parcels.length})</FieldLabel>
        <ul className="border border-border rounded-md overflow-hidden" data-testid={`group-sheet-parcels-${groupId}`}>
          {parcels.map((p) => (
            <li key={p.id} className="border-b border-border last:border-b-0">
              <button
                type="button"
                onClick={() => onOpenParcel(p)}
                className="w-full grid grid-cols-[auto_1fr_auto_auto] gap-2 items-center px-3 py-2.5 text-left hover:bg-muted"
                data-testid={`group-sheet-parcel-${p.id}`}
              >
                <InstallmentBadge number={p.installment_number} total={p.installment_total} />
                <span className="text-[11px] text-muted-foreground truncate">
                  {formatDate(p.occurred_at)} · {STATUS_LABEL[p.status] ?? p.status}
                </span>
                <Money cents={signed(p.direction, p.amount_cents)} signed className="text-[13px]" />
                <ChevronRight size={14} className="text-muted-foreground" />
              </button>
            </li>
          ))}
        </ul>
      </div>

      {/* Rodapé — aceitar/rejeitar todas (só inbox) */}
      {mode === 'inbox' && (
        <div className="px-5 py-4 border-t border-border flex gap-2">
          <Button
            variant="ghost"
            onClick={() => { onRejectGroup(); onClose() }}
            data-testid={`group-sheet-reject-${groupId}`}
          >
            Rejeitar todas
          </Button>
          <Button
            variant="primary"
            className="flex-1"
            onClick={() => { onAcceptGroup(); onClose() }}
            data-testid={`group-sheet-accept-${groupId}`}
          >
            <Check size={16} /> Aceitar todas ({parcels.length})
          </Button>
        </div>
      )}
    </div>
  )
}

function FieldLabel({ icon, children }: { icon?: ReactNode; children: ReactNode }) {
  return (
    <div className="flex items-center gap-1.5 text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
      {icon}
      <span>{children}</span>
    </div>
  )
}
