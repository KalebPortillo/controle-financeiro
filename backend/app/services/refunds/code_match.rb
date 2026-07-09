module Refunds
  # RF10.6 — casa um estorno (credit) ao gasto original pelo CÓDIGO exato que
  # costuma aparecer no próprio nome (referência da compra). Dois regimes:
  #
  #  - **Estorno comum** (não-IOF): o código identifica a compra e o vínculo é
  #    pelo código, **independente do valor** — pode ser estorno PARCIAL (a
  #    compra de R$1.030 volta em pedaços). Alvo = a própria compra.
  #  - **Estorno de IOF** ("IOF de volta de X CÓDIGO"): o código identifica a
  #    compra, mas o alvo é o **débito de IOF** daquela compra (satélite RF23) e
  #    o valor tem de ser EXATAMENTE o do IOF cobrado antes.
  #
  # Devolve o débito-alvo só quando o casamento é ÚNICO; nome genérico, código
  # repetido (ex.: "99FOOD") ou IOF sem satélite de valor exato → nil (fica só
  # como sugestão on-demand, nunca auto-vínculo).
  module CodeMatch
    # Token distintivo: sequência alfanumérica de 5+ chars com ao menos um dígito
    # (refs/IDs têm dígito; "COMPRA"/"ESTORNO" são puro texto e ficam de fora;
    # máscaras de 4 dígitos caem fora pelo comprimento).
    CODE_RE = /[A-Z0-9]{5,}/
    IOF_RE  = /iof/i

    # A compra pode anteceder o estorno em semanas/meses; a "de volta" é curta.
    WINDOW_BEFORE = 180
    WINDOW_AFTER  = 15

    module_function

    def call(credit:)
      return unless credit.direction == "credit"

      codes = codes_in(credit.original_description)
      return if codes.empty?

      purchase = unique_coded_debit(credit, codes)
      return unless purchase

      iof_refund?(credit) ? exact_iof_debit(purchase, credit) : purchase
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

    def unique_coded_debit(credit, codes)
      matches = coded_debits(credit).select { |d| codes_in(d.original_description).intersect?(codes) }
      matches.first if matches.one?
    end

    def coded_debits(credit)
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
  end
end
