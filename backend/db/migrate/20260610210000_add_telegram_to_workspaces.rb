class AddTelegramToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Vínculo Telegram do workspace (RF17, canal externo): 1 grupo do casal por
    # workspace. chat_id é bigint — IDs de grupo no Telegram são negativos e
    # estouram int4. link_code é o código de uso único do deep-link
    # t.me/<bot>?startgroup=<code>, com expiração curta.
    change_table :workspaces, bulk: true do |t|
      t.bigint   :telegram_chat_id
      t.string   :telegram_chat_title
      t.datetime :telegram_linked_at
      t.string   :telegram_link_code
      t.datetime :telegram_link_code_expires_at
    end

    add_index :workspaces, :telegram_link_code, unique: true,
              where: "telegram_link_code IS NOT NULL"
  end
end
