class Api::V1::CategoriesController < ApplicationController
  before_action :require_authentication!
  before_action :set_category, only: [ :update, :destroy, :merge ]

  # GET /api/v1/categories — categorias do workspace com suas tags (RF6).
  def index
    categories = current_workspace.categories.includes(:tags).order(:name)
    render json: { categories: categories.map { |c| serialize(c) } }
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
      tags:  category.tags.order(:name).map { |t| { id: t.id, name: t.name, color: t.color } }
    }
  end
end
