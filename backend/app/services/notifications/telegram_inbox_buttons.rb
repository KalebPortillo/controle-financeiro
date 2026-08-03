module Notifications
  # Mensagens com botões inline por transação pendente (RF17) — Consolidar /
  # Rejeitar / Abrir no app. Telegram-only (o sininho in-app já cobre o resumo).
  #
  # Dois fluxos:
  #   - `call`         → disparado pelo Sync com os ids novos: manda as PAGE_SIZE
  #                      mais recentes; se o lote tiver mais, uma mensagem com
  #                      link pro inbox do app pra gerenciar o resto.
  #   - `push_pending` → comando /pendentes (e botão "ver mais"): manda PAGE_SIZE
  #                      pendentes a partir de `offset`; se sobrar, um botão que
  #                      pagina os próximos.
  module TelegramInboxButtons
    module_function

    PAGE_SIZE = 7

    def call(workspace:, transaction_ids:, channel: NotificationChannels::Telegram.new)
      chat_id = workspace.telegram_chat_id
      return if chat_id.blank?

      scope = workspace.transactions.where(id: transaction_ids, status: "pending")
      page  = ordered(scope).limit(PAGE_SIZE).to_a
      return if page.empty?

      # Retomada: a janela mostrada é sempre a mesma (as PAGE_SIZE mais
      # recentes), mas só reenvia o que ainda não foi entregue. Numa re-execução
      # após timeout, isso manda o resto do lote sem duplicar o que já chegou.
      # Se o `page` inteiro já foi entregue, ainda cai no rodapé — é o caso de a
      # falha ter sido justamente nele.
      send_buttons(channel, chat_id, page.reject(&:telegram_notified_at))

      # Botão "Ver mais 7" também aqui (não só no /pendentes): pagina TODOS os
      # pendentes a partir dos já mostrados — dá pra limpar o inbox pelo Telegram.
      shown         = page.size
      total_pending = workspace.transactions.where(status: "pending").count
      overflow      = scope.count - shown # novos além dos exibidos

      text = if overflow.positive?
        "Mais #{overflow} #{overflow == 1 ? 'gasto novo' : 'gastos novos'}"
      else
        "Gerencie no inbox do app"
      end
      more_offset = total_pending > shown ? shown : nil
      send_footer(channel, chat_id, text, more_offset: more_offset)
    end

    def push_pending(workspace:, offset: 0, channel: NotificationChannels::Telegram.new)
      chat_id = workspace.telegram_chat_id
      return if chat_id.blank?

      scope = workspace.transactions.where(status: "pending")
      total = scope.count
      page  = ordered(scope).offset(offset).limit(PAGE_SIZE).to_a

      if page.empty?
        text = offset.zero? ? "Nenhum gasto pendente no inbox" : "Sem mais gastos pendentes"
        return channel.send_message(chat_id: chat_id, text: text)
      end

      send_buttons(channel, chat_id, page)

      shown = offset + page.size
      more  = total > shown ? shown : nil
      text  = more ? "Mostrando #{shown} de #{total} pendentes" : "Esses são todos os pendentes"
      send_footer(channel, chat_id, text, more_offset: more)
    end

    # --- helpers ----------------------------------------------------------

    # Mais recentes primeiro (a janela das PAGE_SIZE "últimas" pendentes).
    def ordered(scope)
      scope.includes(:account, :tags).order(occurred_at: :desc, created_at: :desc)
    end

    # Carimba DEPOIS de cada envio, um a um: se a rede cair no meio do lote, o
    # que já chegou fica marcado e só o resto volta no retry.
    #
    # `update_column` de propósito: é metadado de entrega, não edição do gasto.
    # Não mexe em updated_at nem no lock_version — senão um envio concorrente ao
    # toque do botão faria o HandleTelegramCallback perder a corrida do
    # optimistic lock e virar "já processada" sem ter sido.
    def send_buttons(channel, chat_id, txs)
      txs.each do |tx|
        channel.send_message(chat_id: chat_id, text: text_for(tx), reply_markup: keyboard_for(tx))
        tx.update_column(:telegram_notified_at, Time.current)
      end
    end

    # Rodapé único: opcionalmente "Ver mais 7" (paginação) e SEMPRE "Abrir no
    # app" embaixo — em vez de repetir o link em cada gasto.
    def send_footer(channel, chat_id, text, more_offset: nil)
      rows = []
      rows << [ { text: "Ver mais #{PAGE_SIZE}", callback_data: "inbox:more:#{more_offset}" } ] if more_offset
      rows << [ { text: "Abrir no app", url: inbox_url } ]
      channel.send_message(chat_id: chat_id, text: text, reply_markup: { inline_keyboard: rows })
    end

    # Mensagem por transação com contexto suficiente pra decidir consolidar/rejeitar
    # sem abrir o app (RF17): título + valor, natureza (cartão ••dígitos, ou
    # transferência/pagamento de conta), e as tags (aplicadas ou sugeridas pela IA).
    def text_for(tx)
      title = tx.improved_title.presence || tx.original_description
      lines = [ "#{title} — #{Brl.format(tx.amount_cents)}", source_line(tx) ]
      tags = tags_line(tx)
      lines << tags if tags
      lines.join("\n")
    end

    # Natureza da transação + data. Cartão → "Cartão ••1234". Conta com natureza no
    # extrato ("Transferência enviada|…", "Pagamento efetuado|…", "Aplicação RDB|…")
    # → "Transferência enviada · Conta". Senão → só o nome da conta.
    def source_line(tx)
      date = tx.occurred_at.strftime("%d/%m")
      card = tx.source_metadata&.dig("creditCardMetadata", "cardNumber")
      desc = tx.original_description.to_s

      if tx.account&.kind == "credit_card" && card.present?
        "Cartão ••#{card} · #{date}"
      elsif desc.include?("|")
        nature = desc.split("|").first.strip
        "#{nature} · #{tx.account&.name} · #{date}"
      else
        "#{tx.account&.name} · #{date}"
      end
    end

    # Tags aplicadas; se não houver, as sugeridas pela IA (tag_names + new_tags).
    def tags_line(tx)
      names = tx.tags.map(&:name)
      prefix = "Tags"
      if names.empty?
        names  = suggested_tag_names(tx)
        prefix = "Sugestão"
      end
      return if names.empty?

      "#{prefix}: #{names.first(4).join(', ')}"
    end

    def suggested_tag_names(tx)
      s = tx.ai_suggestion || {}
      (Array(s["tag_names"]) + Array(s["new_tags"])).uniq
    end

    def keyboard_for(tx)
      {
        inline_keyboard: [
          [
            { text: "Consolidar", callback_data: "tx:consolidate:#{tx.id}" },
            { text: "Rejeitar",   callback_data: "tx:reject:#{tx.id}" }
          ]
        ]
      }
    end

    def inbox_url
      "https://#{ENV.fetch('APP_HOST')}/inbox"
    end
  end
end
