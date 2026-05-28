class Api::V1::TagsController < ApplicationController
  before_action :require_authentication!

  # GET /api/v1/tags?q= — lista as tags do workspace com contagem de uso.
  # `q` filtra por prefixo (autocomplete, case-insensitive via citext).
  def index
    tags = current_workspace.tags
                            .left_joins(:transaction_tags)
                            .select("tags.*, COUNT(transaction_tags.id) AS usage_count")
                            .group("tags.id")
                            .order(:name)
    tags = tags.where("tags.name LIKE ?", "#{params[:q]}%") if params[:q].present?

    render json: { tags: tags.map { |t| serialize(t) } }
  end

  # POST /api/v1/tags — { name, color, icon }.
  def create
    tag = current_workspace.tags.create!(tag_params)
    render json: { tag: serialize(tag) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "validation_failed", message: e.message } },
           status: :unprocessable_entity
  end

  private

  def tag_params
    params.permit(:name, :color, :icon)
  end

  def current_workspace
    selected   = session[:active_workspace_id]
    workspaces = current_user.workspaces
    (selected && workspaces.find_by(id: selected)) || workspaces.order(:created_at).first
  end

  def serialize(tag)
    {
      id:          tag.id,
      name:        tag.name,
      color:       tag.color,
      icon:        tag.icon,
      usage_count: tag.respond_to?(:usage_count) ? tag.usage_count.to_i : tag.transactions.count
    }
  end
end
