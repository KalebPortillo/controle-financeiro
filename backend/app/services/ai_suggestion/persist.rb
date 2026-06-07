module AiSuggestion
  # Grava o resultado de uma sugestão (de Service ou BatchService) numa transação:
  # improved_title, ai_confidence, snapshot ai_suggestion e as tags resolvidas.
  # Compartilhado entre SuggestJob (1 tx) e BatchSuggestJob (lote) pra ter um
  # único caminho de persistência.
  module Persist
    module_function

    # tx: Transaction pending; result: hash no formato de AiSuggestion::Service.call.
    # Sucesso → ai_status "analyzed" (a IA rodou, com ou sem sugestão útil).
    # Fallback (bug inesperado) → ai_status "failed" (não fica preso em "queued").
    # Retorna true se persistiu sugestão.
    def call(tx, result)
      return mark_failed([ tx.id ]) && false if result[:source] == "fallback"

      ActiveRecord::Base.transaction do
        applied_tags = resolve_tags(tx, result)

        updates = { ai_status: "analyzed" }
        updates[:improved_title] = result[:improved_title] if result[:improved_title].present?
        updates[:ai_confidence]  = confidence_to_decimal(result[:confidence]) if result[:confidence]

        # Snapshot persistente do que a IA sugeriu — base do histórico no UI e
        # sinal de "transação já analisada" (progresso real).
        updates[:ai_suggestion] = {
          "title"        => result[:improved_title],
          "tag_ids"      => applied_tags.map(&:id),
          "tag_names"    => applied_tags.map(&:name),
          "new_tags"     => result[:suggested_new_tags] || [],
          "confidence"   => result[:confidence],
          "source"       => result[:source],
          "suggested_at" => Time.current.iso8601
        }

        tx.update_columns(updates)
        tx.tags = applied_tags if applied_tags.any?
      end
      true
    end

    # Marca como "failed" (IA não conseguiu) só as que ainda estão aguardando —
    # nunca rebaixa uma já analyzed. Usado quando um lote desiste (give-up) ou
    # bate erro permanente (quota/daily). Retorna true (pra encadear no call).
    def mark_failed(transaction_ids)
      Transaction.where(id: transaction_ids, status: "pending", ai_status: "queued")
                 .update_all(ai_status: "failed")
      true
    end

    def resolve_tags(tx, result)
      if result[:suggested_tag_ids].present?
        # Modo normal: tags existentes sugeridas pela IA
        tx.workspace.tags.where(id: result[:suggested_tag_ids]).to_a
      elsif result[:new_tag_suggestion].present?
        # Modo normal: nenhuma tag existente encaixou, IA sugere criar uma nova
        [ tx.workspace.tags.find_or_create_by!(name: result[:new_tag_suggestion].strip.truncate(50)) ]
      elsif result[:suggested_new_tags].present? && tx.tags.empty?
        # Modo onboarding: IA sugere múltiplas tags novas
        result[:suggested_new_tags].map do |name|
          tx.workspace.tags.find_or_create_by!(name: name.strip.truncate(50))
        end
      else
        []
      end
    end

    def confidence_to_decimal(level)
      case level
      when "high"   then 0.9
      when "medium" then 0.6
      when "low"    then 0.3
      end
    end
  end
end
