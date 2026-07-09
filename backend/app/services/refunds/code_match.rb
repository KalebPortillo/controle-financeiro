module Refunds
  # RF10.6 — casa um estorno (credit) ao gasto original pelo CÓDIGO exato que
  # muitas vezes aparece no próprio nome (referência da compra, ID do
  # estabelecimento, etc.). Cruza os códigos do estorno com os dos candidatos
  # por valor+recência (Refunds::Candidates). Devolve o gasto SÓ quando o match
  # é único — nome genérico ou código que casa vários fica ambíguo (nil) e vira
  # apenas sugestão on-demand, nunca auto-vínculo.
  module CodeMatch
    # Token distintivo: sequência alfanumérica de 5+ chars contendo ao menos um
    # dígito (referências e IDs têm dígito; palavras comuns como "COMPRA" e
    # "ESTORNO" são puro texto e ficam de fora). Máscaras de 4 dígitos (••5190)
    # também caem fora pelo comprimento.
    CODE_RE = /[A-Z0-9]{5,}/

    module_function

    def call(credit:)
      return unless credit.direction == "credit"

      codes = codes_in(credit.original_description)
      return if codes.empty?

      matches = Candidates.call(credit: credit).select do |debit|
        codes_in(debit.original_description).intersect?(codes)
      end
      matches.first if matches.one?
    end

    def codes_in(description)
      description.to_s.upcase.scan(CODE_RE).select { |token| token.match?(/\d/) }.to_set
    end
  end
end
