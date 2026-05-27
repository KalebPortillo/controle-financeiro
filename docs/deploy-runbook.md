# Deploy Runbook — Controle Financeiro

Decisões e armadilhas do caminho até `v0.2.0-rf16-auth` em produção. Mantém
contexto que não dá pra inferir do código sozinho — desde a virada pra
`oracle-app-box` (infra) até o CI rodando hands-off.

> Quem ler isso depois: o **PRD** descreve o que entregar, o **requisitos-tecnicos**
> descreve a stack e a arquitetura. Aqui ficam as **lições aprendidas em campo**
> que se transformam em "por que esse arquivo tem essa linha estranha?".

---

## Topologia atual (em uma tela)

```
Browser
  │
  ├──→ Cloudflare (proxy, Full strict TLS)
  │      │
  │      └──→ oracle-app-box (Oracle Cloud Ampere A1, ARM64, sa-saopaulo-1)
  │             │
  │             ├── kamal-proxy (80/443, cert Let's Encrypt)
  │             │     │
  │             │     ├──→ controle-financeiro-web-staging   (host: wallet-staging.portilho.cc)
  │             │     └──→ controle-financeiro-web-production (host: wallet.portilho.cc)
  │             │
  │             └── PostgreSQL 16 nativo (host.docker.internal:5432)
  │
  └──[SSH ops via Tailscale]──→ oracle-app-box (porta 22 fechada na internet pública)
```

Dev acontece num VPS separado (`oracle-dev-box`, Oracle Always Free também). De
lá, deploy via `kamal deploy -d staging` ou via `git push` (CI faz o resto).

---

## Como deployar (happy path)

### Local (do dev VPS)

Pré-requisitos: `~/.config/controle-financeiro/secrets.env` populado, Tailscale
ativo, chave `kamal_deploy_key` autorizada em `oracle-app-box`.

```bash
cd backend
bundle exec kamal deploy -d staging
# … smoke test em https://wallet-staging.portilho.cc/up …
# Promover pra produção:
git tag v0.X.0-feature && git push origin v0.X.0-feature
# (CI faz o deploy-production com environment approval gate)
```

### CI (push em main → staging, tag v* → production)

Configurado em `.github/workflows/deploy.yml`. Sequência por job:

1. `actions/checkout` + `ruby/setup-ruby` (cache de gems).
2. `Restore master.key` a partir do GH secret.
3. `docker login ghcr.io` (necessário porque o buildx remoto precisa das creds do runner).
4. `tailscale/github-action@v3` — conecta o runner ao tailnet com `tag:ci`.
5. `/etc/hosts` ganha entrada `100.68.129.58 oracle-app-box` (MagicDNS off).
6. SSH chave em disco + `~/.ssh/config` apontando `Host oracle-app-box User portilho IdentityFile ~/.ssh/id_ed25519`.
7. Espelha secrets em `~/.config/controle-financeiro/secrets.env` no runner.
8. `bundle exec kamal setup -d staging` (ou `production` no outro job).

---

## Lições aprendidas (e o porquê de cada linha esquisita)

### 1. Tailscale OAuth: scope `auth_keys`, não `oauth_keys`

No Tailscale admin (`https://login.tailscale.com/admin/settings/oauth`), ao criar
o OAuth client pro CI, **o scope tem que ser `auth_keys:write`** (cria auth keys
no tailnet pra runners se autenticarem).

Custou um deploy inteiro porque o nome `oauth_keys` (gerencia OAuth clients) está
em paralelo na lista e é fácil clicar errado. Sintoma: `backend error: invalid
key: unable to validate API key` no step do tailscale.

Pra validar:
```bash
TOKEN=$(curl -sS -u "$CID:$CSEC" -d "grant_type=client_credentials" \
  https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token)
curl -sS -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"capabilities":{"devices":{"create":{"ephemeral":true,"preauthorized":true,"tags":["tag:ci"]}}},"expirySeconds":120}' \
  https://api.tailscale.com/api/v2/tailnet/-/keys
# HTTP 200 + .key = OK; HTTP 403 = scope errado
```

### 2. ACL do tailnet precisa abrir `tag:ci → 100.68.129.58:22`

Sem regra explícita o tailnet é default-deny entre tags. ACL mínima:

```json
{
  "tagOwners": { "tag:ci": ["autogroup:admin"] },
  "acls": [
    { "action": "accept", "src": ["tag:ci"], "dst": ["100.68.129.58/32:22"] }
  ]
}
```

Cuidado: `dst` aceita CIDR ou hostname, **não IP nu**. `100.68.129.58:22` é
inválido; tem que ser `100.68.129.58/32:22`.

Sintoma quando faltava: `ssh: connect to host oracle-app-box port 22: Connection
timed out` (timeout TCP, característico de ACL silenciosa — não de porta fechada).

### 3. `tailscale-action` não habilita MagicDNS

A action sobe com `--accept-dns=false` por default, então hostnames do tailnet
(ex.: `oracle-app-box`) não resolvem no runner. Solução no workflow:

```yaml
run: echo "100.68.129.58 oracle-app-box" | sudo tee -a /etc/hosts > /dev/null
```

Se o IP do tailnet mudar (raro), atualizar este map.

### 4. `User portilho` explícito no `~/.ssh/config` do runner

Runner do GHA roda como `runner`. Mesmo o Kamal forçando `ssh.user: portilho` na
config principal, alguns sub-comandos do `kamal-proxy` leem o `~/.ssh/config`
direto. Sem `User portilho`, eles tentam logar como `runner@oracle-app-box` e
levam `Permission denied (publickey)`.

```ssh-config
Host oracle-app-box
  User portilho
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

### 5. `gh secret set --body -` interpreta `-` como valor literal

```bash
# ❌ ERRADO — armazena o caractere "-" como secret:
jq -r '.web.client_id' file.json | gh secret set NAME --body -

# ✅ CERTO — gh lê stdin quando --body é omitido:
jq -j '.web.client_id' file.json | gh secret set NAME

# ✅ Também ok — passa o valor inline:
gh secret set NAME --body "$VALUE"
```

Detectamos isso em produção quando o Google respondeu `invalid_client` (o
`client_id` chegou como `-`). **Sempre verifique `kamal app exec -d staging
'echo \${#VAR}'` depois de setar secrets críticas**.

### 6. Chave SSH dedicada pro CI precisa estar autorizada

`~/.ssh/kamal_deploy_key.pub` (gerada localmente, privada como `SSH_PRIVATE_KEY`
no GH) **tem que entrar no `~/.ssh/authorized_keys` do `oracle-app-box`**.
Fácil esquecer porque a chave existe no dev VPS desde antes do RF16.

O `infra/setup-oracle-app-box.sh` faz isso quando rodado com
`CI_PUBLIC_KEY="$(cat ~/.ssh/kamal_deploy_key.pub)" ssh oracle-app-box 'bash -s' < infra/setup-oracle-app-box.sh`.

### 7. `Dotenv.parse` no `.kamal/secrets-common` **não executa shell**

Kamal usa `Dotenv.parse` (não bash) pra ler `secrets-common`. Isso significa:
- Blocos `if/then/source/fi` rodam como código morto (são lidos como chave/valor literais).
- `$VAR` é resolvido pelo Dotenv com lookup em `env` interno ou `ENV` do processo.
- `$(...)` é **command substitution**: Dotenv passa o conteúdo via backticks Ruby (executa via `/bin/sh`).
- **Crítico**: dentro de `$(...)`, referências a `$VAR` são **pré-substituídas pelo
  Dotenv ANTES** do shell rodar. Pra deixar o shell expandir, escape com `\$VAR`.

Padrão atual em `secrets-common`:
```
KAMAL_REGISTRY_PASSWORD=$(. ~/.config/controle-financeiro/secrets.env 2>/dev/null; printf %s "\$KAMAL_REGISTRY_PASSWORD")
```

O `. file 2>/dev/null` sourceia silenciosamente; `printf %s "\$VAR"` lê do env do
subshell. Em dev local o arquivo existe; em CI o workflow escreve-o no runner
**antes** do `kamal setup` rodar (step "Espelhar secrets").

### 8. Kamal usa rede `kamal` (172.18.0.0/16), não a bridge padrão

Ao bootar o app, Kamal cria uma rede Docker dedicada chamada `kamal`. Por isso:
- `host.docker.internal` resolve pra `172.18.0.1` (gateway dessa rede),
  **não** `172.17.0.1` (bridge default).
- iptables precisa de regras pra `172.18.0.0/16` em DOCKER-USER + INPUT.
- `pg_hba.conf` precisa de entrada pra `172.18.0.0/16`.
- `listen_addresses` do Postgres tem que incluir `172.18.0.1`.

Tudo aplicado pelo `infra/setup-oracle-app-box.sh`.

### 9. `host.docker.internal` não é automático no Linux

Em macOS/Windows, Docker resolve automaticamente. No Linux precisa de
`--add-host=host.docker.internal:host-gateway`. Kamal 2.x faz isso via
`servers.web.options.add-host` em `deploy.yml`.

### 10. Cloudflare Full strict precisa de cert real no origin

`Full (strict)` = CF valida o cert que o origin apresenta. Como o
`kamal-proxy` faz Let's Encrypt via ACME HTTP-01, **a porta 80 do `oracle-app-box`
precisa estar aberta na internet** mesmo com CF proxy ativo (pra LE renovar).
DNS pode ficar com `proxied: true`.

`Flexible` mode (CF cifra só o leg cliente↔CF) evita esse trabalho, mas
**quebra o end-to-end TLS** — a app vê HTTP. Não é aceitável; mantemos Full
strict.

### 11. `render file:` em Rails 8 API-only é caprichoso

Em `StaticController#index` usávamos `render file: path, layout: false`. Funciona
pelo route `root` mas entrega body vazio quando atendido pelo catch-all
`*path`. Provável interação com X-Sendfile do Thruster.

Solução simples: `render plain: path.read, content_type: "text/html"`. Coberto
pelo teste `test/integration/static_spa_serving_test.rb`.

### 12. `kamal env push` não existe em Kamal 2.11

`kamal --help` lista `app`, `proxy`, `secrets`, etc, mas **não há subcomando
isolado pra "push env vars"**. As env vars (clear + secret) sobem como parte de
`kamal deploy` / `kamal setup`. Pra rodar idempotente, usar `kamal setup`.

### 13. `workflow_dispatch` no `deploy.yml`

Sem isso, re-rodar um deploy sem novo commit obriga `gh run rerun <id>` (que
pode estar travado por "environment approval gate" da production). Adicionamos
`workflow_dispatch` com input `target: staging|production` pra triggar manualmente.

### 14. Sentry em test deve ser inerte

`SENTRY_DSN` carregado pelo dotenv-rails em test → o SDK tenta mandar eventos
durante `bin/rails test` e bate em rede mockada por WebMock (falha barulhenta).
Fix em `config/initializers/sentry.rb`:

```ruby
return if ENV["SENTRY_DSN"].blank?
return if Rails.env.test?
```

### 15. Sentry probe route gated a non-production

`get "test_error" ...` deve ter `unless Rails.env.production?` no `routes.rb` —
senão qualquer um pode disparar 500s pra esgotar a quota Sentry.

### 16. Healthcheck timeout do kamal-proxy: 60s

Default 30s deixa pouco espaço quando o Rails 8 boota com eager_load + Solid
stack + Sentry init em ARM64. Subimos pra 60s em `deploy.yml`. Sintoma de
timeout curto: deploy reverte porque o container "novo" não respondeu `/up` a
tempo durante zero-downtime swap.

---

## Setup completo do zero (recovery)

Se `oracle-app-box` for re-criada do nada:

1. Provisionar VM Oracle Always Free Ampere A1 ARM64 em sa-saopaulo-1.
2. Habilitar Tailscale + autenticar como `tag:server` (ou autorizar ad-hoc).
3. Adicionar à zone Cloudflare (A records `wallet.portilho.cc` e
   `wallet-staging.portilho.cc`, proxied).
4. Instalar Docker 24+, PostgreSQL 16, netfilter-persistent.
5. Rodar:
   ```bash
   newapp controle-financeiro    # cria DB + ~/apps/controle-financeiro
   CI_PUBLIC_KEY="$(cat ~/.ssh/kamal_deploy_key.pub)" \
     ssh oracle-app-box 'bash -s' < infra/setup-oracle-app-box.sh
   ```
6. Ajustar Cloudflare SSL mode para "Full (strict)".
7. Validar ACL Tailscale tem regra `tag:ci → IP-novo/32:22`.
8. Atualizar `/etc/hosts` no workflow CI com o IP novo do tailnet.
9. `cd backend && bundle exec kamal setup -d staging`.

## Setup do GHCR / GH Actions secrets

Lista canônica (mantida em sync com `.github/workflows/deploy.yml`):

| Secret | Origem | Como setar |
|---|---|---|
| `RAILS_MASTER_KEY` | `backend/config/master.key` (local, gitignored) | `gh secret set RAILS_MASTER_KEY < backend/config/master.key` |
| `SSH_PRIVATE_KEY` | `~/.ssh/kamal_deploy_key` | `gh secret set SSH_PRIVATE_KEY < ~/.ssh/kamal_deploy_key` |
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale admin OAuth | `jq -j .client_id file.json \| gh secret set TAILSCALE_OAUTH_CLIENT_ID` |
| `TAILSCALE_OAUTH_SECRET` | Idem | `jq -j .client_secret file.json \| gh secret set TAILSCALE_OAUTH_SECRET` |
| `SENTRY_DSN_BACKEND` | Sentry project settings | `gh secret set SENTRY_DSN_BACKEND --body "$DSN"` |
| `GOOGLE_OAUTH_CLIENT_ID` | Google Cloud Console OAuth client JSON | `jq -j .web.client_id file.json \| gh secret set GOOGLE_OAUTH_CLIENT_ID` |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Idem | `jq -j .web.client_secret file.json \| gh secret set GOOGLE_OAUTH_CLIENT_SECRET` |

> **NUNCA** use `--body -` esperando que ele leia stdin: ele armazena o caractere
> literal `-`. Use `--body "$valor"` ou omita `--body` para ler stdin.

## Validação rápida pós-deploy

```bash
# 200 nos health checks
curl -sS -o /dev/null -w "%{http_code}\n" https://wallet-staging.portilho.cc/up
curl -sS -o /dev/null -w "%{http_code}\n" https://wallet.portilho.cc/up

# OAuth client_id certo no container
bundle exec kamal app exec -d staging --reuse \
  'sh -c "echo CID_HEAD=\$(echo \$GOOGLE_OAUTH_CLIENT_ID | head -c 25)"'

# Login URL aponta pro Google com client_id real
curl -sS -D - "https://wallet-staging.portilho.cc/api/v1/auth/google_oauth2" \
  | grep -oE "client_id=[^&]+"

# Sessão sem login → 401
curl -sS -o /dev/null -w "%{http_code}\n" https://wallet.portilho.cc/api/v1/sessions/current
```

---

**Status:** v1.0 — extraído do histórico de deploy do RF16 (2026-05-26 a 2026-05-27).
