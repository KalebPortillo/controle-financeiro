class Api::V1::SuggestedCategoriesController < ApplicationController
  before_action :require_authentication!
  before_action :set_suggested_category, only: [ :accept, :destroy ]

  # GET /api/v1/suggested_categories — sugestões pendentes do workspace (RF22).
  def index
    suggestions = current_workspace.suggested_categories.pending.order(name: :asc)
    render json: { suggested_categories: suggestions.map { |s| serialize(s) } }
  end

  # POST /api/v1/suggested_categories/:id/accept — promove a Category real
  # (reaproveita uma de mesmo nome) e associa as tags por nome (escopadas ao
  # workspace). Marca a sugestão como accepted.
  def accept
    category = nil
    ActiveRecord::Base.transaction do
      category = current_workspace.categories.find_or_create_by!(name: @suggested_category.name)
      tags = current_workspace.tags.where(name: @suggested_category.tag_names)
      category.tags = tags if tags.any?
      @suggested_category.update!(status: "accepted")
    end
    render json: { category: serialize_category(category) }
  end

  # DELETE /api/v1/suggested_categories/:id — recusa (status dismissed).
  def destroy
    @suggested_category.update!(status: "dismissed")
    head :no_content
  end

  private

  def set_suggested_category
    @suggested_category = current_workspace.suggested_categories.find(params[:id])
  end

  def serialize(suggestion)
    {
      id:        suggestion.id,
      name:      suggestion.name,
      tag_names: suggestion.tag_names,
      status:    suggestion.status
    }
  end

  def serialize_category(category)
    {
      id:    category.id,
      name:  category.name,
      color: category.color,
      tags:  category.tags.order(:name).map { |t| { id: t.id, name: t.name, color: t.color } }
    }
  end
end
