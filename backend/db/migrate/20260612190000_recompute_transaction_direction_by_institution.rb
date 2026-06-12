class RecomputeTransactionDirectionByInstitution < ActiveRecord::Migration[8.0]
  # Recalcula a direção (débito/crédito) das transações sincronizadas, usando a
  # regra correta por instituição. Supera a migração anterior (20260612180000),
  # que confiava só no `type` do Pluggy e, por isso, invertia o cartão no
  # conector SANDBOX.
  #
  # Regra (mesma de BankConnections::Sync#direction_for):
  #   - institution = 'sandbox' (ou sem `type` utilizável): usa o SINAL do amount
  #     (negativo = débito). No sandbox o `type` do cartão vem invertido.
  #   - demais instituições: usa o `type` do Pluggy ("DEBIT"/"CREDIT"), que é
  #     canônico e correto pra conta corrente e cartão (Nubank: compra = DEBIT
  #     com amount positivo).
  #
  # amount_cents já é sempre positivo; só a coluna `direction` muda. Idempotente:
  # só toca linhas cujo valor recalculado difere do atual.
  def up
    execute(<<~SQL)
      UPDATE transactions AS t
      SET direction = src.dir
      FROM (
        SELECT tx.id,
          CASE
            -- Sandbox não segue a convenção do Pluggy: usa o sinal (bank-style).
            WHEN a.institution = 'sandbox'
              THEN CASE WHEN (tx.source_metadata->>'amount')::numeric < 0 THEN 'debit' ELSE 'credit' END
            -- `type` é canônico (doc): DEBIT = saída/gasto, CREDIT = entrada.
            WHEN upper(tx.source_metadata->>'type') = 'DEBIT'  THEN 'debit'
            WHEN upper(tx.source_metadata->>'type') = 'CREDIT' THEN 'credit'
            -- Sem `type`: sinal do amount, com a convenção invertida do cartão.
            WHEN a.kind = 'credit_card'
              THEN CASE WHEN (tx.source_metadata->>'amount')::numeric > 0 THEN 'debit' ELSE 'credit' END
            ELSE CASE WHEN (tx.source_metadata->>'amount')::numeric < 0 THEN 'debit' ELSE 'credit' END
          END AS dir
        FROM transactions tx
        JOIN accounts a ON a.id = tx.account_id
        WHERE tx.source = 'automatic_sync'
          AND (tx.source_metadata ? 'type' OR tx.source_metadata ? 'amount')
      ) AS src
      WHERE t.id = src.id
        AND src.dir IS NOT NULL
        AND t.direction <> src.dir
    SQL
  end

  # Correção de dado — sem estado anterior "bom" pra restaurar.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
