# Sugestão de tag para uma categoria (RF6) — a IA propõe uma tag JÁ consolidada
# que ainda não está na categoria. Persistida (catálogo) pra o usuário aceitar
# (adiciona a tag à categoria) ou recusar depois. Nunca cria tag nova: só
# referencia tags reais do workspace (via category.workspace).
class CategoryTagSuggestion < ApplicationRecord
  STATUSES = %w[pending accepted dismissed].freeze

  belongs_to :category
  belongs_to :tag

  validates :status, inclusion: { in: STATUSES }
  validates :tag_id, uniqueness: { scope: :category_id }

  scope :pending,   -> { where(status: "pending") }
  scope :accepted,  -> { where(status: "accepted") }
  scope :dismissed, -> { where(status: "dismissed") }
end
