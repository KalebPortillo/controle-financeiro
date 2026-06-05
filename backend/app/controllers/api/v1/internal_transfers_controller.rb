class Api::V1::InternalTransfersController < ApplicationController
  before_action :require_authentication!
  before_action :set_internal_transfer, only: [ :destroy ]

  # GET /api/v1/internal_transfers — pares do workspace pra reconciliação (RF11.3).
  def index
    transfers = current_workspace.internal_transfers
                                 .includes(debit_transaction: :account, credit_transaction: :account)
                                 .order(detected_at: :desc)
    render json: { internal_transfers: transfers.map { |t| serialize(t) } }
  end

  # POST /api/v1/internal_transfers { debit_transaction_id, credit_transaction_id }
  # Marca manualmente (RF11.4). FKs buscadas escopadas — nunca mass-assignment.
  def create
    debit  = current_workspace.transactions.find(params.require(:debit_transaction_id))
    credit = current_workspace.transactions.find(params.require(:credit_transaction_id))
    transfer = current_workspace.internal_transfers.create!(
      debit_transaction: debit, credit_transaction: credit,
      confirmed_by_membership: current_membership, detected_at: Time.current
    )
    render json: { internal_transfer: serialize(transfer) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "invalid_transfer", message: e.message } }, status: :unprocessable_entity
  end

  # DELETE /api/v1/internal_transfers/:id — desmarca (RF11.4).
  def destroy
    @internal_transfer.destroy!
    head :no_content
  end

  private

  def set_internal_transfer
    @internal_transfer = current_workspace.internal_transfers.find(params[:id])
  end

  def serialize(t)
    {
      id:          t.id,
      manual:      t.manual?,
      detected_at: t.detected_at.iso8601,
      debit:  tx_summary(t.debit_transaction),
      credit: tx_summary(t.credit_transaction)
    }
  end

  def tx_summary(tx)
    {
      id:           tx.id,
      account_name: tx.account&.name,
      amount_cents: tx.amount_cents,
      occurred_at:  tx.occurred_at.iso8601,
      title:        tx.improved_title || tx.original_description
    }
  end
end
