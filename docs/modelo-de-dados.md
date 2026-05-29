# Controle Financeiro — Modelo de Dados (v1.0)

## Contexto

Doc complementar ao PRD v1.2 e Requisitos Técnicos v1.1. Define as entidades do banco PostgreSQL, suas relações, constraints e índices. Serve de base para gerar as migrations Rails na fase de implementação — esta versão é o **design**, não a migration final.

Cada entidade é justificada pelos RFs que ela atende. Quando algum RF estiver implícito numa regra de domínio que vive em código (não no schema), está anotado.

## Princípios

1. **Postgres-first**: aproveitar `uuid`, `jsonb`, `daterange`, constraints exclusivos onde fizer sentido.
2. **UUIDs como chaves primárias** (não bigint sequencial) — não revela cardinalidade e facilita futuros merges entre workspaces.
3. **Workspace-scoping**: toda entidade de domínio carrega `workspace_id` (NOT NULL, indexada). Queries de aplicação sempre escopadas.
4. **Money em centavos (integer)** — evita imprecisão de float/decimal.
5. **Naming snake_case**, padrão Rails/Postgres.
6. **`created_at` e `updated_at`** em todas as tabelas (Rails default).
7. **Audit onde importa, hard delete onde não**: histórico granular em `TransactionEdit`; tags/categorias sem uso podem ser deletadas duro.

## Visão geral das entidades

```
User —< WorkspaceMembership >— Workspace
                                  |
                                  +— Account —< BankConnection
                                  |     |
                                  |     +— Transaction —< TransactionTag >— Tag
                                  |            |                           |
                                  |            +— TransactionEdit          +—< CategoryTag >— Category
                                  |            +— children (self-ref split)
                                  |            +— TransactionRefund (self-ref)
                                  |            +— InternalTransfer
                                  |
                                  +— Budget (— BudgetCompositeTag — Tag)
                                  +— Recurrence
                                  +— AiLearnedRule
                                  +— ManualRule
                                  +— Import
                                  +— Notification
```

## Entidades

### `users`
Pessoa física que acessa o sistema. Login via Google OAuth.

| coluna | tipo | constraints | notas |
|---|---|---|---|
| id | uuid | PK, default gen_random_uuid() | |
| email | citext | UNIQUE NOT NULL | citext = case-insensitive |
| google_uid | string | UNIQUE NOT NULL | sub do Google OIDC |
| name | string | NOT NULL | |
| avatar_url | string | | |
| created_at, updated_at | timestamp | | |

**RFs**: RF16.1.

### `workspaces`
Espaço financeiro compartilhado.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| name | string | NOT NULL |
| created_by_user_id | uuid | FK → users.id NOT NULL |
| created_at, updated_at | timestamp | |

**RFs**: RF16.2.

### `workspace_memberships`
Vínculo N:N entre usuário e workspace.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | FK → users.id NOT NULL |
| workspace_id | uuid | FK → workspaces.id NOT NULL |
| role | enum | NOT NULL default 'editor' |
| joined_at | timestamp | NOT NULL default now() |
| created_at, updated_at | timestamp | |

**Constraints**: UNIQUE (user_id, workspace_id).
**Enum role**: `editor` (preparado para `viewer` no futuro).
**RFs**: RF16.3 (convite por email já cadastrado), RF16.4 (editor pleno).

### `accounts`
Conta corrente ou cartão de crédito.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL, indexed |
| owner_membership_id | uuid | FK → workspace_memberships.id NOT NULL |
| name | string | NOT NULL — rótulo do usuário (ex.: "Nubank CC do Kaleb") |
| kind | enum | NOT NULL |
| institution | enum | NOT NULL |
| external_id | string | NULL — id da conta no agregador (Pluggy) |
| currency | char(3) | NOT NULL default 'BRL' |
| created_at, updated_at | timestamp | |

**Enum kind**: `checking`, `credit_card`.
**Enum institution**: `nubank`, `inter`, `itau`, `santander`, `bb`, `manual` (extensível).
**RFs**: RF1.1, RF1.2, RF12 (origem "Externo/Dinheiro" → `institution='manual'`).

### `bank_connections`
Conexão via agregador (Pluggy) para sync automática.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| owner_membership_id | uuid | FK NOT NULL — quem conectou (workspace_memberships) |
| provider | enum | NOT NULL default 'pluggy' |
| external_connection_id | string | NOT NULL — unique por (provider, external_connection_id) |
| credentials_ref | string | NULL — chave em vault/Rails credentials, não o segredo direto |
| status | enum | NOT NULL default 'connected' |
| error_message | text | NULL |
| sync_history_since | date | NOT NULL — RF1.7 histórico inicial configurável |
| last_sync_at | timestamp | NULL |
| next_sync_at | timestamp | NULL — próxima sync agendada (RF21.2) |
| last_sync_created_count | integer | NOT NULL default 0 — contadores da última sync (RF21.2) |
| last_sync_duplicate_count | integer | NOT NULL default 0 |
| last_sync_error_count | integer | NOT NULL default 0 |
| last_sync_duration_seconds | integer | NULL |
| created_at, updated_at | timestamp | |

**Enum provider**: `pluggy`, `manual`.
**Enum status**: `connected`, `syncing`, `expired`, `error`, `disconnected` (check constraint).
**RFs**: RF1.3–RF1.7, RF21.

> Em `after_update_commit`, mudanças em `status`/`last_sync_at` disparam broadcast
> no `BankConnectionsChannel` (Action Cable) pro painel de sync (RF21.3).

### `bank_connection_syncs`
Histórico de execuções de sync (RF21.7 — últimas N por conexão). O `Sync` grava
uma linha por run, em sucesso ou erro.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| bank_connection_id | uuid | FK NOT NULL |
| started_at | timestamp | NOT NULL |
| finished_at | timestamp | NULL |
| duration_seconds | integer | NULL |
| status | enum | NOT NULL — `success` \| `error` |
| created_count | integer | NOT NULL default 0 |
| duplicate_count | integer | NOT NULL default 0 |
| error_count | integer | NOT NULL default 0 |
| error_message | text | NULL |
| created_at, updated_at | timestamp | |

Índice: `(bank_connection_id, started_at)` — query "últimas N por conexão".
**RFs**: RF21.7.

### `transactions`
Coração do sistema: gasto, receita ou estorno. Vive no inbox ou consolidado.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL, indexed |
| account_id | uuid | FK NOT NULL, indexed |
| direction | enum | NOT NULL — `debit` (gasto) ou `credit` (receita/estorno) |
| amount_cents | integer | NOT NULL, sempre positivo |
| currency | char(3) | NOT NULL default 'BRL' |
| occurred_at | date | NOT NULL — RF14.2 data da compra (cartão) ou da transação (conta) |
| original_description | text | NOT NULL |
| improved_title | text | NULL — sugerido por AI ou editado pelo usuário |
| status | enum | NOT NULL default 'pending' |
| source | enum | NOT NULL |
| source_metadata | jsonb | NULL — payload bruto do Pluggy/CSV/OFX |
| created_by_membership_id | uuid | FK NULL — null se veio de sync automática |
| parent_transaction_id | uuid | FK → transactions.id NULL — para splits |
| ai_confidence | numeric(3,2) | NULL — 0.00 a 1.00 |
| installment_number | smallint | NULL — RF9.4, ex.: 3 |
| installment_total | smallint | NULL — RF9.4, ex.: 12 |
| installment_group_id | uuid | NULL — agrupa todas as parcelas de uma mesma compra |
| consolidated_at | timestamp | NULL — quando virou consolidated |
| rejected_at | timestamp | NULL — quando virou rejected |
| lock_version | integer | NOT NULL default 0 — otimista locking para edição concorrente |
| created_at, updated_at | timestamp | |

**Enum direction**: `debit`, `credit`.
**Enum status**: `pending` (inbox), `consolidated`, `rejected`, `split` (transação original que foi dividida).
**Enum source**: `automatic_sync`, `manual_import` (CSV/OFX), `manual_entry` (RF12), `installment_generated` (gerada por sistema a partir de uma compra parcelada).
**RFs**: RF2, RF4, RF7, RF9.4, RF12, RF14.

**Constraints CHECK**:
- `amount_cents > 0`
- `(installment_number IS NULL) = (installment_total IS NULL)`
- `installment_number BETWEEN 1 AND installment_total` quando preenchidos
- `(consolidated_at IS NOT NULL) = (status = 'consolidated')`

### `transaction_edits` ✅ implementado (RF4.3)
Histórico de alterações em uma transação. RF4.3 audit trail leve. (No model Ruby,
a associação pro lado da transação chama-se `txn` — `transaction` colide com AR.)

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| transaction_id | uuid | FK NOT NULL, indexed |
| edited_by_membership_id | uuid | FK NOT NULL |
| edited_at | timestamp | NOT NULL default now() |
| field_name | string | NOT NULL — ex.: 'improved_title', 'amount_cents', 'tags' |
| old_value | jsonb | — flexível para tipos diferentes |
| new_value | jsonb | |

**RFs**: RF4.3.

### `tags` ✅ implementado (RF5 slice 1)
Etiqueta livre aplicável a transações.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| name | citext | NOT NULL |
| color | string | NULL |
| icon | string | NULL |
| created_at, updated_at | timestamp | |

**Constraints**: UNIQUE (workspace_id, name).
**RFs**: RF5.

### `transaction_tags` ✅ implementado (RF5 slice 1)
M:N entre transação e tag. (No model Ruby, a associação pro lado da transação
chama-se `txn` — `transaction` colide com método interno do ActiveRecord.)

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| transaction_id | uuid | FK NOT NULL |
| tag_id | uuid | FK NOT NULL |

**Constraints**: UNIQUE (transaction_id, tag_id).
**RFs**: RF5.2.

### `categories` ✅ implementado (RF6)
Agregador de tags (RF6).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| name | citext | NOT NULL |
| color | string | NULL |
| icon | string | NULL |
| created_at, updated_at | timestamp | |

**Constraints**: UNIQUE (workspace_id, name).
**RFs**: RF6.

### `category_tags` ✅ implementado (RF6)
M:N entre categoria e tag (RF6.2: uma tag em N categorias).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| category_id | uuid | FK NOT NULL |
| tag_id | uuid | FK NOT NULL |

**Constraints**: UNIQUE (category_id, tag_id).
**RFs**: RF6.2, RF6.6 (não-duplicação é regra de **query**, não de schema).

### `budgets`
Teto mensal por tag, categoria ou composto.

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| name | string | NOT NULL |
| kind | enum | NOT NULL |
| target_tag_id | uuid | FK NULL |
| target_category_id | uuid | FK NULL |
| monthly_limit_cents | integer | NOT NULL |
| starts_on | date | NULL — quando o teto entra em vigor |
| ends_on | date | NULL — para orçamento temporário |
| alert_threshold_pct | smallint | NOT NULL default 80 |
| enabled | boolean | NOT NULL default true |
| created_at, updated_at | timestamp | |

**Enum kind**: `tag`, `category`, `composite`.
**Constraints CHECK**:
- `(kind='tag') = (target_tag_id IS NOT NULL AND target_category_id IS NULL)`
- `(kind='category') = (target_category_id IS NOT NULL AND target_tag_id IS NULL)`
- `(kind='composite') = (target_tag_id IS NULL AND target_category_id IS NULL)`
- `monthly_limit_cents > 0`
**RFs**: RF8.

### `budget_composite_tags`
M:N para orçamentos compostos (RF8.3).

| coluna | tipo | constraints |
|---|---|---|
| budget_id | uuid | FK NOT NULL |
| tag_id | uuid | FK NOT NULL |

**Constraints**: PRIMARY KEY (budget_id, tag_id).

### `recurrences`
Padrão recorrente detectado ou cadastrado manualmente (RF9).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| account_id | uuid | FK NOT NULL |
| descriptor_pattern | string | NOT NULL |
| expected_amount_cents | integer | NULL |
| amount_tolerance_pct | numeric(4,2) | NOT NULL default 5.00 |
| cadence | enum | NOT NULL |
| next_expected_at | date | NULL |
| status | enum | NOT NULL default 'active' |
| source | enum | NOT NULL |
| created_at, updated_at | timestamp | |

**Enum cadence**: `weekly`, `monthly`, `yearly`, `custom`.
**Enum status**: `active`, `paused`, `cancelled`.
**Enum source**: `detected`, `manual`.
**RFs**: RF9.1, RF9.2, RF9.6.

### `transaction_refunds`
Vínculo de estorno a gasto original (RF10).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| refund_transaction_id | uuid | FK NOT NULL UNIQUE — credit |
| refunded_transaction_id | uuid | FK NOT NULL — debit |
| confirmed_at | timestamp | NOT NULL |
| confirmed_by_membership_id | uuid | FK NOT NULL |
| created_at | timestamp | |

**Constraints**: workspace_id de ambas as transações deve coincidir (validação em service, mais barato que via DB).
**RFs**: RF10. Importante: o valor consolidado efetivo do gasto original é calculado por query (`amount - SUM(refunds.amount)`), não mutado em coluna.

### `internal_transfers`
Vínculo de transferência interna (RF11).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| debit_transaction_id | uuid | FK NOT NULL UNIQUE |
| credit_transaction_id | uuid | FK NOT NULL UNIQUE |
| detected_at | timestamp | NOT NULL |
| confirmed_by_membership_id | uuid | FK NULL — null se confirmado automaticamente |
| created_at | timestamp | |

**RFs**: RF11.

### `ai_learned_rules`
Regra aprendida a partir de correção do usuário (RF3.2).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| descriptor_pattern | string | NOT NULL |
| match_type | enum | NOT NULL |
| suggested_title | string | NULL |
| suggested_tag_ids | uuid[] | NULL — array de tag ids |
| suggested_category_id | uuid | FK NULL |
| learned_from_transaction_id | uuid | FK NULL — rastreabilidade |
| hits | integer | NOT NULL default 0 — quantas vezes a regra pegou |
| last_used_at | timestamp | NULL |
| created_at, updated_at | timestamp | |

**Enum match_type**: `exact`, `contains`, `regex`.
**RFs**: RF3.2.

### `manual_rules`
Regra explicitamente criada pelo usuário (RF3.3).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| name | string | NOT NULL |
| descriptor_pattern | string | NOT NULL |
| match_type | enum | NOT NULL |
| assign_tag_ids | uuid[] | NULL |
| assign_category_id | uuid | FK NULL |
| override_title | string | NULL |
| priority | integer | NOT NULL default 100 — menor = mais prioritária |
| enabled | boolean | NOT NULL default true |
| created_at, updated_at | timestamp | |

**Enum match_type**: `exact`, `contains`, `regex`.
**RFs**: RF3.3.

### `imports`
Registro de cada upload de arquivo (RF20).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| uploaded_by_membership_id | uuid | FK NOT NULL |
| account_id | uuid | FK NULL — opcional, usuário associa pós-parse |
| filename | string | NOT NULL |
| format | enum | NOT NULL |
| file_size_bytes | integer | NOT NULL |
| file_blob_ref | string | NOT NULL — Active Storage key |
| status | enum | NOT NULL default 'pending' |
| created_count | integer | NOT NULL default 0 |
| duplicate_count | integer | NOT NULL default 0 |
| error_count | integer | NOT NULL default 0 |
| error_log | jsonb | NULL — array de {row, message} |
| started_at | timestamp | NULL |
| completed_at | timestamp | NULL |
| created_at, updated_at | timestamp | |

**Enum format**: `csv`, `ofx`.
**Enum status**: `pending`, `processing`, `completed`, `failed`.
**RFs**: RF20.

### `notifications`
Notificação in-app (RF17).

| coluna | tipo | constraints |
|---|---|---|
| id | uuid | PK |
| workspace_id | uuid | FK NOT NULL |
| recipient_membership_id | uuid | FK NULL — null = broadcast pro workspace |
| kind | enum | NOT NULL |
| payload | jsonb | NOT NULL |
| read_at | timestamp | NULL |
| created_at | timestamp | |

**Enum kind**: `inbox_new`, `budget_warning`, `budget_exceeded`, `recurrent_missed`, `sync_failed`, `import_completed`.
**RFs**: RF17.

## Regras de invariante (lógicas, não DDL)

1. **Split**: `SUM(child.amount_cents WHERE parent_transaction_id = X) = parent.amount_cents`. Validado em `Transactions::SplitService`. Pai fica em `status='split'` e some das totalizações.
2. **Refund**: `refund.direction='credit' AND refunded.direction='debit'`. Workspace iguais. `refund.amount_cents <= refunded.amount_cents` (maioria dos casos; estornos parciais permitidos).
3. **Internal transfer**: `debit.amount_cents = credit.amount_cents`. `|debit.occurred_at - credit.occurred_at| <= 3 dias` (configurável).
4. **RF6.6 não-duplicação**: queries de "total do período" usam `SELECT DISTINCT transaction_id` antes de somar; queries por categoria fazem join + sinalizam quando há transações em múltiplas categorias.
5. **Inbox não conta**: relatórios e orçamentos sempre filtram `status='consolidated'`.

## Índices críticos

| Tabela | Índice | Razão |
|---|---|---|
| transactions | (workspace_id, status, occurred_at DESC) | listing por inbox/consolidados ordenado por data |
| transactions | (workspace_id, occurred_at) | relatórios por período |
| transactions | (account_id, occurred_at) | quebra por conta/cartão |
| transactions | (parent_transaction_id) | encontrar children de split |
| transactions | (installment_group_id) | mostrar parcelas de uma compra |
| transaction_tags | (transaction_id, tag_id) UNIQUE | join + dedup |
| transaction_tags | (tag_id) | relatório por tag |
| category_tags | (tag_id) | RF6.6: dado um gasto com tag X, em quais categorias ele entra |
| ai_learned_rules | (workspace_id, descriptor_pattern) | match na pré-categorização |
| manual_rules | (workspace_id, enabled, priority) | aplicação ordenada de regras |
| recurrences | (workspace_id, next_expected_at) | aviso "próximos N dias" |
| notifications | (recipient_membership_id, read_at) | inbox de notificações não lidas |

## Decisões e justificativas

- **UUIDs > bigint**: pequena dor (índice maior), grande ganho (segurança + portabilidade entre workspaces).
- **citext em email/name de tags/categorias**: case-insensitive comparison nativo do Postgres. Evita lógica `LOWER()` em queries.
- **Money em centavos (integer)**: zero ambiguidade. Conversão de exibição fica no app.
- **JSONB em source_metadata**: snapshot do payload bruto do Pluggy/CSV/OFX. Útil para debug, reprocessamento e prova de origem.
- **`lock_version` só em Transaction**: única tabela com edição realmente concorrente (você e esposa podendo mexer no mesmo gasto). Outras dispensam.
- **Soft delete via `status='rejected'`**: mantém o registro para evitar reimport pelo Pluggy/parser. Hard delete vira opção raro no UI (RF2.3).
- **Currency em todas as money-tables**: BRL fixo no MVP. Preparado pra multi-moeda sem migration de schema futura.

## Decisões finalizadas após revisão

| Tema | Decisão |
|---|---|
| Armazenamento de arquivos de import | **Active Storage** com backend S3-compatível apontando para Oracle Object Storage. Indireção limpa, padrão Rails. |
| Dedup de transações sync via Pluggy | Coluna **gerada `external_transaction_id`** extraída de `source_metadata` jsonb, com **unique index `(account_id, external_transaction_id)`**. GIN no jsonb fica de fora (overhead desnecessário). |
| Particionamento de `transactions` | **Out-of-scope** no MVP e provavelmente sempre. Volume estimado (2 usuários, ~50–200 tx/mês, ~10k em 5 anos) não justifica. |
| Versionamento de `ai_learned_rules` | **Sem histórico**. Regra é mutável; aprendizado é incremental. Event log futuro se algum dia precisar. |
| Modelagem de **fatura** do cartão | **Sem entidade física**. Fatura é objeto **derivado por query** (`transactions WHERE account.kind='credit_card' AND occurred_at IN <período>`), atendendo RF9.5. Reavaliar se faltar feature. |

## Próximos passos

1. Modelo de dados v1.0 fechado.
2. Próximo doc: setup do monorepo (estrutura, Dockerfile, migrations skeleton, etc.).
3. Depois: primeira fatia TDD.

## Validação

- Cada RF do PRD tem entidade(s) que o suporta — checagem cruzada entre tabela de mapeamento dos RFs (em `docs/requisitos-tecnicos.md`) e este modelo.
- Constraints físicas (NOT NULL, FK, UNIQUE, CHECK) protegem o que dá pra proteger no DB; o resto fica em services + testes.
- Índices cobrem as queries quentes (inbox, relatórios por período, agregação por tag/categoria).

**Status:** v1.1 — `bank_connections` alinhado à implementação (Fatias 4–5c):
`owner_membership_id`, contadores da última sync + `next_sync_at` (RF21.2),
enum status real (`connected/syncing/expired/error/disconnected`), `credentials_ref`
nullable, broadcast via Action Cable.

v1.0 — fechado após revisão das 5 decisões pendentes (Active Storage, dedup Pluggy, particionamento, versionamento AI, fatura derivada).
