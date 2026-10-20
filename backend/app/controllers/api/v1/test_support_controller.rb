class Api::V1::TestSupportController < ApplicationController
  before_action :require_authentication!

  # POST /api/v1/test_support/seed { scenario }
  #
  # Semeia dados fixos no workspace atual para o E2E (Playwright) exercitar fluxos
  # que dependem de transações com metadata específica (IOF, moeda estrangeira),
  # impossíveis de criar só pela UI. Devolve os ids criados pros seletores.
  #
  # SÓ existe em dev/test (gate `Rails.env.local?` em routes.rb) — nunca em staging
  # nem produção, que têm dados reais. Mesmo princípio do `auth/test_sign_in`.
  def seed
    # Precondição comum: usuário PÓS-onboarding (senão RequireAuth manda pro fluxo
    # de onboarding em vez do app). O `not_started` default redirecionaria.
    current_workspace.skip_onboarding!

    case params[:scenario]
    when "related_inbox" then render json: seed_related_inbox
    when "link_manual"   then render json: seed_link_manual
    when "budget_setup"  then render json: seed_budget_setup
    when "long_inbox"    then render json: seed_long_inbox
    when "gastos_sections" then render json: seed_gastos_sections
    else render json: { error: { code: "unknown_scenario", message: params[:scenario] } },
                status: :unprocessable_entity
    end
  end

  private

  # RF23 F2 — compra internacional + IOF, ambos PENDENTES e vinculados, na mesma
  # conta: o inbox deve agrupá-los num item só (`buildInboxItems` kind related).
  def seed_related_inbox
    account  = credit_card_account
    purchase = tx(account:, cents: 35_284, desc: "FIGMA", occurred: Date.new(2026, 6, 4),
                  metadata: { "currencyCode" => "USD" })
    iof      = tx(account:, cents: 1_235, desc: "IOF de compra internacional",
                  occurred: Date.new(2026, 6, 5))
    TransactionLink.create!(workspace: current_workspace, primary_transaction: purchase,
                            related_transaction: iof, relation_type: "iof", origin: "automatic")
    { account_id: account.id, purchase_id: purchase.id, iof_id: iof.id }
  end

  # RF23 F3 — dois gastos consolidados na mesma conta, SEM vínculo: o E2E abre o
  # órfão e o vincula manualmente ao gasto de origem via LinkOriginSection.
  def seed_link_manual
    account = credit_card_account
    origin  = tx(account:, cents: 5_000, desc: "ASSINATURA ANUAL", status: "consolidated",
                 occurred: Date.new(2026, 6, 1))
    orphan  = tx(account:, cents: 120, desc: "TARIFA", status: "consolidated",
                 occurred: Date.new(2026, 6, 3))
    { account_id: account.id, origin_id: origin.id, orphan_id: orphan.id }
  end

  # RF8 — uma tag + um gasto consolidado no mês corrente com essa tag, pro E2E
  # criar um orçamento e ver o progresso refletir o gasto semeado.
  def seed_budget_setup
    account = credit_card_account
    tag     = current_workspace.tags.create!(name: "Mercado E2E")
    gasto   = tx(account:, cents: 40_000, desc: "SUPERMERCADO", status: "consolidated",
                 occurred: Date.current)
    gasto.tags = [ tag ]
    { account_id: account.id, tag_id: tag.id, tag_name: tag.name, spent_cents: 40_000 }
  end

  # Inbox maior que a tela — o E2E seleciona um gasto, rola e confere que a barra
  # de ações em massa continua visível (fixa no rodapé da janela).
  def seed_long_inbox
    account = credit_card_account
    ids = (1..30).map do |i|
      tx(account:, cents: 1_000 + i, desc: "GASTO #{i}", occurred: Date.current - i).id
    end
    { account_id: account.id, transaction_ids: ids }
  end

  # Gastos do mês: uma compra feita no mês + a parcela 3/6 de uma compra de dois
  # meses antes, ambas consolidadas e faturadas no mês corrente.
  def seed_gastos_sections
    account = credit_card_account
    day     = Date.current.beginning_of_month + 4
    current = tx(account:, cents: 11_989, desc: "SUPER ZE", status: "consolidated", occurred: day)
    parcel  = tx(account:, cents: 23_315, desc: "MAGAZINE LUIZA", status: "consolidated", occurred: day + 10)
    parcel.update!(installment_group_id: SecureRandom.uuid, installment_number: 3, installment_total: 6)
    { account_id: account.id, current_id: current.id, parcel_id: parcel.id }
  end

  def credit_card_account
    current_workspace.accounts.create!(institution: "nubank", name: "Nubank", kind: "credit_card",
                                       owner_membership: current_membership)
  end

  def tx(account:, cents:, desc:, occurred:, status: "pending", metadata: {})
    current_workspace.transactions.create!(
      account:              account,
      direction:            "debit",
      amount_cents:         cents,
      currency:             "BRL",
      occurred_at:          occurred,
      original_description: desc,
      status:               status,
      source:               "automatic_sync",
      ai_status:            "analyzed",
      consolidated_at:      (status == "consolidated" ? Time.current : nil),
      source_metadata:      { "id" => SecureRandom.hex(6) }.merge(metadata)
    )
  end
end
