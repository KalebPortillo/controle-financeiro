# Etiqueta livre aplicável a transações (RF5). Plana — agregação fica nas
# Categorias (RF6, ainda não implementado). Única por workspace (citext).
class Tag < ApplicationRecord
  belongs_to :workspace

  has_many :transaction_tags, dependent: :destroy
  has_many :transactions, through: :transaction_tags, source: :txn

  validates :name, presence: true,
                   uniqueness: { scope: :workspace_id, case_sensitive: false }
end
