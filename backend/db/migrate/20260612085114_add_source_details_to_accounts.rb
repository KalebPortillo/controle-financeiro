class AddSourceDetailsToAccounts < ActiveRecord::Migration[8.1]
  # Detalhes da fonte do gasto vindos do Pluggy (RF2.7): nome real do banco
  # (conector — fim do "Manual" pra bancos fora do enum), bandeira e os 4 últimos
  # dígitos do cartão. Capturados no connect (BankConnections::Create).
  def change
    add_column :accounts, :institution_name, :string  # ex.: "Nubank", "Banco Inter"
    add_column :accounts, :card_brand,       :string  # ex.: "Mastercard"
    add_column :accounts, :last_digits,      :string  # ex.: "9437" (só cartão)
  end
end
