class AddAiLastErrorToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Último erro não-recuperável de IA (camada de feedback). { reason, message,
    # detail, at }. nil = sem erro pendente. Limpo no próximo sucesso de IA.
    add_column :workspaces, :ai_last_error, :jsonb
  end
end
