class Api::V1::SuggestedTagsController < ApplicationController
  include SuggestionsEndpoint

  # POST /api/v1/suggested_tags/:id/accept — promove a sugestão a Tag real
  # (reaproveita uma tag de mesmo nome se já existir) e a marca como accepted.
  # Body opcional { transaction_id } aplica a tag àquela transação (chip fantasma
  # da inbox). transaction_id é buscado escopado — nunca por mass-assignment.
  def accept
    tag = nil
    ActiveRecord::Base.transaction do
      tag = current_workspace.tags.find_or_create_by!(name: @suggestion.name)
      @suggestion.update!(status: "accepted")
      apply_to_transaction(tag) if params[:transaction_id].present?
    end
    render json: { tag: serialize_tag(tag) }
  end

  private

  def suggestion_scope = current_workspace.suggested_tags
  def index_root = :suggested_tags
  def index_order = { coverage: :desc, name: :asc }

  def apply_to_transaction(tag)
    txn = current_workspace.transactions.find(params[:transaction_id])
    txn.tags << tag unless txn.tags.exists?(tag.id)
  end

  def serialize(suggestion)
    {
      id:        suggestion.id,
      name:      suggestion.name,
      rationale: suggestion.rationale,
      coverage:  suggestion.coverage,
      source:    suggestion.source,
      status:    suggestion.status
    }
  end

  def serialize_tag(tag)
    { id: tag.id, name: tag.name, color: tag.color, icon: tag.icon }
  end
end
