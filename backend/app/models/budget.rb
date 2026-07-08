# Orçamento mensal (RF8): teto de gasto por tag, categoria ou combinação livre
# de tags (composite). O gasto é sempre sobre consolidados (RF8.6); o cálculo de
# progresso vive em Budgets::Progress. Um mesmo gasto pode contar em vários
# orçamentos (RF6.6) — cada orçamento é uma visão independente de consumo.
class Budget < ApplicationRecord
  KINDS = %w[tag category composite].freeze

  belongs_to :workspace
  belongs_to :target_tag,      class_name: "Tag",      optional: true
  belongs_to :target_category, class_name: "Category", optional: true

  has_many :budget_composite_tags, dependent: :destroy
  has_many :composite_tags, through: :budget_composite_tags, source: :tag

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :monthly_limit_cents, numericality: { greater_than: 0 }
  validates :alert_threshold_pct, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validate  :target_matches_kind
  validate  :targets_in_workspace

  scope :enabled, -> { where(enabled: true) }

  # Vigente na data: habilitado e dentro da janela starts_on..ends_on (ambas
  # opcionais — nil = sem limite daquele lado).
  scope :active_on, ->(date) {
    enabled
      .where("starts_on IS NULL OR starts_on <= ?", date)
      .where("ends_on IS NULL OR ends_on >= ?", date)
  }

  # Tags que este orçamento rastreia — base do cálculo de gasto. tag → a própria;
  # category → todas as tags da categoria; composite → as tags escolhidas.
  def tracked_tag_ids
    case kind
    when "tag"       then [ target_tag_id ].compact
    when "category"  then target_category&.tag_ids || []
    when "composite" then composite_tags.ids
    else []
    end
  end

  private

  # Checa a ASSOCIAÇÃO (não o _id) — em registro construído (unsaved) o FK ainda
  # é nil mesmo com o alvo presente.
  def target_matches_kind
    case kind
    when "tag"
      errors.add(:target_tag, "é obrigatório para orçamento por tag") if target_tag.blank?
      errors.add(:target_category, "não se aplica a orçamento por tag") if target_category.present?
    when "category"
      errors.add(:target_category, "é obrigatória para orçamento por categoria") if target_category.blank?
      errors.add(:target_tag, "não se aplica a orçamento por categoria") if target_tag.present?
    when "composite"
      errors.add(:target_tag, "não se aplica a orçamento composto") if target_tag.present?
      errors.add(:target_category, "não se aplica a orçamento composto") if target_category.present?
    end
  end

  def targets_in_workspace
    if target_tag && target_tag.workspace_id != workspace_id
      errors.add(:target_tag, "deve ser do mesmo workspace")
    end
    if target_category && target_category.workspace_id != workspace_id
      errors.add(:target_category, "deve ser do mesmo workspace")
    end
  end
end
