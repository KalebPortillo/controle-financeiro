module Transactions
  # Detecta "ajuste de agregador": linhas que o Pluggy INJETA pra reconciliar o
  # saldo/fatura (ex.: "Ajuste a débito"/"Ajuste a crédito"), que NÃO existem como
  # compra no app do banco. Assinatura: descrição de ajuste + é lançamento de
  # cartão (creditCardMetadata) SEM data de compra (não é compra real). Sinalizadas
  # no inbox pra o usuário saber que não são gasto seu (RF2.7).
  module AggregatorAdjustment
    DESCRIPTION_RE = /\Aajuste a (d[eé]bito|cr[eé]dito)\b/i

    module_function

    def match?(description:, source_metadata:)
      return false unless description.to_s.strip.match?(DESCRIPTION_RE)

      meta = source_metadata.is_a?(Hash) ? source_metadata["creditCardMetadata"] : nil
      meta.is_a?(Hash) && meta["purchaseDate"].blank?
    end
  end
end
