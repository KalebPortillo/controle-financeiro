# Controle Financeiro

App privado de gestão financeira do casal — **inbox-first**, busca automática de transações via Pluggy, pré-categorização com AI (Gemini), tags + categorias, splits, orçamentos, relatórios.

## Documentação

Specs canônicas em [`docs/`](./docs):

- [Requisitos de Produto (PRD)](./docs/requisitos-produto.md) — RF1–RF21, comparação de mercado, decisões.
- [Requisitos Técnicos](./docs/requisitos-tecnicos.md) — stack, infra, TDD, CI/CD, monitoramento.
- [Modelo de Dados](./docs/modelo-de-dados.md) — entidades, índices, constraints.
- [Contratos de API](./docs/contratos-api.md) — endpoints, payloads, convenções.
- [Requisitos de Design](./docs/requisitos-design.md) — vibe, tokens, IA, telas-chave.
- [Deploy Runbook](./docs/deploy-runbook.md) — armadilhas de campo, lições do CI/Tailscale/Kamal, recovery do zero.

Design system completo em [`design-system/`](./design-system) (handoff de claude.ai/design — tokens CSS, ícones, UI kit React).

## Estrutura

```
controle-financeiro/
├── backend/                   # Rails 8 API (em construção)
│   ├── config/deploy.yml      # Kamal — base + destination (staging/production)
│   └── .kamal/                # secrets-common + hooks (commitado, sem segredo literal)
├── frontend/                  # Vite + React + TS (em construção)
├── infra/                     # docker-compose.yml (Postgres dev local)
├── docs/                      # specs canônicas (PRD, técnicos, dados, API, design)
├── design-system/             # handoff Claude Design — tokens, kit, ícones
├── Dockerfile                 # multi-stage build (frontend → backend → runtime)
├── .tool-versions             # Ruby 3.3.5 + Node 22.11.0 (asdf)
└── .github/workflows/         # CI/CD: test.yml + deploy.yml (Kamal)
```

## Deploy

- **Host:** `oracle-app-box` (Oracle Cloud Ampere A1, ARM64, sa-saopaulo-1).
- **Acesso:** Tailscale (porta 22 fechada na internet pública).
- **TLS:** Cloudflare proxy (Full strict) → kamal-proxy com cert Let's Encrypt → app HTTP interno.
- **Postgres:** nativo no host (não é Kamal accessory). Conexão via `host.docker.internal:5432`, user `portilho`.
- **Storage:** bind mounts em `~/apps/controle-financeiro/data/` (convenção do helper `newapp`).
- **Comandos:**
  ```bash
  cd backend
  bundle exec kamal deploy -d staging       # push em main → CI dispara
  bundle exec kamal deploy -d production    # tag v* → CI dispara
  bundle exec kamal app logs -d staging
  bundle exec kamal app exec -d staging "bin/rails console"
  ```

## Dev environment (VPS workspace)

Pré-requisitos instalados na VPS:
- `asdf` (~/.asdf) + plugins `ruby` e `nodejs` com versões pinadas em `.tool-versions`.
- `docker` + `docker compose` para Postgres em container.

### Bootstrap

```bash
bin/setup       # idempotente: instala gems, npm deps, sobe Postgres, migra, semeia
```

### Rodar tudo em paralelo

```bash
bin/dev         # Rails API + Vite + Solid Queue worker (foreman)
```

### Testes

```bash
backend $ bin/rails test               # Minitest
frontend $ npm run test                # Vitest
frontend $ npm run test:e2e            # Playwright
```

## TDD

Princípio fundador. Teste vermelho primeiro, sempre. Ver [`docs/requisitos-tecnicos.md`](./docs/requisitos-tecnicos.md#estratégia-de-testes-tdd) para pirâmide, ferramentas, thresholds (90% domínio / 70% geral) e mapeamento RF → foco de teste.
