class AddConfidenceToTransactionRefunds < ActiveRecord::Migration[8.0]
  def change
    # RF10.6 — confiança do auto-vínculo por heurística: "high" (nome/código
    # único) ou "medium" (nome genérico + valor exato). NULL nos manuais.
    add_column :transaction_refunds, :confidence, :string
    add_check_constraint :transaction_refunds,
                         "confidence IS NULL OR confidence IN ('high','medium')",
                         name: "transaction_refunds_confidence_check"
  end
end
