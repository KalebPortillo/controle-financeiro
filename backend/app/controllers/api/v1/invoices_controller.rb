class Api::V1::InvoicesController < ApplicationController
  before_action :require_authentication!

  # GET /api/v1/accounts/:account_id/invoices?status=open|future
  # Faturas derivadas do cartão (RF9.5). Só faz sentido para contas de cartão.
  def index
    account = current_workspace.accounts.find(params[:account_id])
    unless account.credit_card?
      return render json: {
        error: { code: "not_a_credit_card", message: "Faturas só existem para contas de cartão." }
      }, status: :unprocessable_entity
    end

    status = params[:status].presence_in(%w[open future]) || "open"
    render json: { invoices: Invoices::Builder.call(account: account, status: status) }
  end
end
