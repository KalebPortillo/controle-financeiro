# Controle Financeiro — guia para agentes

App de finanças pessoais "inbox-first" para um casal. Backend Rails 8 (API),
frontend Vite + React + TS + Tailwind, deploy Kamal na Oracle Cloud.

## Antes de implementar — consulte sempre

- **Novas funcionalidades de UI/tela** → consulte o **design system** em
  `design-system/project/` ANTES de construir. Os tokens já estão em
  `frontend/src/styles/tokens.css` (espelham `design-system/project/colors_and_type.css`).
  O UI kit de referência (shapes, copy, espaçamento, interações) está em
  `design-system/project/ui_kits/app/` e os componentes/telas isolados em
  `design-system/project/preview/`. Recrie fielmente em React/Tailwind — não
  invente layout novo quando já existe desenhado. Specs de telas ainda não
  desenhadas: `docs/requisitos-design.md`.
- **Decisões de tecnologia/arquitetura** → consulte `docs/requisitos-tecnicos.md`
  (stack, testes/TDD, infra, providers atrás de abstração). Não introduza
  dependência ou padrão novo que contrarie o doc sem alinhar antes.
- **Contratos de API** → `docs/contratos-api.md`. **Modelo de dados** →
  `docs/modelo-de-dados.md`. **Produto/requisitos (RFs)** → `docs/requisitos-produto.md`.
- **Deploy / CI / armadilhas de infra** → `docs/deploy-runbook.md`.

### Hard rules de design (de `design-system/project/SKILL.md`)
- Vibe Linear/Notion: limpo e minimalista. Sem glass, sem gradientes, sem
  rounded-2xl, sem pills, sem sombra em cards. **Bordas, não sombras**, para
  separação (sombra só em overlays: modal, popover, toast).
- **Ícones Lucide apenas** (`lucide-react`). Sem emoji, sem glifos unicode.
- **Copy em PT-BR**, sentence case, sem ponto final em strings curtas, sem emoji.
- **Dinheiro é monospace**, tabular-nums, `R$ 1.234,56`. Negativo usa `−` (em-dash), não `-`.
- Acento único: Violet. Toasts sóbrios ("Gasto consolidado", não "🎉 Salvo!").

## Convenções de trabalho

- **TDD** (Red → Green → Refactor): teste falhando antes do código de produção.
  Cada RF tem cobertura. Backend Minitest + FactoryBot + VCR; frontend Vitest +
  Testing Library; E2E Playwright (gate de deploy).
- **Mensagens de commit em inglês**, conventional-commits (`feat`/`fix`/`refactor`/`chore` + escopo).
- Antes de commitar: backend `bin/rails test` + `rubocop`; frontend `vitest` +
  `tsc --noEmit` + `eslint` + `npm run build`.
- Deploy: push em `main` → staging (CI hands-off); tag `v*` → produção (com
  aprovação manual no GitHub). Migrations rodam no boot via entrypoint `db:prepare`.
