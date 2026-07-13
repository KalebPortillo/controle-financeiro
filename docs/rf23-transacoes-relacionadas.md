# RF23 — Transações relacionadas (IOF, tarifas, estornos)

Status: **Fases 1–3 implementadas** (F1 em prod v0.24.0; F2+F3 2026-07-07).
Complementa PRD, `modelo-de-dados.md` e `contratos-api.md`.

- **Fase 1** — tabela + `TransactionLinks::DetectIof` (auto no sync) + `related` no
  serializer + seção "Relacionadas" no detalhe + `DELETE /transaction_links/:id` +
  backfill `transaction_links:detect_iof`. **Em prod.**
- **Fase 2** — agrupamento no inbox: âncora + satélites presentes viram um item
  único (`buildInboxItems` kind `related`; `RelatedGroupRow`/`RelatedGroupSheet`;
  overlay `?rel`). Aceitar/rejeitar o conjunto via bulk. Falta membro → não agrupa
  (cai na seção "Relacionadas").
- **Fase 3** — vínculo manual: `POST /transactions/:id/link { origin_id,
  relation_type }` (:id = satélite) + `GET .../link_candidates?q=`
  (`TransactionLinks::OriginCandidates`) + `LinkOriginSection` no detalhe. Sem
  detecção automática de tarifa/juros (não há âncora no extrato) — só manual.

## Problema

Uma compra gera transações satélites que hoje aparecem soltas no inbox e nos
consolidados: **IOF** de compra internacional (cobrança e devolução), estornos,
tarifas. O usuário quer:

1. **Agrupar** as relacionadas num único item quando estão **todas** juntas na
   lista (inbox), como já acontece com parcelas.
2. Quando **nem todas** estão na lista, **linkar** a transação relacionada nos
   detalhes (navegável), como já acontece com estornos.

## O que já existe (reaproveitar)

| mecanismo | modelo | superfície |
|---|---|---|
| Parcelas | `installment_group_id` (chave compartilhada) | agrupadas no inbox (`buildInboxItems`) |
| Estornos (RF10) | `TransactionRefund` (link débito↔crédito, confirmação humana) | `RefundSection` no detail |
| Transferências (RF11) | `InternalTransfer` (link débito↔crédito) | excluídas de relatórios |

RF23 **generaliza** esses padrões, sem migrar os existentes: estorno continua em
`TransactionRefund`; a view unificada "relacionadas" soma refunds + links novos.

## Decisões (2026-07-06)

- **Framework genérico**: `relation_type` cobre `iof | fee | interest | adjustment`.
  Estorno permanece em `TransactionRefund` e entra na view unificada.
- **Auto-link de confiança alta**: o sync detecta e **já vincula** o IOF à compra
  (`origin: automatic`, auto-confirmado); o usuário só **desfaz** se errar. Sem
  fricção — IOF é mecânico. Estorno segue manual (fluxo RF10). Tarifa/juros/ajuste:
  schema pronto, mas **vínculo manual** no começo (sem âncora clara no extrato).

## Modelo de dados

Nova tabela `transaction_links`:

| coluna | tipo | notas |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL, indexed |
| primary_transaction_id | uuid | FK→transactions — a **âncora** (a compra) |
| related_transaction_id | uuid | FK→transactions — IOF/tarifa/juros/ajuste |
| relation_type | enum | `iof \| fee \| interest \| adjustment` (check constraint) |
| origin | enum | `automatic \| manual` |
| confidence | numeric(3,2) | NULL — score da heurística |
| confirmed_by_membership_id | uuid | FK NULL — null = sugestão; preenchido = confirmado |
| created_at, updated_at | timestamp | |

**Constraints**: `UNIQUE (related_transaction_id, relation_type)` — um IOF pertence
a uma única compra. Índices: `(primary_transaction_id)`, `(workspace_id)`.

Model `TransactionLink` espelha validações de `TransactionRefund`: mesmo workspace,
ambas transações existem, não referencia a si mesma.

## Detecção automática — `TransactionLinks::Detect`

Roda ao fim de `BankConnections::Sync` (e num backfill task). **Calibrado com dados
reais de produção (2026-07-06)**:

### Sinais do IOF (Pluggy / `source_metadata`)
- **É IOF**: `original_description ILIKE '%iof%'` **OU**
  `creditCardMetadata.feeTypeAdditionalInfo == 'IOF_COMPRA_INTERNACIONAL'`.
- **Direção**:
  - `debit` = cobrança do IOF → âncora = a compra internacional.
    Descrição genérica ("IOF de compra internacional") ou com comerciante
    (`IOF de "Three Girls Bakery"`).
  - `credit` = IOF devolvido ("IOF de volta de X" / "Estorno de IOF de compra
    internacional") → âncora = a compra (normalmente também estornada).

### Ancoragem contra compras estrangeiras
Candidatas: mesmo `account_id`, mesmo cartão (`creditCardMetadata.cardNumber`),
`currencyCode != BRL` (moeda estrangeira), `occurred_at ∈ [iof_date − 5, iof_date]`.
Score combinado (por data só dá 14–23 candidatas; os sinais abaixo colapsam pra ~1):

1. **Nome do comerciante** extraído da descrição do IOF (após "IOF de"/"IOF de
   volta de", sem aspas) casando com a descrição da compra → sinal forte.
2. **Razão de valor**: `iof_amount / purchase_amount ≈ 3,38%` (alíquota atual;
   tolerar faixa ~2–7% pra cobrir histórico 6,38%→3,38%). Ex.: IOF R$1,08 →
   compra ≈ R$31,95.
3. **Atribuição gulosa 1:1** por cartão/janela: cada compra estrangeira gera um
   IOF; consumir a compra ao casar, evitando dois IOFs na mesma compra.

Confiança **alta** (auto-confirma) quando o comerciante casa OU a razão de valor é
única na janela; senão fica como sugestão (`confirmed_by` null). Idempotente (o
`UNIQUE` protege re-sync).

> ⚠️ Anuidade aparece como `creditCardMetadata.feeType == 'ANNUAL_FEE'` no metadata,
> mas sem âncora clara — fica pra vínculo manual. `tarifa/anuidade/juros` não
> aparecem por descrição nos dados atuais.

## Backend — API

- Serializer de transação ganha `related: [...]` — **view unificada** somando
  `TransactionRefund` (recebidos/dado) + `TransactionLink` (âncora e relacionada),
  cada item `{ id, relation_type, direction, amount_cents, title, status,
  present_in_list }`. Preload no `index` pra evitar N+1 (padrão já usado lá).
- `POST /api/v1/transactions/:id/link { related_id, relation_type }` — vínculo manual.
- `DELETE /api/v1/transaction_links/:id` — desvincular (auto ou manual).

## Frontend

- **Detail sheet — seção "Vínculos"** (`LinksSection`, unificada 2026-07-13):
  uma seção só lista IOF/tarifa/juros/ajuste **e estornos** juntos (estorno é só
  mais um `relation_type: "refund"` na view), com resumo de valor efetivo quando o
  débito foi estornado; membros presentes na lista viram link `?tx=` navegável;
  ausentes abrem a transação (mesmo consolidada). Desvincular roteia por
  `link_kind` (`refund` → `DELETE /transaction_refunds/:id`; senão
  `/transaction_links/:id`). O picker de vincular oferece o chip **"Estorno"** ao
  lado dos demais (crédito → estorno via `/link_refund`; débito → satélite via
  `/link`). Substituiu as antigas `RefundSection` + `RelatedSection` +
  `LinkOriginSection`; armazenamento segue em duas tabelas.
- **Inbox — agrupamento** (`buildInboxItems`): novo passo colapsa âncora +
  relacionadas **presentes na lista** num item de grupo, reusando a UX do
  `InstallmentGroupSheet` (linha expansível; aceitar o grupo consolida todos).
  Se faltar algum membro, não agrupa — cai na seção "Relacionadas" do detail.

## Faseamento

1. **Tabela + `TransactionLinks::Detect` (IOF) + `related` no serializer +
   seção "Relacionadas" no detail + desvincular + backfill task.**
   Maior valor, menor risco. TDD: model, detecção (fixtures com metadata real),
   serializer, integração da rota, componente do detail.
2. **Agrupamento no inbox** + consolidação em grupo (aceitar/rejeitar o conjunto).
3. **Vínculo manual genérico** ("marcar como relacionada a…") + tarifas/juros.

## Aberto / a confirmar na implementação

- Alíquota do IOF muda por decreto — a faixa de tolerância (2–7%) evita hard-code;
  reavaliar se aparecerem falsos negativos.
- Estorno de compra internacional costuma vir junto do "IOF de volta": avaliar se
  a detecção liga os três (compra ↔ estorno ↔ IOF devolvido) num só grupo.
