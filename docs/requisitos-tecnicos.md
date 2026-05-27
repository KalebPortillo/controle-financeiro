# Controle Financeiro — Requisitos Técnicos (v1.3)

## Contexto

Doc complementar ao `docs/requisitos-produto.md` (PRD v1.2). Aqui ficam decisões de stack, arquitetura, infra, processo de entrega e **estratégia de testes (TDD)**.

As escolhas seguem quatro pilares dados por você:

- **SOLID + Clean Code** como base de engenharia.
- **API-first**: backend serve API; frontend (SPA) consome.
- **Dois ambientes** (homologação e produção) com **CI/CD** promovendo de um para o outro só após validação.
- **TDD**: nenhum código de produção é escrito sem um teste falhando primeiro. Cobertura **extensiva** com pelo menos um teste por requisito funcional.

Esta v1.0 fecha todas as decisões técnicas após três iterações. Próxima fase: modelo de dados + contratos de API.

## Princípios técnicos

1. **SOLID** + **Clean Code** em todas as camadas.
2. **API-first**: contrato REST + JSON bem definido; frontend não conhece o backend além do contrato.
3. **Promoção controlada**: nada vai para produção sem passar por homologação validada.
4. **HTTPS obrigatório** em todos os ambientes externos (inclusive staging).
5. **Configuração via variáveis de ambiente** (12-factor); segredos nunca em código.
6. **Tudo versionado**: backend, frontend, infra (Kamal configs, Dockerfiles) — em monorepo.
7. **TDD** (Test-Driven Development) como padrão. Ciclo **Red → Green → Refactor** para cada requisito funcional. Nenhuma linha de produção é escrita antes do teste correspondente falhar.
8. **Pirâmide de testes**: muitos unitários, alguns de integração, poucos end-to-end. Mas **todos os RFs têm cobertura**.
9. **CI bloqueia merge** se testes falharem, lint falhar ou cobertura cair abaixo do mínimo.
10. **Provedores externos atrás de abstração**: AI, agregador bancário, monitoramento — todos por trás de uma interface que permita trocar implementação sem mexer no domínio.

## Stack escolhida

### Backend
- **Ruby on Rails 8** em modo API (`rails new --api`).
- **Por quê**: você prefere Rails. Rails 8 traz **Solid Queue** (jobs), **Solid Cache** (cache) e **Solid Cable** (websockets) **embutidos**, dispensando Redis. Kamal (deploy) também é nativo.

### Frontend
- **Vite + React + TypeScript**.
- **React Router** para roteamento.
- **TanStack Query** para data fetching e cache.
- **Tailwind CSS** para estilização (mobile-first + desktop diferenciado).

### Banco de dados
- **PostgreSQL 16+**.

### API
- **REST + JSON** com versionamento por path (`/api/v1/...`).

### Background jobs e cache
- **Solid Queue** (jobs) + **Solid Cache** (cache) em Postgres. Sem Redis.

### Tempo real (RF17)
- **Action Cable + Solid Cable**.

## Integração com instituições financeiras

### Decisão: **Pluggy** como agregador primário + **Importação manual por arquivo** como fallback

**Por quê Pluggy:**
- Caminho oficial via Open Finance.
- **Cobre Nubank + outros bancos brasileiros** com a mesma API — alinhado com a sua intenção de expandir para outras instituições no futuro sem refazer a integração.
- Free tier inicial suficiente para uso pessoal (2 conexões iniciais com refresh diário). Se exceder, há planos pagos previsíveis.
- API REST agnóstica de linguagem — funciona direto do Rails sem microsserviço auxiliar.

**Arquitetura da integração (abstração):**

```ruby
# Interface
module BankAggregators
  class Provider
    def fetch_transactions(connection, since:); raise NotImplementedError; end
    def connect(credentials); raise NotImplementedError; end
    def refresh(connection); raise NotImplementedError; end
  end
end

# Implementação Pluggy
class BankAggregators::PluggyProvider < BankAggregators::Provider
  # ...
end

# Outro futuro
class BankAggregators::BelvoProvider < BankAggregators::Provider
  # ...
end
```

Selecionada via config (`ENV['BANK_AGGREGATOR'] = 'pluggy'`). Trocar de provider = trocar a env var.

### Importação manual por arquivo (RF20)

- **Endpoint** `POST /api/v1/imports` com upload de arquivo CSV ou OFX.
- **Parsers** em `app/services/imports/`:
  - `Imports::CsvParser` — detecta delimitador, mapeia colunas (data, descrição, valor) com heurística + override manual do usuário se necessário.
  - `Imports::OfxParser` — usa gem `ofx` ou similar.
- **Dedup**: chave `(account_id, occurred_at, amount, normalized_description)` antes de inserir. Itens duplicados são reportados.
- **Mesmo fluxo de inbox** que a sync automática (RF2): pré-categorização, aprovação manual, sem bypass.

## AI / categorização inteligente (RF3)

### Decisão: **Google Gemini** como provider inicial, com abstração para trocar

**Por quê Gemini:**
- Você já usa em outro projeto (curva de aprendizado zero).
- Free tier generoso o suficiente para uso pessoal.
- Boa qualidade em PT-BR.

**Arquitetura (provider-agnostic):**

```ruby
module AiProviders
  class Provider
    def suggest_categorization(transaction); raise NotImplementedError; end
    def improve_title(raw_description); raise NotImplementedError; end
  end
end

class AiProviders::GeminiProvider < AiProviders::Provider; end
class AiProviders::ClaudeProvider < AiProviders::Provider; end
class AiProviders::OpenAiProvider < AiProviders::Provider; end
```

- Selecionado via `ENV['AI_PROVIDER'] = 'gemini'` (ou `'claude'`, `'openai'`).
- Modelo específico via `ENV['AI_MODEL']` (ex.: `gemini-2.5-flash`).
- **Cache do aprendizado em DB**: cada correção do usuário vira regra (`descritor → tag/categoria/título`) consultada antes de chamar a API.
- **Fallback determinístico**: se provider falhar/atingir cota, regras manuais cobrem.

## Monitoramento de erros

### Decisão: **Sentry** (SaaS) para backend + frontend

**Por quê Sentry:**
- Padrão de mercado, free tier de 5k erros/mês (suficiente para uso pessoal).
- Cobre backend (`sentry-ruby` + `sentry-rails`) e frontend (`@sentry/react`) com o mesmo projeto.
- Source maps no frontend para stack traces legíveis.
- Performance monitoring opcional (traces) já incluído.

**O que vai para o Sentry:**
- **Backend**: exceções não tratadas, falhas em jobs, erros 5xx, jobs com retry esgotado.
- **Frontend**: exceções no React (via Error Boundary), erros de rede não tratados, breadcrumbs de navegação.
- **Não vai**: dados pessoais (valores de gastos, descrições com PII). Configurar `before_send` para sanitizar.

**Abstração**: encapsulado em `ErrorMonitoring::Reporter` para trocar para Rollbar/Bugsnag/GlitchTip futuramente sem mudar o app.

## Hospedagem, HTTPS e domínio

### Decisão atual: VPS Oracle Cloud `oracle-app-box` + **Cloudflare proxy + kamal-proxy + Let's Encrypt**

**Topologia de TLS (ponta-a-ponta):**
1. Browser → Cloudflare edge — TLS termina aqui com cert da Cloudflare.
2. Cloudflare edge → kamal-proxy (porta 443 da VPS) — segundo TLS, com cert Let's Encrypt validado pela CF (modo **Full strict**).
3. kamal-proxy → container Rails — HTTP interno na docker network `kamal`.

**Por quê dessa forma:**
- Cloudflare proxy esconde o IP da VPS (`147.15.51.128`) e absorve DDoS volumétrico no plano gratuito.
- WAF básico, Bot Fight Mode e analytics ficam disponíveis no dashboard CF.
- Let's Encrypt no kamal-proxy é gerenciado automaticamente pelo Kamal (ACME HTTP-01 na porta 80, renovação transparente).
- Não usamos Cloudflare Tunnel: a VPS já tem portas 80/443 públicas e o tunnel adicionaria um daemon a mais sem ganho real de segurança aqui (DDoS L3/L4 a CF já cobre via proxy comum).

**DNS:**
- `wallet.portilho.cc` (production) e `wallet-staging.portilho.cc` (staging) são A records → IP público da `oracle-app-box`, `proxied: true`.
- Gerenciado via API CF; tokens em `~/.config/controle-financeiro/secrets.env`.

**Acesso ops:**
- SSH só pela rede Tailscale (porta 22 fechada na internet pública).
- Hostname interno: `oracle-app-box` (resolvido pelo MagicDNS do Tailscale).

## Arquitetura

### Topologia
```
[Browser]
   |
   | HTTPS (cert Cloudflare)
   v
[Cloudflare edge — proxy + WAF + DDoS]
   |
   | HTTPS (cert Let's Encrypt, Full strict)
   v
[oracle-app-box :443] -- kamal-proxy --> [Rails container :80] --> [Postgres nativo no host]
                                              |
                                              +--> [Solid Queue worker — in-process via SOLID_QUEUE_IN_PUMA]
                                              +--> [Action Cable]
                                              +--> [Pluggy API]  (HTTPS out)
                                              +--> [Gemini API]  (HTTPS out)
                                              +--> [Sentry]      (HTTPS out)

Frontend (SPA Vite): buildado dentro da imagem Docker, servido pelo Rails em /rails/public.
```

### Camadas no backend Rails
- **Controllers** magros: validam input, chamam service, serializam resposta.
- **Services** orquestram regras de uso de caso.
- **Models** Active Record + lógica de domínio simples e validações.
- **Jobs** (Solid Queue) para tudo assíncrono/agendado.
- **Policies** (Pundit) para autorização por workspace.
- **Providers** (`BankAggregators::*`, `AiProviders::*`, `ErrorMonitoring::Reporter`) atrás de interfaces para troca fácil.

### Camadas no frontend
- **Pages** → **Features** → **Components** → **Hooks** → **API client** tipado.

### Estrutura de repositório (monorepo)
```
controle-financeiro/
├── backend/                   # Rails 8 API
│   ├── config/deploy.yml      # Kamal — base + destination (staging/production)
│   └── .kamal/                # secrets-common + hooks
├── frontend/                  # Vite + React + TS
├── infra/                     # docker-compose.yml (Postgres dev local)
├── docs/                      # PRD, requisitos técnicos, modelo de dados, contratos
├── design-system/             # handoff Claude Design — tokens, kit, ícones
├── Dockerfile                 # multi-stage build (frontend → backend → runtime)
└── .github/workflows/         # CI/CD: test.yml + deploy.yml
```

## Estratégia de testes (TDD)

### Filosofia
- **Test-first sempre**. Cada commit que adiciona comportamento começa pelo teste vermelho.
- **Cada requisito funcional (RF1–RF20, incluindo RF6.6) tem cobertura explícita**. Nenhum RF marcado como "implementado" sem teste correspondente.
- **Critérios de aceitação ANTES do código**: cada RF é decomposto em casos "given/when/then" antes da implementação.

### Ciclo TDD (Red → Green → Refactor)
1. **Red**: escrever o menor teste possível que falha.
2. **Green**: escrever o mínimo de produção para passar.
3. **Refactor**: limpar (produção e teste) sem mudar comportamento.
4. **Commit**: idealmente commit do teste falhando + commit verde.

### Ferramentas — backend
- **Minitest** (default Rails 8 — escolhido conforme sua preferência por "o mais recomendado").
- **FactoryBot** para dados de teste reutilizáveis.
- **VCR** + **WebMock** para isolar APIs externas (Pluggy, Gemini, Sentry).
- **Solid Queue test adapter** para testes síncronos de jobs.
- **DatabaseCleaner** + transações para isolamento.
- **SimpleCov** para relatório de cobertura.

### Ferramentas — frontend
- **Vitest** + **Testing Library (React)** para unitário e componente.
- **MSW (Mock Service Worker)** para mockar API.
- **Playwright** para end-to-end em fluxos críticos.

### Pirâmide e proporção alvo
- **70% unitários**.
- **25% integração**.
- **5% end-to-end**.

### Cobertura — thresholds (confirmados)
- **≥ 90%** em `app/services`, `app/models` e regras de domínio do frontend.
- **≥ 70%** geral.
- CI **falha** se cair abaixo.

### Mapeamento RF → foco de teste

| RF | Foco principal de teste |
|---|---|
| **RF1** Conexão Pluggy | Cliente mockado (VCR), tratamento de erro, retry/idempotência, histórico inicial |
| **RF2** Inbox | Services aceitar/split/rejeitar/remover; validação "soma dos splits = original"; ações em massa |
| **RF3** Pré-categorização | Regras, mock Gemini, aprendizado, confiança da sugestão, abstração de provider |
| **RF4** Consolidados | Edição, histórico, ID único estável, vínculos preservados |
| **RF5** Tags | CRUD, renomear, mesclar, autocomplete |
| **RF6** Categorias | CRUD; **especial RF6.6** — não-duplicação no total geral, soma por categoria com overlap, sinalização visual |
| **RF7** Receitas | Espelha despesas; diferenciação entrada/saída |
| **RF8** Orçamentos | Progresso, projeção, alertas, overlap entre orçamentos |
| **RF9** Recorrentes | Detecção de cadência, "3/12", fatura futura, aviso de recorrente faltante |
| **RF10** Estornos | Algoritmo de sugestão; usuário **sempre** confirma; redução/zeragem; trilha |
| **RF11** Transferências internas | Detecção, exclusão de relatórios, reversão manual |
| **RF12** Entrada manual | CRUD direto para consolidados; origem "Externo/Dinheiro" |
| **RF13** Relatórios | Queries de agregação; **especial RF6.6** total geral consistente |
| **RF14** Períodos | Mês calendário; cartão pelo mês da compra |
| **RF15** Plataforma | E2e mobile + desktop (Playwright) |
| **RF16** Auth + workspace | OAuth Google mockado, policies, fluxo de convite |
| **RF17** Notificações | Emissão in-app via Action Cable |
| **RF18** Exportação | Fora do MVP |
| **RF19** Hospedagem | Smoke tests pós-deploy (HTTPS, auth, health endpoint) |
| **RF20** Importação por arquivo | Parsers CSV/OFX, dedup, casos de borda (encoding, delimitador, valores inválidos), feedback do upload |
| **RF21** Painel sync status | Endpoint de listagem com status agregado; job assíncrono dispara sync e atualiza colunas `status`/`last_sync_at`/`error_message` na tabela `bank_connections`; broadcast via Action Cable para o frontend ouvir mudanças em tempo real; histórico (tabela complementar a definir ou contar via logs do job); testes cobrem todos os estados (`conectado`, `sincronizando`, `erro`, `expirado`) |

### Convenções de teste
- **Backend**: `test/services/transactions/consolidate_service_test.rb` espelha `app/services/transactions/consolidate_service.rb`.
- **Frontend**: `Component.test.tsx` ao lado de `Component.tsx`.
- Nome do teste = comportamento em frase.

## Ambientes e CI/CD

### Ambientes
- **staging** — homologação.
- **production**.
- VMs separadas na Oracle Cloud Always Free.
- Bancos separados; massa de teste em staging.

### Pipeline (GitHub Actions)
1. **PR aberto**: lint + todos os testes + cobertura + comentário no PR.
2. **Merge em `main`**: build Docker → push registry → **deploy automático em staging** via Kamal → smoke tests.
3. **Promoção para produção**: manual via `workflow_dispatch` ou tag `v*` → deploy → smoke tests.
4. **Rollback**: `kamal rollback`.

### Gates obrigatórios para merge
- ✅ Lint sem warnings novos.
- ✅ Testes verdes.
- ✅ Cobertura ≥ threshold.
- ✅ Pelo menos um teste novo se a PR adiciona comportamento.

## Autenticação e autorização

### Login
- **Google OAuth 2.0** via **OmniAuth** + `omniauth-google-oauth2`.
- Sem senha local, sem outros providers no MVP.
- Sessão server-side (cookie HTTP-only, signed).
- **Sem email transacional** (confirmado): nada de SMTP no MVP, sem reset de senha (login Google cobre).

### Autorização
- `Workspace` → `WorkspaceMembership` → `User`.
- Queries escopadas por `current_workspace`.
- Ambos editores plenos (RF16.4). Pundit defensivo.

### Convite (RF16.3)
- Convidado cria conta primeiro (Google).
- Dono adiciona pelo email já cadastrado.

## Hospedagem e infra (resumo)

- **Oracle Cloud Always Free Tier** (Ampere A1 ARM, sa-saopaulo-1).
- **VM única (`oracle-app-box`)** roda staging + production como containers Docker isolados (mesmo host, kamal-proxy roteia por Host header).
- Componentes no host:
  - Docker Engine 29 + buildkit (kamal-proxy + containers de app).
  - PostgreSQL 16 **nativo** (não containerizado) — DBs separados por destination, role `portilho`, conexão via `host.docker.internal`.
  - Tailscale para acesso SSH (porta 22 fechada na internet pública).
- TLS: Cloudflare Full strict (cert CF na borda + Let's Encrypt no kamal-proxy).
- Logs: `STDOUT` com `TaggedLogging` (request_id) → `kamal app logs` agrega via Docker.
- `pg_dump` por app em `~/apps/<nome>/backups/`; retenção/upload off-site fica para fase posterior.

## Ambiente de desenvolvimento (VPS workspace)

Você desenvolve numa **VPS Oracle externa** (separada das VMs de staging/produção), com **Claude Code** como interface — sem IDE GUI tradicional.

### Composição
- **Postgres** roda em **Docker Compose** (`postgres:16-alpine`), volume persistente em `./tmp/db-data`.
- **Ruby + Node nativos** na VPS via **`asdf`** (versões pinadas em `.tool-versions` versionado no repo).
- **Rails API + Vite + Solid Queue worker** rodam nativos via **`bin/dev`** (Rails 8 padrão, usa `foreman`/`overmind` para orquestrar os processos).
- **`bin/setup`** faz bootstrap inicial: instala gems, dependências npm, sobe o container do Postgres, cria DB, roda migrations, popula seeds.
- **Sem devcontainer**: o ambiente nativo da VPS já é o "container" funcional, e não há editor GUI que se beneficiaria da integração.
- **Kamal** roda apenas sob demanda (push de build/deploy para `oracle-app-box`).

### Por que Docker só para o Postgres
- **Parity de versão** com staging/produção garantida via `docker-compose.yml` versionado.
- **Reset/wipe** trivial (`docker compose down -v`).
- Docker já vai estar instalado na VPS workspace de qualquer jeito (build local opcional, Postgres dev).
- Custo marginal de manter o container é insignificante (~150MB RAM na Ampere A1).

### Por que NÃO Docker para Rails/Vite
- TDD exige test runs rápidos — overhead de container atrapalha o feedback loop.
- Debug nativo é mais simples (breakpoint, `rails console`, logs).
- `bin/dev` orquestra tudo nativo sem complicação.

### Workflow típico
```
$ git pull
$ bin/setup           # idempotente: sobe Postgres, migra, semeia
$ bin/dev             # Rails API + Vite + worker em paralelo
$ bin/rails test      # rodada de TDD
```

## Decisões fechadas nesta iteração

| Tema | Decisão |
|---|---|
| Backend | Ruby on Rails 8 (modo API). |
| Frontend | Vite + React + TypeScript + Tailwind + TanStack Query. |
| Banco | PostgreSQL 16+. |
| API | REST + JSON, versionada por path. |
| Jobs / cache / realtime | Solid Queue / Cache / Cable (sem Redis). |
| Integração bancária | Pluggy como primário (multi-banco), abstração para trocar de provider. |
| Importação manual | CSV + OFX no MVP, mesmo fluxo de inbox da sync automática. |
| AI | Google Gemini como provider inicial; abstração `AiProviders::Provider` permite trocar facilmente. |
| Monitoramento | Sentry SaaS, free tier; abstração para futura troca. |
| Email transacional | Sem SMTP no MVP. Login Google cobre o caso de uso. |
| Domínio + HTTPS | `portilho.cc` na Cloudflare. A records para `wallet.portilho.cc` (production) e `wallet-staging.portilho.cc` (staging), proxied. TLS Full strict (CF na borda + Let's Encrypt no kamal-proxy). |
| Test framework backend | Minitest (default Rails 8). |
| Coverage thresholds | ≥90% domínio, ≥70% geral. |
| Hospedagem | Oracle Cloud Always Free (Ampere A1, ARM64). VM única `oracle-app-box` roda staging + production como containers isolados; kamal-proxy roteia por Host header. |
| Deploy | Kamal. |
| Logs | STDOUT com `TaggedLogging` (request_id) inspecionado via `kamal app logs`. Lograge JSON estruturado avaliado quando o volume justificar. |
| Backup off-site | Oracle Object Storage (mesmo provider, free tier 20GB). Sem redundância de provider no MVP. |
| Cloudflare | Conta gratuita + zone `portilho.cc`. Proxy ativo nos A records (esconde IP da VPS, absorve DDoS L3/L4, WAF básico). API token com escopo `Zone:Read + Zone Settings:Edit + DNS:Edit` para automação. |
| Monitoramento (final) | Sentry SaaS (free tier 5k erros/mês). GlitchTip self-hosted considerado e descartado pelo custo de manutenção. |
| Ambiente de desenvolvimento | VPS Oracle externa como workspace. Postgres em Docker Compose para parity de versão; Rails/Vite nativos via asdf. `bin/dev` orquestra processos. Sem devcontainer (Claude Code como editor). |

## Pontos em aberto

Nenhum em requisitos técnicos. Todas as decisões fechadas (ver tabela "Decisões fechadas nesta iteração").

## Ações suas antes do deploy

1. ~~**Conta Cloudflare + zone `portilho.cc`**~~ — feito; A records `wallet.portilho.cc` e `wallet-staging.portilho.cc` apontando para a `oracle-app-box`, proxy ativo, Full strict.
2. ~~**Conta Sentry + projetos backend/frontend**~~ — feito; DSNs em `~/.config/controle-financeiro/secrets.env`.
3. ~~**Conta Oracle Cloud + VM `oracle-app-box`**~~ — feito; Tailscale + Postgres nativo + Docker provisionados.
4. **Criar conta Pluggy** em `pluggy.ai` para obter `clientId` e `clientSecret` — para RF1.
5. **Confirmar acesso à API do Gemini** (Google AI Studio) e gerar uma API key se ainda não tiver — para RF3.

## Próximos passos no plano de engenharia

1. ~~**Modelo de dados**~~ — feito em `docs/modelo-de-dados.md` (v1.0).
2. ~~**Contratos de API v1**~~ — feitos em `docs/contratos-api.md` (v1.0).
3. **Setup do monorepo** (estrutura de pastas, Dockerfile, Kamal config, GitHub Actions skeletons, SimpleCov, Sentry SDK, MSW, etc.).
4. **Plano de implementação em fatias TDD** — cada fatia entrega um RF de ponta a ponta: (1) testes vermelhos, (2) implementação mínima verde, (3) refactor, (4) merge → staging → produção.
5. **Ordem das fatias**: começar pelo fluxo core (RF15 plataforma + RF16 auth + workspace), depois ingestão (RF1 Pluggy + RF20 import por arquivo), depois inbox (RF2 + RF3 AI), depois consolidados (RF4 + RF5 + RF6 incluindo RF6.6), depois agregações (RF8 orçamentos + RF13 relatórios), e por fim o restante.

## Validação deste doc

- Você lê e diz "sim, é assim que quero construir, com TDD desde o primeiro commit".
- Decisões fundamentadas e não arbitrárias.
- Tecnologias batem com seu domínio (Rails + React + Gemini) e seu ambiente (Oracle Cloud).
- Estratégia de testes garante que cada RF do PRD tem rede de segurança.
- Nenhuma decisão técnica fechada deixa um RF inviável.

**Status:** v1.2 — adicionado mapeamento de testes do RF21 (painel sync status) à tabela RF → foco de teste. Sem mudanças estruturais no resto.
