module Api
  module V1
    # Lista enxuta das contas do workspace — alimenta os filtros de relatório
    # (conta/cartão e pessoa) e outras seleções de conta no front.
    class AccountsController < ApplicationController
      before_action :require_authentication!

      # GET /api/v1/accounts
      def index
        accounts = current_workspace.accounts.order(:kind, :name)
        render json: { accounts: accounts.map { |a| serialize(a) } }
      end

      private

      def serialize(a)
        {
          id:                   a.id,
          name:                 a.name,
          kind:                 a.kind,
          institution:          a.institution,
          institution_label:    BankConnections::Serializer::INSTITUTION_LABELS[a.institution],
          last_digits:          a.last_digits,
          owner_membership_id:  a.owner_membership_id,
          currency:             a.currency
        }
      end
    end
  end
end
