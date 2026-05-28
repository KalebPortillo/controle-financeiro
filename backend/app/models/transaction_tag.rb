# Junção M:N entre Transaction e Tag (RF5.2). A associação se chama `txn`
# porque `transaction` colide com um método interno do ActiveRecord.
class TransactionTag < ApplicationRecord
  belongs_to :txn, class_name: "Transaction", foreign_key: :transaction_id
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :transaction_id }
end
