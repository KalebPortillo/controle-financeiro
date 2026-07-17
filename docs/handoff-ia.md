# Handoff para agentes de IA — controle-financeiro (PortilhoWallet)

> Documento de transferência de contexto. Objetivo: qualquer IA (ou dev) pegar este
> arquivo e entender o produto, a arquitetura, as convenções e — principalmente —
> as armadilhas não-óbvias que custaram bugs reais. Atualizado em 2026-07-17
> (produção = v1.5.1).

## 1. O que é

App de finanças pessoais **"inbox-first" para um casal** (2 usuários reais:
Kaleb + Rebeca). Transações chegam automaticamente dos bancos (via Pluggy),
caem numa **inbox de pendentes**, a IA (Gemini) sugere título/tags, e o casal
revisa/consolida no **celular** (mobile-first é regra, não preferência —
ver §6). Produção: `wallet.portilho.cc`. Staging: `wallet-staging.portilho.cc`
(conecta bancos REAIS — staging tem dados reais, trate como produção).

Filosofia de produto: revisão humana obrigatória (nada é consolidado sem toque),
copy sóbrio em PT-BR, visual Linear/Notion minimalista.

## 2. Stack e topologia

- **Backend**: Rails 8.1 **api_only** (Ruby 3.3), Postgres, Solid Queue/Cache/Cable
  (SEM Redis). Minitest + FactoryBot + WebMock/VCR.
- **Frontend**: Vite + React 19 + TypeScript + Tailwind v4, TanStack React Query,
  React Router, Action Cable (`@rails/actioncable`), PWA com service worker próprio.
  Vitest + Testing Library; E2E Playwright (`frontend/tests/e2e/`).
- **Deploy**: Kamal 2 → Oracle Cloud (`oracle-app-box`), Thruster na frente do Puma
  serve o SPA buildado (mesmo host pra front+API, sem CORS). Cloudflare na borda
  (Full strict). CI GitHub Actions: **push em `main` → staging (automático)**;
  **tag `v*` → produção (gate de aprovação manual no GitHub)**. Migrations rodam
  no boot via entrypoint `db:prepare`.
- **Integrações**: Pluggy (agregador bancário), Google Gemini (sugestões IA,
  **free tier** — ver §8), Telegram (notificações + botões interativos), Google
  OAuth (login), Sentry (erros).

## 3. Layout do repo e fontes de verdade

```
backend/          Rails API (app/{models,controllers/api/v1,services,jobs,channels})
frontend/         SPA (src/ por feature: transactions/, budgets/, bank/, auth/…)
docs/             ESPECIFICAÇÕES — consultar ANTES de implementar:
  requisitos-produto.md    RFs (numeração RF1..RF23 usada em commits/testes/memória)
  contratos-api.md         formato de request/response/erros
  modelo-de-dados.md       schema lógico
  requisitos-tecnicos.md   decisões de stack/arquitetura (não contrariar sem alinhar)
  requisitos-design.md     specs de telas ainda não desenhadas
  deploy-runbook.md        infra + 21 lições aprendidas (LEIA antes de mexer em deploy)
design-system/project/     tokens, UI kit e previews — recriar fielmente, não inventar
.claude/skills/ship/       skill de deploy (gate → staging → prod em loop)
CLAUDE.md                  instruções para agentes (resumo operacional)
```

Regra de ouro: **UI nova → design system primeiro; endpoint novo → contratos-api.md;
padrão/dependência nova → requisitos-tecnicos.md**. Não invente layout nem introduza
dependência sem verificar esses docs.

### Hard rules de design (inegociáveis)
- Linear/Notion: limpo, minimalista. **Bordas, não sombras** (sombra só em overlay:
  modal/popover/toast). Sem glass, gradientes, rounded-2xl, pills.
- **Ícones Lucide apenas** (`lucide-react`). Sem emoji, sem glifos unicode.
- **Copy PT-BR**, sentence case, sem ponto final em strings curtas, sem emoji.
- **Dinheiro em monospace**, tabular-nums, `R$ 1.234,56`; negativo usa `−` (minus
  sign), não hífen. Componente pronto: `frontend/src/components/Money.tsx`.
- Acento único: Violet. Toasts sóbrios ("Gasto consolidado", não "🎉 Salvo!").

## 4. Convenções de trabalho

- **TDD** (Red → Green → Refactor): teste falhando antes do código de produção.
  Cada RF tem cobertura.
- **Commits em inglês**, conventional-commits (`feat`/`fix`/`refactor`/`chore`/`test`
  + escopo). Commitar/pushar **só quando o usuário pedir**.
- **Gate antes de qualquer commit/deploy** (zero falhas nos dois):
  ```bash
  # backend/ :
  bin/rails test && bundle exec rubocop && bundle exec brakeman --no-pager --quiet
  # frontend/ :
  npm run typecheck && npm run lint && npm run test:run && npm run build
  ```
- Deploy conduzido pela skill **`/ship`** (gate → checklist de smoke → staging →
  espera validação humana → tag → aprova gate de prod → `deploy-production: success`).
  O push da tag `v*` e a aprovação do gate de produção são atos do USUÁRIO
  (o classificador de permissões bloqueia o agente — comportamento desejado).

## 5. Arquitetura backend (padrões a seguir)

- **Services por domínio** em `app/services/<dominio>/<verbo>.rb`, com
  `def self.call(**kwargs)` → instância. Toda lógica de negócio vive aqui.
- **Jobs finos** (Solid Queue) em `app/jobs/`, só wrappers: carregam o registro,
  marcam status, delegam pro service, tratam erro pra UI não ficar presa
  (ex.: `Imports::ProcessJob` garante `failed`). `discard_on RecordNotFound`
  para registros apagados entre enqueue e perform.
- **Controllers finos**; serialização compartilhada via concern
  (`TransactionSerialization` com `SERIALIZE_INCLUDES` pra evitar N+1 — sempre
  fazer preload do que o serialize toca).
- **Escopo por workspace SEMPRE**: todo lookup parte de `current_workspace.xxx` ou
  `current_user.workspaces` (404 para não-membro). Concerns: `Authentication`
  (`current_user`, `require_authentication!`), `WorkspaceScope` (`current_workspace`,
  `current_membership`), `require_editor!(workspace)` no `ApplicationController`
  (roles: `editor` muda, `viewer` só lê).
- **Concorrência**: optimistic locking (`lock_version`) nas transações; conflito →
  409 com código `stale_object`/`already_decided` (o casal usa simultaneamente,
  web + Telegram). Aceitar/rejeitar é idempotente.
- **Erros da API**: formato canônico `{ error: { code, message, details } }`
  (concern `ApiErrorResponses`; contratos-api.md v1.1).
- **Providers atrás de abstração**: `BankAggregators::Pluggy`, `AiProviders::
  GeminiProvider`, `NotificationChannels::Telegram` — injetáveis nos testes
  (fake/WebMock/VCR). Não acoplar código de domínio ao provider.

## 6. Arquitetura frontend (padrões a seguir)

- **Feature folders** (`src/transactions/`, `src/budgets/`…). Componentes de UI
  genéricos em `src/components/` (Button, Card, Sheet, Money, TagChip…).
- **Cliente HTTP único**: `src/api/client.ts` (`apiFetch`) — cookies de sessão,
  erros viram `ApiError`/`UnauthorizedError`, tolera corpo vazio (202/204).
- **React Query com cache cirúrgico** (`src/transactions/useInbox.ts` é o modelo):
  mutações fazem update otimista/patch do cache em vez de invalidar tudo; a raiz
  `['transactions']` tem sub-chaves `pending` / `consolidated,<YYYY-MM>` /
  `search,<q>`. Ao editar uma transação, `replaceInTransactionLists` atualiza
  TODAS as listas (bug real v1.4.1: só atualizava a inbox e consolidados ficavam
  stale, inclusive o lock_version).
- **Overlays são estado de URL, NUNCA `useState`**: hook `src/app/useOverlay.ts`
  (`push`/`close`/`replaceWith`; params `?tx=`, `?group=`, `?new=1`, `?notifs=1`).
  Motivo: o gesto de "voltar" do celular deve fechar o overlay. Regra absoluta
  para overlay/sheet novo.
- **Mobile-first é obrigatório**: o usuário testa no iPhone. Layout base = mobile
  (`md:` para desktop); conteúdo extra em Sheet de tela cheia, não popover.
- Helpers compartilhados: `transactions/display.ts` (títulos, datas, sinal),
  `transactions/period.ts` (períodos YYYY-MM). Não duplicar formatação.

## 7. Segurança (estado pós-v1.5.1)

Sessão = cookie httponly + SameSite=Lax + secure (`force_ssl`), **middleware de
sessão manual em `config/application.rb`** (ver armadilha §9.1). Camadas ativas:

- `OriginVerification` (concern global): request mutante com header Origin de outro
  host → 403. **Comparação é HOST-ONLY de propósito** — o proxy do Vite (dev
  :5173→:3000 e preview E2E) reescreve a porta; comparação estrita de URL quebra
  dev e E2E. Webhooks (sem Origin) passam. `sessions#failure` tem skip (o
  `on_failure` do OmniAuth reusa o env do POST rejeitado).
- OAuth Google: request phase **POST-only** (`LoginPage` é form POST) com
  `request_validation_phase` por Origin (o gem `omniauth-rails_csrf_protection`
  exige form token que SPA api-only não tem); callback protegido por state param.
- **`ALLOWED_EMAILS` fail-closed em production**: whitelist em
  `backend/config/deploy.yml` (3 emails do casal); lista vazia em production NEGA
  todo mundo. Dev/test com lista vazia libera (fluxo local/E2E).
- Rack::Attack: throttle geral 300/min/IP em `/api/*` + específicos (auth 10/min,
  reanálise IA 5/min, Pluggy write 10/min). Storage = Rails.cache (solid_cache).
- Webhooks Pluggy/Telegram: secret compartilhado em header, `secure_compare`,
  fail-closed.
- Gemini: chave no header `x-goog-api-key` (nunca na URL).
- Rotas de teste (`test_sign_in`, `test_support/seed`, `test_error`) gated em
  `Rails.env.local?` — NUNCA existem em staging/prod.

## 8. Integrações externas — o que já mordeu

### Pluggy (leia antes de tocar em sync)
1. **O `id` da transação NÃO é estável**: quando compra de cartão vai de PENDING →
   POSTED (fatura fecha), o Pluggy deleta e recria com id novo (causou 106 grupos
   de duplicatas em prod). Defesas em produção: reconciliação por assinatura de
   conteúdo `(occurred_at, amount_cents, direction, original_description)` no
   `BankConnections::Sync`, `TransactionTombstone` (excluído não ressuscita),
   webhook `transactions/deleted` → `PruneTransactionsJob`, e rake
   `transactions:dedup` (dry-run por padrão, `CONFIRM=1` aplica). **Nunca**
   confiar em dedup só por id.
2. **Direção vem do campo `type`** (DEBIT/CREDIT), NUNCA do sinal do amount — no
   cartão o sinal é invertido (compra = positivo). Regra em
   `Sync#direction_for`. Exceção: conector **sandbox** viola a doc, aí cai no
   sinal — logo staging com sandbox não testa fielmente cartão real.
3. **Parcelas não têm id de compra**: agrupamento por
   `conta:descritor:MÊS-da-compra-retrocalculado:total`
   (`Transactions::Installment`). O `purchaseDate` do Pluggy é SINTÉTICO nas
   parcelas projetadas — não usar, nem exibir.

### Gemini
**Free tier** (projeto sem billing): RPM ~10/min, limite DIÁRIO reseta ~04:00 BRT.
Nunca reanalisar centenas em rajada. Resiliência via concern `AiResilient`
(retry com backoff para 429/5xx transitório; quota/daily = permanente → banner de
erro via `workspace.ai_last_error`). Batching de 25 tx por chamada. Estado por
transação em `ai_status` (queued/analyzed/failed).

### Telegram
Bot por ambiente; webhook com `secret_token`; grupo vinculado por
`workspace.telegram_chat_id` (`/start <code>`). Jobs best-effort (`discard_on`
API errors, `retry_on` rate limit). Botões inline consolidam/rejeitam da inbox.

## 9. Armadilhas técnicas (cada uma custou um bug real)

1. **api_only + sessão**: `config/initializers/session_store.rb` é INERTE. O
   middleware real está em `config/application.rb` — toda opção de cookie
   (`expire_after: 30.days` inclusive, senão iOS/PWA desloga ao fechar) mora LÁ.
2. **Cache do shell do SPA**: `index.html`/`sw.js` são no-cache via middleware
   `StaticCacheControl` + SW com `cache: 'reload'`; `/assets/*` hasheado é
   imutável. Não mexer nesses headers — o app já ficou preso 1 ano em cache de
   edge por causa disso. Assets de `public/` presos no Cloudflare exigem bump
   `?v=N` nas referências.
3. **`bin/rails runner` com RAILS_ENV=test POLUI o banco de teste** (não é
   transacional). Depois de debugar assim: `bin/rails db:test:prepare`. O E2E
   local compartilha o mesmo DB — mesma regra.
4. **Flake do Active Storage em teste paralelo**: `file.attach` tem corrida de
   teardown (`NoMethodError: attachment_reflections for nil`). Quarentenado no CI
   com `minitest-retry` (só essa exceção). Em testes novos de jobs, stubar o
   service em vez de anexar arquivo (ver `test/jobs/imports/process_job_test.rb`).
5. **Kamal lock preso**: deploy cancelado no meio (timeout do buildx remoto — flake
   conhecida) deixa `~/.kamal/lock-...` no host → próximo deploy falha com
   `LockError`. O CI já tem cleanup automático; se acontecer manual:
   `kamal lock release -d <dest>`. Runbook lições 20–21.
6. **Minitest 6**: `minitest/mock` não vem mais embutido (LoadError). Para stub de
   método de classe, monkeypatch com `define_singleton_method` + restore no ensure.
7. **Renomeou `data-testid`? Grep em `frontend/tests/e2e/`** — E2E é gate de
   deploy e já quebrou por testid órfão.
8. **Diagnóstico direto no Postgres de prod/staging** (`ssh oracle-app-box` →
   `psql`) exige aprovação explícita do usuário por sessão.

## 10. Estado atual (2026-07-17)

**Produção: v1.5.1** (hardening de segurança — §7; sem migration, sem backfill).
Antes: v1.5.0 (seção "Vínculos" unificada — estorno é `relation_type` como
IOF/tarifa; parcelas no detalhe; Telegram espera sugestão da IA), v1.4.x
(relatórios navegáveis + drill-down), v1.3.x (dedup Pluggy + auto-vínculo de
estorno por heurística), v1.0.0 (RF8 orçamentos fechou o MVP).

**RFs prontos**: RF1 Pluggy, RF2 inbox, RF3 IA, RF4 consolidados, RF5 tags,
RF6 categorias, RF8 orçamentos, RF9 recorrentes, RF10 estornos, RF11
transferências internas, RF12 entrada manual, RF13 relatórios, RF15 shell,
RF16 auth/workspaces, RF17 notificações (in-app + Telegram), RF20 import CSV,
RF21 painel de sync, RF22 onboarding, RF23 transações relacionadas.

**Pendências conhecidas (não-bloqueantes)**:
- RF7 receitas dedicadas (parcial via entrada manual)
- RF9.5 card de fatura no frontend (backend pronto: `/accounts/:id/invoices`)
- RF20 OFX (hoje só CSV)
- Busca Fase 2 (tsvector ponderado + Cmd-K) — Fase 1 (unaccent + `?q`) em prod
  com teto de 200 resultados; **paginação decidida como "não fazer agora"**
  (volumes reais não justificam; revisitar junto com a Fase 2)
- Testes de componentes frontend faltando: BudgetWizard, BudgetsPage,
  NotificationsPanel, ManualEntrySheet; E2E cobre só 3 fluxos (golden-paths,
  RF23, RF8)
- Extração de `Reports::*` services do `ReportsController` (375 linhas) — adiada
  de propósito até relatórios evoluírem de novo

**Auditoria completa 2026-07-15**: Brakeman 0 warnings, bundler-audit/npm audit 0
vulnerabilidades, 950 testes backend + 306 frontend verdes. Os achados viraram a
v1.5.1.

## 11. Contexto de memória

Se você é um agente com acesso ao diretório de memória do Claude Code
(`~/.claude/projects/-home-portilho-projects-controle-financeiro/memory/`),
o índice `MEMORY.md` aponta arquivos por tema (Pluggy, deploy, decisões de
produto). Este handoff resume o essencial deles, mas os arquivos têm mais
detalhe histórico (planos, evidências de bugs, decisões do usuário com data).

## 12. Como o usuário trabalha (expectativas)

- Pede em PT-BR; espera respostas e copy em PT-BR (código/commits em inglês).
- Valida features **no celular** em staging antes de aprovar produção.
- Deploy de produção passa por aprovação manual DELE (gate do GitHub) — não
  automatizar por cima disso.
- Prefere que o agente conduza loops completos (gate → deploy → smoke checklist →
  Sentry) e reporte com resumo objetivo, mas decisões de produto e ações
  irreversíveis são dele.
