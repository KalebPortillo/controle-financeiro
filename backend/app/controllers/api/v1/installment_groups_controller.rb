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

  private

  def group_params
    params.permit(:improved_title, tag_ids: []).to_h.symbolize_keys
  end
end
