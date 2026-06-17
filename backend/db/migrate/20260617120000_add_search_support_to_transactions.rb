class AddSearchSupportToTransactions < ActiveRecord::Migration[8.0]
  # Busca textual (Fase 1): habilita `unaccent` para busca acento-insensível
  # (usada via unaccent() no WHERE de Transaction.search). Índices funcionais
  # sobre unaccent exigem wrapper IMMUTABLE, que o schema.rb não dumpa — ficam
  # para a Fase 2 (junto da migração para structure.sql + tsvector ponderado).
  def up
    enable_extension "unaccent" unless extension_enabled?("unaccent")
  end

  def down
    # Extensão fica habilitada — pode ser usada por outras features / próximas fases.
  end
end
