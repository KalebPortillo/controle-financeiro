---
name: ship
description: >-
  Verifica e deploya o controle-financeiro como um LOOP com critério de saída
  explícito. Use quando o usuário disser "sobe pra staging", "manda pra prod",
  "ship", "deploya", ou pedir pra rodar o gate de verificação antes de commitar.
  Roda o gate completo (backend + frontend), monta a checklist de smoke test da
  feature, decide backfill, e conduz o deploy até `deploy-production: success`.
---

# /ship — verificar e deployar

Objetivo: transformar "implementar → staging → testar → prod" num loop que o
agente conduz até um critério de saída verificável, em vez de o usuário pilotar
passo a passo. Fonte de verdade da infra: `docs/deploy-runbook.md`.

## 1. Gate de verificação (SEMPRE antes de commit/deploy)

Rode e só siga se TUDO passar. Critério de saída da fase: zero falhas nos dois.

```bash
# Backend (cwd = backend/)
bin/rails test && bundle exec rubocop && bundle exec brakeman --no-pager --quiet

# Frontend (cwd = frontend/)
npm run typecheck && npm run lint && npm run test:run && npm run build
```

- Falhou 1 teste backend com `NoMethodError: attachment_reflections for nil`?
  É a flake conhecida do Active Storage (runbook lição 20) — re-rode; não é bug.
- Commits em **inglês**, conventional-commits (`feat`/`fix`/`refactor`/`chore` +
  escopo). Commitar/pushar só quando o usuário pedir.

## 2. Decisões antes de taggar (a checklist pré-deploy do runbook)

Responda explicitamente, no resumo pro usuário:

1. **Migration?** Roda no boot (`db:prepare`). Destrutiva → sinalizar.
2. **Backfill retroativo?** A mudança altera dados JÁ importados?
   - Sim → há rake task idempotente (`namespace:task`)? Rodar em prod pós-deploy:
     `ssh oracle-app-box docker exec <rails_container> bin/rails <task>` + conferir amostra.
   - Não (só UI/endpoint sob demanda) → escrever "sem backfill" pro usuário não
     esperar dado retroativo.
3. **O que testar em staging?** Gerar a lista de smoke tests da feature (o usuário
   NÃO deve precisar perguntar "o que testo?"). 1 item por caminho + 1 de regressão
   do que foi tocado por perto. Mobile-first (o usuário testa no celular).
4. **Versão**: feature nova = bump minor; fix isolado = patch.

## 3. Loop de deploy (goal: `deploy-production: success`)

### Staging (push em `main`)
```bash
git push origin main
```
Espere o workflow `deploy` (não `ghcr-cleanup`). Poll com backoff até `completed`.
Reporte sucesso + a checklist de smoke test do passo 2. **Pare e espere o "ok" do
usuário** — staging conecta bancos reais; a validação é humana.

### Produção (tag `v*`, com gate manual)
```bash
git tag -a vX.Y.Z -m "<resumo>" && git push origin vX.Y.Z
```
1. Poll o run até o gate: `gh api repos/<owner>/<repo>/actions/runs/<id>/pending_deployments`
   retornar `length > 0`.
2. Se o job `test` falhar na flake → `gh run rerun <id> --failed`.
3. Aprovar o gate (o usuário já autorizou o deploy prod):
   ```bash
   envid=$(gh api .../actions/runs/<id>/pending_deployments -q '.[0].environment.id')
   echo '{"environment_ids":['$envid'],"state":"approved","comment":"<motivo>"}' \
     | gh api .../actions/runs/<id>/pending_deployments -X POST --input -
   ```
4. Poll até `deploy-production: success`. **Critério de saída do loop atingido.**
5. Pós-deploy: rodar backfill (se decidido no passo 2) + `bin/sentry-triage --since <hora>`.

## 4. Fechar o loop

- Atualizar memória (`estado-produto.md`, doc da feature) com a versão em prod.
- Resumo final pro usuário: versão no ar + o que testar + backfill (rodado ou N/A).

## Pacing (quando invocado via /loop ou em background)

Poll de CI é trabalho externo que o harness não notifica: use intervalos curtos
(~270s, cache quente) enquanto um run está ativo; nunca fique em foreground `sleep`.
Não re-rode rotinas mais vezes que o necessário (custo de token — ver o artigo de
loops). Um run de deploy leva ~2–5 min; staging ~4 min.
