# Controle Financeiro

App **privado** de gestão financeira do casal — **inbox-first**, busca automática
de transações via Pluggy, pré-categorização com AI (Gemini), tags + categorias,
splits, orçamentos, relatórios. Self-hosted na VPS Oracle Cloud do usuário.

[![staging](https://img.shields.io/badge/staging-wallet--staging.portilho.cc-7C3AED)](https://wallet-staging.portilho.cc)
[![production](https://img.shields.io/badge/production-wallet.portilho.cc-0A0A0A)](https://wallet.portilho.cc)

## Status

Estado atual: **`v0.10.0` em produção**. RF1 + RF2 + RF3 + RF4 + RF5 + RF6 + RF12 + RF13 + RF16 + RF21 entregues.

| Fase | RF | Estado |
|---|---|---|
| Infra | — | ✅ `v0.1.0-infra` |
| Auth + Workspace | RF16 | ✅ `v0.2.0-rf16-auth` — Google OAuth + allowlist por email, convite, workspace selection |
| Integração Pluggy | RF1, RF21 | ✅ `v0.3.0-rf1-pluggy` — connect/sync/webhook, painel realtime via Action Cable |
| Inbox + Tags | RF2, RF5 | ✅ `v0.5.0-inbox-tags` |
| Consolidados + Lançamento manual | RF4, RF12 | ✅ `v0.8.0-manual-entry` |
| Categorias + Relatórios | RF6, RF13 | ✅ `v0.9.0` |
| AI (Gemini) | RF3 | ✅ `v0.10.0` — sugestão de título e tags + aprendizado passivo + reanálise |
| Orçamentos | RF8 | ⏳ próximo |
| Recorrentes / Estornos / Recibo | RF7, RF9, RF10, RF11 | ⏳ |

Detalhes em [PRD](./docs/requisitos-produto.md) e [estado-produto.md](./docs/) (memória interna).

## Documentação

Specs canônicas em [`docs/`](./docs):

| Doc | Para que serve |
|---|---|
| [Requisitos de Produto (PRD)](./docs/requisitos-produto.md) | RF1–RF21, comparação de mercado, decisões. |
| [Requisitos Técnicos](./docs/requisitos-tecnicos.md) | Stack, infra, TDD, CI/CD, monitoramento. |
| [Modelo de Dados](./docs/modelo-de-dados.md) | Entidades, índices, constraints. |
| [Contratos de API](./docs/contratos-api.md) | Endpoints, payloads, convenções. |
| [Requisitos de Design](./docs/requisitos-design.md) | Vibe, tokens, IA, telas-chave. |
| [Deploy Runbook](./docs/deploy-runbook.md) | Armadilhas de campo do CI/Tailscale/Kamal, recovery do zero. |

Design system (handoff `claude.ai/design`) em [`design-system/`](./design-system) — tokens CSS, ícones, UI kit React de referência.

## Stack

- **Backend** — Rails 8.1, PostgreSQL 16, Solid Stack (Cache/Queue/Cable), Thruster, Puma, OmniAuth (Google), Rack::Attack, Sentry, Pluggy (RF1), Gemini (RF3).
- **Frontend** — Vite 7, React 19, TypeScript 6, React Router 7, TanStack Query 5, Tailwind 4 (tokens canônicos do design system via `@theme`), Sentry React.
- **Testes** — Minitest + factory_bot + webmock/vcr (backend); Vitest + Testing Library + `vi.mock` direto em `globalThis.fetch` (frontend); Playwright (E2E).
- **Infra** — Oracle Cloud Ampere A1 ARM64, Docker + Kamal 2.11, Cloudflare proxy (Full strict), Tailscale para ops.

## Estrutura

```
controle-financeiro/
├── backend/                       # Rails 8 API
│   ├── app/
│   │   ├── controllers/api/v1/    # Sessions, Workspaces, Memberships, BankConnections,
│   │   │                          # Transactions, Tags, Categories, Reports,
│   │   │                          # AiLearnedRules, AppConfig, Webhooks, Health
│   │   ├── controllers/concerns/  # Authentication, WorkspaceScope, ApiErrorResponses
│   │   ├── models/                # User, Workspace, WorkspaceMembership, BankConnection,
│   │   │                          # Account, Transaction, TransactionEdit, Tag, Category,
│   │   │                          # AiLearnedRule, BankConnectionSync
│   │   ├── services/              # bank_aggregators/ (Pluggy), bank_connections/,
│   │   │                          # ai_providers/ (Gemini), ai_suggestion/, users/
│   │   ├── jobs/                  # bank_connections/sync_job, ai_suggestion/{suggest,
│   │   │                          # reanalyze, record_correction}_job
│   │   └── channels/              # BankConnectionsChannel (RF21 painel realtime)
│   ├── config/
│   │   ├── deploy.yml             # Kamal — base + destinos (staging/production)
│   │   └── initializers/          # omniauth, rack_attack, sentry, session_store
│   ├── test/                      # integration/ models/ services/ jobs/ factories/
│   └── .kamal/                    # secrets-common (referências, sem valor literal)
├── frontend/
│   ├── src/
│   │   ├── api/                   # apiFetch + ApiError tipados, cable client
│   │   ├── auth/                  # useSession, LoginPage, RequireAuth
│   │   ├── components/            # Button, Card, Input, Sheet, Money, TagChip, WalletLogo
│   │   ├── app/                   # AppLayout (sidebar/topbar/bottomnav), useTheme
│   │   ├── workspace/             # DashboardPage (=Mais), ContasPage, MembersCard
│   │   ├── transactions/          # InboxPage, GastosPage, ReportsPage, TagsPage,
│   │   │                          # CategoriasPage, TransactionDetailSheet,
│   │   │                          # SwipeableRow, ManualEntrySheet, TagEditor
│   │   ├── bank/                  # ConnectBankButton, SyncStatusPanel, GlobalSyncIndicator
│   │   └── styles/tokens.css      # Cópia do design-system/colors_and_type.css
│   └── tests/e2e/                 # Playwright golden paths
├── infra/                         # docker-compose (Postgres dev) + setup-oracle-app-box.sh
├── docs/                          # Specs canônicas + runbook
├── design-system/                 # Handoff de design (tokens, kit, ícones, logo SVG)
├── Dockerfile                     # Multi-stage (frontend → backend → runtime)
├── .tool-versions                 # Ruby 3.3.5 + Node 22.11.0 (asdf)
└── .github/workflows/             # test.yml (unit+e2e) + deploy.yml (Kamal)
```

## Dev environment

Pré-requisitos:
- `asdf` com plugins `ruby` e `nodejs` (versões em `.tool-versions`).
- `docker` + `docker compose` (Postgres dev local).
- `~/.config/controle-financeiro/secrets.env` populado — ver
  [Deploy Runbook §Setup do GHCR / GH Actions secrets](./docs/deploy-runbook.md#setup-do-ghcr--gh-actions-secrets)
  pra lista canônica.

### Bootstrap

```bash
bin/setup        # idempotente: instala gems, npm deps, sobe Postgres, migra, semeia
```

### Rodar tudo em paralelo

```bash
bin/dev          # Rails API (:3000) + Vite (:5173) + Solid Queue worker (foreman)
```

Em dev, Vite faz proxy de `/api/v1`, `/up` e `/cable` pra Rails — frontend e
backend ficam same-origin, sem CORS.

## Testes

Três camadas, todas no gate de deploy:

```bash
# Backend — Minitest (unit + integration)
backend $ bin/rails test
backend $ bundle exec rubocop                # estilo
backend $ bundle exec brakeman --quiet       # segurança estática
backend $ bundle exec bundler-audit          # CVEs em gems

# Frontend — Vitest (unit + component)
frontend $ npm run test                      # watch mode
frontend $ npm run test:run                  # one-shot CI
frontend $ npm run typecheck                 # tsc -b
frontend $ npm run lint                      # eslint

# E2E — Playwright (golden paths)
frontend $ npm run test:e2e:install          # uma vez: instala chromium + system deps
frontend $ npm run test:e2e                  # ~40s; sobe Rails + Vite preview automaticamente
frontend $ npm run test:e2e:ui               # modo interativo
```

### E2E

Vive em `frontend/tests/e2e/`. Playwright bate em `localhost:5173` (Vite preview)
que proxia pra Rails em `:3000` (env=test). Pra evitar o handshake real com o
Google, há um bypass em non-production: `POST /api/v1/auth/test_sign_in` cria/loga
user via o **mesmo** `Users::CreateWithPersonalWorkspace` do callback OAuth.
Detalhes em [`docs/requisitos-tecnicos.md → Estratégia de E2E`](./docs/requisitos-tecnicos.md#estratégia-de-e2e).

**Golden paths cobertos (6):** visitor anônimo redireciona pra login, dashboard
pós-login, logout, sessão persiste após reload, convite por email cadastrado,
convite por email não cadastrado.

## TDD

Princípio fundador. Vermelho → verde → refactor. Ver
[`docs/requisitos-tecnicos.md → Estratégia de testes`](./docs/requisitos-tecnicos.md#estratégia-de-testes-tdd)
pra pirâmide, ferramentas, thresholds (90% domínio / 70% geral), convenções e
mapeamento RF → foco de teste.

## CI/CD

[`.github/workflows/`](./.github/workflows/):
- **`test.yml`** — corre em todo push em `main` e PR:
  - `backend` — Minitest + Rubocop + Brakeman + bundler-audit.
  - `frontend` — typecheck + lint + Vitest.
  - `e2e` — sobe Postgres + Rails + Vite preview, roda Playwright.
- **`deploy.yml`** — `uses: test.yml` como gate; deploya via Kamal:
  - Push em `main` → **deploy automático em staging**.
  - Tag `v*` → **deploy em production** (com approval gate do GH Environment).

Detalhes operacionais e armadilhas em [`docs/deploy-runbook.md`](./docs/deploy-runbook.md).

## Deploy

- **Host**: `oracle-app-box` (Oracle Cloud Ampere A1, ARM64, sa-saopaulo-1).
- **Acesso ops**: Tailscale (porta 22 fechada na internet pública).
- **TLS**: Cloudflare proxy (Full strict) → `kamal-proxy` com cert Let's Encrypt → app HTTP interno.
- **Postgres**: nativo no host, conexão via `host.docker.internal:5432`, user `portilho`.
- **Storage**: bind mounts em `~/apps/controle-financeiro/data/` (convenção do helper `newapp`).

```bash
cd backend
bundle exec kamal deploy -d staging                # push em main → CI faz
bundle exec kamal deploy -d production             # tag v* → CI faz
bundle exec kamal app logs -d staging
bundle exec kamal app exec -d staging "bin/rails console"
bundle exec kamal rollback -d staging              # volta pra versão anterior
```

Pra recuperar do zero ou debugar problemas de pipeline, ver
[Deploy Runbook](./docs/deploy-runbook.md).

## Restrição de login (allowlist)

O app é privado. Apenas emails listados em `ALLOWED_EMAILS` (env var, separados
por vírgula) conseguem completar o callback OAuth do Google. Qualquer outro
email recebe redirect `?auth_error=unauthorized_email` sem criar usuário.

Configurado em [`backend/config/deploy.yml`](./backend/config/deploy.yml) no
bloco `env.clear`. Não-segredo (lista de emails), por isso vai versionado.

Quando `ALLOWED_EMAILS` não está definida (dev local + testes), qualquer email
é aceito — compatível com bootstrap e fluxo E2E.

## Rate limiting

Throttles do [`Rack::Attack`](./backend/config/initializers/rack_attack.rb):

| Endpoint | Limite | Motivo |
|---|---|---|
| `/api/v1/auth/*` | 10/min/IP | Brute-force no callback OAuth |
| `POST /transactions/reanalyze` | 5/min/IP | Queima quota Gemini |
| Pluggy write (`connect_token`, `sync`, `sync_all`, `reconnect`) | 10/min/IP | Quota Pluggy + tokens |
