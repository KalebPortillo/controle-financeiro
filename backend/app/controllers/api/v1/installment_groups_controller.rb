class Api::V1::InstallmentGroupsController < ApplicationController
  before_action :require_authentication!

  # PATCH /api/v1/installment_groups/:id — edita título/tags de todas as parcelas
  # do parcelamento (RF9.4.1). :id é o installment_group_id.
  def update
    transactions = Transactions::UpdateInstallmentGroup.call(
      workspace:  current_workspace,
      group_id:   params[:id],
      membership: current_membership,
      attrs:      group_params
    )
    render json: {
      updated_count: transactions.size,
      transactions:  transactions.map { |t| { id: t.id, improved_title: t.improved_title,
                                              tags: t.tags.map { |tag| { id: tag.id, name: tag.name } } } }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: { code: "not_found", message: "Parcelamento não encontrado." } },
           status: :not_found
  end

  # POST /api/v1/installment_groups/:id/consolidate — aceita TODAS as parcelas
  # pendentes do grupo de uma vez (RF9.4 — item agregado do inbox).
  def consolidate
    apply_status("consolidated", consolidated_at: Time.current)
  end

  # POST /api/v1/installment_groups/:id/reject — rejeita todas as pendentes.
  def reject
    apply_status("rejected", rejected_at: Time.current)
  end

  private

  def apply_status(status, **timestamps)
    return render_not_found unless group_exists?

    count = pending_in_group.update_all({ status: status }.merge(timestamps))
    render json: { count: count }
  end

  def group_exists?
    current_workspace.transactions.exists?(installment_group_id: params[:id])
  end

  def pending_in_group
    current_workspace.transactions.where(installment_group_id: params[:id], status: "pending")
  end

  def render_not_found
    render json: { error: { code: "not_found", message: "Parcelamento não encontrado." } },
           status: :not_found
  end

  def group_params
    params.permit(:improved_title, tag_ids: []).to_h.symbolize_keys
  end
end
