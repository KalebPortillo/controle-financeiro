# Backend — Controle Financeiro

Rails 8.1 (modo padrão; serve a API + os assets do SPA Vite via `public/`).

Documentação canônica vive no [README da raiz](../README.md) e em [`docs/`](../docs).

## Stack

- **Ruby 3.3.5** (pinado em `.tool-versions` na raiz; instala via `asdf`).
- **Rails 8.1.3**, Puma, PostgreSQL 16+.
- **Solid Cache / Queue / Cable** (sem Redis — toda a infra mora no Postgres).
- **Thruster** na frente do Puma quando containerizado (compressão, X-Sendfile, cache).
- **Sentry** (`sentry-ruby` + `sentry-rails`) para erros.
- **Pundit** para autorização escopada por workspace.
- **JSONAPI::Serializer** para serializers.

## Testes

Stack default Rails 8 (Minitest) + extras:
- **factory_bot_rails** — factories
- **webmock + vcr** — isolar APIs externas (Pluggy, Gemini, Sentry)
- **simplecov** — cobertura
- **brakeman** + **bundler-audit** — segurança estática (rodam no CI)
- **rubocop-rails-omakase** — estilo

```bash
bin/rails test                                  # toda a suíte
bin/rails test test/path/to/some_test.rb        # arquivo único
bundle exec rubocop                             # estilo
bundle exec brakeman --no-pager --quiet         # segurança
bundle exec bundler-audit --update              # CVEs em gems
```

CI roda tudo a cada push/PR (`.github/workflows/test.yml`).

## Banco

Dev/test usa o Postgres do `infra/docker-compose.yml` (porta `5433` no host).
Staging/produção usam Postgres **nativo** no `oracle-app-box` (não é container).
Conexão via `host.docker.internal:5432`, user `portilho`. Databases criados pelo helper
`ssh oracle-app-box newapp controle-financeiro`; Solid stack DBs via `bin/rails db:create`.

Cada ambiente tem **4 databases** (Solid stack precisa de DBs separados):
- `controle_financeiro_<env>` — domínio
- `controle_financeiro_<env>_cache` — Solid Cache
- `controle_financeiro_<env>_queue` — Solid Queue
- `controle_financeiro_<env>_cable` — Solid Cable

```bash
bin/rails db:prepare      # cria, migra, semeia (idempotente)
bin/rails db:reset        # wipe + recreate
bin/rails db:migrate
bin/rails console
bin/rails dbconsole       # repl no Postgres
```

## Deploy

Via Kamal. Configs em `config/deploy.yml` (base) + `config/deploy.staging.yml` + `config/deploy.production.yml`. Ver [doc raiz](../README.md#deploy) pro fluxo.

```bash
bundle exec kamal app logs -d staging          # logs do container
bundle exec kamal app exec -d staging "bin/rails console"  # console remoto
bundle exec kamal rollback -d staging          # rollback pra versão anterior
```
