module InternalTransfers
  # RF11.1 — detecção automática de transferências internas a partir do histórico
  # consolidado: para cada débito (saída), procura um crédito de MESMO valor em
  # OUTRA conta do workspace dentro de uma janela curta, ainda não vinculado.
  # Idempotente (não recria vínculos existentes). Cria com confirmed_by nil (auto).
  class Detect
    WINDOW_DAYS = 3

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(workspace:)
      @workspace = workspace
    end

    # Retorna as transferências criadas nesta passagem.
    def call
      debits = @workspace.transactions.consolidated.where(direction: "debit")
                         .where.missing(:transfer_as_debit)
                         .order(:occurred_at)

      debits.filter_map { |debit| try_match(debit) }
    end

    private

    def try_match(debit)
      credit = candidate_credit_for(debit)
      return unless credit

      InternalTransfer.create!(
        workspace: @workspace,
        debit_transaction: debit,
        credit_transaction: credit,
        detected_at: Time.current
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      nil # corrida/duplicado — ignora
    end

    # Crédito de mesmo valor, outra conta, janela curta, ainda não vinculado.
    def candidate_credit_for(debit)
      @workspace.transactions.consolidated
                .where(direction: "credit", amount_cents: debit.amount_cents)
                .where.not(account_id: debit.account_id)
                .where(occurred_at: (debit.occurred_at - WINDOW_DAYS)..(debit.occurred_at + WINDOW_DAYS))
                .where.missing(:transfer_as_credit)
                .order(Arel.sql("ABS(occurred_at - DATE '#{debit.occurred_at}')"))
                .first
    end
  end
end
