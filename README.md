# Controle Financeiro

App **privado** de gestão financeira do casal — **inbox-first**, busca automática
de transações via Pluggy, pré-categorização com AI (Gemini), tags + categorias,
splits, orçamentos, relatórios. Self-hosted na VPS Oracle Cloud do usuário.

[![staging](https://img.shields.io/badge/staging-wallet--staging.portilho.cc-7C3AED)](https://wallet-staging.portilho.cc)
[![production](https://img.shields.io/badge/production-wallet.portilho.cc-0A0A0A)](https://wallet.portilho.cc)

## Status

| Fase | RF | Estado |
|---|---|---|
| Infra | — | ✅ `v0.1.0-infra` — oracle-app-box no ar, Cloudflare Full strict, Postgres nativo |
| Auth + Workspace | RF16 | ✅ `v0.2.0-rf16-auth` em produção — Google OAuth, convite por email, workspace selection |
| Integração Pluggy | RF1 | ⏳ próximo |
| Inbox + AI | RF2, RF3 | ⏳ |
| Demais RFs | RF4–RF21 | ⏳ ver [PRD](./docs/requisitos-produto.md) |

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

- **Backend** — Rails 8.1, PostgreSQL 16, Solid Stack (Cache/Queue/Cable), Thruster, Puma, Pundit, JSONAPI::Serializer, OmniAuth (Google), Rack::Attack, Sentry.
- **Frontend** — Vite 7, React 19, TypeScript 6, React Router 7, TanStack Query 5, Tailwind 4 (tokens canônicos do design system via `@theme`), Sentry React.
- **Testes** — Minitest + factory_bot + webmock/vcr (backend); Vitest + Testing Library + MSW (frontend); Playwright (E2E).
- **Infra** — Oracle Cloud Ampere A1 ARM64, Docker + Kamal 2.11, Cloudflare proxy (Full strict), Tailscale para ops.

## Estrutura

```
controle-financeiro/
├── backend/                       # Rails 8 API
│   ├── app/
│   │   ├── controllers/api/v1/    # SessionsController, WorkspacesController, MembershipsController, …
│   │   ├── controllers/concerns/  # Authentication, ApiErrorResponses
│   │   ├── models/                # User, Workspace, WorkspaceMembership
│   │   └── services/              # Users::CreateWithPersonalWorkspace
│   ├── config/
│   │   ├── deploy.yml             # Kamal — base + destinos (staging/production)
│   │   └── initializers/          # omniauth, rack_attack, sentry, session_store
│   ├── test/
│   │   ├── integration/           # auth_flow, workspaces_api, memberships_api, …
│   │   ├── models/ services/      # Espelham app/
│   │   └── factories/             # factory_bot
│   └── .kamal/                    # secrets-common (referências, sem valor literal)
├── frontend/
│   ├── src/
│   │   ├── api/                   # apiFetch + ApiError tipados
│   │   ├── auth/                  # useSession, LoginPage, RequireAuth
│   │   ├── components/            # Button, Card, Input, WalletLogo
│   │   ├── workspace/             # DashboardPage, MembersCard, useMemberships
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
