module Transactions
  # Conserta gastos em moeda estrangeira que entraram com o valor NOMINAL (ex.:
  # USD) como se fosse BRL. Recalcula amount_cents/currency a partir do
  # amountInAccountCurrency do Pluggy (valor já convertido), guardado no
  # source_metadata. Idempotente. Ver BankConnections::Sync (caminho do sync).
  module BackfillForeignCurrency
    module_function

    def call
      fixed = 0
      skipped = 0

      Transaction.where("source_metadata ->> 'currencyCode' IS NOT NULL").find_each do |t|
        code      = t.source_metadata["currencyCode"]
        converted = t.source_metadata["amountInAccountCurrency"]
        base      = t.account&.currency.presence || "BRL"

        if code.to_s.upcase == base.to_s.upcase || converted.blank?
          skipped += 1
          next
        end

        cents = (converted.to_f.abs * 100).round
        if t.amount_cents == cents && t.currency == base
          skipped += 1 # já convertido
          next
        end

        # update_columns: backfill puro, sem callbacks/lock_version/broadcast.
        t.update_columns(amount_cents: cents, currency: base, updated_at: Time.current)
        fixed += 1
      end

      { fixed: fixed, skipped: skipped }
    end
  end
end
