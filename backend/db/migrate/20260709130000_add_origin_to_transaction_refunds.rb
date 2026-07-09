class AddOriginToTransactionRefunds < ActiveRecord::Migration[8.0]
  def change
    # RF10.6 — estornos vinculados automaticamente (match de código exato único)
    # não têm confirmação humana; membership vira opcional e `origin` distingue.
    add_column :transaction_refunds, :origin, :string, null: false, default: "manual"
    change_column_null :transaction_refunds, :confirmed_by_membership_id, true
    add_check_constraint :transaction_refunds, "origin IN ('manual','automatic')",
                         name: "transaction_refunds_origin_check"
  end
end
