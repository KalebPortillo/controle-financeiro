# Melhorias — barra de ação flutuante, ordem dos gastos, parcelas no Telegram

Status: **aprovado e implementado (2026-10-20)** — M1, M3, M2 em commits próprios. Design: ver artefato "Proposta de melhorias" (mockups mobile).

Três melhorias independentes, entregáveis em fatias separadas (M1, M2, M3).

---

## M1 — Barra de ação do inbox sempre visível

### Problema
Ao selecionar gastos no inbox, a barra "N selecionados · Rejeitar · Aceitar" aparece
só no fim da lista. Numa lista grande (principalmente no celular) é preciso rolar
até o fim pra agir.

**Causa raiz**: a barra já é `sticky bottom-4`, mas o `<main>` do `AppLayout` tem
`overflow-y-auto` sem altura limitada. Ele vira o container de scroll do sticky, mas
quem rola de fato é a janela — o sticky nunca engata. No mobile, se engatasse,
ficaria escondido atrás da bottom nav (`fixed`, 56px, z-30).

### Requisitos
- **M1.1** Com ≥1 gasto selecionado, a barra fica fixa no rodapé da janela, visível
  em qualquer posição do scroll.
- **M1.2** Mobile: acima da bottom nav (56px + 8px + safe-area), margem lateral 16px.
  Desktop: centrada na coluna de conteúdo (desconta a sidebar de 256px), mesma
  largura máxima da lista (`max-w-4xl`), 16px do rodapé.
- **M1.3** A lista ganha padding inferior igual à altura da barra enquanto ela
  existe — o último gasto nunca fica coberto.
- **M1.4** Entrada: slide-up 150ms + fade; sem animação com `prefers-reduced-motion`.
- **M1.5** Toasts (Sonner) não podem cair em cima da barra: no mobile o offset
  inferior do Toaster sobe acima da barra enquanto há seleção.
- **M1.6** Conteúdo e copy inalterados ("7 selecionados · limpar", "Rejeitar",
  "Aceitar (7)"). Alvos de toque ≥44px no mobile.
- **M1.7** A barra some ao limpar a seleção, aceitar ou rejeitar.

### Fora de escopo
"Selecionar todos" na barra; barra flutuante em outras telas.

### Testes
Vitest: barra renderiza com `position: fixed` e classe de offset do mobile quando
há seleção; lista ganha o padding. Playwright (mobile viewport): selecionar o 1º
item, rolar até o meio, a barra está no viewport e "Aceitar" funciona.

---

## M2 — Gastos: compras do mês primeiro, parcelas antigas depois

### Problema
A tela de gastos consolidados ordena por `occurred_at desc`. Parcelas de compras
de meses anteriores (ex.: compra em 30/07 em 6x → a parcela de outubro tem data
30/10) aparecem no topo, acima das compras reais do mês. O usuário quer ver
primeiro o que comprou no mês.

### Requisitos
- **M2.1** Na visão por mês, a lista se divide em duas seções:
  1. **Compras do mês** — gastos cuja *data da compra* cai no mês exibido.
     Ordenadas pela data da compra, mais recente primeiro.
  2. **Parcelas de compras anteriores** — parcelas cuja data da compra é anterior
     ao mês. Ordenadas pela data da parcela (`occurred_at`), mais recente primeiro.
- **M2.2** *Data da compra*: para parcela é o `purchase_date` do serializer (âncora
  retro-calculada `occurred − (n−1) meses`, ver `Transactions::Installment`); sem
  ele, `occurred_at`. Gasto avulso usa sempre `occurred_at` — uma compra de 30/09 que
  postou em 01/10 é de outubro, não "parcela antiga". Logo, à vista e 1ª parcela
  ficam na seção 1; parcela 2/6 em diante, na seção 2.
- **M2.3** Divisor visual da seção 2: linha de cabeçalho dentro da lista com
  rótulo "Parcelas de compras anteriores", contagem e subtotal em mono. A seção 1
  usa o cabeçalho de colunas atual (sem rótulo extra quando a seção 2 está vazia).
- **M2.4** Nas linhas da seção 2, abaixo do meta (conta + badge 3/6), uma linha
  "compra em 30/07" — em linha própria pra não espremer a conta no mobile.
- **M2.5** Grupos de relacionadas (compra + IOF/estorno, RF23) seguem a âncora.
- **M2.6** Totais do topo ("R$ X em N gastos", receita) não mudam.
- **M2.7** Modo busca (`?q=`, sem recorte de mês): lista única por data, sem seções.
- **M2.8** Receitas (crédito) seguem a mesma regra (não são parcelas → seção 1).

### Implementação prevista
Só frontend: função pura `splitByPurchaseMonth(items, period)` ao lado de
`buildInboxItems`, testada isoladamente. Backend e contrato de API não mudam.

### Testes
Vitest da função (à vista, 1/6, 3/6, sem purchase_date, grupo RF23, busca) +
GastosPage renderiza o divisor e a ordem.

---

## M3 — Telegram: uma mensagem por compra parcelada

### Problema
Quando o sync traz uma compra parcelada, o Telegram manda uma mensagem com botões
**por parcela** — uma compra em 10x vira 10 mensagens. O inbox do app já agrupa por
`installment_group_id` e aceita/rejeita o grupo inteiro.

### Requisitos
- **M3.1** Em `TelegramInboxButtons` (`call` e `push_pending`), pendentes com o
  mesmo `installment_group_id` viram **um item** — mesma regra do inbox
  (`buildInboxItems`, que agrupa qualquer parcela com `installment_group_id`).
  Com 1 parcela pendente no grupo a mensagem usa o mesmo formato, com
  "1 parcela no inbox" e botões sem contagem.
- **M3.2** Texto do item agrupado:
  ```
  Amazon Br — 12x · R$ 555,65
  Cartão ••5190 · compra em 08/10
  12 parcelas no inbox (R$ 46,30 cada)
  Sugestão: Compras
  ```
  Total = soma das pendentes do grupo. Se os valores variam, omite "cada".
- **M3.3** Botões: "Consolidar 12x" / "Rejeitar 12x". `callback_data`
  `grp:consolidate:<group_id>` / `grp:reject:<group_id>` (≤64 bytes).
- **M3.4** Callback de grupo aplica a ação a **todas as pendentes** do grupo no
  workspace (mesma semântica de `installment_groups#consolidate|reject`), edita a
  mensagem pra "— Consolidado (12 parcelas)" e remove os botões. Nenhuma pendente
  → "Já processada". Autorização igual à de hoje (chat vinculado + escopo do workspace).
- **M3.5** Paginação (`PAGE_SIZE = 7`, "Ver mais 7", "Mais N gastos novos",
  "Mostrando X de Y pendentes") conta **itens** (grupo = 1), não transações.
- **M3.6** Entrega idempotente: o item do grupo é enviado se alguma parcela ainda
  não tem `telegram_notified_at`; após o envio carimba todas as parcelas do grupo.
- **M3.7** Parcelas que chegam depois do grupo consolidado já entram consolidadas
  (`InstallmentInheritance`) — não geram mensagem nova.
- **M3.8** Botões individuais antigos (`tx:...`) continuam funcionando.

### Fora de escopo
Agrupar relacionadas (IOF) no Telegram; mudar o resumo in-app.

### Testes
Minitest: `TelegramInboxButtons` agrupa (12 parcelas → 1 mensagem, teclado `grp:`),
parcela solitária usa o formato de grupo sem contagem, paginação conta itens, retomada carimba o grupo;
`HandleTelegramCallback` consolida/rejeita grupo, toque duplo, grupo de outro
workspace sem efeito. Sem mudança de `allowed_updates` (não precisa re-rodar
`set_webhook`).

---

## Ordem sugerida de entrega
M1 (menor, maior atrito diário) → M3 (backend isolado) → M2. Cada um em commit
próprio, staging, validação, depois tag de produção.
