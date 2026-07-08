require "test_helper"

class Transactions::AggregatorAdjustmentTest < ActiveSupport::TestCase
  def match?(desc, meta)
    Transactions::AggregatorAdjustment.match?(description: desc, source_metadata: meta)
  end

  test "matches Pluggy adjustment lines (débito/crédito) sem purchaseDate" do
    cc = { "creditCardMetadata" => { "feeType" => "OTHER" } }
    assert match?("Ajuste a débito", cc)
    assert match?("Ajuste a crédito", cc)
    assert match?("Ajuste a debito", cc) # sem acento
  end

  test "does not match a real purchase" do
    cc = { "creditCardMetadata" => { "purchaseDate" => "2026-07-08T02:19:35.001Z" } }
    assert_not match?("Pag*Steam 1/3", cc)
    # mesmo que a descrição contivesse 'ajuste', com purchaseDate não é ajuste
    assert_not match?("Ajuste a débito", cc)
  end

  test "does not match non credit-card transactions" do
    assert_not match?("Ajuste a débito", { "id" => "x" })       # sem creditCardMetadata
    assert_not match?("Ajuste a débito", nil)
  end

  test "does not match unrelated descriptions" do
    cc = { "creditCardMetadata" => { "feeType" => "OTHER" } }
    assert_not match?("Reajuste anuidade", cc)
    assert_not match?("Compra ajuste fino", cc)
  end
end
