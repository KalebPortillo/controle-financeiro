class Api::V1::CategoriesController < ApplicationController
  before_action :require_authentication!
  before_action :set_category, only: [ :update, :destroy, :merge, :suggest_tags,
                                       :accept_tag_suggestion, :dismiss_tag_suggestion ]

  # GET /api/v1/categories — categorias do workspace com suas tags + as tags
  # sugeridas pendentes por categoria (RF6). `ai_error` (camada de feedback) traz
  # o último erro de IA não-recuperável — null quando não há.
  def index
    categories = current_workspace.categories
                                  .includes(:tags, category_tag_suggestions: :tag).order(:name)
    render json: {
      categories: categories.map { |c| serialize(c) },
      ai_error:   current_workspace.ai_error_payload
    }
  end

  # POST /api/v1/categories — { name, color, icon, tag_ids }.
  def create
    category = current_workspace.categories.new(category_params)
    category.save!
    apply_tags(category, params[:tag_ids]) if params.key?(:tag_ids)
    render json: { category: serialize(category) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_entity
  end

  # PATCH /api/v1/categories/:id — renomeia/cor + substitui tags (RF6.4).
  def update
    @category.update!(category_params)
    apply_tags(@category, params[:tag_ids]) if params.key?(:tag_ids)
    render json: { category: serialize(@category) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_entity
  end

  # DELETE /api/v1/categories/:id
  def destroy
    @category.destroy!
    head :no_content
  end

  # POST /api/v1/categories/:id/merge — { into_category_id } (RF6.4).
  def merge
    dest = current_workspace.categories.find(params.require(:into_category_id))
    Category.transaction do
      taken = CategoryTag.where(category_id: dest.id).select(:tag_id)
      @category.category_tags.where.not(tag_id: taken).update_all(category_id: dest.id)
      @category.destroy!
    end
    render json: { category: serialize(dest) }
  end

  # POST /api/v1/categories/:id/suggest_tags — gera, via IA, sugestões de tags
  # consolidadas que faltam na categoria (on-demand, assíncrono). 202.
  def suggest_tags
    current_workspace.clear_ai_error!
    Categories::SuggestTagsJob.perform_later(@category.id)
    head :accepted
  end

  # POST /api/v1/categories/:id/tag_suggestions/:tag_id/accept — adiciona a tag
  # sugerida à categoria e marca a sugestão como accepted.
  def accept_tag_suggestion
    suggestion = @category.category_tag_suggestions.find_by!(tag_id: params[:tag_id])
    ActiveRecord::Base.transaction do
      @category.tags << suggestion.tag unless @category.tags.exists?(suggestion.tag_id)
      suggestion.update!(status: "accepted")
    end
    render json: { category: serialize(@category) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: { code: "not_found", message: "Sugestão não encontrada." } }, status: :not_found
  end

  # DELETE /api/v1/categories/:id/tag_suggestions/:tag_id — recusa (dismissed).
  def dismiss_tag_suggestion
    suggestion = @category.category_tag_suggestions.find_by!(tag_id: params[:tag_id])
    suggestion.update!(status: "dismissed")
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: { code: "not_found", message: "Sugestão não encontrada." } }, status: :not_found
  end

  private

  def set_category
    @category = current_workspace.categories.find(params[:id])
  end

  def category_params
    params.permit(:name, :color, :icon)
  end

  # Substitui as tags da categoria (RF6.2). Escopado no workspace.
  def apply_tags(category, tag_ids)
    ids = Array(tag_ids).map(&:to_s)
    category.tags = current_workspace.tags.where(id: ids)
  end

  def serialize(category)
    {
      id:    category.id,
      name:  category.name,
      color: category.color,
      icon:  category.icon,
      tags:  category.tags.order(:name).map { |t| { id: t.id, name: t.name, color: t.color } },
      # Tags sugeridas pendentes (RF6) — id é o da TAG (chave do accept/dismiss).
      tag_suggestions: category.category_tag_suggestions.select { |s| s.status == "pending" }
                               .map { |s| { id: s.tag.id, name: s.tag.name, color: s.tag.color } }
    }
  end
end
