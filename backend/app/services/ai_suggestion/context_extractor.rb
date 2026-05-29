module AiSuggestion
  module ContextExtractor
    def self.call(transaction)
      meta = transaction.source_metadata || {}

      {
        description:      transaction.original_description,
        amount:           transaction.amount_cents / 100.0,
        direction:        transaction.direction,
        merchant_name:    meta.dig("merchant", "businessName"),
        merchant_cnae:    meta.dig("merchant", "cnae"),
        pluggy_category:  meta["category"],
        payment_method:   meta.dig("paymentData", "paymentMethod"),
        receiver_name:    meta.dig("paymentData", "receiver", "name")
      }
    end
  end
end
