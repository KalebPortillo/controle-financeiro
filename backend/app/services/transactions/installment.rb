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

    # group_id determinístico das parcelas da mesma compra. A chave é
    # conta+descritor+MÊS_DA_COMPRA+total. O mês da compra é RETRO-CALCULADO da
    # parcela (`occurred` − (`number`−1) meses), não lido do
    # `creditCardMetadata.purchaseDate`: o Pluggy emite purchaseDate SINTÉTICO (= a
    # data da fatura) nas parcelas futuras/projetadas E varia o cardNumber entre a
    # canônica e as projetadas, o que fragmentava uma compra em vários grupos.
    #
    # Usamos só o MÊS (não o dia) porque a 1ª parcela costuma postar na DATA DA
    # COMPRA e as demais no DIA DA FATURA — dias diferentes que quebrariam o
    # agrupamento se a chave usasse o dia (bug real "Steam 1/3" separada de 2/3).
    # Trade-off aceito: duas compras no MESMO lugar, MESMO total e MESMO mês
    # agrupam como uma (raro; a granularidade de dia pegava esse caso mas quebrava
    # o comum). Sem number/occurred (OFX/manual), cai no descritor normalizado.
    def group_id(account_id:, description:, total:, number: nil, occurred: nil)
      desc  = Recurrences::Descriptor.normalize(description)
      month = purchase_anchor(number: number, occurred: occurred)&.slice(0, 7) # "YYYY-MM"
      key   = month ? "#{account_id}:#{desc}:#{month}:#{total}" : "#{account_id}:#{desc}:#{total}"
      Digest::UUID.uuid_v5(NAMESPACE, key)
    end

    # Data (ISO) da compra retro-calculada da parcela: a parcela N faturada em
    # `occurred` veio de uma compra ~(N−1) meses antes. Independe do purchaseDate.
    def purchase_anchor(number:, occurred:)
      return unless number && occurred

      (occurred.to_date << (number.to_i - 1)).iso8601
    rescue ArgumentError, Date::Error, TypeError, NoMethodError
      nil
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

    # Existe no `relation` uma parcela canônica (não projetada) equivalente —
    # mesma posição (número/total) e mesmo estabelecimento (descritor
    # normalizado)? Usado pra (a) não importar a projetada duplicada no sync e
    # (b) rejeitá-la no backfill.
    def canonical_exists?(relation, total:, number:, description:, exclude_id: nil)
      desc = Recurrences::Descriptor.normalize(description)
      rel = relation.where(installment_total: total, installment_number: number)
      rel = rel.where.not(id: exclude_id) if exclude_id
      rel.any? do |s|
        Recurrences::Descriptor.normalize(s.original_description) == desc &&
          !projected?(s.source_metadata, s.occurred_at)
      end
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
