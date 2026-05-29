# Agregador de tags (RF6). Uma categoria agrupa N tags (e uma tag pode estar em
# N categorias). Usada como dimensão de relatório/orçamento (RF6.3). Única por
# workspace (citext).
class Category < ApplicationRecord
  belongs_to :workspace

  has_many :category_tags, dependent: :destroy
  has_many :tags, through: :category_tags

  validates :name, presence: true,
                   uniqueness: { scope: :workspace_id, case_sensitive: false }
end
