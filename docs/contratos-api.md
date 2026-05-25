# Controle Financeiro do Casal — Contratos de API v1 (v0.1)

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

### Bank Connections (RF1.3–RF1.7)
- `POST /api/v1/bank_connections` — body: `{ provider: "pluggy", item_id: "...", account_external_ids: [...], history_since: "2026-01-01" }`. Pluggy Connect (widget) roda no frontend; depois o frontend POSTa o resultado aqui.
- `GET  /api/v1/bank_connections` — list.
- `POST /api/v1/bank_connections/:id/sync` — força sync agora. 202 Accepted + retorna job_id.
- `DELETE /api/v1/bank_connections/:id` — disconnect.

### Transactions — listagem e leitura (RF2, RF4, RF13)
- `GET /api/v1/transactions` — list. Filtros:
  - `status` (`pending`, `consolidated`, `rejected`, `split`)
  - `direction` (`debit`, `credit`)
  - `account_id`
  - `tag_id`
  - `category_id`
  - `owner_membership_id`
  - `from`, `to` (datas)
  - `q` (full-text em description/title)
  - Default sort: `-occurred_at`.
- `GET /api/v1/transactions/:id` — detalhe completo (com tags, category, splits, refund, history count).
- `GET /api/v1/transactions/:id/edits` — histórico (RF4.3).

### Transactions — escrita e workflow inbox (RF2.3, RF12)
- `POST /api/v1/transactions` — entrada manual (RF12). Body:
  ```json
  {
    "account_id": "...",
    "direction": "debit",
    "amount_cents": 8500,
    "occurred_at": "2026-05-20",
    "improved_title": "Almoço Padaria",
    "tag_ids": ["..."],
    "category_id": "..."
  }
  ```
  Status inicial = `consolidated` (RF12.3).
- `PATCH /api/v1/transactions/:id` — body inclui `lock_version`. Campos editáveis: `improved_title`, `amount_cents`, `occurred_at`, `tag_ids` (substitui), `category_id`.
- `DELETE /api/v1/transactions/:id` — hard delete.
- `POST /api/v1/transactions/:id/consolidate` — accept (RF2.3).
- `POST /api/v1/transactions/:id/reject` — reject (RF2.3).
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

### Refunds (RF10)
- `GET  /api/v1/transactions/:id/refund_candidates` — lista de transações débito candidatas (mesmo estabelecimento, valor compatível, janela de tempo). Algoritmo retorna até 10 ordenadas por confiança.
- `POST /api/v1/transactions/:id/link_refund` — body: `{ refunded_transaction_id }`. Transação `:id` deve ser credit. 422 se direções inconsistentes.
- `DELETE /api/v1/transaction_refunds/:id` — desfaz vínculo.

### Internal Transfers (RF11)
- `GET    /api/v1/internal_transfers`
- `POST   /api/v1/internal_transfers` — marcar manualmente. Body: `{ debit_transaction_id, credit_transaction_id }`.
- `DELETE /api/v1/internal_transfers/:id` — desfaz.

### Tags (RF5)
- `GET    /api/v1/tags` — list com contagem de uso. `?q=` para autocomplete.
- `POST   /api/v1/tags` — body: `{ name, color, icon }`.
- `PATCH  /api/v1/tags/:id`
- `DELETE /api/v1/tags/:id` — 422 se em uso, com mensagem orientando merge.
- `POST   /api/v1/tags/:id/merge` — body: `{ into_tag_id }`. Move todas as relações para a tag destino, remove origem.

### Categories (RF6)
- `GET    /api/v1/categories` — list com tag_ids.
- `POST   /api/v1/categories` — body: `{ name, color, icon, tag_ids }`.
- `PATCH  /api/v1/categories/:id`
- `DELETE /api/v1/categories/:id`
- `POST   /api/v1/categories/:id/merge` — body: `{ into_category_id }`.
- `PUT    /api/v1/categories/:id/tags` — body: `{ tag_ids: [...] }`. Substitui (não acumula).

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

### Imports (RF20)
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
- `GET    /api/v1/manual_rules`
- `POST   /api/v1/manual_rules` — RF3.3.
- `PATCH  /api/v1/manual_rules/:id`
- `DELETE /api/v1/manual_rules/:id`
- `GET    /api/v1/ai_learned_rules` — ver regras aprendidas.
- `DELETE /api/v1/ai_learned_rules/:id` — esquecer regra aprendida.

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

### Notifications (RF17)
- `GET    /api/v1/notifications?unread=true`
- `POST   /api/v1/notifications/:id/mark_read`
- `POST   /api/v1/notifications/mark_all_read`
- **WebSocket via Action Cable**: canal `NotificationsChannel`, identificado por workspace_id + membership_id. Eventos broadcast: `notification_created`.

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

## Pontos em aberto

1. **Tamanho máximo de upload em `/imports`**: sugerido 10 MB por arquivo. OK?
2. **Filtros multi-valor**: `?tag_id=t1&tag_id=t2` (qualquer) vs `?tag_ids=t1,t2` (AND/OR)? Recomendação: `?tag_id_in=t1,t2` (OR) e `?tag_id_all=t1,t2` (AND).
3. **WebSocket auth**: cookie de sessão funciona em Action Cable (default Rails). OK.
4. **Webhooks Pluggy**: receber notificação de "nova transação disponível" para sync sob demanda em vez de polling. Endpoint `POST /api/v1/webhooks/pluggy` com assinatura HMAC. Entra no MVP ou fica como segunda fase? Recomendação: MVP, evita polling caro.

## Próximos passos

1. Você revisa contratos e ajusta.
2. Fechamos a v1.0.
3. Passamos para **setup do monorepo** (estrutura, Dockerfile, Kamal config, GitHub Actions skeletons).
4. Depois: **plano de implementação em fatias TDD**.

## Validação

- Cada RF do PRD tem endpoint(s) que o expõe.
- Convenções (paginação, erros, timestamps, money) consistentes entre todas as rotas.
- Frontend consegue, em teoria, montar telas para todos os fluxos a partir desses endpoints.

**Status:** v0.1 — primeiro draft após Modelo de Dados v0.1.
