require "test_helper"

class AiSuggestion::NormalizerTest < ActiveSupport::TestCase
  test "lowercases and strips" do
    assert_equal "mercado extra", AiSuggestion::Normalizer.call("  MERCADO EXTRA  ")
  end

  test "removes long numeric tokens" do
    assert_equal "pgto pix ifood restaurante xyz", AiSuggestion::Normalizer.call("PGTO PIX 43958 IFOOD RESTAURANTE XYZ")
  end

  test "removes dates dd/mm and dd/mm/yy" do
    assert_equal "boleto vivo", AiSuggestion::Normalizer.call("BOLETO VIVO 05/26")
    assert_equal "boleto vivo", AiSuggestion::Normalizer.call("BOLETO VIVO 05/05/2026")
  end

  test "removes CPF-like patterns" do
    assert_equal "pix fulano silva", AiSuggestion::Normalizer.call("PIX 111.111.111-11 FULANO SILVA")
  end

  test "collapses multiple spaces" do
    assert_equal "uber trip", AiSuggestion::Normalizer.call("UBER   TRIP")
  end

  test "keeps meaningful short numbers" do
    assert_equal "g2 cafe", AiSuggestion::Normalizer.call("G2 CAFE")
  end

  test "removes asterisk globs common in card descriptions" do
    assert_equal "ifood restaurante", AiSuggestion::Normalizer.call("IFOOD*RESTAURANTE")
  end
end
