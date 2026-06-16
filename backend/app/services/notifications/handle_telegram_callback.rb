module Notifications
  # Processa o toque num botão inline (callback_query) do Telegram (RF17):
  # consolida/rejeita a transação e responde o usuário no grupo.
  #
  # Autorização em DUAS camadas: o secret do webhook já foi validado no
  # controller; aqui o chat de origem precisa ser o grupo VINCULADO ao
  # workspace, e a transação é buscada escopada nele — toque de outro chat ou
  # contra tx de outro workspace não tem efeito.
  module HandleTelegramCallback
    module_function

    CALLBACK = /\Atx:(consolidate|reject):(.+)\z/
    MORE     = /\Ainbox:more:(\d+)\z/

    def call(callback_query:, channel: NotificationChannels::Telegram.new)
      cq_id      = callback_query[:id]
      data       = callback_query[:data].to_s
      message    = callback_query[:message] || {}
      chat_id    = message.dig(:chat, :id)
      message_id = message[:message_id]
      orig_text  = message[:text].to_s

      workspace = Workspace.find_by(telegram_chat_id: chat_id)
      return answer(channel, cq_id, "Grupo não vinculado") if workspace.nil?

      # "Ver mais" — pagina os pendentes num job (pode mandar várias mensagens).
      if (more = MORE.match(data))
        answer(channel, cq_id)
        return TelegramPendingDigestJob.perform_later(workspace.id, more[1].to_i)
      end

      match = CALLBACK.match(data)
      return answer(channel, cq_id, "Ação inválida") unless match

      action = match[1]
      tx     = workspace.transactions.find_by(id: match[2])
      return answer(channel, cq_id, "Transação não encontrada") if tx.nil?

      result = apply(tx, action)
      answer(channel, cq_id, toast_for(result))
      edit_done(channel, chat_id, message_id, orig_text, result) if message_id && result != :already_done
    end

    # Só age se ainda está pendente; toque duplo (ou ação pela tela do app no
    # meio) vira no-op idempotente.
    def apply(tx, action)
      return :already_done unless tx.pending?

      case action
      when "consolidate"
        tx.update!(status: "consolidated", consolidated_at: Time.current)
        :consolidated
      when "reject"
        tx.update!(status: "rejected", rejected_at: Time.current)
        :rejected
      end
    end

    def toast_for(result)
      case result
      when :consolidated then "Consolidado"
      when :rejected     then "Rejeitado"
      else                    "Já processada"
      end
    end

    def answer(channel, cq_id, text = nil)
      channel.answer_callback_query(callback_query_id: cq_id, text: text)
    end

    # Reescreve a mensagem com o desfecho e sem os botões (editMessageText sem
    # reply_markup remove o teclado).
    def edit_done(channel, chat_id, message_id, orig_text, result)
      label = result == :consolidated ? "Consolidado" : "Rejeitado"
      channel.edit_message_text(chat_id: chat_id, message_id: message_id,
                                text: "#{orig_text}\n— #{label}")
    end
  end
end
