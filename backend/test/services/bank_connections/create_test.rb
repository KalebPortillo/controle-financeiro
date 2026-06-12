require "test_helper"

class BankConnections::CreateTest < ActiveSupport::TestCase
  # Fake provider — implementa a mesma interface do BankAggregators::Pluggy
  # que o service usa (get_item + list_accounts). Mantém o teste offline e
  # determinístico (sem VCR/rede aqui — o provider real é coberto no
  # pluggy_test.rb).
  class FakeProvider
    def initialize(item:, accounts:)
      @item = item
      @accounts = accounts
    end

    def get_item(item_id:)
      @item.merge(id: item_id)
    end

    def list_accounts(item_id:)
      @accounts
    end
  end

  def membership
    @membership ||= create(:workspace_membership)
  end

  def workspace
    membership.workspace
  end

  def nubank_provider
    FakeProvider.new(
      item: { connector_id: 612, connector_name: "Nubank", status: "UPDATED" },
      accounts: [
        { id: "acc-cc", type: "BANK",   name: "Conta Corrente", balance: 1000, currency_code: "BRL" },
        { id: "acc-cr", type: "CREDIT", name: "Cartão",         balance: -50,  currency_code: "BRL" }
      ]
    )
  end

  test "cria BankConnection + Accounts a partir de um item Pluggy" do
    result = nil
    assert_difference -> { BankConnection.count }, 1 do
      assert_difference -> { Account.count }, 2 do
        result = BankConnections::Create.call(
          workspace:        workspace,
          owner_membership: membership,
          item_id:          "pluggy-item-xyz",
          history_since:    Date.new(2026, 1, 1),
          provider:         nubank_provider
        )
      end
    end

    conn = result
    assert_equal "pluggy", conn.provider
    assert_equal "pluggy-item-xyz", conn.external_connection_id
    assert_equal "connected", conn.status
    assert_equal Date.new(2026, 1, 1), conn.sync_history_since
    assert_equal workspace, conn.workspace

    cc = conn.accounts.find_by(external_id: "acc-cc")
    assert_equal "checking", cc.kind
    assert_equal "nubank",   cc.institution
    assert_equal "Conta Corrente", cc.name

    cr = conn.accounts.find_by(external_id: "acc-cr")
    assert_equal "credit_card", cr.kind
  end

  test "captura banco (conector), bandeira e 4 últimos dígitos do cartão (RF2.7)" do
    provider = FakeProvider.new(
      item: { connector_id: 999, connector_name: "Banco Inter", status: "UPDATED" },
      accounts: [
        { id: "cc", type: "BANK",   name: "Conta Corrente", number: "0001/12345-0", currency_code: "BRL" },
        { id: "card", type: "CREDIT", name: "Mastercard Black", number: "9437", brand: "MASTERCARD", currency_code: "BRL" }
      ]
    )
    conn = BankConnections::Create.call(
      workspace: workspace, owner_membership: membership,
      item_id: "inter-item", history_since: Date.new(2026, 1, 1), provider: provider
    )

    # Conector fora do enum → institution "manual", mas institution_name real.
    cc = conn.accounts.find_by(external_id: "cc")
    assert_equal "manual", cc.institution
    assert_equal "Banco Inter", cc.institution_name
    assert_nil cc.last_digits # conta não guarda dígitos
    assert_nil cc.card_brand

    card = conn.accounts.find_by(external_id: "card")
    assert_equal "Banco Inter", card.institution_name
    assert_equal "Mastercard", card.card_brand
    assert_equal "9437", card.last_digits
  end

  test "é idempotente — re-criar com mesmo item não duplica connection nem accounts" do
    args = {
      workspace:        workspace,
      owner_membership: membership,
      item_id:          "pluggy-item-dup",
      history_since:    Date.new(2026, 1, 1),
      provider:         nubank_provider
    }
    BankConnections::Create.call(**args)

    assert_no_difference [ "BankConnection.count", "Account.count" ] do
      BankConnections::Create.call(**args)
    end
  end

  test "mapeia connector sandbox (id 2) pra institution 'sandbox'" do
    sandbox_provider = FakeProvider.new(
      item: { connector_id: 2, connector_name: "Pluggy Bank", status: "UPDATED" },
      accounts: [ { id: "s1", type: "BANK", name: "Conta", balance: 10, currency_code: "BRL" } ]
    )
    conn = BankConnections::Create.call(
      workspace:        workspace,
      owner_membership: membership,
      item_id:          "sandbox-item",
      history_since:    Date.new(2026, 1, 1),
      provider:         sandbox_provider
    )
    assert_equal "sandbox", conn.accounts.first.institution
  end
end
