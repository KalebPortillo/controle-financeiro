class Api::V1::SuggestedCategoriesController < ApplicationController
  include SuggestionsEndpoint

  # POST /api/v1/suggested_categories/:id/accept — promove a Category real
  # (reaproveita uma de mesmo nome) e associa as tags por nome (escopadas ao
  # workspace). Marca a sugestão como accepted.
  def accept
    category = nil
    ActiveRecord::Base.transaction do
      category = current_workspace.categories.find_or_create_by!(name: @suggestion.name)
      tags = current_workspace.tags.where(name: @suggestion.tag_names)
      category.tags = tags if tags.any?
      @suggestion.update!(status: "accepted")
    end
    render json: { category: serialize_category(category) }
  end

  private

  def suggestion_scope = current_workspace.suggested_categories
  def index_root = :suggested_categories
  def index_order = { name: :asc }

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
