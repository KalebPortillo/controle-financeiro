# Controle Financeiro — Contratos de API v1 (v1.2)

## Contexto

Doc complementar ao PRD v1.2, Requisitos Técnicos v1.1 e Modelo de Dados v0.1. Define a superfície de API que o frontend (Vite + React) consome e que terceiros (importações scripted, webhooks Pluggy) também acionam.

**Base URL**: `https://<hostname>/api/v1`.

## Convenções gerais

### Formato
- Request e response em **JSON** (UTF-8).
- `Content-Type: application/json` em todas as requisições com corpo.
- Datas em **ISO 8601** (`2026-05-25` para datas; `2026-05-25T14:30:00Z` para timestamps).
- Money sempre em **centavos** (`amount_cents: 12345` = R$ 123,45).
- IDs em **UUID v4** (string).

### Autenticação
- **Sessão server-side via cookie HTTP-only signed** (Rails session).
- Login inicia em `GET /api/v1/auth/google` → redirect Google → callback popula sessão.
- Frontend não armazena token; cookie acompanha automaticamente.
- Todas as rotas exceto `/auth/*` e `/health` exigem sessão válida.

### Workspace implícito
- Workspace ativo da sessão é **implícito** em todas as rotas — não vai na URL.
- Header `X-Workspace-Id` opcional para selecionar workspace quando o usuário pertence a múltiplos. Server-side, fica em sessão até trocar.
- Para trocar de workspace: `POST /api/v1/sessions/current/select_workspace { workspace_id }`.

### Paginação
- Parâmetros: `page` (1-based, default 1) e `per_page` (default 25, max 100).
- Response inclui objeto `pagination`:
  ```json
  { "pagination": { "current_page": 1, "per_page": 25, "total_pages": 4, "total_count": 87 } }
  ```

### Filtros e ordenação
- Filtros via query params (ex.: `?status=pending&account_id=...`).
- Ordenação via `sort` (ex.: `?sort=-occurred_at` para descendente, `?sort=occurred_at` para ascendente).

### Erros
Formato uniforme:
```json
{
  "error": {
    "code": "validation_failed",
    "message": "Amount must be greater than zero.",
    "details": [
      { "field": "amount_cents", "code": "greater_than", "value": 0 }
    ]
  }
}
```

**Status codes:**
| Código | Uso |
|---|---|
| 200 OK | sucesso com corpo |
| 201 Created | recurso criado |
| 204 No Content | sucesso sem corpo (delete, mark-read) |
| 400 Bad Request | JSON inválido, params malformados |
| 401 Unauthorized | sessão ausente/inválida |
| 403 Forbidden | sessão válida mas sem permissão (policy) |
| 404 Not Found | recurso inexistente ou fora do workspace |
| 409 Conflict | conflito de lock_version, duplicação |
| 422 Unprocessable Entity | regra de negócio quebrada |
| 500 Internal Server Error | erro inesperado (já vai pro Sentry) |

### Versionamento
- Versão na URL (`/api/v1/...`). Quebra de contrato → `v2`.
- Adições compatíveis (campos novos opcionais) **não** quebram versão.

### Concorrência
- Edição de `transactions` exige `lock_version` no body. Mismatch → **409 Conflict**.

## Endpoints por domínio

### Saúde
- `GET /api/v1/health` — smoke pós-deploy. Public. Retorna `{ "status": "ok", "version": "..." }`.

### Config (runtime)
- `GET /api/v1/app_config` — public. Config decidida por `RAILS_ENV` (runtime, não
  build), lida pelo frontend no boot. Como staging e produção rodam a mesma imagem,
  o que difere entre eles (ex.: sandbox do Pluggy) vem daqui.
  ```json
  { "environment": "staging", "pluggy": { "include_sandbox": true, "connector_ids": [2] } }
  ```
  - staging/dev → `include_sandbox: true`, `connector_ids: [2]` (só Pluggy Bank sandbox).
  - production → `include_sandbox: false`, `connector_ids: null` (todos os bancos reais).

### Sessão e auth (RF16.1)
- `GET  /api/v1/auth/google` — inicia OAuth (302 para Google).
- `GET  /api/v1/auth/google/callback` — Google callback, popula sessão, redirect para frontend.
- `GET  /api/v1/sessions/current` — info do usuário logado + workspaces a que pertence.
- `POST /api/v1/sessions/current/select_workspace` — body: `{ workspace_id }`.
- `DELETE /api/v1/sessions/current` — logout.

### Workspaces (RF16.2–16.5)
- `GET  /api/v1/workspaces` — workspaces do usuário.
- `POST /api/v1/workspaces` — criar. Body: `{ name }`.
- `GET  /api/v1/workspaces/:id` — detalhes.
- `PATCH /api/v1/workspaces/:id` — renomear.
- `GET  /api/v1/workspaces/:id/memberships` — listar membros.
- `POST /api/v1/workspaces/:id/memberships` — adicionar por email já cadastrado. Body: `{ email }`. 404 se email não cadastrado.
- `DELETE /api/v1/workspaces/:id/memberships/:membership_id` — remover.

### Accounts (RF1.1, RF1.2, RF12)
- `GET  /api/v1/accounts` — list. Filtros: `kind`, `institution`, `owner_membership_id`.
- `POST /api/v1/accounts` — criar (útil para `institution=manual`).
- `GET  /api/v1/accounts/:id`
- `PATCH /api/v1/accounts/:id` — rename, owner.
- `DELETE /api/v1/accounts/:id` — 422 se houver transactions.

### Bank Connections (RF1.3–RF1.7, RF21)
> Implementado nas Fatias 3a–5c. O schema abaixo reflete o serializer real
> (`BankConnections::Serializer`), compartilhado entre o REST e o broadcast do Cable.
- `POST /api/v1/bank_connections/connect_token` — gera o token curto-prazo que o
  widget Pluggy Connect usa no frontend. Retorna `{ "connect_token": "..." }`.
- `POST /api/v1/bank_connections` — body: `{ item_id: "...", history_since: "2026-01-01" }`.
  O widget roda no frontend; ao concluir, o frontend POSTa o `item_id` aqui. Cria a
  conexão (idempotente), popula accounts e dispara o sync inicial. 201 + `{ bank_connection }`.
- `GET  /api/v1/bank_connections` — list com payload enriquecido (RF21):
  ```json
  {
    "connections": [
      {
        "id": "...",
        "provider": "pluggy",
        "status": "connected",
        "error_message": null,
        "sync_history_since": "2026-01-01",
        "last_sync_at": "2026-05-26T06:00:00Z",
        "next_sync_at": "2026-05-27T06:00:00Z",
        "last_sync_created_count": 23,
        "last_sync_duplicate_count": 2,
        "last_sync_error_count": 0,
        "last_sync_duration_seconds": 14,
        "accounts": [
          { "id": "...", "name": "Nubank CC", "kind": "credit_card",
            "institution": "nubank", "institution_label": "Nubank", "currency": "BRL" }
        ]
      }
    ],
    "summary": { "total": 3, "connected": 2, "syncing": 0, "error": 1 }
  }
  ```
  (`summary.error` agrega `error` + `expired`.)
- `GET  /api/v1/bank_connections/:id` — detalhe individual (`{ bank_connection }`), mesmo schema.
- `POST /api/v1/bank_connections/:id/sync` — força sync agora (RF21.3). 202 + `{ bank_connection }` já com `status: "syncing"`. O avanço seguinte sobe via Action Cable.
- `POST /api/v1/bank_connections/sync_all` — dispara sync de todas as conexões do workspace (RF21.4). 202 + `{ enqueued: N }`.
- `POST /api/v1/bank_connections/:id/reconnect` — gera connect_token de reconexão (RF21.8). `{ "connect_token": "..." }`.
- `DELETE /api/v1/bank_connections/:id` — disconnect. 204.
- `GET /api/v1/bank_connections/:id/sync_history?limit=10` — últimas N execuções de sync (RF21.7), mais recentes primeiro. `limit` clamped a 1–50. Cada item:
  ```json
  { "id": "...", "started_at": "...", "finished_at": "...", "duration_seconds": 12,
    "status": "success", "created_count": 7, "duplicate_count": 2, "error_count": 0,
    "error_message": null }
  ```
  (`status`: `success` | `error`. Persistido em `bank_connection_syncs`, uma linha por run do `SyncJob`.)

**Canal Action Cable `BankConnectionsChannel`** (montado em `/cable`, auth por cookie de sessão) broadcasta `{ "event": "connection_updated", "bank_connection": {…} }` (mesmo schema acima) sempre que `status`/`last_sync_at` mudam — usado pelo painel `/contas` pra refletir progresso em tempo real sem polling. Escopado por `workspace_id` (subscribe valida membership).

### Webhooks (RF1, Fatia 5b)
- `POST /api/v1/webhooks/pluggy` — máquina→máquina (Pluggy → app). **Sem sessão**; autentica pelo header `X-Webhook-Secret` (contra `PLUGGY_WEBHOOK_SECRET`, compare constant-time). Eventos de sync (`item/updated`, `transactions/created|updated`) enfileiram `SyncJob`; eventos de erro (`item/error`, `item/login_error`) marcam a conexão como `error`; item desconhecido / evento ignorado → 200 (ack) sem efeito.

### Transactions — listagem e leitura (RF2, RF4, RF13)
> Inbox (RF2) e Gastos consolidados (RF4 slice 1) implementados sobre o mesmo
> endpoint via `status`. Tela de Gastos usa `status=consolidated&from&to` (mês).
- `GET /api/v1/transactions` — list, escopado no workspace. Retorna
  `{ transactions: [...], pending_count: N }` (RF2.4). Filtros implementados:
  `status` (default `pending`), `direction`, `account_id`, `from`, `to`, `q`
  (LIKE case-insensitive em description/title). Default sort: `-occurred_at`.
  ⏳ Filtros `tag_id`/`category_id`/`owner_membership_id` quando RF5/RF6 existirem.
  Item serializado: `id, account_id, account_name, account_kind, institution_label,
  account_institution_name, account_brand, account_last_digits, direction,
  amount_cents, currency, occurred_at, original_description, improved_title,
  ai_confidence, ai_suggestion, ai_status, status, source, installment_number,
  installment_total, installment_group_id, purchase_date, foreign_currency,
  lock_version, tags, effective_amount_cents, refund`. `amount_cents`/`currency`
  já vêm na MOEDA DA CONTA (BRL): compra em moeda estrangeira usa o valor
  convertido pelo banco (`amountInAccountCurrency` do Pluggy); `foreign_currency`
  traz a moeda original (ex.: "USD") só pra sinalizar no card, null em BRL. Fonte do gasto (RF2.7): `account_kind`
  (checking/credit_card), `account_institution_name` (nome real do banco/conector —
  ex.: "Nubank"), `account_brand` (bandeira do cartão), `account_last_digits`
  (4 últimos, só cartão). `installment_*` o parcelamento (RF9.4); `purchase_date`
  (RF9.4) = data da COMPRA `YYYY-MM-DD` (creditCardMetadata.purchaseDate do Pluggy,
  igual pra todas as parcelas; null fora de cartão) — o front exibe/ordena o
  parcelamento agregado por ela, já que `occurred_at` é a data de cada parcela.
- ⏳ `GET /api/v1/transactions/:id` — detalhe completo (com tags, category, splits, refund) — planejado.
- `GET /api/v1/transactions/:id/edits` — histórico de alterações (RF4.3), mais recente primeiro. Cada item: `{ id, field_name, old_value, new_value, edited_at, edited_by: { id, name } }`. Um registro por campo alterado (improved_title/amount_cents/occurred_at/tags) gravado a cada PATCH.
- `GET /api/v1/transactions/:id/source` (RF2.7) — payload cru do agregador para "exibir mais detalhes". `{ source, source_metadata }` (o JSON do Pluggy guardado na ingestão). Lazy — não vai na listagem. 404 cross-workspace.

### Transactions — escrita e workflow inbox (RF2.3, RF12)
- `PATCH /api/v1/transactions/:id` — edita `improved_title`, `amount_cents`,
  `occurred_at`, `tag_ids` (RF5, substitui). Body inclui `lock_version` (optimistic
  lock; conflito → 409 `stale_object`). Cada campo alterado vira um TransactionEdit
  (RF4.3). ⏳ `category_id` quando RF6 existir.
- `DELETE /api/v1/transactions/:id` — hard delete (RF2.3 remover). 204.
- `PATCH /api/v1/installment_groups/:id` (RF9.4.1) — `:id` = `installment_group_id`.
  Body `improved_title` e/ou `tag_ids`. Aplica a TODAS as parcelas do grupo no
  workspace (um TransactionEdit por parcela alterada); valor/data NÃO mudam.
  Resposta `{ updated_count, transactions: [{ id, improved_title, tags }] }`.
  Grupo desconhecido / de outro workspace → 404.
- `POST /api/v1/installment_groups/:id/consolidate` e `.../reject` (RF9.4.4) —
  aceita/rejeita TODAS as parcelas **pendentes** do grupo de uma vez (item
  agregado do inbox). Resposta `{ count }`. Grupo de outro workspace / inexistente → 404.
- `POST /api/v1/transactions/:id/consolidate` — accept (RF2.3). Seta `consolidated_at`.
- `POST /api/v1/transactions/:id/reject` — reject (RF2.3). Seta `rejected_at`.
- `POST /api/v1/transactions` — entrada manual (RF12). Body:
  ```json
  { "direction": "debit", "amount_cents": 8500, "occurred_at": "2026-05-20",
    "improved_title": "Almoço", "tag_ids": ["..."] }
  ```
  Status inicial = `consolidated` (RF12.3), `source=manual_entry`. Origem fixa na
  conta "Dinheiro / Externo" do workspace (criada sob demanda). 422 se inválido.
  ⏳ escolher conta bancária + `category_id` quando RF6 existir.
- ⏳ `POST /api/v1/transactions/:id/split` — planejado (RF2.3, depende de tags). Body:
- `POST /api/v1/transactions/:id/split` — body:
  ```json
  {
    "children": [
      { "amount_cents": 6000, "improved_title": "Comida", "tag_ids": ["t1"] },
      { "amount_cents": 2500, "improved_title": "Limpeza", "tag_ids": ["t2"] }
    ]
  }
  ```
  Soma dos children DEVE bater com pai. 422 caso contrário.
- `POST /api/v1/transactions/bulk_consolidate` — body: `{ ids: [...] }`.
- `POST /api/v1/transactions/bulk_tag` — body: `{ ids: [...], add_tag_ids: [...], remove_tag_ids: [...] }`.

### Refunds (RF10) — ✅ implementado
- `GET  /api/v1/transactions/:id/refund_candidates` — débitos candidatos a estorno de `:id` (credit): valor dentro de ±10%, janela de 90 dias, ainda não totalmente estornados; até 10, ordenados por proximidade de valor e recência.
- `POST /api/v1/transactions/:id/link_refund` — body: `{ refunded_transaction_id }`. `:id` deve ser credit. 422 se direções inconsistentes; 404 débito de outro workspace.
- `DELETE /api/v1/transaction_refunds/:id` — desfaz vínculo.
- O serializer de transação expõe `effective_amount_cents` (amount − Σ estornos, floor 0) e um bloco `refund` no gasto estornado. Nos relatórios (overview), o gasto desconta estornos e o crédito-estorno não conta como receita.

### Internal Transfers (RF11) — ✅ implementado
- `GET    /api/v1/internal_transfers` — pares do workspace p/ reconciliação. Cada item: `{ id, manual, detected_at, debit{...}, credit{...} }`.
- `POST   /api/v1/internal_transfers` — marcar manualmente. Body: `{ debit_transaction_id, credit_transaction_id }`. 422 direções/contas inválidas; 404 cross-workspace.
- `DELETE /api/v1/internal_transfers/:id` — desmarca.
- Detecção automática (`InternalTransfers::DetectJob`) roda ao fim do sync (fora do onboarding): débito ↔ crédito de mesmo valor em contas diferentes, janela de 3 dias. Pares (auto ou manual) saem dos totais de gasto/receita dos relatórios.

### Tags (RF5)
> Slice 1 implementada (criar/listar/autocomplete + aplicar na inbox). Edição,
> merge e delete protegido ficam pra fatia seguinte.
- `GET    /api/v1/tags` — list do workspace com `usage_count`. `?q=` filtra por prefixo (autocomplete, case-insensitive via citext). Retorna `{ tags: [{ id, name, color, icon, usage_count }] }`.
- `POST   /api/v1/tags` — body: `{ name, color, icon }`. 201 + `{ tag }`. Nome duplicado/vazio → 422.
- Aplicação em transações: `PATCH /api/v1/transactions/:id` aceita `tag_ids` (substitui o conjunto; ids de outro workspace são ignorados). O serializer da transação passa a incluir `tags: [{ id, name, color, icon }]`.
- `PATCH /api/v1/tags/:id` — edita `name`/`color`/`icon`. Nome duplicado → 422.
- `DELETE /api/v1/tags/:id` — 204 se não usada; **422 `tag_in_use`** se aplicada a alguma transação (orienta merge).
- `POST  /api/v1/tags/:id/merge` — `{ into_tag_id }`. Move as relações pro destino (sem duplicar, respeitando o unique) e apaga a origem. Destino de outro workspace → 404.

### Tags sugeridas pela IA (RF3/RF22)
Catálogo separado das tags reais. A IA grava sugestões aqui (`pending`); só viram `Tag`
de verdade no aceite. Ver tabela `suggested_tags` no modelo de dados.
- `GET    /api/v1/suggested_tags` — pendentes do workspace, mais relevantes (maior `coverage`) primeiro. Retorna `{ suggested_tags: [{ id, name, rationale, coverage, source, status }] }`.
- `POST   /api/v1/suggested_tags/:id/accept` — promove a sugestão a `Tag` real (reaproveita uma tag de mesmo nome se já existir) e marca `accepted`. Body opcional `{ transaction_id }` aplica a nova tag àquela transação (caminho do chip fantasma da inbox). Retorna `{ tag: { id, name, color, icon } }`. 404 cross-workspace.
- `DELETE /api/v1/suggested_tags/:id` — recusa a sugestão (status `dismissed`). 204.

### Categorias sugeridas pela IA (RF22, 2ª análise)
Catálogo separado das categorias reais. Gerado **on-demand** na tela de Categorias
(RF6.7): o `AiSuggestion::SuggestCategoriesJob` pede à IA categorias novas a partir
das tags consolidadas, excluindo as já existentes (máx 10). Ver tabela
`suggested_categories` no modelo.
- `POST   /api/v1/suggested_categories/generate` — limpa o `ai_last_error` e enfileira o job (assíncrono). `202`.
- `GET    /api/v1/suggested_categories` — pendentes do workspace. Retorna `{ suggested_categories: [{ id, name, tag_names, status }], ai_error: {reason, message, at}|null }`. A UI pollar até as sugestões chegarem.
- `POST   /api/v1/suggested_categories/:id/accept` — cria a `Category` real (reaproveita uma de mesmo nome) e associa as tags por nome (escopadas ao workspace); marca `accepted`. Retorna `{ category: { id, name, color, tags: [...] } }`. 404 cross-workspace.
- `DELETE /api/v1/suggested_categories/:id` — recusa (status `dismissed`). 204.

### Categories (RF6) — implementado (gestão + sugestão de tags)
- `GET    /api/v1/categories` — list. Resposta `{ categories: [{ id, name, color, icon, tags: [...], tag_suggestions: [{ id, name, color }] }], ai_error: {...}|null }`. `tag_suggestions` são as tags pendentes sugeridas (o `id` é o da TAG).
- `POST   /api/v1/categories` — body: `{ name, color, icon, tag_ids }`. Nome duplicado → 422.
- `PATCH  /api/v1/categories/:id` — renomeia/cor + `tag_ids` (substitui o conjunto; ids de outro workspace ignorados).
- `DELETE /api/v1/categories/:id` — 204.
- `POST   /api/v1/categories/:id/merge` — `{ into_category_id }`. Move as tags pro destino (sem duplicar) e apaga a origem.
- `POST   /api/v1/categories/:id/suggest_tags` — RF6.8: limpa `ai_last_error` e enfileira `Categories::SuggestTagsJob` (sugere tags consolidadas faltantes via IA). `202`.
- `POST   /api/v1/categories/:id/tag_suggestions/:tag_id/accept` — adiciona a tag à categoria e marca a sugestão `accepted`. Retorna `{ category: {...} }`. 404 se a sugestão/categoria não existir no workspace.
- `DELETE /api/v1/categories/:id/tag_suggestions/:tag_id` — recusa (dismissed). 204.
- ⏳ `PUT /api/v1/categories/:id/tags` — coberto por PATCH com `tag_ids`; endpoint dedicado não implementado.

### Budgets (RF8)
- `GET    /api/v1/budgets?period=current_month` — list com progresso embutido.
- `POST   /api/v1/budgets` — body:
  ```json
  {
    "name": "Mercado",
    "kind": "tag",
    "target_tag_id": "...",
    "monthly_limit_cents": 80000,
    "alert_threshold_pct": 80
  }
  ```
  Para `kind=composite`, enviar `composite_tag_ids: [...]` no lugar dos targets.
- `GET    /api/v1/budgets/:id?period=...` — progresso detalhado:
  ```json
  {
    "id": "...",
    "name": "Mercado",
    "kind": "tag",
    "monthly_limit_cents": 80000,
    "current_spent_cents": 42300,
    "current_pct": 52.9,
    "projected_end_of_period_cents": 75000,
    "alert_state": "ok",
    "transactions_count": 14
  }
  ```
- `PATCH  /api/v1/budgets/:id`
- `DELETE /api/v1/budgets/:id`

### Recurrences (RF9)
- `GET    /api/v1/recurrences`
- `POST   /api/v1/recurrences` — manual.
- `PATCH  /api/v1/recurrences/:id`
- `DELETE /api/v1/recurrences/:id`
- `GET    /api/v1/recurrences/upcoming?days=15` — vencimentos previstos (RF9.3).
- `GET    /api/v1/recurrences/:id/missed` — recorrentes esperadas que não chegaram (RF9.6).

### Imports (RF20) — ✅ CSV implementado (OFX pendente)
- `POST   /api/v1/imports` — `multipart/form-data` com `file`, `format`, `account_id` opcional. Resposta 202 com `id` e `status: 'pending'`.
- `GET    /api/v1/imports` — histórico.
- `GET    /api/v1/imports/:id` — status + resultado:
  ```json
  {
    "id": "...",
    "filename": "extrato-2026-04.csv",
    "format": "csv",
    "status": "completed",
    "created_count": 47,
    "duplicate_count": 8,
    "error_count": 1,
    "error_log": [{ "row": 32, "message": "Invalid date format" }]
  }
  ```

### Rules (RF3.3 e RF3.2)
- `GET    /api/v1/manual_rules` — RF3.3, futuro.
- `POST   /api/v1/manual_rules` — RF3.3, futuro.
- `PATCH  /api/v1/manual_rules/:id` — RF3.3, futuro.
- `DELETE /api/v1/manual_rules/:id` — RF3.3, futuro.
- `GET    /api/v1/ai_learned_rules` — ver regras aprendidas. Retorna:
  ```json
  {
    "ai_learned_rules": [
      {
        "id": "uuid",
        "descriptor_pattern": "ifood restaurante xyz",
        "improved_title": "iFood",
        "tag_ids": ["uuid"],
        "match_count": 7,
        "last_seen_at": "2026-05-29T18:00:00Z"
      }
    ]
  }
  ```
- `DELETE /api/v1/ai_learned_rules/:id` — esquecer regra aprendida.

### Reanalisar inbox com IA (RF3.5)
- `POST /api/v1/transactions/reanalyze` — enfileira `AiSuggestion::ReanalyzeJob`
  para todas as transações `pending` elegíveis (sem `improved_title`, com
  `ai_confidence <= 0.4`, ou sem tags). O job processa em lotes de 25
  (`BatchSuggestJob`). Resposta `202 Accepted`:
  ```json
  { "enqueued": true, "pending_count": 47 }
  ```
  Rate-limited a 5 req/min/IP.

### Progresso da análise IA
- `GET /api/v1/transactions/analysis_progress` — progresso **real** da análise em
  lote, por **estado explícito** de cada transação (`ai_status`): `queued`
  (aguardando), `analyzed` (a IA rodou — com ou sem sugestão), `failed` (a IA não
  conseguiu; NÃO está aguardando). `done` = não há mais ninguém **aguardando**
  (`awaiting == 0`) — gastos `failed` **não travam** o progresso. Usado pela barra
  da inbox (poll ~1,5s até `done`). `error` traz o último erro de IA não-recuperável
  do workspace (camada de feedback) ou `null`. `200 OK`:
  ```json
  { "total": 120, "analyzed": 110, "failed": 7, "awaiting": 3, "done": false,
    "error": { "reason": "unavailable", "message": "Serviço de IA indisponível no momento.", "at": "2026-06-07T12:00:00Z" } }
  ```
  `reason`: `quota` (créditos esgotados, permanente) | `daily` (limite diário do
  free tier) | `rate_limit` (por minuto) | `unavailable` (5xx/rede) | `error`. A
  inbox mostra a barra enquanto `awaiting>0`; quando `awaiting==0 && failed>0`,
  um aviso "N gastos não foram analisados" + "Tentar de novo" (reanalyze re-enfileira
  os `failed`). Cada transação `failed` aparece com um chip "não analisado"
  (serializer expõe `ai_status`).

### Reports (RF13)
- `GET /api/v1/reports/overview?period=current_month` — totals + comparativo:
  ```json
  {
    "period": { "from": "2026-05-01", "to": "2026-05-31" },
    "income_cents": 950000,
    "expense_cents": 612300,
    "balance_cents": 337700,
    "top_tags": [{ "tag_id": "...", "name": "Mercado", "amount_cents": 82000 }],
    "top_categories": [{ "category_id": "...", "name": "Alimentação", "amount_cents": 145000 }],
    "previous_period_comparison": {
      "income_delta_pct": 2.1,
      "expense_delta_pct": -4.3
    }
  }
  ```
- `GET /api/v1/reports/by_tag?from=...&to=...` — agregação. Cada item inclui `transactions_count` e `unique_transactions_count` (para sinalizar overlap quando filtrado por categoria).
- `GET /api/v1/reports/by_category?from=...&to=...` — RF6.6 explícito:
  ```json
  {
    "categories": [
      { "category_id": "...", "name": "Alimentação", "amount_cents": 145000, "shared_with_other_categories_count": 3 }
    ],
    "total_distinct_transactions_amount_cents": 612300,
    "sum_of_categories_amount_cents": 718200,
    "overlap_present": true
  }
  ```
  Frontend usa `overlap_present` para sinalizar visualmente que a soma > total (RF6.6).
- `GET /api/v1/reports/monthly_evolution?months=12` — array por mês.

### Onboarding (RF22)
Fluxo guiado de 3 passos para o dono do workspace, na primeira vez.
Apenas o `created_by_user` do workspace tem acesso — convidados recebem `403`.

- `GET /api/v1/onboarding` — estado atual:
  ```json
  {
    "status": "not_started | connecting | analyzing | tagging | categorizing | completed | skipped",
    "current_step": 1,
    "started_at": "2026-05-29T20:00:00Z",
    "completed_at": null,
    "analysis_error": { "reason": "quota", "message": "O limite do serviço de IA foi atingido.", "at": "2026-06-05T20:00:00Z" },
    "has_sync_finished": true,
    "suggested_tags":       [{ "name": "Mercado",  "rationale": "8 transações em mercados", "coverage": 8 }],
    "suggested_categories": [{ "name": "Alimentação", "tag_names": ["Mercado","Padaria"] }],
    "accepted_tag_ids":     ["uuid"],
    "accepted_category_ids":["uuid"]
  }
  ```
  `analysis_error` é `null` quando não há erro de IA pendente; quando preenchido,
  o passo de análise mostra um card amigável com "Continuar manualmente" (avança
  `analyzing → tagging`). Entrar em `analyzing` e `reanalyze` limpam o erro.
- `POST   /api/v1/onboarding/start` — entra em `connecting`. Idempotente (estado atual avança naturalmente). `400` se já completou ou pulou.
- `POST   /api/v1/onboarding/skip` — marca como `skipped`. Pode ser chamado em qualquer estado anterior a `completed`. Sem body.
- `POST   /api/v1/onboarding/advance` — transição idempotente para o próximo passo válido baseado no estado atual. Útil quando a UI quer forçar avançar (ex: pular passo 2 sem aceitar tags). Body opcional `{ to: "categorizing" | "completed" }` para forçar destino.
- `POST   /api/v1/onboarding/tags` — body:
  ```json
  { "accepted": [{ "name": "Mercado" }, { "name": "Comida fora" }] }
  ```
  Cria as tags (find_or_create_by por nome no workspace), persiste em `accepted_tag_ids`, transiciona para `categorizing`. Retorna o `onboarding_state` atualizado + os ids das tags criadas.
- `POST   /api/v1/onboarding/categories` — body:
  ```json
  { "accepted": [{ "name": "Alimentação", "tag_ids": ["uuid", "uuid"] }] }
  ```
  Cria as categorias, associa às tags informadas, persiste em `accepted_category_ids`, transiciona para `completed` e enfileira `AiSuggestion::ReanalyzeJob` para o workspace.
- `GET    /api/v1/onboarding/suggestions/tags?offset=10` — paginação do array `suggested_tags`. Retorna `{ tags: [...], has_more: bool }`.
- `GET    /api/v1/onboarding/suggestions/categories?offset=10` — idem para categorias.
- `POST   /api/v1/onboarding/restart_additive` — RF22.10 (botão "Refazer onboarding com IA" em Mais). Enfileira novo `Onboarding::AnalyzeJob` com `mode: "additive"`. Não muda o `status` (continua `completed`). UI mostra modal de revisão quando as sugestões ficam prontas.

`GET /api/v1/sessions/current` passa a incluir `onboarding_state` (resumido — só `status` e `current_step`) do workspace ativo, para o frontend decidir se redireciona para `/onboarding` no boot.

### Notifications (RF17) — implementado
- `GET    /api/v1/notifications?unread=true` → `{ notifications: [{ id, kind, payload, read_at, created_at }], unread_count }` (desc por created_at, limit 50; broadcast + dirigidas à membership atual)
- `POST   /api/v1/notifications/:id/mark_read` → `{ notification }` (404 cross-workspace)
- `POST   /api/v1/notifications/mark_all_read` → 200
- **WebSocket via Action Cable**: canal `NotificationsChannel` (param `workspace_id`; só membros assinam). Evento broadcast: `notification_created` com `{ event, notification }` no mesmo schema do REST.

### Telegram (RF17, canal externo) — implementado
- `GET    /api/v1/telegram_link` → `{ linked, chat_title, linked_at }`
- `POST   /api/v1/telegram_link` → `{ deep_link, expires_at }` — gera código de uso único (TTL 15 min); deep_link = `https://t.me/<bot>?startgroup=<code>`
- `DELETE /api/v1/telegram_link` → 204 (desvincula; eventos novos ficam só in-app)
- `POST   /api/v1/webhooks/telegram` — updates do bot (sem sessão; valida header `X-Telegram-Bot-Api-Secret-Token` via secure_compare). Sempre responde 200 (Telegram re-envia em não-2xx). Trata dois tipos de update:
  - **`message`**: `/start <code>` (e `/start@bot <code>`) vincula o chat ao workspace dono do código.
  - **`callback_query`** (toque em botão inline): autoriza por chat vinculado (`message.chat.id == workspace.telegram_chat_id`) e `callback_data` no formato `tx:consolidate:<id>` / `tx:reject:<id>`; consolida/rejeita a transação **escopada no workspace** (idempotente — só se `pending`), responde o toque (toast) e edita a mensagem removendo os botões. Toque de chat não vinculado ou contra tx de outro workspace = sem efeito.
- Registro do webhook: `bin/rails telegram:set_webhook` (usa `APP_HOST` + `TELEGRAM_WEBHOOK_SECRET`; `allowed_updates: [message, callback_query]`), uma vez por ambiente. **Re-rodar após o deploy que introduziu callback_query**, senão os toques não chegam.

**Botões de ação no inbox**: quando um sync traz **≤5** gastos novos e o grupo está vinculado, cada gasto vira uma mensagem no Telegram com inline keyboard (`Consolidar` · `Rejeitar` · `Abrir no app`). Acima de 5, mantém só o resumo `inbox_new`. O sininho in-app recebe o resumo nos dois casos.

### Faturas do cartão (RF9.5, derivado)
- `GET /api/v1/accounts/:id/invoices?status=open|future` — lista de faturas do cartão como objetos derivados:
  ```json
  {
    "invoices": [
      {
        "account_id": "...",
        "period": { "from": "2026-05-01", "to": "2026-05-31" },
        "status": "open",
        "total_cents": 425000,
        "transactions_count": 23,
        "installments_breakdown": [{ "group_id": "...", "label": "Geladeira 3/12", "amount_cents": 50000 }]
      }
    ]
  }
  ```
- Sem entidade física; query agrupa transactions por mês de competência (RF14.2).

## Headers e middleware

- **CSRF**: cookies de sessão usam `SameSite=Lax` + token CSRF em forms se houver. Para chamadas JSON do SPA mesma origem, usar mecanismo padrão Rails.
- **CORS**: permitido só pra origens conhecidas (staging URL + production URL). Tipicamente mesma origem (Vite build servido pelo mesmo host).
- **Rate limit**: `Rack::Attack` com limites lenientes (100 req/min por membership). Endpoints de import e bulk: limite mais baixo (10/min).
- **Tracing**: cada response inclui `X-Request-Id` para correlação com logs e Sentry.

## Exemplo de fluxo: aceitar um gasto da inbox com edição

```
1. GET /api/v1/transactions?status=pending
   → lista
2. PATCH /api/v1/transactions/abc-123
   body: { "lock_version": 0, "improved_title": "Almoço Padaria", "tag_ids": ["t1"], "category_id": "c1" }
   → 200 OK, lock_version vira 1
3. POST /api/v1/transactions/abc-123/consolidate
   → 200 OK, status=consolidated
```

## Exemplo de fluxo: split

```
1. GET /api/v1/transactions/abc-123
2. POST /api/v1/transactions/abc-123/split
   body: { "children": [
     { "amount_cents": 6000, "improved_title": "Comida", "tag_ids": ["t1"] },
     { "amount_cents": 2500, "improved_title": "Limpeza", "tag_ids": ["t2"] }
   ] }
   → 201 Created, retorna { parent: {...status: 'split'}, children: [...] }
```

## Exemplo de fluxo: vincular estorno

```
1. GET /api/v1/transactions/xyz-789/refund_candidates
   → top 10 ordenados por confiança
2. POST /api/v1/transactions/xyz-789/link_refund
   body: { "refunded_transaction_id": "abc-123" }
   → 201 Created
```

## Decisões finalizadas após revisão

| Tema | Decisão |
|---|---|
| Tamanho máx de upload em `/imports` | **10 MB** por arquivo. Retorna 413 Payload Too Large acima disso. |
| Filtros multi-valor | **`?campo_in=a,b`** (OR) e **`?campo_all=a,b`** (AND). Aplica-se a `tag_id_in`, `tag_id_all`, `account_id_in`, etc. |
| Autenticação WebSocket | **Cookie de sessão** padrão Rails Action Cable. Frontend conecta no `/cable` sem header extra; sessão valida o membership. |
| Webhooks Pluggy | **Já no MVP**. Endpoint `POST /api/v1/webhooks/pluggy`. **Na implementação (Fatia 5b)**: o Pluggy NÃO assina com HMAC, então a autenticação é via **header secreto compartilhado** `X-Webhook-Secret` (validado contra `PLUGGY_WEBHOOK_SECRET`, comparação constant-time) + IP whitelist. Evita polling caro e dá near-real-time. |

## Próximos passos

1. Contratos de API v1 v1.0 fechados.
2. Próximo doc: setup do monorepo.
3. Depois: primeira fatia TDD.

## Validação

- Cada RF do PRD tem endpoint(s) que o expõe.
- Convenções (paginação, erros, timestamps, money) consistentes entre todas as rotas.
- Frontend consegue, em teoria, montar telas para todos os fluxos a partir desses endpoints.

**Status:** v1.2 — Bank Connections (RF1+RF21) alinhado à implementação real
(Fatias 3a–5c): `connect_token`, body/schema do serializer, resposta do `sync`,
canal `BankConnectionsChannel` em `/cable`. Adicionados: endpoint de webhook Pluggy
(`POST /webhooks/pluggy`, header secreto — Fatia 5b) e `GET /api/v1/app_config`
(sandbox por runtime). `sync_history` marcado como planejado (RF21.7).

v1.1 — adicionados endpoints + payload enriquecido de Bank Connections para RF21.
