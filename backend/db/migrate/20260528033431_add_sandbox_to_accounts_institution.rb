class AddSandboxToAccountsInstitution < ActiveRecord::Migration[8.1]
  # 'sandbox' cobre contas criadas via Pluggy Sandbox connector (dev/test) —
  # não é uma instituição real, mas precisa passar pela CHECK constraint.
  def change
    remove_check_constraint :accounts, name: "accounts_institution_check"
    add_check_constraint :accounts,
                         "institution IN ('nubank', 'inter', 'itau', 'santander', 'bb', 'sandbox', 'manual')",
                         name: "accounts_institution_check"
  end
end
