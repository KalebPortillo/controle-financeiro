# Controle Financeiro — Requisitos Técnicos (v1.5)

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
10. **Provedores externos atrás de abstração**: AI, agregador bancário, monitoramento, **canais de notificação** (Telegram via `NotificationChannels::`) — todos por trás de uma interface que permita trocar implementação sem mexer no domínio.

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

### Tempo real (RF17, RF21)
- **Action Cable + Solid Cable**. Montado em `/cable`, auth pelo cookie de sessão
  encriptado (`ApplicationCable::Connection`). Em uso desde o RF21 (`BankConnectionsChannel`,
  painel de sync).
- **Pré-requisito de deploy:** o Solid Cable grava num banco próprio por ambiente
  (`controle_financeiro_<env>_cable`), montado por **schema load** (`db/cable_schema.rb`).
  Rodar `bin/rails db:prepare` no destino antes do primeiro deploy que usa Cable —
  ver `docs/deploy-runbook.md` (#17).

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

### Status de implementação (RF1 + RF21 — em staging)

Entregue em fatias TDD (3a–5c), deployado em staging:

| Item | Estado |
|---|---|
| `BankAggregators::Pluggy` provider (api_key, accounts, transactions, connect_token, get_item) + VCR | ✅ |
| `BankConnection` + `Account` models; `BankConnections::Create` (idempotente) | ✅ |
| Connect flow: `POST /bank_connections/connect_token` + `POST /bank_connections` + widget Pluggy no frontend | ✅ |
| `Transaction` model + `SyncJob` (Solid Queue): puxa transações → inbox (`pending`), dedup por (account, external id) | ✅ |
| REST de gestão (RF21): index+summary, show, sync, sync_all, reconnect, destroy | ✅ |
| Webhook `POST /webhooks/pluggy` — **header secreto `X-Webhook-Secret`** (Pluggy não assina HMAC), não o HMAC do plano original | ✅ |
| Painel `/contas` (RF21.1–21.4) + `BankConnectionsChannel` (Action Cable) empurrando status em tempo real | ✅ |
| **Sandbox por runtime**: `GET /api/v1/app_config` decide `include_sandbox`/`connector_ids` por `RAILS_ENV` (staging só sandbox, prod só real) — não build-time, pois staging/prod são a mesma imagem | ✅ |
| `sync_history` (RF21.7), indicador global no header (RF21.5), notificação in-app de falha (RF21.6) | ✅ |

### Notificações (RF17) — ✅ in-app + Telegram

- **In-app**: tabela `notifications` (broadcast ou dirigida; `dedup_key` com
  unique parcial p/ idempotência), `Notifications::Create` (caminho único:
  persiste + broadcast `NotificationsChannel` + fan-out Telegram), sininho no
  header + painel, REST (`/notifications`), tempo real via Action Cable. Tipos:
  `inbox_new`, `sync_failed` (RF21.6), `recurrent_missed` (job diário).
- **Canal externo atrás de abstração** (mesmo princípio de AI/agregador):
  `NotificationChannels::Telegram` (Net::HTTP, sem gem) — `send_message` com
  inline keyboard, `answer_callback_query`, `edit_message_text`. Vínculo por
  deep-link `startgroup` + webhook `POST /webhooks/telegram` (secret token).
  **Botões inline**: gastos novos (sync ≤5) viram mensagens com Consolidar/
  Rejeitar; o webhook trata `callback_query`, autoriza pelo chat vinculado,
  idempotente. Entrega best-effort (in-app nunca depende do canal externo).
  ENV: `TELEGRAM_BOT_TOKEN`/`TELEGRAM_WEBHOOK_SECRET`/`TELEGRAM_BOT_USERNAME`
  (bot separado por ambiente; re-rodar `telegram:set_webhook` quando
  `allowed_updates` mudar).

> Banco real (Nubank `612`) via Open Finance exige acesso de produção na conta
> Pluggy; teste em staging usa o **sandbox Pluggy Bank** (`user-ok`/`password-ok`,
> connector `2`). Detalhes operacionais em `docs/deploy-runbook.md`.

### Importação manual por arquivo (RF20) — ✅ CSV implementado

- **Endpoint** `POST /api/v1/imports` (multipart, ≤10MB → 413). Arquivo no Active
  Storage; processamento assíncrono via `Imports::ProcessJob` (status
  pending→processing→completed/failed). 202 na criação.
- **Parsers** em `app/services/imports/` (interface `call(content:) → {rows, errors}`):
  - `Imports::CsvParser` — ✅ detecta delimitador (`, ; \t`), mapeia colunas
    (data/descrição/valor) por heurística de cabeçalho + formato; datas BR/ISO,
    decimal com vírgula/ponto. Linha inválida vira erro, não aborta.
  - `Imports::OfxParser` — ⏳ pendente (mesma interface, gem `ofx` ou parser próprio).
- **Dedup**: id sintético determinístico `SHA(account|date|amount|description)` em
  `source_metadata['id']`, reaproveitando o índice unique de `external_transaction_id`
  (rescue RecordNotUnique conta como duplicado). Em `Imports::Process`.
- **Mesmo fluxo de inbox** que a sync automática (RF2): pending, `manual_import`,
  enfileira `BatchSuggestJob` em lotes — pré-categorização e aprovação manual, sem bypass.

## AI / sugestão de título e tags (RF3)

### Escopo e decisões de produto

- Na **inbox** a IA atua só em `status = pending` (consolidados não são retocados):
  **`improved_title`** + **tags sugeridas** (prioriza existentes; nova tag só se
  nenhuma encaixar). Tags sugeridas vão para o catálogo `suggested_tags` (não viram
  tag real até o usuário aceitar — RF3/RF22).
- **Taxonomia ampla**: a IA sugere tags por **tema** (Alimentação, Transporte,
  Assinaturas, Contas da casa…), nunca nome de estabelecimento. Diretriz única em
  `GeminiProvider::TAG_TAXONOMY_GUIDANCE`, usada nos prompts de onboarding e inbox.
- **Categorias**: manuais no uso normal, mas **no onboarding a IA sugere categorias**
  a partir das tags aceitas (2ª análise — `Onboarding::SuggestCategoriesJob`).
- Confiança (`high`/`medium`/`low`) exposta por sugestão.

### Decisão: **Google Gemini** como provider inicial, com abstração para trocar

**Por quê Gemini:**
- Você já usa em outro projeto (curva de aprendizado zero).
- Free tier generoso o suficiente para uso pessoal (≈ 1 M tokens/dia no Flash).
- Boa qualidade em PT-BR.

**Arquitetura (provider-agnostic):**

```ruby
module AiProviders
  class Provider
    # Retorna { improved_title:, tags: [{id:, name:, confidence:}], confidence: }
    # `existing_tags` = lista de tags do workspace (id + name) passada no prompt.
    def suggest(transaction_context:, existing_tags:)
      raise NotImplementedError
    end
  end
end

class AiProviders::GeminiProvider < AiProviders::Provider; end
class AiProviders::ClaudeProvider  < AiProviders::Provider; end
class AiProviders::OpenAiProvider  < AiProviders::Provider; end
```

- Selecionado via `ENV['AI_PROVIDER'] = 'gemini'` (ou `'claude'`, `'openai'`).
- Modelo via `ENV['AI_MODEL']` (ex.: `gemini-2.5-flash`).

### Pipeline de sugestão — **em lote** (executado após o sync/import)

A análise roda em **lote** (não 1 chamada por transação): o `Sync`, o
`Imports::Process` e o `ReanalyzeJob` juntam os ids das transações criadas e
enfileiram `AiSuggestion::BatchSuggestJob` em fatias de **25**. Cada job:

```
1. Regras aprendidas (RF3.2)   → por tx, match? → aplica (confidence=high), NÃO vai pra API.
2. Chamada única à API         → as tx restantes do lote numa só requisição
                                 (AiSuggestion::BatchService → suggest_inbox_batch),
                                 mapeada por transaction_id.
3. Persistência (Persist)      → improved_title + ai_confidence + snapshot ai_suggestion
                                 + tags, por tx.
4. Fallback (API falhou/cota)  → por tx, mantém original_description, sem sugestão.
```

Motivação: antes era 1 `SuggestJob`/tx numa fila de 1 thread → 100 tx =
100 chamadas serializadas (minutos + 100× tokens de prompt). Com o lote são
~4 chamadas para 100 tx. O `SuggestJob` de 1 tx foi aposentado; a fila
`ai_suggestion` segue com **1 thread** (free tier 15 RPM), polling 1s.

### Performance da chamada ao Gemini (`generationConfig`)

Para classificação estruturada não precisamos do raciocínio interno do modelo.
O `GeminiProvider` envia em toda chamada:
- `thinkingConfig: { thinkingBudget: 0 }` — desliga o *thinking* do 2.5-flash
  (maior ganho de latência/tokens);
- `maxOutputTokens: 2048` — limita a saída ao JSON esperado (cabe um lote de ~25);
- `temperature: 0.2` — classificação determinística;
- `responseMimeType: "application/json"`.

### Dados enviados à IA (prompt compacto)

Lidos do `source_metadata` JSONB já armazenado — **sem nova coluna no DB**:

| Campo extraído | Fonte no JSONB |
|---|---|
| Descrição | `description` / `descriptionRaw` |
| Nome do estabelecimento | `merchant.businessName` |
| CNAE do estabelecimento | `merchant.cnae` |
| Categoria Pluggy (hint) | `category` (string em inglês) |
| Método de pagamento | `paymentData.paymentMethod` |
| Nome do destinatário | `paymentData.receiver.name` |
| Valor + direção | `amount` + `type` |

O prompt inclui também a **lista completa de tags existentes no workspace** (`id` + `name`), para que a IA escolha por ID — eliminando ambiguidade e evitando criação desnecessária.

### Dois modos de operação

O service detecta o modo com base no número de tags existentes no workspace no momento do sync:

| Modo | Condição | Comportamento da IA |
|---|---|---|
| **Onboarding** | `tags.count == 0` | Sugere nomes de tags novas livremente; objetivo é construir a taxonomia inicial. Sem IDs para referenciar. |
| **Normal** | `tags.count > 0` | Prioriza tags existentes por ID; sugere tag nova só como fallback. |

No modo **onboarding**, o job processa as transações em **lote único** (todas de uma vez no prompt), pedindo à IA que sugira um conjunto coerente de tags para todo o lote — evitando inconsistências como `"Supermercado"` e `"Mercado"` para o mesmo tipo de gasto.

### Estrutura do prompt — modo normal (tags existem)

```
Você é um assistente de finanças pessoais. Dado o gasto abaixo, retorne JSON:
{
  "improved_title": "Nome legível em PT-BR (máx 50 chars)",
  "suggested_tag_ids": ["uuid1", "uuid2"],   // IDs das tags existentes, mais relevantes primeiro
  "new_tag_suggestion": "nome da tag" | null, // só se nenhuma existente encaixar
  "confidence": "high" | "medium" | "low"
}

Tags disponíveis: [{"id":"...","name":"..."},...]

Gasto:
- Descrição: {description}
- Estabelecimento: {merchant_name} (CNAE: {cnae})
- Categoria do banco: {pluggy_category}
- Método: {payment_method}
- Destinatário: {receiver_name}
- Valor: R$ {amount} ({direction})
```

### Estrutura do prompt — modo onboarding (sem tags)

```
Você é um assistente de finanças pessoais. O usuário não tem nenhuma tag criada ainda.
Analise as transações abaixo e:
1. Sugira um título legível em PT-BR para cada uma.
2. Sugira tags em PT-BR para cada transação. Seja consistente: transações similares
   devem receber a mesma tag. Prefira nomes genéricos e reutilizáveis
   (ex.: "Mercado", "Delivery", "Transporte", "Assinatura").
3. Retorne JSON com o array de resultados na mesma ordem das transações de entrada.

Formato de saída:
[
  {
    "transaction_id": "...",
    "improved_title": "...",
    "suggested_new_tags": ["Mercado", "Alimentação"],  // nomes a criar
    "confidence": "high" | "medium" | "low"
  },
  ...
]

Transações:
[
  { "id": "...", "description": "...", "merchant": "...", "category": "...", "method": "...", "amount": ..., "direction": "..." },
  ...
]
```

O job de onboarding processa no máximo **50 transações por chamada** (para não exceder o limite de contexto). Se houver mais, divide em lotes de 50 com a mesma lista de tags emergentes acumulada entre os lotes.

### Reanálise sob demanda (RF3.5) — `POST /api/v1/transactions/reanalyze`

Endpoint acionado pelo botão "Reanalisar com IA" na inbox. Enfileira `AiSuggestion::ReanalyzeJob` para o workspace.

**O que o job processa:**
- Todas as transações `pending` do workspace que atendam a pelo menos um critério:
  - `improved_title IS NULL` (nunca foi processada pela IA)
  - `ai_confidence = 'low'` (IA não teve confiança na primeira rodada)
  - Tags vazias (nenhuma tag aplicada, nem pelo usuário nem pela IA)
- Transações com tags já definidas pelo usuário (confidence = high) são **ignoradas** — não sobrescreve preferências já expressas.

**Contexto atualizado:**
- No momento da reanálise, o job carrega o estado atual de `ai_learned_rules` e `tags` do workspace — portanto reflete tudo que foi aprendido desde o último sync.
- Se já existem tags no workspace, usa o modo normal (prioriza existentes). Se ainda não existem, usa o modo onboarding (sugere novas).

**Pipeline do job:** o `ReanalyzeJob` separa as elegíveis em lotes de **25** e
enfileira um `BatchSuggestJob` por lote (mesmo pipeline em lote da seção acima:
regras aprendidas por tx → 1 chamada para o resto → persiste por tx).

**Resposta ao frontend:** o endpoint retorna `{ enqueued: true, pending_count: N }`
imediatamente (202). O frontend acompanha o **progresso real** via
`GET /api/v1/transactions/analysis_progress` → `{ total, analyzed, done }` (uma
pending conta como analisada quando já tem `ai_suggestion`), e a barra anda em
degraus de batch até `done`, quando recarrega a inbox.

### Aprendizado passivo (RF3.2) — tabela `ai_learned_rules`

**Como é detectado**: o `TransactionsController#update` já grava `TransactionEdit` para cada campo alterado. Um `after_create` callback (ou concern) em `TransactionEdit` dispara `AiLearning::RecordCorrectionJob` quando `field_name` é `improved_title` ou `tags`.

**Schema da tabela:**
```
ai_learned_rules
  id                uuid PK
  workspace_id      uuid FK
  descriptor_pattern text   -- descritor normalizado (núcleo semântico, lowercase)
  improved_title    text   -- preferência aprendida de título (nullable)
  tag_ids           uuid[] -- preferência aprendida de tags (nullable)
  match_count       int    -- vezes que esse padrão foi confirmado/corrigido
  last_seen_at      datetime
  created_at / updated_at
  UNIQUE(workspace_id, descriptor_pattern)
```

**Normalização do descritor** (`AiLearning::Normalizer`):
- Lowercase
- Remove tokens numéricos longos (refs, CPFs mascarados): `/\b\d{4,}\b/`
- Remove datas no descritor: `/\d{2}\/\d{2}(\/\d{2,4})?/`
- Remove caracteres especiais exceto espaço
- Colapsa espaços múltiplos
- Exemplo: `"PGTO PIX 43958 IFOOD*RESTAURANTE XYZ 05/26"` → `"pgto pix ifood restaurante xyz"`

**Uso na sugestão**: antes de chamar a API, `AiSuggestion::Service` faz lookup por `descriptor_pattern` com similaridade fuzzy (trigram `pg_trgm` ou simples `LIKE '%pattern%'`). Match acima de threshold → aplica a regra, `confidence = high`, não chama a API.

**Atualização**: se o usuário corrigir uma regra já aprendida (editar novamente), o registro é `upsert`-ado com os novos valores e `match_count` incrementado.

**Visibilidade**: endpoint `GET /api/v1/ai_learned_rules` retorna as regras para exibição + `DELETE /api/v1/ai_learned_rules/:id` para o usuário apagar.

### Regras manuais (RF3.3) — tabela `manual_rules`

`manual_rules(workspace_id, pattern, match_type, tag_ids, improved_title)` onde `match_type` ∈ `{exact, prefix, glob}`. Gerenciadas via UI (fora do MVP inicial — entram depois do aprendizado passivo estar estável).

### Fallback e resiliência

- Timeout de 8 s na chamada à API. Se estourar → `improved_title = original_description`, tags vazias, confidence = nil.
- Erros de quota/rede → idem. O usuário categoriza manualmente na inbox normalmente.
- VCR em testes: cassettes gravam a chamada real ao Gemini uma vez; CI sempre usa o cassette.

## Onboarding de novo usuário (RF22)

Fluxo guiado de 3 passos para o dono do workspace recém-criado. Não é uma
feature stand-alone — orquestra peças que já existem (Pluggy, AiProviders,
Tag, Category) com um wrapper de estado e UI dedicada.

### Persistência de estado — campo `onboarding_state` no Workspace

Decisão: **jsonb no `workspaces`**, não tabela própria.

Motivo: relação é 1-1 com workspace, não há histórico a manter, e o conjunto
de campos vai evoluir várias vezes durante implementação. Schema flexível
elimina ciclos de migration por mudança pequena.

```ruby
# Migration
add_column :workspaces, :onboarding_state, :jsonb, default: { "status" => "not_started" }
add_index :workspaces, "(onboarding_state ->> 'status')",
          name: "index_workspaces_on_onboarding_status"
```

Shape do JSON:

```json
{
  "status": "not_started | connecting | analyzing | tagging | categorizing | completed | skipped",
  "started_at": "2026-05-29T20:00:00Z",
  "completed_at": null,
  "suggested_tags":       [{ "name": "Mercado",  "rationale": "8 transações em mercados" }, …],
  "suggested_categories": [{ "name": "Alimentação", "tag_names": ["Mercado","Padaria"] }, …],
  "accepted_tag_ids":     ["uuid", …],
  "accepted_category_ids":["uuid", …]
}
```

### Quem dispara, quando

- **RF22.1 detecção**: o frontend não decide — pergunta ao backend.
  `GET /sessions/current` passa a incluir `onboarding_state` do workspace ativo,
  e o `RequireAuth` redireciona pra `/onboarding` se `status ∈ {not_started,
  connecting, analyzing, tagging, categorizing}`. Estados `completed` e
  `skipped` deixam o app fluir normal.
- **RF22.2 só pro dono**: lookup checa `workspace.created_by_user == current_user`.
  Membros convidados nunca veem o fluxo.

### Endpoints

```
GET  /api/v1/onboarding           → { status, current_step, suggested_*, accepted_* }
POST /api/v1/onboarding/start     → marca status='connecting', started_at=now
POST /api/v1/onboarding/skip      → marca status='skipped'  (qualquer hora)
POST /api/v1/onboarding/advance   → idempotente; transiciona pro próximo step
                                    válido baseado no estado atual
POST /api/v1/onboarding/tags      → body { accepted: [{ name }] }
                                    cria as tags, persiste accepted_tag_ids,
                                    avança pra 'categorizing'
POST /api/v1/onboarding/categories → body { accepted: [{ name, tag_ids }] }
                                    cria as categorias, persiste, completed
GET  /api/v1/onboarding/suggestions/tags?offset=N → próximos 10
GET  /api/v1/onboarding/suggestions/categories?offset=N → próximos 10
```

Todos exceto `start` exigem que `status != 'not_started'`. `start` exige
o oposto (idempotente se já foi chamado).

### Análise IA — `Onboarding::AnalyzeJob`

Dispara automaticamente assim que o sync inicial do passo 1 termina, **se**
o workspace está em `connecting` ou `analyzing`.

Encadeamento de eventos:
1. `Onboarding#start` → `status = connecting`.
2. Usuário conecta no Pluggy → `BankConnections::Create` → `SyncJob.perform_later`.
3. `SyncJob` ao terminar com sucesso → enfileira `Onboarding::AnalyzeJob` se
   `workspace.onboarding_state['status'] == 'connecting'`. Atualiza para
   `analyzing` no mesmo update.
4. `Onboarding::AnalyzeJob`:
   - Carrega todas as transações pending do workspace (no máximo as últimas
     200 — limite de contexto da API).
   - Chama `AiProviders::GeminiProvider#suggest_onboarding` (método novo)
     com prompt de descoberta de tags+categorias em PT-BR.
   - Persiste resultados em `suggested_tags` e `suggested_categories`.
   - Atualiza `status = 'tagging'`.
5. Frontend, no passo 2, consome `GET /onboarding` e renderiza os 10
   primeiros de `suggested_tags`.

**Modo aditivo** (re-execução via RF22.10):

- Mesmo `AnalyzeJob`, mas chamado com flag `mode: 'additive'`. Carrega
  `Tag.where(workspace: ws).pluck(:name)` e passa no prompt como exclusion
  list — IA só sugere o que falta. Idem categorias.
- Resultado vai direto pro estado de onboarding como se fosse a primeira
  rodada, mas o frontend renderiza um modal de revisão em vez do fluxo
  completo (não há passo 1).

### Prompt da análise inicial (modo discovery)

```
Você é um assistente de finanças pessoais. Analise as transações abaixo
e descubra a taxonomia que melhor descreve o padrão de gastos do usuário.

Retorne JSON:
{
  "tags": [
    {
      "name": "Nome em PT-BR (1-3 palavras, máx 30 chars)",
      "rationale": "frase curta dizendo por que essa tag aparece",
      "coverage": número-aproximado-de-transações-que-encaixam
    }
  ],
  "categories": [
    {
      "name": "Nome em PT-BR (1-3 palavras)",
      "tag_names": ["nomes de tags do array acima que pertencem aqui"]
    }
  ]
}

Regras:
- Tags são granulares (estabelecimento ou tipo específico).
- Categorias agrupam tags por afinidade (uma tag pode estar em + de uma
  categoria).
- Ordene tags por coverage decrescente.
- Gere quantas tags e categorias forem relevantes — não há limite mínimo
  nem máximo, mas tente NÃO repetir conceitos.
- Apenas tags com cobertura ≥ 1 transação.

Transações:
[ { id, descrição, merchant, categoria-pluggy, valor, direction }, … ]
```

### Pré-categorização durante o sync inicial

**Decisão deliberada**: enquanto `status ∈ {connecting, analyzing, tagging,
categorizing}`, o `Sync` **não** enfileira `AiSuggestion::BatchSuggestJob`.
Razões:

1. Sem tags criadas, a IA cairia em modo onboarding (RF3.1) e geraria tags
   inconsistentes uma a uma — exatamente o problema que esse RF22 resolve.
2. Custo de tokens duplicado (uma chamada por transação + a análise em batch).

Quando o usuário **completa** o onboarding (`status = completed`), um único
`AiSuggestion::ReanalyzeJob` é enfileirado para o workspace. Esse roda o
modo normal — com as tags criadas — e aplica sugestões em todas as pending.

### Pular: efeitos por estado

| Onde pula | Status final | O que acontece |
|---|---|---|
| Passo 1 (sem conexão) | `skipped` | Vai pro inbox vazio. Pluggy/CSV pode ser conectado depois pela UI normal. |
| Passo 2 (depois de conectar) | `completed` | Vai pro inbox. `ReanalyzeJob` ainda dispara mas IA opera em modo onboarding (cria tags livremente). |
| Passo 3 (depois de criar tags) | `completed` | Vai pro inbox. Tags existem; IA opera em modo normal. Categorias podem ser criadas depois pela UI. |
| "Pular onboarding" em qualquer passo | `skipped` | Igual ao acima, mas `started_at`/`completed_at` ficam nulos. |

### Frontend — fluxo

- Nova rota `/onboarding` no React Router, fora do `AppLayout` (não tem
  sidebar/topbar — é fullscreen guiado).
- Componentes: `<OnboardingShell />` (steps indicator + skip total) com
  rotas filhas `/onboarding/conectar`, `/onboarding/tags`, `/onboarding/categorias`.
- `useOnboardingState()` faz polling leve (5s) quando está em `connecting`
  ou `analyzing`, para detectar fim do sync/análise. Action Cable seria o
  ideal mas exige canal novo — polling é suficiente pro MVP.
- Pluggy widget reaproveita `<ConnectBankButton>` já existente.

### Testes (RF22)

| Camada | Foco |
|---|---|
| Backend models | `workspace.onboarding_state` defaults e transições |
| Backend service `Onboarding::Service` | start/advance/skip; idempotência |
| Backend job `Onboarding::AnalyzeJob` | dispara após SyncJob com sucesso; modo discovery vs additive; persiste em estado |
| Backend integration | endpoints, autorização (só dono) |
| Frontend component | OnboardingShell, cada step, skip flow |
| E2E | golden path: login → conectar → analisar → aceitar tags → aceitar categorias → inbox |

## Feedback de erro ao usuário (camada uniforme)

Erro de API nunca deve virar spinner infinito ou silêncio. Princípio: **amigável +
motivo** — mostra a categoria legível, nunca o corpo cru da API (o detalhe técnico
vai pro log/Sentry).

**Frontend — toasts globais (ações do usuário).** O `QueryClient`
(`src/api/queryClient.ts`) tem um `MutationCache.onError` que dispara um toast
(Sonner) por mutation falha, mapeando o erro via `errorFeedback()`
(`src/api/errorMessage.ts`): rede caída → "Sem conexão"; 429 → "Limite atingido";
5xx → "Erro no servidor"; 422 → mensagem do backend; 403 → "Sem permissão". 401 é
ignorado (o fluxo de auth redireciona). Opt-out por mutation via
`meta: { silent: true }` quando a tela já mostra erro inline (ex.: `ImportarPage`).
Queries **não** geram toast (evita ruído de polling). O `<Toaster>` é montado uma
vez em `main.tsx`. Toast é pra evento efêmero; estado de erro persistente usa o
componente `Alert` (`src/components/Alert.tsx`, bordas não sombras).

**Backend — erro de IA classificado + canal assíncrono.** Jobs de IA respondem 202
e falham depois, então o erro não cabe num toast — vai por um canal de estado.
`AiProviders::ApiError` carrega `reason` (`:quota` | `:rate_limit` | `:unavailable`
| `:error`), `user_message` (PT-BR) e `retryable?` (quota é permanente até recarga
de crédito). `GeminiProvider#call_api` classifica o HTTP/rede. O último erro
não-recuperável fica em `workspaces.ai_last_error` (jsonb `{reason, message, at}`),
gravado pelos jobs (`Onboarding::AnalyzeJob`, `AiSuggestion::BatchSuggestJob`) e
**limpo no próximo sucesso** de IA. Em `:quota` os jobs **não** re-tentam (evita o
hang de ~6 min de backoff); transitórios seguem o `retry_on`. A UI lê o canal via
`onboarding#show` (`analysis_error`) e `analysis_progress` (`error`): card no
onboarding ("Continuar manualmente") e banner na inbox ("Tentar de novo", que
limpa o erro e reanalisa).

**Libs:** toast = **Sonner** (sancionado no design system, §Feedback).

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
- **Playwright** para end-to-end em fluxos críticos — vive em `frontend/tests/e2e/`,
  configurado em `frontend/playwright.config.ts`. Roda contra Rails (test env) + Vite preview.

### Estratégia de E2E

Os E2E **não** testam o handshake real com o Google (UI muda e exige conta real);
exercitam o resto da pilha (rota → cookie de sessão → frontend renderizado) num browser real.

- **Bypass de auth em non-production**: `POST /api/v1/auth/test_sign_in` (gated por
  `unless Rails.env.production?` em `routes.rb`) cria/loga user via o **mesmo**
  `Users::CreateWithPersonalWorkspace` que o callback OAuth — então o user fica com
  workspace pessoal idêntico ao fluxo real. Playwright usa esse endpoint pra entrar
  no app sem passar pela tela do Google.
- **Escopo (golden paths)**: visitor anônimo redireciona pra `/login`; user logado
  vê dashboard; logout volta pra login; sessão persiste após reload; convite por
  email cadastrado adiciona membro; convite por email não cadastrado mostra erro
  amigável. **Sem edge cases** — esses ficam em testes específicos quando entrarem
  em conflito.
- **Quando rodar**: `npm run test:e2e` local (~40s); job dedicado no CI gateia
  todos os deploys (`needs: test` em deploy.yml inclui o job e2e).

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
| **RF22** Onboarding | Transições de `onboarding_state`; idempotência de `start/advance/skip`; `AnalyzeJob` dispara após SyncJob com sucesso e só em modo `discovery` quando workspace está em `connecting`; modo `additive` exclui tags/categorias existentes do prompt; só dono passa pelo fluxo; pular em cada passo leva ao status correto (`skipped` vs `completed`); reanalyze enfileirado uma vez ao completar |

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
- ✅ Testes verdes (Minitest backend + Vitest frontend + **Playwright E2E golden paths**).
- ✅ Cobertura ≥ threshold.
- ✅ Pelo menos um teste novo se a PR adiciona comportamento.
- ✅ Deploys (staging em push em `main`, production em tag `v*`) só disparam após
  o job de E2E passar.

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

### Status de implementação (RF16 — v0.2.0-rf16-auth em produção)

| Item | Estado |
|---|---|
| `User` model (UUID, email citext, google_uid, name, avatar_url) | ✅ |
| `Workspace` + `WorkspaceMembership` (role check-constrained editor/viewer) | ✅ |
| OmniAuth Google callback (`/api/v1/auth/google_oauth2/callback`) | ✅ |
| `Users::CreateWithPersonalWorkspace` (cria user + workspace + membership numa transação) | ✅ |
| Sessions endpoints (`/api/v1/sessions/current` GET/DELETE + `select_workspace`) | ✅ |
| Workspaces + Memberships REST (RF16.3 convite por email cadastrado, 404 user_not_found) | ✅ |
| Rack::Attack throttle 10 req/min por IP em `/api/v1/auth/*` | ✅ |
| Pundit | ⏳ não wired — scoping via `current_user.workspaces.find(id)` resolve RF16; entra quando RF tiver authz granular |
| CSRF token em rotas mutadoras | ⏳ defer — SPA same-origin + cookie SameSite=Lax cobre o MVP do casal |

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

**Status:** v1.6 — RF1 (Pluggy: connect + sync + webhook) e RF21 core (painel de
sync via Action Cable) implementados em fatias TDD e deployados em **staging**.
Adicionados: status de implementação RF1/RF21, sandbox por runtime config
(`/api/v1/app_config`) e pré-requisito do banco `cable` (Solid Cable) no deploy.
RF16 (auth Google OAuth + workspace) em produção em `v0.2.0-rf16-auth`. Lições e
armadilhas de campo do CI/deploy ficam em [`docs/deploy-runbook.md`](./deploy-runbook.md).

v1.5 — adicionada estratégia detalhada de E2E (Playwright + bypass route + CI gate).
