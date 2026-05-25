# Controle Financeiro — Requisitos de Produto (PRD v1.2)

## Contexto

Aplicação privada para gestão financeira de um casal (você + esposa), com **login individual por usuário** e visão compartilhada total dentro de um "workspace" comum. Objetivo central: ter uma visão consolidada e categorizada de todos os gastos por período, com **busca automática** das transações e o mínimo de fricção manual — mas sempre com supervisão humana antes de qualquer lançamento ser oficializado.

Por que essa app existe e não usar algo do mercado:
- Escopo só de vocês dois, sem features de massa, marketplace ou monetização.
- Você quer um fluxo **"inbox-first"** que praticamente nenhum app brasileiro tem hoje (Organizze, Mobills, etc. auto-consolidam).
- Você quer **AI ativa** sugerindo título e tags, com aprendizado a partir das suas correções.
- Tags múltiplas, splits, vínculo de estornos a gastos originais — flexibilidade que os concorrentes não dão.
- Self-hosted na sua VPS Oracle (sem custo recorrente além da infra que você já tem).

Esta v1.0 fecha todos os pontos de produto após duas iterações com o usuário. Cobre **só requisitos de produto** — stack, modelo de dados e integração técnica com Nubank entram na próxima fase.

## Personas e modelo de uso

- **Você** + **sua esposa** — cada um com login próprio, mas dentro de um mesmo **workspace** com visão e edição completas de tudo.
- Modelo de convite: um usuário cria o workspace e convida o outro.
- Sem admin separado. Sem outros usuários no MVP, mas arquitetura preparada para múltiplos workspaces por usuário.

## Princípios de produto

1. **Automático por padrão, manual quando importa.** O sistema busca e pré-processa; o usuário confirma antes de virar gasto oficial.
2. **Inbox-first.** Todo gasto importado passa por uma caixa de entrada antes de ser consolidado — análogo a email.
3. **Tags planas + categorias como agregador.** Tags são livres e múltiplas por gasto. Categorias são uma entidade separada que agrupa N tags para fins de relatório e orçamento. Uma tag pode pertencer a múltiplas categorias.
4. **Visão única do casal.** Ambos veem tudo. A origem do gasto (conta, cartão, pessoa) está sempre visível.
5. **AI aprende com você.** Cada correção manual deve melhorar futuras sugestões.
6. **Preparado para o futuro, simples no presente.** Notificações, exportação e múltiplas instituições não entram no MVP, mas a arquitetura é desenhada para acomodá-las sem refazer o core.

## Requisitos funcionais

### RF1. Conexão com instituições financeiras
- **RF1.1** Suporte a múltiplas contas (conta corrente + cartões) por pessoa.
- **RF1.2** Suporte a múltiplos cartões dentro da mesma conta.
- **RF1.3** Integração inicial apenas com **Nubank** (conta corrente e cartão de crédito), para os dois usuários.
- **RF1.4** Sincronização automática periódica (ex.: diária) + botão de "atualizar agora".
- **RF1.5** Arquitetura preparada para outras instituições no futuro (Itaú, Inter, Santander) sem refazer o core.
- **RF1.6** Tratamento de erros de sincronização (token expirado, MFA, falha de rede) com aviso ao usuário.
- **RF1.7** **Histórico inicial configurável**: ao conectar a conta pela primeira vez, o usuário escolhe a data de início da importação (default sugerido: 1º de janeiro do ano corrente).

### RF2. Caixa de entrada de gastos pendentes (Inbox)
- **RF2.1** Toda transação importada cai automaticamente na inbox.
- **RF2.2** Itens na inbox **não afetam relatórios nem orçamentos** até serem consolidados.
- **RF2.3** Ações em cada gasto da inbox:
  - **Aceitar** (consolidar) — individual ou em massa.
  - **Editar título** (sobrescrever sugestão da AI ou texto bruto do banco).
  - **Editar valor.**
  - **Split** — dividir um gasto em N gastos com valores e tags diferentes (soma dos splits = valor original).
  - **Editar/adicionar tags e categoria.**
  - **Vincular a gasto existente** (para estornos/reembolsos — ver RF11).
  - **Rejeitar** — não conta no controle, registrado para evitar reimportação.
  - **Remover** — exclusão definitiva.
- **RF2.4** Badge com número de gastos pendentes.
- **RF2.5** Filtros e ordenação (data, valor, conta, tag sugerida, pessoa).
- **RF2.6** Seleção múltipla para ações em massa (aceitar várias, aplicar mesma tag).

### RF3. Pré-categorização inteligente
- **RF3.1** Cada gasto na inbox recebe automaticamente:
  - Tags sugeridas (1+).
  - Categoria sugerida (se as tags se encaixam em uma).
  - Título melhorado (ex.: "PAGAMENTO PIX REC: ANA M." → "Almoço Ana").
- **RF3.2** Aprendizado com correções: quando o usuário corrige uma sugestão, gastos similares no futuro usam a versão aprendida.
- **RF3.3** Regras manuais opcionais por texto/estabelecimento (ex.: "iFood*" → tag "Comida fora").
- **RF3.4** Indicador visual de confiança da sugestão para priorizar revisão.

### RF4. Gastos consolidados
- **RF4.1** Após aceitação, o gasto entra na área de **consolidados** e passa a contar para relatórios, orçamentos e dashboards.
- **RF4.2** Consolidados ainda podem ser editados (valor, título, tags, categoria) e removidos, com aviso de impacto no histórico.
- **RF4.3** Histórico de alterações por gasto (quem, quando, o quê) para auditoria leve entre o casal.
- **RF4.4** **ID único e estável por gasto** — base para vínculos (estornos, splits, edições).

### RF5. Tags
- **RF5.1** Tags livres (texto curto), com autocomplete de tags já usadas.
- **RF5.2** Múltiplas tags por gasto.
- **RF5.3** Cor/ícone opcional por tag.
- **RF5.4** Gestão: renomear, mesclar duas tags, excluir.
- **RF5.5** **Tags são planas** — sem hierarquia pai/filho. Agregação é feita via Categorias (RF6).

### RF6. Categorias
- **RF6.1** Categoria = entidade separada que **agrupa uma ou mais tags**.
- **RF6.2** Uma tag pode pertencer a **múltiplas** categorias (ex.: tag "Padaria" pode estar em "Alimentação" e "Pequenos prazeres").
- **RF6.3** Categorias são usadas como **dimensão de agregação** em relatórios, dashboards e orçamentos. Não substituem tags.
- **RF6.4** Gestão: criar, renomear, mesclar, excluir.
- **RF6.5** Categorias são acessadas e mantidas na área de gastos **consolidados** (não na inbox).
- **RF6.6** **Não-duplicação em totalizações.** Quando uma tag pertence a múltiplas categorias, o valor do gasto **nunca é somado mais de uma vez** no total real do período. Regras:
  - **Total geral do período** (ex.: "você gastou R$ X este mês"): cada gasto entra exatamente uma vez, independente de quantas categorias suas tags integrem. É a soma direta dos gastos consolidados.
  - **Visão por categoria** (ex.: gráfico de pizza, lista de categorias com valor): o mesmo gasto pode aparecer em mais de uma categoria. A soma das categorias **pode ser maior** que o total real do período — isso é esperado e o sistema deve sinalizar visualmente quando há overlap (ex.: nota no rodapé do gráfico, ou contagem "X gastos contam em mais de uma categoria").
  - **Orçamentos por categoria**: o gasto **conta em cada orçamento** das categorias onde alguma de suas tags aparece. Isso é intencional — cada orçamento é uma visão independente de "consumo". Mas o sistema mostra explicitamente o overlap quando o usuário configura um orçamento sobre uma categoria cuja tag já está em outra categoria com orçamento ativo.

### RF7. Receitas
- **RF7.1** Importação automática de créditos da conta corrente (salário, PIX recebido, rendimentos).
- **RF7.2** Mesmo fluxo de inbox → consolidado das despesas.
- **RF7.3** Diferenciação clara entre entrada e saída em relatórios.
- **RF7.4** Marcação de receitas previstas/recorrentes (ex.: salário mensal).

### RF8. Orçamentos
- **RF8.1** Orçamento mensal por **tag** (ex.: R$ 800 em "Mercado").
- **RF8.2** Orçamento mensal por **categoria** (agrega todas as tags da categoria).
- **RF8.3** Orçamentos compostos (combinação livre de tags em um único teto), além de tag/categoria.
- **RF8.4** Visualização do progresso: gasto vs teto, % consumido, projeção até fim do mês com base no ritmo atual.
- **RF8.5** Alerta visual ao aproximar (ex.: 80%) e ao ultrapassar o teto.
- **RF8.6** Orçamentos só consideram gastos **consolidados** (não os da inbox).

### RF9. Despesas recorrentes e contas a pagar
- **RF9.1** Detecção automática de recorrentes a partir do histórico (mesmo estabelecimento + valor próximo + cadência consistente).
- **RF9.2** Cadastro manual de contas fixas previstas (aluguel, condomínio, escola).
- **RF9.3** Visualização "contas previstas para os próximos N dias".
- **RF9.4** **Parcelamentos no cartão**: cada parcela vira gasto separado no mês de competência, com indicador "3/12". Padrão de mercado (Organizze, Mobills).
- **RF9.5** **Faturas futuras do cartão**: visão do total previsto da fatura aberta + faturas dos próximos meses (compostas pelos parcelamentos já em curso + recorrentes detectadas).
- **RF9.6** Aviso quando uma recorrente esperada não chegou no prazo (ex.: assinatura cancelada?).

### RF10. Estornos e reembolsos
- **RF10.1** Quando uma transação de **crédito** chega na inbox e parece ser estorno (mesmo estabelecimento + valor compatível com um gasto recente), o sistema **sugere** o vínculo mas **sempre pede confirmação** antes de aplicar.
- **RF10.2** O usuário aprova o vínculo sugerido, escolhe outro gasto manualmente, ou marca como entrada solta (não é estorno).
- **RF10.3** Estornos vinculados **reduzem ou zeram o valor consolidado** do gasto original, mantendo trilha visível ("estornado em DD/MM, valor -R$ X").
- **RF10.4** Possível encadear: gasto editado → estornado → novo gasto relacionado. Histórico de alterações (RF4.3) cobre.
- **RF10.5** Sem auto-vínculo no MVP — todo vínculo passa por aprovação humana. Se a sugestão da AI se mostrar confiável com o tempo, podemos revisitar essa regra em versão futura.

### RF11. Transferências internas
- **RF11.1** Detecção automática de transferências entre contas do mesmo workspace (saída de uma conta + entrada de mesmo valor em outra conta nossa em janela curta).
- **RF11.2** Transferências internas **não contam** como gasto ou receita em relatórios e orçamentos.
- **RF11.3** Aparecem em uma vista de "movimentações internas" para reconciliação.
- **RF11.4** Usuário pode marcar/desmarcar manualmente se a detecção errar.

### RF12. Entrada manual de gasto/receita
- **RF12.1** Usuário pode criar gasto/receita **manualmente do zero** para casos sem integração (dinheiro vivo, PicPay, Mercado Pago, presentes recebidos).
- **RF12.2** Mesmos campos: título, valor, data, conta/origem (com opção "Externo / Dinheiro"), tags, categoria, pessoa.
- **RF12.3** Lançamentos manuais vão **direto para consolidados** (não passam pela inbox, já que foi o usuário quem criou).
- **RF12.4** Podem ser editados e removidos como qualquer consolidado.

### RF13. Relatórios e dashboards
- **RF13.1** Visão geral do período (mês atual): total gasto, total recebido, saldo, top tags/categorias, comparativo com mês anterior.
- **RF13.2** Gráfico de gastos por tag e por categoria (pizza/barras).
- **RF13.3** Gráfico de evolução mensal (linha histórica).
- **RF13.4** Filtros: período, conta, cartão, tag, categoria, pessoa.
- **RF13.5** Quebra por conta/cartão (ex.: "gastos só no meu Nubank cartão este mês").
- **RF13.6** Vista do casal: total combinado vs por pessoa.

### RF14. Períodos
- **RF14.1** Período de controle: **mês calendário** (dia 1 ao último dia). Sem ciclo customizado no MVP.
- **RF14.2** Cartão de crédito: gasto entra pelo **mês da compra** (data da transação), não pelo mês da fatura — alinhado ao seu cenário onde a fatura cai na hora.

### RF15. Plataforma e UX
- **RF15.1** **Web app** responsivo, acessível via navegador.
- **RF15.2** **Mobile-first**: layout principal otimizado para celular.
- **RF15.3** **Desktop com experiência diferenciada**: telas maiores aproveitam o espaço com tabelas largas, gráficos lado a lado, painéis múltiplos (não é só "mobile esticado").

### RF16. Autenticação e workspace
- **RF16.1** Login individual por usuário (email + senha; login social pode entrar no futuro).
- **RF16.2** **Workspace** = espaço financeiro compartilhado. Contém contas, gastos, tags, categorias, orçamentos.
- **RF16.3** Convite **por email cadastrado**: o usuário convidado primeiro cria sua conta no app; depois o dono do workspace adiciona pelo email já existente. (Trade-off: dois passos para a esposa, mas evita lidar com tokens de convite de uso único.)
- **RF16.4** Membros do workspace são **editores plenos**: ambos podem aceitar, editar e remover qualquer gasto, criar/editar tags, categorias e orçamentos. Sem distinção de papéis no MVP.
- **RF16.5** Um usuário pode pertencer a múltiplos workspaces no futuro (arquitetura preparada).

### RF17. Notificações (preparado, escopo enxuto no MVP)
- **RF17.1** Apenas **notificações internas (in-app)** no MVP. Sem push, sem email.
- **RF17.2** Tipos previstos: novos gastos aguardando na inbox, estouro de orçamento, recorrente que não chegou, falha de sincronização.
- **RF17.3** Arquitetura preparada para canais externos (push, email) no futuro.

### RF18. Exportação (preparado, fora do MVP)
- **RF18.1** Exportação CSV/Excel não entra no MVP.
- **RF18.2** Modelo de dados preparado para facilitar exportação futura sem refatoração.

### RF19. Hospedagem e acesso
- **RF19.1** Self-hosted na **VPS Oracle Cloud** do usuário.
- **RF19.2** Acessível de qualquer lugar via web, com autenticação obrigatória.
- **RF19.3** HTTPS (vai entrar no plano técnico, mas registrado aqui como requisito de produto não-funcional).

### RF20. Importação em massa por arquivo (CSV / OFX)
- **RF20.1** Usuário pode fazer **upload de arquivos CSV ou OFX** exportados de instituições financeiras (Nubank, Inter, Itaú etc. exportam algum desses formatos).
- **RF20.2** O sistema **parseia** o arquivo, deduplica contra o que já existe (chave: data + valor + descritor, ou ID externo se vier no arquivo) e joga os novos itens na **mesma inbox** da sincronização automática (RF2). Não bypassa pré-categorização nem aprovação manual.
- **RF20.3** Casos de uso:
  - Importar histórico antes de conectar a conta via integração automática.
  - Instituições não cobertas pela integração automática (RF1).
  - Fallback quando a integração automática falha por períodos prolongados.
- **RF20.4** Feedback ao usuário ao fim do upload: quantos itens novos foram criados, quantos foram detectados como duplicados, quantos falharam (com motivo).
- **RF20.5** Formatos suportados no MVP: **CSV** (delimitador detectado: vírgula, ponto-e-vírgula, tab) e **OFX**. XLS/XLSX podem entrar depois.

## Comparação com o mercado (atualizada)

| Feature | Sua app | Organizze | Mobills | YNAB | Monarch |
|---|---|---|---|---|---|
| Sync automático BR | Nubank direto (planejado) | Open Finance (pago) | Open Finance (pago) | Manual no BR | Não funciona no BR |
| Inbox de pendentes com aprovação | **Sim — diferencial** | Não, auto-consolida | Não, auto-consolida | Não | Parcial |
| AI para título e tag | **Sim — diferencial** | Regras simples | Regras simples | Não | AI de categorização |
| Tags múltiplas por gasto | **Sim** | Não (1 categoria) | Não (1 categoria) | Não (1 categoria) | Não |
| Categoria como agregador de tags | **Sim — diferencial** | Não | Não | Não | Não |
| Split de gastos | Sim | Não nativo | Limitado | Sim (manual) | Sim |
| Vínculo de estorno → gasto original | **Sim — diferencial** | Não | Não | Não | Parcial |
| Compartilhamento casal | Login próprio + workspace | Sim (multi-conta) | Sim (multi-conta) | Sim | Sim |
| Orçamentos por tag e categoria | Sim | Sim (1 categoria) | Sim (1 categoria) | Núcleo (envelope) | Sim |
| Recorrentes auto-detect | Sim | Parcial | Parcial | Não | Sim |
| Faturas futuras do cartão | Sim | Sim | Sim | Não | Sim |
| Investimentos | Fora do MVP | Sim (pago) | Sim | Não | Sim |
| Metas de economia | **Fora do escopo** | Sim | Sim | Sim | Sim |
| Self-hosted | **Sim** | Não (SaaS) | Não (SaaS) | Não | Não |

**Diferenciais que ficaram mais claros nesta versão:**
1. Workflow inbox-first com **vínculo explícito de estornos**.
2. **Categoria como entidade separada** que agrega tags — algo realmente único.
3. AI ativa com aprendizado.
4. Self-hosted sem custo recorrente.

## Decisões fechadas nesta iteração

| Tema | Decisão |
|---|---|
| Parcelamentos | Cada parcela vira gasto separado no mês de competência ("3/12"). |
| Estornos | Sistema tenta vincular automaticamente; usuário aprova/ajusta. ID único por gasto. |
| Transferências internas | Detectadas e excluídas de relatórios. Vista separada de reconciliação. |
| Dinheiro vivo / carteiras externas | Entrada manual do zero (direto para consolidados). |
| Período | Mês calendário, sem ciclo customizado. |
| Visão da fatura | Pela data da compra (a fatura do usuário cai na hora). |
| Metas de economia | Fora do escopo. |
| Notificações | Apenas in-app no MVP; arquitetura preparada para push/email. |
| Exportação CSV/Excel | Fora do MVP; modelo de dados preparado para futuro. |
| Histórico inicial | Usuário escolhe a data de início; default sugerido = 1º de janeiro do ano corrente. |
| Hierarquia de tags | Tags planas + Categorias como entidade separada (recomendação adotada). |
| Plataforma | Web app responsivo, mobile-first, com desktop diferenciado. |
| Login | Individual por usuário; workspace compartilhado por convite. |
| Hospedagem | Self-hosted na VPS Oracle Cloud do usuário. |
| Permissões no workspace | Ambos editores plenos. Sem papéis no MVP. |
| Vínculo de estorno | Sistema sugere, usuário sempre confirma. Sem auto-vínculo no MVP. |
| Convite no workspace | Por email cadastrado (esposa cria conta primeiro, depois é adicionada). |
| Tag em N categorias | Total geral do período nunca duplica o gasto. Visões por categoria podem sobrepor, com sinalização visual. Orçamentos por categoria contam o gasto em cada um (intencional). |
| Importação em massa por arquivo | CSV/OFX suportados no MVP. Mesmo fluxo de inbox da sync automática (dedup + pré-categorização + aprovação manual). |

## Integração com Nubank — pesquisa preliminar (decisão técnica, mas afeta produto)

Você pediu pesquisa sobre integração grátis. Resumo das opções conhecidas:

| Opção | Custo | Esforço | Risco | Confiabilidade |
|---|---|---|---|---|
| **Open Finance via Pluggy/Belvo** (agregador) | Free tier pequeno, depois pago (Pluggy tem free tier de ~100 conexões/mês ou similar — confirmar) | Médio (OAuth + onboarding como dev) | Baixíssimo, caminho oficial | Alta |
| **pynubank** (lib não-oficial) | Grátis | Baixo | Médio — viola TOS, pode quebrar quando o Nubank muda API interna | Média (histórico de quebras esporádicas, mas comunidade ativa) |
| **Importação manual** (CSV/OFX/PDF do app Nubank) | Grátis | Baixo, mas ação humana periódica | Zero | Alta, mas não é "automático" |

Riscos do pynubank para uso pessoal:
- Em termos práticos, o Nubank **historicamente não toma ação contra usuários individuais** acessando a própria conta via bibliotecas pessoais. Não vi caso documentado de bloqueio por isso.
- Risco real maior: a biblioteca **pode parar de funcionar de repente** se o Nubank mudar o app interno. Já aconteceu antes; a comunidade costuma corrigir em dias/semanas.
- "Violação de termos" existe na letra, mas é uma cláusula raramente acionada para uso pessoal.

Recomendação preliminar (a aprofundar na fase técnica):
- **MVP**: começar com pynubank pela velocidade + custo zero. Aceitando o risco de quebras esporádicas.
- **Plano B**: se pynubank quebrar com frequência ou se o produto for "produção crítica" pra vocês, migrar para Pluggy (ou outro agregador) usando o free tier.
- **Fallback manual sempre disponível** via RF12 (entrada manual) — garante que o app continua útil mesmo se a integração falhar.

## Pontos em aberto

Nenhum em produto. Todos os itens foram fechados ao longo das iterações (ver tabela "Decisões fechadas" acima).

Para o estado atual da engenharia, ver:
- `docs/requisitos-tecnicos.md` (v1.1) — stack, infra, testes (TDD), CI/CD, integração com Pluggy e Gemini, monitoramento Sentry, hospedagem.
- `docs/modelo-de-dados.md` — entidades, índices, constraints.
- `docs/contratos-api.md` — endpoints, payloads, convenções.

## Próximos passos

1. PRD v1.2 fechado.
2. Setup do monorepo (estrutura, Dockerfile, Kamal, GitHub Actions, dependências).
3. Plano de implementação em fatias TDD — primeiro fluxo recomendado: RF16 (auth + workspace).

## Validação deste PRD

- Você lê o documento e diz "sim, é isso que quero usar".
- Cada decisão fechada faz sentido para o seu uso real.
- A comparação com o mercado bate com sua percepção.
- Não falta feature óbvia para o seu cenário.

**Status:** v1.2 — adicionada RF20 (importação em massa por arquivo CSV/OFX). Pronta para evolução paralela com a fase técnica.
