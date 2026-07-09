module Recurrences
  # RF9.1 — detecção automática de recorrentes a partir do histórico
  # consolidado. Agrupa débitos consolidados por (conta, descritor normalizado)
  # e, quando há cadência consistente + valores próximos, cria/atualiza uma
  # Recurrence com source "detected".
  #
  # Não responsável por avisar atrasos (RF9.6) nem projetar vencimentos
  # (RF9.3) — isso fica em fatias seguintes. Aqui só popula/atualiza o catálogo.
  class Detect
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(workspace:)
      @workspace = workspace
    end

    # Retorna as recorrentes criadas/atualizadas nesta passagem.
    def call
      groups = @workspace.transactions
                         .consolidated
                         .where(direction: "debit")
                         .order(:occurred_at)
                         .group_by { |t| [ t.account_id, Descriptor.normalize(t.original_description) ] }

      groups.filter_map { |(account_id, pattern), txs| detect_group(account_id, pattern, txs) }
    end

    private

    def detect_group(account_id, pattern, txs)
      return if pattern.blank?

      guess = Guess.confident(txs)
      return unless guess

      existing = @workspace.recurrences.find_by(account_id: account_id, descriptor_pattern: pattern)
      return if existing&.source == "manual" # nunca sobrescreve cadastro manual

      rec = existing || @workspace.recurrences.new(
        account_id: account_id, descriptor_pattern: pattern, source: "detected"
      )
      rec.assign_attributes(guess.merge(status: rec.status.presence || "active"))
      rec.save!
      rec
    end
  end
end
