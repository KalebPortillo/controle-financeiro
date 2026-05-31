class Api::V1::SuggestedTagsController < ApplicationController
  before_action :require_authentication!
  before_action :set_suggested_tag, only: [ :accept, :destroy ]

  # GET /api/v1/suggested_tags — sugestões pendentes do workspace (RF3/RF22),
  # mais relevantes (maior cobertura) primeiro.
  def index
    suggestions = current_workspace.suggested_tags.pending.order(coverage: :desc, name: :asc)
    render json: { suggested_tags: suggestions.map { |s| serialize(s) } }
  end

  # POST /api/v1/suggested_tags/:id/accept — promove a sugestão a Tag real
  # (reaproveita uma tag de mesmo nome se já existir) e a marca como accepted.
  # Body opcional { transaction_id } aplica a tag àquela transação (chip fantasma
  # da inbox). transaction_id é buscado escopado — nunca por mass-assignment.
  def accept
    tag = nil
    ActiveRecord::Base.transaction do
      tag = current_workspace.tags.find_or_create_by!(name: @suggested_tag.name)
      @suggested_tag.update!(status: "accepted")
      apply_to_transaction(tag) if params[:transaction_id].present?
    end
    render json: { tag: serialize_tag(tag) }
  end

  # DELETE /api/v1/suggested_tags/:id — recusa a sugestão (status dismissed).
  def destroy
    @suggested_tag.update!(status: "dismissed")
    head :no_content
  end

  private

  def set_suggested_tag
    @suggested_tag = current_workspace.suggested_tags.find(params[:id])
  end

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
