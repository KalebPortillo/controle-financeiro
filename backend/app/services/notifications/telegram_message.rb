module Notifications
  # Renderiza uma Notification como texto PT-BR pro Telegram. Texto puro, sem
  # emoji e sem Markdown (a hard rule de dinheiro monospace é só na UI).
  module TelegramMessage
    module_function

    ERROR_SNIPPET_MAX = 120

    def call(notification)
      payload = notification.payload

      case notification.kind
      when "sync_failed"      then sync_failed(payload)
      when "inbox_new"        then inbox_new(payload)
      when "recurrent_missed" then recurrent_missed(payload)
      else
        "Novo aviso no controle financeiro."
      end
    end

    def sync_failed(payload)
      parts = [ "Falha na sincronização do #{payload['institution_label']}." ]
      if payload["error_message"].present?
        parts << "Motivo: #{payload['error_message'].truncate(ERROR_SNIPPET_MAX)}."
      end
      parts << "Verifique a conexão no app."
      parts.join(" ")
    end

    def inbox_new(payload)
      count = payload.fetch("count", 0).to_i
      gastos = count == 1 ? "1 novo gasto aguardando" : "#{count} novos gastos aguardando"
      "Sincronização concluída: #{gastos} revisão na inbox."
    end

    def recurrent_missed(payload)
      expected = Date.parse(payload.fetch("expected_at")).strftime("%d/%m/%Y")
      days     = payload.fetch("days_overdue", 0).to_i
      atraso   = days == 1 ? "1 dia de atraso" : "#{days} dias de atraso"

      msg = "Recorrente atrasada: #{payload['descriptor_pattern']}. " \
            "Esperada em #{expected}, #{atraso}"
      cents = payload["expected_amount_cents"]
      msg += " (valor previsto #{Brl.format(cents)})" if cents.present?
      "#{msg}."
    end
  end
end
