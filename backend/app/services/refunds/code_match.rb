module Refunds
  # RF10.6 — casa um estorno (credit) ao gasto original. Dois regimes:
  #
  #  - **Estorno comum** (não-IOF): casa pelo CÓDIGO distintivo do nome
  #    (referência da compra), independente do valor — pode ser PARCIAL. Alvo = a
  #    compra. Sem código ⇒ nil (fica como sugestão).
  #  - **Estorno de IOF** ("IOF de volta de <COMERCIANTE>"): usa o COMERCIANTE do
  #    nome (que é o mesmo da compra — com ou sem código) pra achar a compra, e o
  #    alvo é o **débito de IOF** dela (satélite RF23) com valor EXATAMENTE igual
  #    ao do IOF cobrado. O valor exato desambigua.
  #
  # Só devolve o alvo quando o casamento é ÚNICO; ambíguo/genérico ⇒ nil.
  module CodeMatch
    # Token distintivo p/ estorno comum: 5+ alfanuméricos com ao menos um dígito.
    CODE_RE = /[A-Z0-9]{5,}/
    IOF_RE  = /iof/i
    # "IOF de volta de <comerciante>" — captura o comerciante.
    IOF_MERCHANT_RE = /iof\s+de\s+volta\s+de\s+(.+)/i

    # A compra pode anteceder o estorno em semanas/meses.
    WINDOW_BEFORE = 180
    WINDOW_AFTER  = 15

    module_function

    def call(credit:)
      return unless credit.direction == "credit"

      iof_refund?(credit) ? iof_refund_target(credit) : coded_refund_target(credit)
    end

    # --- estorno comum: por código, qualquer valor ---------------------------

    def coded_refund_target(credit)
      codes = codes_in(credit.original_description)
      return if codes.empty?

      matches = debits_in_window(credit).select { |d| codes_in(d.original_description).intersect?(codes) }
      matches.first if matches.one?
    end

    # --- estorno de IOF: por comerciante, valor exato do IOF -----------------

    def iof_refund_target(credit)
      merchant = iof_merchant(credit)
      return if merchant.blank?

      targets = debits_in_window(credit)
                .select { |d| merchant_match?(d.original_description, merchant) }
                .filter_map { |purchase| exact_iof_debit(purchase, credit) }
                .uniq
      targets.first if targets.one?
    end

    def iof_merchant(credit)
      raw = credit.original_description.to_s[IOF_MERCHANT_RE, 1]
      normalize_merchant(raw) if raw
    end

    def merchant_match?(purchase_description, merchant)
      p = normalize_merchant(purchase_description)
      return false if p.blank? || merchant.blank?

      p == merchant || p.include?(merchant) || merchant.include?(p)
    end

    # Débito de IOF (satélite RF23 da compra) com valor EXATAMENTE igual ao do
    # estorno de IOF. Único, senão nil.
    def exact_iof_debit(purchase, credit)
      iofs = purchase.related_links
                     .select { |l| l.relation_type == "iof" }
                     .map(&:related_transaction)
                     .select { |iof| iof.amount_cents == credit.amount_cents }
      iofs.first if iofs.one?
    end

    # --- helpers -------------------------------------------------------------

    def debits_in_window(credit)
      credit.workspace.transactions
            .where(direction: "debit")
            .where(occurred_at: (credit.occurred_at - WINDOW_BEFORE)..(credit.occurred_at + WINDOW_AFTER))
    end

    def iof_refund?(credit)
      credit.original_description.to_s.match?(IOF_RE)
    end

    def codes_in(description)
      description.to_s.upcase.scan(CODE_RE).select { |token| token.match?(/\d/) }.to_set
    end

    def normalize_merchant(str)
      str.to_s.upcase.gsub(/[^A-Z0-9]/, " ").squish
    end
  end
end
