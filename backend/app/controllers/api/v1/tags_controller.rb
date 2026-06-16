class Api::V1::TagsController < ApplicationController
  before_action :require_authentication!
  before_action :set_tag, only: [ :update, :destroy, :merge ]

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
  end

  # PATCH /api/v1/tags/:id — { name, color, icon }.
  def update
    @tag.update!(tag_params)
    render json: { tag: serialize(@tag) }
  end

  # DELETE /api/v1/tags/:id — 422 se em uso (orienta merge), senão remove.
  def destroy
    if @tag.transaction_tags.exists?
      render json: { error: { code: "tag_in_use",
                              message: "Tag em uso. Use 'mesclar' para movê-la para outra tag antes de excluir." } },
             status: :unprocessable_entity
      return
    end
    @tag.destroy!
    head :no_content
  end

  # POST /api/v1/tags/:id/merge — { into_tag_id }. Move as relações da tag origem
  # pra destino (sem duplicar) e apaga a origem.
  def merge
    dest = current_workspace.tags.find(params.require(:into_tag_id))

    Tag.transaction do
      # Só reassocia onde o destino ainda não está, pra respeitar o unique
      # (transaction_id, tag_id); as colisões são descartadas com a origem.
      taken = TransactionTag.where(tag_id: dest.id).select(:transaction_id)
      @tag.transaction_tags.where.not(transaction_id: taken).update_all(tag_id: dest.id)
      @tag.destroy!
    end
    render json: { tag: serialize(dest) }
  end

  private

  def set_tag
    @tag = current_workspace.tags.find(params[:id])
  end

  def tag_params
    params.permit(:name, :color, :icon)
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
