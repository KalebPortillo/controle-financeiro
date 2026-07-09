# RF9.7 — itens que o usuário removeu (ou restaurou) do grupo de uma
# recorrência. A recorrência casa gastos por descritor (RF9.1); a exclusão tira
# um gasto avulso que caiu no padrão sem fazer parte da assinatura.
class Api::V1::RecurrenceExclusionsController < ApplicationController
  before_action :require_authentication!
  before_action :set_recurrence

  # POST /api/v1/recurrences/:recurrence_id/exclusions — remove o gasto do grupo.
  # Idempotente: se já está excluído, devolve 200 sem duplicar.
  def create
    tx = current_workspace.transactions.find(params[:transaction_id])
    exclusion = @recurrence.exclusions.find_by(transaction_id: tx.id)
    return head :ok if exclusion

    @recurrence.exclusions.create!(transaction_id: tx.id, workspace: current_workspace)
    head :created
  end

  # DELETE /api/v1/recurrences/:recurrence_id/exclusions/:transaction_id —
  # restaura o gasto ao grupo.
  def destroy
    @recurrence.exclusions.where(transaction_id: params[:transaction_id]).destroy_all
    head :no_content
  end

  private

  def set_recurrence
    @recurrence = current_workspace.recurrences.find(params[:recurrence_id])
  end
end
