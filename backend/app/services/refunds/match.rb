module Refunds
  # RF10.6 — casa um estorno (credit) ao gasto original por HEURÍSTICA de
  # confiança, não só por código exato:
  #
  #  - **ALTA**: o nome/código do estorno bate um ÚNICO gasto (ou desempata pelo
  #    valor quando o nome casa vários). Vincula mesmo com valor diferente
  #    (estorno parcial, Nike, código único).
  #  - **MÉDIA**: nome genérico, mas o VALOR exato casa um único gasto/IOF.
  #  - **BAIXA (nil)**: nome genérico + valor diferente → fica solto (o usuário
  #    resolve).
  #
  # Portão: só considera créditos que PARECEM estorno (nunca salário/transferência).
  # Estorno de IOF ("IOF de volta de X") ancora no débito de IOF (satélite RF23)
  # com o valor exato do IOF.
  module Match
    Result = Data.define(:debit, :confidence)

    IOF_RE          = /iof/i
    IOF_VOLTA_RE    = /iof\s+de\s+volta\s+de\s+(.+)/i
    REFUND_LIKE_RE  = /estorno|cr[eé]dito de|iof de volta|reembolso|devolu[cç]/i
    MERCHANT_PREFIX = /\A(?:estorno de|cr[eé]dito de|reembolso de|devolu[cç][aã]o de)\s+(.+)/i
    WINDOW_BEFORE   = 180
    WINDOW_AFTER    = 15
    MIN_MERCHANT    = 3

    module_function

    def call(credit:)
      return unless credit.direction == "credit"
      return unless refund_like?(credit)

      iof_refund?(credit) ? match_iof(credit) : match_common(credit)
    end

    # --- estorno comum --------------------------------------------------------

    def match_common(credit)
      debits   = debits_in_window(credit)
      merchant = refund_merchant(credit)
      hits     = merchant ? debits.select { |d| merchant_match?(d.original_description, merchant) } : []

      # Correspondência EXATA de nome (código único) ganha do substring genérico:
      # "Estorno de AMAZON RETA PZ7SW7MV3" casa a compra homônima, não os débitos
      # genéricos "Amazon" que também batem por substring (senão vira ambíguo).
      exact = hits.select { |d| normalize_merchant(d.original_description) == merchant }
      return Result.new(exact.first, :high) if exact.one?

      return Result.new(hits.first, :high) if hits.one?

      if hits.size > 1 # nome ambíguo → desempata pelo valor exato
        exact = hits.select { |d| d.amount_cents == credit.amount_cents }
        return exact.one? ? Result.new(exact.first, :high) : nil
      end

      # nome genérico → valor exato único
      value_hits = debits.select { |d| d.amount_cents == credit.amount_cents }
      Result.new(value_hits.first, :medium) if value_hits.one?
    end

    # --- estorno de IOF -------------------------------------------------------

    def match_iof(credit)
      debits   = debits_in_window(credit)
      merchant = iof_merchant(credit)

      if merchant
        targets = debits.select { |d| merchant_match?(d.original_description, merchant) }
                        .filter_map { |purchase| exact_iof_debit(purchase, credit) }
        return Result.new(targets.first, :high) if targets.one?
      end

      # IOF genérico (ou nome ambíguo): débito de IOF com valor exato, único.
      iofs = debits.select { |d| iof_charge?(d) && d.amount_cents == credit.amount_cents }
      Result.new(iofs.first, :medium) if iofs.one?
    end

    # Débito de IOF (satélite RF23 da compra) com valor EXATAMENTE igual, único.
    def exact_iof_debit(purchase, credit)
      iofs = purchase.related_links.select { |l| l.relation_type == "iof" }
                     .map(&:related_transaction)
                     .select { |iof| iof.amount_cents == credit.amount_cents }
      iofs.first if iofs.one?
    end

    # --- classificação/normalização ------------------------------------------

    def refund_like?(credit)
      credit.original_description.to_s.match?(REFUND_LIKE_RE)
    end

    def iof_refund?(credit)
      credit.original_description.to_s.match?(IOF_RE)
    end

    def iof_charge?(debit)
      debit.original_description.to_s.match?(IOF_RE)
    end

    def iof_merchant(credit)
      merchant_from(credit.original_description.to_s[IOF_VOLTA_RE, 1])
    end

    def refund_merchant(credit)
      d = credit.original_description.to_s
      merchant_from(d[/"([^"]+)"/, 1] || d[MERCHANT_PREFIX, 1])
    end

    def merchant_from(raw)
      return unless raw

      m = normalize_merchant(raw)
      m if m.length >= MIN_MERCHANT
    end

    def merchant_match?(purchase_description, merchant)
      p = normalize_merchant(purchase_description)
      return false if p.length < MIN_MERCHANT

      p == merchant || p.include?(merchant) || merchant.include?(p)
    end

    def debits_in_window(credit)
      credit.workspace.transactions.where(direction: "debit")
            .where(occurred_at: (credit.occurred_at - WINDOW_BEFORE)..(credit.occurred_at + WINDOW_AFTER))
    end

    def normalize_merchant(str)
      str.to_s.upcase.gsub(/[^A-Z0-9]/, " ").squish
    end
  end
end
