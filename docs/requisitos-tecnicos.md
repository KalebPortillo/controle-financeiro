# Controle Financeiro — Requisitos Técnicos (v1.1)

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

### Decisão atual: VPS Oracle Cloud + **Cloudflare Tunnel** para HTTPS sem domínio próprio

**Como vai funcionar enquanto não há domínio:**
- VM Ampere A1 (Always Free) na Oracle Cloud roda a aplicação.
- **Cloudflare Tunnel "named"** (`cloudflared`) conecta a VM à rede Cloudflare por uma conexão de saída — **não precisa abrir portas inbound na VM** (mais seguro).
- Cloudflare expõe um hostname **estável** com **HTTPS automático** (certificado Cloudflare).
- **Ação sua antes do deploy**: criar conta gratuita Cloudflare (~2 minutos em `cloudflare.com/sign-up`). É grátis e não exige domínio próprio.
- Não usamos "quick tunnel" porque a URL muda a cada restart — inviável para staging/produção.

**Quando você registrar o domínio (próximo passo):**
- Apontar DNS do domínio para Cloudflare (gratuito).
- Migrar de Tunnel "provisório" para o domínio definitivo em minutos (mesma config, hostname diferente).
- Manter Cloudflare Tunnel (não precisa abrir portas) **OU** mover para Kamal Proxy direto + Let's Encrypt — decidir quando chegarmos lá. Tunnel é mais seguro; Kamal Proxy é menos infra.

**Implicação no Kamal:**
- Kamal Proxy continua servindo a app dentro da VM (porta 8080 ou similar).
- `cloudflared` redireciona o tráfego externo HTTPS para essa porta interna.
- Configurações ficam em `infra/cloudflare-tunnel/`.

## Arquitetura

### Topologia
```
[Browser] --HTTPS--> [Cloudflare Edge] --Tunnel--> [VM Oracle] --> [Rails API] --> [Postgres]
                                                                      |
                                                                      +--> [Solid Queue worker]
                                                                      +--> [Action Cable]
                                                                      +--> [Pluggy API] (HTTPS out)
                                                                      +--> [Gemini API] (HTTPS out)
                                                                      +--> [Sentry] (HTTPS out)
[Browser] --HTTPS--> [Cloudflare Edge] --Tunnel--> [VM Oracle] --> [Static SPA (Vite build)]
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
├── backend/         # Rails 8 API
├── frontend/        # Vite + React + TS
├── infra/           # Kamal config, Dockerfiles, Cloudflare Tunnel config
├── docs/            # PRD, requisitos técnicos, etc.
└── .github/workflows/  # CI/CD pipelines
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

- **Oracle Cloud Always Free Tier** (Ampere A1 ARM).
- 1 VM staging + 1 VM produção.
- Cada VM: Rails + Postgres + Solid Queue + cloudflared.
- **Cloudflare Tunnel** para HTTPS sem domínio próprio (provisório). Migração futura quando registrar domínio.
- Lograge para logs JSON estruturados; inspeção via `kamal app logs`.
- `pg_dump` diário; retenção 7d local + 30d em **Oracle Object Storage** (mesmo provider, free tier 20GB).

## Ambiente de desenvolvimento (VPS workspace)

Você desenvolve numa **VPS Oracle externa** (separada das VMs de staging/produção), com **Claude Code** como interface — sem IDE GUI tradicional.

### Composição
- **Postgres** roda em **Docker Compose** (`postgres:16-alpine`), volume persistente em `./tmp/db-data`.
- **Ruby + Node nativos** na VPS via **`asdf`** (versões pinadas em `.tool-versions` versionado no repo).
- **Rails API + Vite + Solid Queue worker** rodam nativos via **`bin/dev`** (Rails 8 padrão, usa `foreman`/`overmind` para orquestrar os processos).
- **`bin/setup`** faz bootstrap inicial: instala gems, dependências npm, sobe o container do Postgres, cria DB, roda migrations, popula seeds.
- **Sem devcontainer**: o ambiente nativo da VPS já é o "container" funcional, e não há editor GUI que se beneficiaria da integração.
- **Kamal Proxy e cloudflared** não rodam 24/7 no dev — só são levantados sob demanda quando você quiser testar deploy ou tunnel local.

### Por que Docker só para o Postgres
- **Parity de versão** com staging/produção garantida via `docker-compose.yml` versionado.
- **Reset/wipe** trivial (`docker compose down -v`).
- Docker já vai estar instalado na VPS workspace de qualquer jeito (Kamal local, cloudflared testing).
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
| Domínio + HTTPS | Sem domínio próprio inicialmente. Cloudflare Tunnel fornece HTTPS. Migração planejada quando registrar domínio. |
| Test framework backend | Minitest (default Rails 8). |
| Coverage thresholds | ≥90% domínio, ≥70% geral. |
| Hospedagem | Oracle Cloud Always Free (Ampere A1), 1 VM por ambiente. |
| Deploy | Kamal. |
| Logs | Lograge stdout estruturado + `kamal app logs`. |
| Backup off-site | Oracle Object Storage (mesmo provider, free tier 20GB). Sem redundância de provider no MVP. |
| Cloudflare | Conta gratuita + Tunnel "named" para hostname estável e HTTPS sem domínio próprio. Migração para domínio futura quando registrado. |
| Monitoramento (final) | Sentry SaaS (free tier 5k erros/mês). GlitchTip self-hosted considerado e descartado pelo custo de manutenção. |
| Ambiente de desenvolvimento | VPS Oracle externa como workspace. Postgres em Docker Compose para parity de versão; Rails/Vite nativos via asdf. `bin/dev` orquestra processos. Sem devcontainer (Claude Code como editor). |

## Pontos em aberto

Nenhum em requisitos técnicos. Todas as decisões fechadas (ver tabela "Decisões fechadas nesta iteração").

## Ações suas antes do deploy

1. **Criar conta gratuita Cloudflare** em `cloudflare.com/sign-up` (~2 min). Usaremos para Tunnel "named" e HTTPS sem domínio próprio.
2. **Criar conta Sentry** em `sentry.io/signup` (free tier). Usar OAuth com Google para alinhar com a auth da aplicação.
3. **Criar conta Pluggy** em `pluggy.ai` para obter `clientId` e `clientSecret`.
4. **Confirmar acesso à API do Gemini** (Google AI Studio) e gerar uma API key se ainda não tiver para esse projeto.
5. **Conta Oracle Cloud Always Free** com 1+ VM Ampere A1 disponível (você já tem).

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

**Status:** v1.1 — adicionada seção "Ambiente de desenvolvimento (VPS workspace)" com Postgres em Docker Compose + Rails/Vite nativos via asdf.
