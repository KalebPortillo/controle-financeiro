import { useState } from 'react'
import { X, Tag as TagIcon, Folder, Layers, Check, ArrowLeft } from 'lucide-react'
import { Sheet } from '../components/Sheet'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { useTags } from '../transactions/useTags'
import { useCategories } from '../transactions/useCategories'
import {
  useCreateBudget, useUpdateBudget,
  type Budget, type BudgetKind, type BudgetInput,
} from './useBudgets'

const KINDS: { kind: BudgetKind; label: string; Icon: typeof TagIcon }[] = [
  { kind: 'tag', label: 'Tag', Icon: TagIcon },
  { kind: 'category', label: 'Categoria', Icon: Folder },
  { kind: 'composite', label: 'Composto', Icon: Layers },
]

/**
 * Wizard de orçamento (RF8) em 2 passos: (1) escopo — tag, categoria ou combinação
 * de tags; (2) teto mensal + alerta. Cria ou edita. Mobile-first (Sheet cheio).
 */
export function BudgetWizard({
  open, budgetId, budgets, onClose,
}: {
  open: boolean
  budgetId: string | null
  budgets: Budget[]
  onClose: () => void
}) {
  const existing = budgetId ? budgets.find((b) => b.id === budgetId) ?? null : null
  return (
    <Sheet open={open} onClose={onClose} width={460}>
      {open && <Inner key={budgetId ?? 'new'} existing={existing} onClose={onClose} />}
    </Sheet>
  )
}

function centsToReais(cents: number): string {
  return (cents / 100).toFixed(2)
}
function reaisToCents(v: string): number {
  return Math.round(parseFloat(v.replace(',', '.')) * 100)
}

function Inner({ existing, onClose }: { existing: Budget | null; onClose: () => void }) {
  const { data: tags } = useTags()
  const categories = useCategories().data?.categories ?? []
  const create = useCreateBudget()
  const update = useUpdateBudget()

  const [step, setStep] = useState<1 | 2>(existing ? 2 : 1)
  const [kind, setKind] = useState<BudgetKind>(existing?.kind ?? 'tag')
  const [tagId, setTagId] = useState<string | null>(existing?.target_tag?.id ?? null)
  const [categoryId, setCategoryId] = useState<string | null>(existing?.target_category?.id ?? null)
  const [compositeIds, setCompositeIds] = useState<Set<string>>(
    new Set(existing?.composite_tags.map((t) => t.id) ?? []),
  )
  const [name, setName] = useState(existing?.name ?? '')
  const [limit, setLimit] = useState(existing ? centsToReais(existing.monthly_limit_cents) : '')
  const [threshold, setThreshold] = useState(String(existing?.alert_threshold_pct ?? 80))
  const [enabled, setEnabled] = useState(existing?.enabled ?? true)

  const targetChosen =
    (kind === 'tag' && tagId) ||
    (kind === 'category' && categoryId) ||
    (kind === 'composite' && compositeIds.size > 0)

  const limitCents = reaisToCents(limit)
  const canSave = name.trim().length > 0 && Number.isFinite(limitCents) && limitCents > 0 && !!targetChosen
  const busy = create.isPending || update.isPending

  const toggleComposite = (id: string) =>
    setCompositeIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })

  const save = () => {
    const body: BudgetInput = {
      name: name.trim(),
      kind,
      monthly_limit_cents: limitCents,
      alert_threshold_pct: Math.min(100, Math.max(1, parseInt(threshold, 10) || 80)),
      enabled,
      target_tag_id: kind === 'tag' ? tagId : null,
      target_category_id: kind === 'category' ? categoryId : null,
      composite_tag_ids: kind === 'composite' ? [...compositeIds] : [],
    }
    const done = { onSuccess: onClose }
    if (existing) update.mutate({ id: existing.id, ...body }, done)
    else create.mutate(body, done)
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-5 pt-5 pb-4 border-b border-border flex items-start justify-between gap-2.5">
        <div>
          <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">
            {existing ? 'Editar orçamento' : `Novo orçamento · passo ${step} de 2`}
          </div>
          <div className="font-display text-lg font-semibold tracking-tight mt-0.5">
            {step === 1 ? 'Escolha o escopo' : 'Defina o teto'}
          </div>
        </div>
        <button onClick={onClose} aria-label="Fechar" className="h-8 w-8 inline-flex items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground shrink-0">
          <X size={16} />
        </button>
      </div>

      {/* Body */}
      <div className="flex-1 overflow-y-auto px-5 py-5 flex flex-col gap-3.5">
        {step === 1 ? (
          <>
            <FieldLabel>Tipo</FieldLabel>
            <div className="grid grid-cols-3 gap-2">
              {KINDS.map(({ kind: k, label, Icon }) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setKind(k)}
                  data-testid={`budget-kind-${k}`}
                  className={`flex flex-col items-center gap-1 rounded-md border px-2 py-3 text-xs transition-colors ${
                    kind === k ? 'border-accent bg-accent/10 text-accent' : 'border-border text-muted-foreground hover:bg-muted'
                  }`}
                >
                  <Icon size={16} />
                  {label}
                </button>
              ))}
            </div>

            {kind === 'tag' && (
              <>
                <FieldLabel>Tag</FieldLabel>
                <PickList
                  items={(tags ?? []).map((t) => ({ id: t.id, name: t.name }))}
                  selected={tagId ? [tagId] : []}
                  onPick={(id) => setTagId(id)}
                  testid="budget-tag-list"
                />
              </>
            )}
            {kind === 'category' && (
              <>
                <FieldLabel>Categoria</FieldLabel>
                <PickList
                  items={categories.map((c) => ({ id: c.id, name: c.name }))}
                  selected={categoryId ? [categoryId] : []}
                  onPick={(id) => setCategoryId(id)}
                  testid="budget-category-list"
                />
              </>
            )}
            {kind === 'composite' && (
              <>
                <FieldLabel>Tags ({compositeIds.size})</FieldLabel>
                <PickList
                  items={(tags ?? []).map((t) => ({ id: t.id, name: t.name }))}
                  selected={[...compositeIds]}
                  onPick={toggleComposite}
                  multi
                  testid="budget-composite-list"
                />
              </>
            )}
          </>
        ) : (
          <>
            <FieldLabel>Nome</FieldLabel>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="ex.: Mercado" data-testid="budget-name" />

            <FieldLabel>Teto mensal (R$)</FieldLabel>
            <Input value={limit} onChange={(e) => setLimit(e.target.value)} inputMode="decimal" placeholder="800,00" className="cf-money" data-testid="budget-limit" />

            <FieldLabel>Alertar em (% do teto)</FieldLabel>
            <Input value={threshold} onChange={(e) => setThreshold(e.target.value)} inputMode="numeric" data-testid="budget-threshold" />

            <label className="flex items-center gap-2 text-sm mt-1">
              <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} className="accent-[var(--accent)]" data-testid="budget-enabled" />
              Orçamento ativo
            </label>
          </>
        )}
      </div>

      {/* Footer */}
      <div className="px-5 py-4 border-t border-border flex gap-2">
        {step === 1 ? (
          <Button className="flex-1" disabled={!targetChosen} onClick={() => setStep(2)} data-testid="budget-next">
            Continuar
          </Button>
        ) : (
          <>
            {!existing && (
              <Button variant="ghost" onClick={() => setStep(1)} data-testid="budget-back">
                <ArrowLeft size={14} /> Voltar
              </Button>
            )}
            <Button variant="primary" className="flex-1" disabled={!canSave || busy} onClick={save} data-testid="budget-save">
              <Check size={14} /> {existing ? 'Salvar' : 'Criar orçamento'}
            </Button>
          </>
        )}
      </div>
    </div>
  )
}

function PickList({
  items, selected, onPick, multi = false, testid,
}: {
  items: { id: string; name: string }[]
  selected: string[]
  onPick: (id: string) => void
  multi?: boolean
  testid: string
}) {
  const sel = new Set(selected)
  if (items.length === 0) {
    return <p className="text-xs text-muted-foreground">Nenhuma opção — crie tags/categorias antes.</p>
  }
  return (
    <ul className="border border-border rounded-md overflow-hidden max-h-64 overflow-y-auto" data-testid={testid}>
      {items.map((it) => (
        <li key={it.id} className="border-b border-border last:border-b-0">
          <button
            type="button"
            onClick={() => onPick(it.id)}
            data-testid={`${testid}-${it.id}`}
            className={`w-full flex items-center justify-between px-3 py-2.5 text-sm text-left hover:bg-muted ${
              sel.has(it.id) ? 'bg-accent/10 text-accent' : ''
            }`}
          >
            <span className="truncate">{it.name}</span>
            {sel.has(it.id) && <Check size={14} className="shrink-0" />}
          </button>
        </li>
      ))}
      {multi && <li className="px-3 py-1.5 text-[11px] text-muted-foreground">Selecione uma ou mais</li>}
    </ul>
  )
}

function FieldLabel({ children }: { children: React.ReactNode }) {
  return <div className="text-[11px] uppercase tracking-wider font-medium text-muted-foreground">{children}</div>
}
