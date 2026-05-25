# Controle Financeiro — Requisitos de Design (v1.0)

## Contexto

Doc complementar ao PRD v1.2, Requisitos Técnicos v1.1, Modelo de Dados v1.0 e Contratos de API v1.0. Define a **direção de UX/UI** que orienta a implementação do frontend (Vite + React + Tailwind + shadcn/ui).

**Decisões âncora confirmadas:**
- **Vibe**: clean & minimal (referência: Linear / Notion).
- **Sistema de componentes**: shadcn/ui (Radix UI + Tailwind).
- **Tema**: claro + escuro com toggle.

## Princípios de UX

1. **Conteúdo primeiro, cromo depois.** Os gastos, valores, gráficos têm que respirar. Decoração ornamental é cortada.
2. **Inbox como hub.** A primeira tela após login é a inbox — o lugar onde mora trabalho pendente. Tudo que demanda atenção do casal converge ali.
3. **Estados visíveis, não escondidos.** Loading, empty, error, success — cada estado tem visual próprio. Nunca uma tela vazia sem feedback.
4. **Ações reversíveis, confirmações curtas.** Aceitar gasto = um clique. Split = wizard de 2 passos. Deletar definitivo = confirmação. Estornar = sugestão + confirmação.
5. **Toda ação tem keyboard shortcut no desktop.** `J/K` para navegar lista, `A` para aceitar, `R` para rejeitar, `/` para focar busca. Mobile: gestos (swipe).
6. **Densidade configurável.** Default confortável; usuário pode ativar "modo compacto" em listas (mais linhas visíveis).
7. **Toques, não cliques, no mobile.** Áreas de toque ≥ 44×44px; FAB para criação rápida; bottom nav fixo.
8. **Acessibilidade nativa.** Contraste WCAG AA mínimo; navegação por teclado completa; aria labels corretos (shadcn/ui já entrega isso).

## Identidade visual

### Paleta — modo claro

| Token | Hex | Uso |
|---|---|---|
| `background` | `#FFFFFF` | fundo da página |
| `foreground` | `#0A0A0A` | texto principal |
| `card` | `#FFFFFF` | cards/painéis |
| `muted` | `#F5F5F5` | fundos secundários (toolbar, sidebar) |
| `muted-foreground` | `#737373` | texto secundário |
| `border` | `#E5E5E5` | divisórias sutis |
| `primary` | `#171717` | CTA primário (botão "Aceitar", etc.) |
| `accent` | `#7C3AED` | links, foco, destaques discretos (Violet 600 — Linear-style) |
| `success` | `#16A34A` | receita, valores positivos (Green 600) |
| `warning` | `#F59E0B` | orçamento próximo do teto (Amber 500) |
| `destructive` | `#DC2626` | excluir, estorno, gasto rejeitado (Red 600) |

### Paleta — modo escuro

| Token | Hex | Uso |
|---|---|---|
| `background` | `#0A0A0A` | fundo da página |
| `foreground` | `#FAFAFA` | texto principal |
| `card` | `#171717` | cards/painéis |
| `muted` | `#262626` | fundos secundários |
| `muted-foreground` | `#A3A3A3` | texto secundário |
| `border` | `#262626` | divisórias |
| `primary` | `#FAFAFA` | CTA primário invertido |
| `accent` | `#A78BFA` | links, foco (Violet 400) |
| `success` | `#22C55E` | (Green 500) |
| `warning` | `#FBBF24` | (Amber 400) |
| `destructive` | `#EF4444` | (Red 500) |

### Tipografia
- **Sans**: **Geist Sans** (Vercel) ou **Inter** como fallback — moderno, ótima legibilidade em tamanhos pequenos.
- **Mono**: **Geist Mono** (Vercel) ou **JetBrains Mono** — usado em valores monetários para alinhamento de dígitos.
- **Escala**:
  - Display (overview header): `text-4xl` / `font-semibold`
  - Heading 1: `text-2xl` / `font-semibold`
  - Heading 2: `text-xl` / `font-medium`
  - Body: `text-sm` / `font-normal` — base do app
  - Caption: `text-xs` / `font-normal` — metadata (data, conta)
  - Money: `font-mono` / `font-medium` / `tabular-nums`

### Espaçamento, radius, sombras
- **Espaçamento**: escala Tailwind padrão (4px base). Padding de cards: `p-4` (16px) mobile, `p-6` (24px) desktop.
- **Border radius**: `rounded-md` (6px) default. Cards: `rounded-lg` (8px). Inputs: `rounded-md`. Botões: `rounded-md`. Nada de `rounded-2xl` ou pílulas — vibe Linear é discreta.
- **Sombras**: praticamente nenhuma. Borders dão a separação. Apenas modais e dropdowns usam `shadow-lg`.

### Iconografia
- **Lucide Icons** (lucide-react) — pacote oficial do shadcn/ui, neutro, vibe Linear/Notion.
- Tamanho default `h-4 w-4` (16px). Em ações primárias, `h-5 w-5` (20px).

## Sistema de componentes (shadcn/ui)

### Componentes que entram no MVP
- **Form**: `Input`, `Textarea`, `Select`, `Combobox` (para tag/categoria autocomplete), `Checkbox`, `RadioGroup`, `Switch`, `DatePicker`.
- **Layout**: `Card`, `Sheet` (drawer mobile), `Dialog` (modal), `Tabs`, `ScrollArea`, `Separator`.
- **Feedback**: `Toast` (Sonner), `Alert`, `Skeleton` (loading), `Progress`, `Badge`.
- **Data**: `Table`, `Pagination`, custom `TransactionRow` baseado em primitivas.
- **Navegação**: `Sidebar` (desktop), `BottomNav` (mobile — custom, baseado em Tabs/NavigationMenu).
- **Charts**: usar **Recharts** ou **Tremor** (Tremor combina muito bem com shadcn/ui). Recomendação: **Tremor** para charts financeiros prontos (donut, area, bar).

### Variants padronizadas
- **Button**: `default`, `secondary`, `outline`, `ghost`, `destructive`. Tamanhos: `sm`, `default`, `lg`, `icon`.
- **Badge**: `default`, `secondary`, `outline`, `destructive`, `success`, `warning`. Cores derivam dos tokens.

## Information Architecture

### Navegação principal (mobile e desktop)
1. **Inbox** (com badge de contagem de pendentes)
2. **Gastos** (consolidados, com filtros)
3. **Orçamentos**
4. **Relatórios**
5. **Mais** (settings + ações secundárias)

### "Mais" / Settings
- Workspace + membros
- Contas e cartões (conexões Pluggy + manuais)
- Tags
- Categorias
- Regras manuais (RF3.3) + regras aprendidas (RF3.2)
- Recorrentes
- Importações (RF20)
- Notificações
- Sua conta (Google login, logout)
- Tema (light/dark toggle)

### Padrão de layout
- **Mobile (< 768px)**: header fino fixo no topo (logo + ações contextuais), conteúdo em scroll vertical, **bottom nav fixo** com 5 itens.
- **Desktop (≥ 768px)**: **sidebar lateral esquerda** colapsável (256px aberta, 56px colapsada) com os 5 itens, header com breadcrumbs + busca global + avatar.
- **Tablet**: sidebar começa colapsada; expande no hover.

## Telas e fluxos principais

### Auth (RF16)
- **Login**: tela cheia, logo centralizado, único CTA "Entrar com Google". Fundo `background`, card central com `border`. Footer com link para "Política de privacidade" futura.
- **Onboarding pós-login** (primeira vez):
  - Se usuário não tem workspace: prompt "Criar seu workspace" → input nome (default: "Casa do {{first_name}}") → cria + entra.
  - Se foi convidado: aceitar convite → entra.

### Inbox (RF2 — tela principal)

**Mobile (vertical list):**
```
┌─────────────────────────────┐
│  ☰  Inbox        Filtros 🔍 │
├─────────────────────────────┤
│  ●  Almoço Padaria          │  ← AI sugeriu título
│     R$ 28,50 · Nubank CC    │
│     [Mercado] [Comida fora] │
│     Sex, 22/05              │
├─────────────────────────────┤
│  ●  IFOOD*REST              │  ← sem sugestão (baixa confiança)
│     R$ 62,00 · Nubank CC    │
│     Sex, 22/05              │
├─────────────────────────────┤
│         (mais 12 itens)     │
└─────────────────────────────┘
[ Aceitar selecionados (3) ]    ← bottom action bar quando seleciona
```

- Cada linha = card pressionável que abre o detalhe (Sheet/drawer mobile).
- Swipe direita = aceitar; swipe esquerda = rejeitar (com confirmação se valor > X).
- Long-press = entra em modo seleção múltipla → ações em massa.
- Indicador de confiança da AI (`ai_confidence`): bolinha colorida (verde alta, amarelo média, cinza baixa) à esquerda.

**Desktop (table):**
- Tabela com colunas: Data, Descrição/Título sugerido, Conta, Valor, Tags, Confiança, Ações.
- Linha selecionável por checkbox; multi-select com Shift+click.
- Hotkeys: J/K = navegar, Space = selecionar, A = aceitar, R = rejeitar, E = editar, S = split.

### Detalhe de gasto pendente (Sheet/drawer mobile, painel lateral desktop)
- Cabeçalho: descrição original (bruta do banco) + indicador da fonte (Pluggy/import/manual).
- Campo de **título melhorado** (editável, default = sugestão AI ou original).
- Campo de **valor** (editável; formato monetário com `font-mono`).
- Campo de **data** (calendar picker).
- **Tags** (combobox com autocomplete; criar nova inline; chips coloridos).
- **Categoria** (select; mostra quais tags compõem cada uma).
- Ações primárias (footer fixo):
  - `Aceitar` (primary, atalho `A`)
  - `Rejeitar` (ghost, atalho `R`)
  - `Split` (ghost, abre wizard)
- Ações secundárias (menu `⋯`):
  - `Vincular a gasto (estorno)`
  - `Marcar como transferência interna`
  - `Excluir definitivamente`

### Split wizard (RF2.3)
- Passo 1: quantas partes? (default 2, ajustável).
- Passo 2: para cada parte, definir valor, título, tags. Total no rodapé com indicador: ✅ R$ 300,00 / R$ 300,00 ou ❌ R$ 280,00 / R$ 300,00.
- CTA "Salvar splits" só habilita quando soma bate.

### Vincular estorno (RF10)
- A partir de uma credit pendente: botão "Esta transação é um estorno?"
- Abre lista de candidatos (`GET /transactions/:id/refund_candidates`):
  - Cada candidato: descrição original do gasto + valor + data + indicador de confiança.
  - Botão "É este" em cada linha.
- Após vincular: confirmação "Estorno vinculado a {{título}}. Valor consolidado de {{título}} agora é R$ X."

### Gastos consolidados (RF4, RF13)
- Mesma anatomia da inbox, mas com filtros visíveis:
  - Período (default: mês atual; chips: este mês, últimos 30 dias, custom).
  - Conta/cartão.
  - Tags (multi-select via combobox).
  - Categoria (multi-select).
  - Pessoa (você / esposa / ambos).
  - Direção (gasto / receita).
- Total do período fixo no header da lista: "**R$ 4.320,00** em 87 gastos · Receita R$ 6.500,00".
- Quebra por conta visível em sumário expansível.

### Orçamentos (RF8)
- **Lista**: cards verticais (mobile) / grid 2-3 colunas (desktop). Cada card:
  - Nome + tag/categoria-alvo.
  - **Barra de progresso** horizontal: verde até 79%, amarelo 80-99%, vermelho ≥ 100%.
  - "R$ 423,00 de R$ 800,00 · 53%".
  - Projeção: "Estimado pra fim do mês: R$ 750,00".
- **Detalhe**: histórico do orçamento (meses anteriores), lista de transações que compõem o gasto, opção de editar/excluir.
- **Criar orçamento**: wizard de 2 passos (escolher escopo: tag/categoria/composto → definir teto + alerta).

### Relatórios (RF13)
- **Overview** (default):
  - 4 cards no topo: total gasto, total recebido, saldo, vs mês anterior (delta).
  - **Donut chart**: gastos por categoria (Tremor).
  - **Bar chart**: top 10 tags do período.
  - **Line chart**: evolução mensal (últimos 12 meses).
  - Quando `overlap_present=true`, mostrar callout discreto: "ℹ Alguns gastos aparecem em mais de uma categoria; a soma das categorias pode ser maior que o total real."
- **By tag** e **By category**: páginas dedicadas com tabela ordenável + chart.
- **Custom**: range picker + filtros completos.

### Fatura do cartão (RF9.5)
- Para cada `account.kind='credit_card'`: card com fatura aberta (valor atual + previsto até fechamento), e tabs para faturas dos próximos 3 meses (com parcelamentos já planejados).

### Conectar conta (RF1, Pluggy Connect)
- Botão "Conectar conta" em Settings → Contas.
- Abre o **Pluggy Connect widget** (modal) — handoff para a UI do Pluggy.
- Pós-conexão: tela "Histórico inicial — escolha a partir de qual data importar" (RF1.7).
  - Default: 1º de janeiro do ano corrente.
  - Opções: último 1 mês, 3 meses, 12 meses, custom.

### Importação por arquivo (RF20)
- Drag-and-drop area ou botão "Selecionar arquivo".
- Após upload: tela de processamento (`status=processing`), com spinner.
- Após conclusão: resumo "**47** criados · **8** duplicados · **1** com erro" com link "Ver detalhes" (lista de erros).

### Tags e Categorias (RF5, RF6)
- **Tags**: lista vertical com cor + nome + contagem de gastos. Ações: criar, renomear, mesclar, excluir. Filtro `/q` para busca.
- **Categorias**: cards. Cada card mostra nome + tags-membros (chips). Ações: criar, renomear, gerenciar tags, mesclar, excluir.

### Recorrentes (RF9)
- Lista: descrição + cadência + última ocorrência + próxima esperada.
- Detectadas automaticamente vs manuais marcadas com badge `auto`/`manual`.
- Detalhe: editar tolerância, pausar, cancelar.

### Workspace + convite (RF16)
- Lista de membros (foto Google + nome + email + role).
- "Convidar pelo email": input → busca usuário → adiciona (se não cadastrado, mensagem "Pessoa precisa criar conta primeiro").
- Membro pode sair (a si mesmo). Dono não pode ser removido — só sair, transferindo dono pra outro.

## Estados visuais padronizados

### Empty states
- Ilustração discreta (linha minimalista, monocromática) + headline + ação primária.
- Ex.: Inbox vazia → "Tudo em dia. Volte depois ou conecte uma conta para começar."
- Ex.: Sem orçamentos → "Crie seu primeiro orçamento" + CTA.

### Loading states
- **Skeleton** (shadcn) imitando o layout final. Não usar spinners para listas — só para ações pontuais.
- Botões com loading: spinner inline + texto "Aceitando...".

### Error states
- Toast (Sonner) com ícone destructive + mensagem curta + ação "Tentar de novo" quando aplicável.
- Erros 5xx em UI: tela de erro com botão "Recarregar" + report automático ao Sentry.

### Success / feedback
- Toast verde discreto: "Gasto consolidado".
- Sem confetes nem celebrações exageradas — vibe Linear é sóbria.

## Mobile vs Desktop — diferenças explícitas

| Aspecto | Mobile | Desktop |
|---|---|---|
| Navegação primária | Bottom nav fixo, 5 itens | Sidebar lateral colapsável |
| Detalhe de gasto | Sheet (drawer bottom-up) | Painel lateral direito (Sheet side='right') ou Dialog |
| Tabelas de gastos | Cards verticais empilhados | Tabela densa com colunas |
| Multi-select | Long-press + bottom action bar | Checkboxes + shift-click + header action bar |
| Filtros | Sheet bottom-up com formulário | Bar lateral ou popover |
| Charts | Stack vertical | Grid 2-3 colunas |
| Atalhos teclado | — | Hotkeys completos (J/K/A/R/E/S/Cmd+K) |

## Acessibilidade

- **WCAG 2.1 AA** como mínimo no MVP.
- Contraste de texto: pelo menos 4.5:1 (verificado nos tokens da paleta acima).
- Navegação por **teclado** completa em todas as telas (shadcn/ui + Radix entregam isso).
- `aria-label` em ícones-botão; `aria-live` para toasts e contadores de inbox.
- Focus ring visível (ring-2 do Tailwind, cor `accent`).
- Suporte a `prefers-reduced-motion` — animações respeitam.
- Texto: tamanho base 14px (sm); usuário pode aumentar via configuração futura.

## Internacionalização

- **PT-BR único** no MVP. Mas estrutura preparada com `react-intl` ou `i18next` desde o início (chaves nomeadas, não strings inline) para facilitar inglês/espanhol em v2.
- Formatos:
  - Datas: `dd/MM/yyyy` (curtas) e `D MMM yyyy` (longas).
  - Moeda: `Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })` → `R$ 1.234,56`.
  - Números: separador de milhar com ponto, decimal com vírgula.

## Logo e nome

- **Nome no UI**: "Controle Financeiro" no header/sidebar. Sem subtítulo no chrome.
- **Logo**: ícone **Lucide `wallet`** como símbolo permanente, à esquerda do nome. Cor: `foreground` (segue o tema). Sem custo de design, alinhado com Lucide já usado no resto da interface.
  - Alternativas se quiser trocar depois (mesma família visual): `coins`, `banknote`, `landmark`, `piggy-bank`.
- **Favicon**: gerar a partir do mesmo ícone `wallet` em SVG, 32×32 + 16×16 + 192×192 + 512×512 para PWA-readiness futura. Cores: foreground sobre background do tema light (para favicon padrão).

## Decisões fechadas

| Tema | Decisão |
|---|---|
| Vibe | Clean & minimal (Linear/Notion) |
| Componentes | shadcn/ui (Radix + Tailwind) |
| Tema | Claro + escuro com toggle; **default segue `prefers-color-scheme` do SO** no primeiro acesso; preferência manual sobrescreve e é persistida em `localStorage` |
| Cor de acento | Violet 600 (`#7C3AED`) no light, Violet 400 (`#A78BFA`) no dark — Linear-style |
| Logo | Ícone Lucide `wallet` como símbolo permanente, sem logo customizado no MVP |
| Wireframes high-fidelity | Rascunhar **3 telas-chave em Figma** antes da implementação: Inbox, Detalhe de gasto pendente, Orçamentos. Resto da app guiado por este doc + shadcn/ui |
| Tipografia | Geist Sans (fallback Inter) + Geist Mono para valores |
| Icons | Lucide React |
| Charts | Tremor (sobre Recharts) |
| Toast | Sonner |
| Idioma | PT-BR único no MVP, estrutura i18n desde o início |
| Acessibilidade | WCAG 2.1 AA mínimo |
| Navegação primária | Bottom nav mobile + sidebar desktop, 5 itens (Inbox, Gastos, Orçamentos, Relatórios, Mais) |

## Pontos em aberto

Nenhum. As 4 decisões pendentes (logo, accent, wireframes, tema default) foram fechadas e estão na tabela de Decisões.

## Próximos passos

1. **Wireframes Figma** das 3 telas-chave (Inbox, Detalhe de gasto pendente, Orçamentos) — fazer **antes** do setup do monorepo. Posso usar a integração Figma do Claude Code para criar.
2. **Setup do monorepo** (estrutura, Dockerfile, Kamal, GitHub Actions, dependências de front com shadcn/ui já bootstrapped com tokens dessa paleta + tema dark/light wired).
3. **Primeira fatia TDD**: RF16 (auth + workspace) com a tela de login + onboarding.

## Validação

- Você lê e diz "sim, essa é a app que quero ver".
- Cada RF do PRD tem ao menos uma tela ou padrão de interação que o expõe.
- Decisões visuais consistentes (palette, tipografia, radius, sombras) — não há "uma tela com cara de outro app".
- Acessibilidade e responsividade resolvidas no nível de princípio + biblioteca.

**Status:** v1.0 — fechado após 4 decisões finais (logo Lucide `wallet` permanente, accent Violet 600/400, wireframes Figma de 3 telas-chave antes do código, tema default `prefers-color-scheme`).
