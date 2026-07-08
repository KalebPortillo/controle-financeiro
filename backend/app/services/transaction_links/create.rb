module TransactionLinks
  # RF23 Fase 3 — vínculo MANUAL entre um gasto de origem (primary) e uma
  # transação satélite (related): tarifa, juros, ajuste ou IOF que a detecção
  # automática não ancorou. Sempre confirmado por um humano (origin "manual",
  # confirmed_by preenchido). Levanta ActiveRecord::RecordInvalid quando as
  # validações do model falham (mesma transação, outro workspace, já vinculado).
  module Create
    module_function

    def call(workspace:, primary:, related:, relation_type:, membership:)
      TransactionLink.create!(
        workspace:               workspace,
        primary_transaction:     primary,
        related_transaction:     related,
        relation_type:           relation_type,
        origin:                  "manual",
        confirmed_by_membership: membership
      )
    end
  end
end
