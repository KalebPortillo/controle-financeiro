class Api::V1::TransactionLinksController < ApplicationController
  before_action :require_authentication!

  # DELETE /api/v1/transaction_links/:id — desvincula um IOF/tarifa do gasto de
  # origem (RF23). Escopado ao workspace atual.
  def destroy
    link = current_workspace.transaction_links.find(params[:id])
    link.destroy!
    head :no_content
  end
end
