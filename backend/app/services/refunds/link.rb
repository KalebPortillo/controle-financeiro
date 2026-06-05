module Refunds
  # RF10.2 — cria o vínculo de estorno (credit → debit), sempre confirmado por
  # um humano (RF10.5). Levanta ActiveRecord::RecordInvalid se as direções/
  # workspace não baterem (validado no model TransactionRefund).
  class Link
    InvalidLink = Class.new(StandardError)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(credit:, debit:, membership:)
      @credit     = credit
      @debit      = debit
      @membership = membership
    end

    def call
      TransactionRefund.create!(
        refund_transaction:      @credit,
        refunded_transaction:    @debit,
        confirmed_by_membership: @membership,
        confirmed_at:            Time.current
      )
    end
  end
end
