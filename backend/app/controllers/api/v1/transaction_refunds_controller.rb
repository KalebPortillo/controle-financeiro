class Api::V1::TransactionRefundsController < ApplicationController
  before_action :require_authentication!

  # DELETE /api/v1/transaction_refunds/:id — desfaz um vínculo de estorno (RF10).
  # Escopado: só estornos cujas transações são do workspace atual.
  def destroy
    refund = current_workspace_refunds.find(params[:id])
    refund.destroy!
    head :no_content
  end

  private

  def current_workspace_refunds
    TransactionRefund.joins(:refund_transaction)
                     .where(transactions: { workspace_id: current_workspace.id })
  end
end
