class FixCreditCardTransactionDirection < ActiveRecord::Migration[8.0]
  # Bug: a direção (débito/crédito) das transações sincronizadas via Pluggy era
  # inferida do SINAL do amount. Em cartão de crédito o Pluggy inverte o sinal —
  # a compra (gasto) chega POSITIVA — então gastos viravam "credit" (receita,
  # com + na frente). O sync agora usa o campo `type` ("DEBIT"/"CREDIT") do
  # Pluggy; aqui corrigimos as linhas já gravadas usando esse mesmo `type`, que
  # ficou salvo no source_metadata cru.
  #
  # Só toca em automatic_sync com `type` presente e divergente. amount_cents já
  # é sempre positivo, então só a coluna `direction` precisa mudar.
  def up
    execute(<<~SQL)
      UPDATE transactions
      SET direction = CASE upper(source_metadata->>'type')
                        WHEN 'DEBIT'  THEN 'debit'
                        WHEN 'CREDIT' THEN 'credit'
                      END
      WHERE source = 'automatic_sync'
        AND upper(source_metadata->>'type') IN ('DEBIT', 'CREDIT')
        AND direction <> CASE upper(source_metadata->>'type')
                           WHEN 'DEBIT'  THEN 'debit'
                           WHEN 'CREDIT' THEN 'credit'
                         END
    SQL
  end

  # Correção de dado corrompido — não há estado anterior "bom" pra restaurar.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
