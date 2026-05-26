# Controle Financeiro

App privado de gestão financeira do casal — **inbox-first**, busca automática de transações via Pluggy, pré-categorização com AI (Gemini), tags + categorias, splits, orçamentos, relatórios.

## Documentação

Specs canônicas em [`docs/`](./docs):

- [Requisitos de Produto (PRD)](./docs/requisitos-produto.md) — RF1–RF21, comparação de mercado, decisões.
- [Requisitos Técnicos](./docs/requisitos-tecnicos.md) — stack, infra, TDD, CI/CD, monitoramento.
- [Modelo de Dados](./docs/modelo-de-dados.md) — entidades, índices, constraints.
- [Contratos de API](./docs/contratos-api.md) — endpoints, payloads, convenções.
- [Requisitos de Design](./docs/requisitos-design.md) — vibe, tokens, IA, telas-chave.

Design system completo em [`design-system/`](./design-system) (handoff de claude.ai/design — tokens CSS, ícones, UI kit React).

## Estrutura

```
controle-financeiro/
├── backend/         # Rails 8 API (em construção)
├── frontend/        # Vite + React + TS (em construção)
├── infra/           # docker-compose.yml (Postgres), Kamal config (futuro)
├── docs/            # specs canônicas
├── design-system/   # handoff Claude Design — tokens, kit, ícones
├── .tool-versions   # Ruby 3.3.5 + Node 22.11.0 (asdf)
└── .github/workflows/  # CI/CD (futuro)
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
