require "test_helper"

class AiSuggestion::ContextExtractorTest < ActiveSupport::TestCase
  def transaction_with(source_metadata)
    build(:transaction,
          original_description: "VIVO SERVICOS",
          amount_cents: 12000,
          direction: "debit",
          source_metadata: source_metadata)
  end

  test "extracts basic fields when source_metadata is minimal" do
    tx = transaction_with({ "id" => "abc", "amount" => -120 })
    ctx = AiSuggestion::ContextExtractor.call(tx)

    assert_equal "VIVO SERVICOS", ctx[:description]
    assert_equal 120.0, ctx[:amount]
    assert_equal "debit", ctx[:direction]
  end

  test "extracts merchant name" do
    tx = transaction_with({ "merchant" => { "businessName" => "VIVO S.A.", "cnae" => "6120501" } })
    ctx = AiSuggestion::ContextExtractor.call(tx)

    assert_equal "VIVO S.A.", ctx[:merchant_name]
    assert_equal "6120501",   ctx[:merchant_cnae]
  end

  test "extracts pluggy category hint" do
    tx = transaction_with({ "category" => "Telecommunications" })
    ctx = AiSuggestion::ContextExtractor.call(tx)

    assert_equal "Telecommunications", ctx[:pluggy_category]
  end

  test "extracts payment method and receiver name" do
    tx = transaction_with({
      "paymentData" => {
        "paymentMethod" => "PIX",
        "receiver"      => { "name" => "João Silva" }
      }
    })
    ctx = AiSuggestion::ContextExtractor.call(tx)

    assert_equal "PIX",        ctx[:payment_method]
    assert_equal "João Silva", ctx[:receiver_name]
  end

  test "handles nil source_metadata" do
    tx = build(:transaction, original_description: "TESTE", amount_cents: 100,
               direction: "debit", source_metadata: nil)
    ctx = AiSuggestion::ContextExtractor.call(tx)

    assert_equal "TESTE", ctx[:description]
    assert_nil ctx[:merchant_name]
  end
end
