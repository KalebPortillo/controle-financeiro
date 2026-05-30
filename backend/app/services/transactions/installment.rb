module Transactions
  # RF9.4 — parcelamento de cartão. Extrai número/total da parcela do payload do
  # agregador (creditCardMetadata do Pluggy) com fallback pra descrição ("3/12"),
  # e gera um group_id estável que liga todas as parcelas da mesma compra ao
  # longo dos meses.
  module Installment
    Info = Struct.new(:number, :total, keyword_init: true)

    # Namespace fixo pro UUIDv5 (determinístico) do agrupamento de parcelas.
    NAMESPACE      = "9b2e1f3a-7c4d-4e8a-bd6f-2a1c3e5d7f90".freeze
    MAX_TOTAL      = 60 # acima disso é provável ruído (data, código), não parcela
    DESCRIPTION_RE = %r{\b(\d{1,2})\s*/\s*(\d{1,2})\b}

    module_function

    # → Info(number:, total:) ou nil. Metadata tem precedência sobre a descrição.
    def parse(raw: nil, description: nil)
      from_metadata(raw) || from_description(description)
    end

    # group_id determinístico: mesma conta + mesmo estabelecimento (descritor
    # normalizado) + mesmo total ⇒ mesmas parcelas. Normalização remove o "3/12"
    # da descrição, então parcelas diferentes da mesma compra colidem de propósito.
    def group_id(account_id:, description:, total:)
      key = "#{account_id}:#{Recurrences::Descriptor.normalize(description)}:#{total}"
      Digest::UUID.uuid_v5(NAMESPACE, key)
    end

    def from_metadata(raw)
      meta = raw["creditCardMetadata"] if raw.is_a?(Hash)
      return unless meta.is_a?(Hash)

      build(meta["installmentNumber"], meta["totalInstallments"])
    end

    def from_description(description)
      m = description.to_s.match(DESCRIPTION_RE)
      m && build(m[1], m[2])
    end

    def build(number, total)
      number = number.to_i
      total  = total.to_i
      return unless total.between?(2, MAX_TOTAL)
      return unless number.between?(1, total)

      Info.new(number: number, total: total)
    end
  end
end
