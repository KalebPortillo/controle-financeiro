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

    # group_id determinístico das parcelas da mesma compra. O Pluggy não expõe um
    # id de compra, mas o `creditCardMetadata.purchaseDate` (timestamp da compra
    # original) é idêntico em todas as parcelas reais — é o identificador de fato.
    # Quando presente, a chave é conta+cartão+purchaseDate+total, o que distingue
    # compras diferentes no MESMO estabelecimento e total (que colidiam pelo
    # descritor). Sem purchaseDate (OFX/manual), cai no descritor normalizado.
    def group_id(account_id:, description:, total:, raw: nil)
      meta = raw["creditCardMetadata"] if raw.is_a?(Hash)
      purchase = meta["purchaseDate"].presence if meta.is_a?(Hash)
      key =
        if purchase
          "#{account_id}:#{meta['cardNumber']}:#{purchase}:#{total}"
        else
          "#{account_id}:#{Recurrences::Descriptor.normalize(description)}:#{total}"
        end
      Digest::UUID.uuid_v5(NAMESPACE, key)
    end

    # Parcela "projetada" do Pluggy: quando não há a compra real no extrato, ele
    # emite a parcela futura com um purchaseDate SINTÉTICO (= a própria data de
    # vencimento, à meia-noite) e sem payeeMCC. Essas vêm com `id` próprio e
    # furam o dedup, virando duplicata da parcela canônica. occurred é a data da
    # transação (Date) pra casar com o purchaseDate sintético.
    def projected?(raw, occurred)
      meta = raw["creditCardMetadata"] if raw.is_a?(Hash)
      return false unless meta.is_a?(Hash)
      return false if meta["payeeMCC"].present?

      pd = meta["purchaseDate"].presence
      return false unless pd

      t = Time.parse(pd)
      t.hour.zero? && t.min.zero? && t.sec.zero? && t.to_date == occurred
    rescue ArgumentError
      false
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
