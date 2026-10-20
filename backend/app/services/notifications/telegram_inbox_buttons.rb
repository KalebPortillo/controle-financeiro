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
  #
  # A unidade é o ITEM, como no inbox do app (`buildInboxItems`): parcelas da
  # mesma compra (installment_group_id) viram uma mensagem só, com botões que
  # agem no conjunto (grp:*). PAGE_SIZE, overflow e paginação contam itens.
  module TelegramInboxButtons
    module_function

    PAGE_SIZE = 7

    # Gasto avulso (`parcels` vazio) ou compra parcelada (todas as parcelas
    # PENDENTES do grupo no workspace, ordenadas por número).
    Item = Struct.new(:tx, :parcels, keyword_init: true) do
      def group? = parcels.any?
      def members = group? ? parcels : [ tx ]
      def notified? = members.all?(&:telegram_notified_at)

      # Data pra ordenar: a da compra (âncora retro-calculada) no grupo — igual
      # ao inbox, o grupo não "flutua" pra data da última parcela.
      def sort_date
        return tx.occurred_at unless group?

        first = parcels.first
        anchor = Transactions::Installment.purchase_anchor(number: first.installment_number, occurred: first.occurred_at)
        anchor ? Date.parse(anchor) : first.occurred_at
      end
    end

    def call(workspace:, transaction_ids:, channel: NotificationChannels::Telegram.new)
      chat_id = workspace.telegram_chat_id
      return if chat_id.blank?

      items = build_items(workspace, workspace.transactions.where(id: transaction_ids, status: "pending"))
      page  = items.first(PAGE_SIZE)
      return if page.empty?

      # Retomada: a janela mostrada é sempre a mesma (os PAGE_SIZE itens mais
      # recentes), mas só reenvia o que ainda não foi entregue. Numa re-execução
      # após timeout, isso manda o resto do lote sem duplicar o que já chegou.
      # Se o `page` inteiro já foi entregue, ainda cai no rodapé — é o caso de a
      # falha ter sido justamente nele.
      send_buttons(channel, chat_id, page.reject(&:notified?))

      # Botão "Ver mais 7" também aqui (não só no /pendentes): pagina TODOS os
      # pendentes a partir dos já mostrados — dá pra limpar o inbox pelo Telegram.
      shown         = page.size
      total_pending = build_items(workspace, workspace.transactions.where(status: "pending")).size
      overflow      = items.size - shown # novos além dos exibidos

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

      items = build_items(workspace, workspace.transactions.where(status: "pending"))
      total = items.size
      page  = items.drop(offset).first(PAGE_SIZE)

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

    # Itens (avulsos + compras parceladas), mais recentes primeiro — a janela dos
    # PAGE_SIZE "últimos". Um grupo traz TODAS as parcelas pendentes da compra no
    # workspace, mesmo as que não estão em `scope` (a mensagem fala do conjunto).
    def build_items(workspace, scope)
      txs = scope.includes(:account, :tags).order(occurred_at: :desc, created_at: :desc).to_a
      group_ids = txs.filter_map(&:installment_group_id).uniq
      parcels = workspace.transactions.where(status: "pending", installment_group_id: group_ids)
                         .includes(:account, :tags).order(:installment_number).group_by(&:installment_group_id)

      seen = {}
      items = txs.filter_map do |tx|
        gid = tx.installment_group_id
        next Item.new(tx: tx, parcels: []) if gid.nil?
        next if seen[gid]

        seen[gid] = true
        Item.new(tx: tx, parcels: parcels.fetch(gid, [ tx ]))
      end
      # sort_by estável (índice desempata) mantém a ordem do banco entre iguais.
      items.each_with_index.sort_by { |item, i| [ -item.sort_date.jd, i ] }.map(&:first)
    end

    # Carimba DEPOIS de cada envio, um a um: se a rede cair no meio do lote, o
    # que já chegou fica marcado e só o resto volta no retry.
    #
    # `update_column` de propósito: é metadado de entrega, não edição do gasto.
    # Não mexe em updated_at nem no lock_version — senão um envio concorrente ao
    # toque do botão faria o HandleTelegramCallback perder a corrida do
    # optimistic lock e virar "já processada" sem ter sido.
    def send_buttons(channel, chat_id, items)
      items.each do |item|
        if item.group?
          channel.send_message(chat_id: chat_id, text: group_text_for(item.parcels),
                               reply_markup: group_keyboard_for(item.parcels))
        else
          channel.send_message(chat_id: chat_id, text: text_for(item.tx), reply_markup: keyboard_for(item.tx))
        end
        now = Time.current
        item.members.each { |tx| tx.update_column(:telegram_notified_at, now) }
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

    # Compra parcelada: total pendente, cartão + data da COMPRA, quantas parcelas
    # estão no inbox (e o valor de cada, quando iguais) e as tags.
    #   Amazon Br — 12x · R$ 555,60
    #   Cartão ••5190 · compra em 08/10
    #   12 parcelas no inbox (R$ 46,30 cada)
    def group_text_for(parcels)
      rep   = representative(parcels)
      title = rep.improved_title.presence || rep.original_description
      total = parcels.sum(&:amount_cents)
      count = parcels.size

      anchor = Transactions::Installment.purchase_anchor(number: rep.installment_number, occurred: rep.occurred_at)
      bought = "compra em #{Date.parse(anchor).strftime('%d/%m')}" if anchor

      in_inbox = "#{count} #{count == 1 ? 'parcela' : 'parcelas'} no inbox"
      amounts  = parcels.map(&:amount_cents).uniq
      in_inbox += " (#{Brl.format(amounts.first)} cada)" if count > 1 && amounts.size == 1

      lines = [ "#{title} — #{rep.installment_total}x · #{Brl.format(total)}", source_line(rep, date: bought), in_inbox ]
      tags = tags_line(rep)
      lines << tags if tags
      lines.join("\n")
    end

    # Mesma escolha do inbox: a parcela com título melhorado, senão a primeira.
    def representative(parcels)
      parcels.find { |p| p.improved_title.present? } || parcels.first
    end

    # Natureza da transação + data. Cartão → "Cartão ••1234". Conta com natureza no
    # extrato ("Transferência enviada|…", "Pagamento efetuado|…", "Aplicação RDB|…")
    # → "Transferência enviada · Conta". Senão → só o nome da conta.
    def source_line(tx, date: nil)
      date ||= tx.occurred_at.strftime("%d/%m")
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

    # "Consolidar 12x" / "Rejeitar 12x" — agem em todas as pendentes da compra.
    # Uma parcela só: sem contagem. grp:<ação>:<uuid> = 52 bytes (< 64).
    def group_keyboard_for(parcels)
      gid    = parcels.first.installment_group_id
      suffix = parcels.size > 1 ? " #{parcels.size}x" : ""
      {
        inline_keyboard: [
          [
            { text: "Consolidar#{suffix}", callback_data: "grp:consolidate:#{gid}" },
            { text: "Rejeitar#{suffix}",   callback_data: "grp:reject:#{gid}" }
          ]
        ]
      }
    end

    def inbox_url
      "https://#{ENV.fetch('APP_HOST')}/inbox"
    end
  end
end
