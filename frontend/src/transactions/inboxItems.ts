import type { InboxTransaction, RelatedItem } from './useInbox'

// Item da lista do inbox: um gasto avulso, um parcelamento agregado (parcelas do
// mesmo installment_group_id) ou um gasto + suas relacionadas (IOF/tarifa…, RF23)
// quando âncora e TODOS os satélites presentes na lista aparecem juntos.
export type InboxItem =
  | { kind: 'single'; transaction: InboxTransaction }
  | {
      kind: 'installment'
      groupId: string
      parcels: InboxTransaction[]
      total: number
      representative: InboxTransaction
      // Data da COMPRA do parcelamento (purchase_date; fallback: 1ª parcela).
      purchaseDate: string
    }
  | {
      kind: 'related'
      // Id da âncora — chave do overlay (?rel) e da linha.
      key: string
      anchor: InboxTransaction
      satellites: InboxTransaction[]
      members: InboxTransaction[] // [anchor, ...satellites]
      memberIds: string[]
      // Tipo de cada satélite (id → relation_type), incluindo os "netos" que
      // sobem como irmãos (ex.: estorno de IOF). Usado pelos badges do grupo.
      satelliteTypes: Map<string, RelatedItem['relation_type']>
      // Custo combinado assinado (compra + IOF/tarifas − estornos), por direção.
      signedTotalCents: number
    }

function isInstallment(t: InboxTransaction): boolean {
  return t.installment_total != null && t.installment_group_id != null
}

function signedCents(t: InboxTransaction): number {
  return t.direction === 'debit' ? -t.amount_cents : t.amount_cents
}

// Data que posiciona o item na lista: avulso = data do gasto; parcelamento =
// data da compra; relacionadas = data da âncora. Todas YYYY-MM-DD (lexicográfico).
export function itemDate(item: InboxItem): string {
  if (item.kind === 'installment') return item.purchaseDate
  if (item.kind === 'related') return item.anchor.occurred_at
  return item.transaction.occurred_at
}

/**
 * Resolve os grupos de relacionadas (RF23): uma âncora (gasto de origem) e seus
 * satélites (IOF/tarifa…) viram um item ÚNICO quando âncora e TODOS os satélites
 * estão presentes na lista. Se faltar algum satélite, não agrupa (cai na seção
 * "Relacionadas" do detalhe). Parcelamentos têm prioridade — uma âncora parcelada
 * não vira grupo de relacionadas. Retorna o mapa âncora→satélites e o conjunto de
 * ids consumidos (satélites que não devem renderizar avulsos).
 */
type Group = { members: InboxTransaction[]; types: Map<string, RelatedItem['relation_type']> }

function resolveRelatedGroups(transactions: InboxTransaction[]) {
  const byId = new Map(transactions.map((t) => [t.id, t]))
  const anchors = new Map<string, Group>() // anchorId → membros + tipos
  const consumed = new Set<string>()

  // Estornos (role satellite, relation_type refund) presentes de uma transação.
  const refundSatsOf = (t: InboxTransaction) =>
    (t.related ?? [])
      .filter((r) => r.role === 'satellite' && r.relation_type === 'refund')
      .map((r) => byId.get(r.transaction_id))
      .filter((s): s is InboxTransaction => s != null && !isInstallment(s))

  for (const t of transactions) {
    if (isInstallment(t)) continue
    const satelliteRefs = (t.related ?? []).filter((r) => r.role === 'satellite')
    if (satelliteRefs.length === 0) continue

    const linkRefs = satelliteRefs.filter((r) => r.relation_type !== 'refund')
    const refundRefs = satelliteRefs.filter((r) => r.relation_type === 'refund')
    const linkSats = linkRefs.map((r) => byId.get(r.transaction_id))
    // IOF/tarifa (RF23): tudo-ou-nada — só agrupa com TODOS presentes.
    const linksComplete = linkRefs.length > 0 && linkSats.every((s) => s != null && !isInstallment(s))

    const members: InboxTransaction[] = []
    const types = new Map<string, RelatedItem['relation_type']>()
    const add = (s: InboxTransaction, type: RelatedItem['relation_type']) => {
      if (types.has(s.id)) return
      members.push(s)
      types.set(s.id, type)
    }

    // Satélites RF23 (se completos) + os estornos DESSES satélites como IRMÃOS
    // (ex.: estorno de IOF sobe pro grupo da compra, no mesmo nível).
    if (linksComplete) {
      linkRefs.forEach((r) => {
        const sat = byId.get(r.transaction_id)!
        add(sat, r.relation_type)
        refundSatsOf(sat).forEach((g) => add(g, 'refund'))
      })
    }
    // Estornos diretos da âncora (RF10.6): presença parcial, sem exigir todos.
    refundRefs.forEach((r) => {
      const s = byId.get(r.transaction_id)
      if (s != null && !isInstallment(s)) add(s, 'refund')
    })

    if (members.length === 0) continue
    anchors.set(t.id, { members, types })
    members.forEach((s) => consumed.add(s.id))
  }

  // Um satélite consumido não pode ser âncora de outro grupo (evita corrente).
  for (const id of anchors.keys()) if (consumed.has(id)) anchors.delete(id)

  return { anchors, consumed }
}

/**
 * Agrega parcelamentos e relacionadas num item por grupo, preservando a ordem da
 * lista (o grupo ocupa a posição da 1ª transação que aparece). Ordena por data
 * desc no fim (gasto = occurred_at; parcelamento = data da compra; relacionadas =
 * data da âncora).
 */
export function buildInboxItems(
  transactions: InboxTransaction[],
  // No consolidado (RF9.4.4) NÃO agrupamos parcelas — cada parcela é uma linha
  // no seu mês; só o agrupamento de relacionadas/estornos (RF23/RF10.6) vale.
  { groupInstallments = true }: { groupInstallments?: boolean } = {},
): InboxItem[] {
  const { anchors, consumed } = resolveRelatedGroups(transactions)
  const items: InboxItem[] = []
  const groupIndex = new Map<string, number>() // installment_group_id → posição

  for (const t of transactions) {
    // Satélite já absorvido por um grupo de relacionadas — não renderiza avulso.
    if (consumed.has(t.id) && !anchors.has(t.id)) continue

    // Âncora de relacionadas presente com seus satélites (e netos-irmãos).
    const group = anchors.get(t.id)
    if (group) {
      const members = [t, ...group.members]
      items.push({
        kind: 'related',
        key: t.id,
        anchor: t,
        satellites: group.members,
        members,
        memberIds: members.map((m) => m.id),
        satelliteTypes: group.types,
        signedTotalCents: members.reduce((sum, m) => sum + signedCents(m), 0),
      })
      continue
    }

    if (!groupInstallments || !isInstallment(t)) {
      items.push({ kind: 'single', transaction: t })
      continue
    }

    const groupId = t.installment_group_id as string
    const at = groupIndex.get(groupId)
    if (at == null) {
      groupIndex.set(groupId, items.length)
      items.push({
        kind: 'installment',
        groupId,
        parcels: [t],
        total: t.amount_cents,
        representative: t,
        purchaseDate: t.occurred_at, // recomputado abaixo
      })
    } else {
      const item = items[at]
      if (item.kind !== 'installment') continue
      item.parcels.push(t)
      item.total += t.amount_cents
    }
  }

  // Por grupo de parcelamento: ordena parcelas por número, escolhe o representante
  // (com título primeiro) e fixa a data da compra (purchase_date; fallback = 1ª).
  for (const item of items) {
    if (item.kind !== 'installment') continue
    item.parcels.sort((a, b) => (a.installment_number ?? 0) - (b.installment_number ?? 0))
    item.representative = item.parcels.find((p) => p.improved_title) ?? item.parcels[0]
    item.purchaseDate =
      item.representative.purchase_date ??
      item.parcels.reduce((min, p) => (p.occurred_at < min ? p.occurred_at : min), item.parcels[0].occurred_at)
  }

  // Ordena a lista por data desc pra o grupo não flutuar pra posição da sua
  // transação mais recente. Empate mantém a ordem que veio do backend.
  return items.sort((a, b) => itemDate(b).localeCompare(itemDate(a)))
}
