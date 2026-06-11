namespace :telegram do
  desc "Registra o webhook do bot no Telegram (rodar uma vez por ambiente, pós-deploy)"
  task set_webhook: :environment do
    webhook_url = "https://#{ENV.fetch('APP_HOST')}/api/v1/webhooks/telegram"
    NotificationChannels::Telegram.new.set_webhook(
      url:          webhook_url,
      secret_token: ENV.fetch("TELEGRAM_WEBHOOK_SECRET")
    )
    puts "Webhook registrado: #{webhook_url}"
  end

  desc "Smoke: envia mensagem de teste pros grupos vinculados (verifica fiação bot↔grupo)"
  task smoke: :environment do
    linked = Workspace.where.not(telegram_chat_id: nil)
    if linked.none?
      puts "Nenhum workspace vinculado ao Telegram. Vincule pelo app (/mais → Conectar Telegram)."
      next
    end

    channel = NotificationChannels::Telegram.new
    linked.find_each do |ws|
      channel.send_message(
        chat_id: ws.telegram_chat_id,
        text:    "Teste de integração do controle financeiro. Se vocês receberam " \
                 "esta mensagem, o bot está vinculado ao grupo corretamente."
      )
      puts "Enviado pro grupo de '#{ws.name}' (chat #{ws.telegram_chat_id})."
    end
  end

  desc "Smoke real: emite uma notificação sync_failed de teste (in-app + Telegram) no workspace vinculado"
  task smoke_notification: :environment do
    ws = Workspace.where.not(telegram_chat_id: nil).first
    if ws.nil?
      puts "Nenhum workspace vinculado ao Telegram."
      next
    end

    Notifications::Create.call(
      workspace: ws,
      kind:      "sync_failed",
      dedup_key: "sync_failed:smoke:#{Time.current.to_i}",
      payload:   {
        "bank_connection_id" => nil,
        "institution_label"  => "Banco de Teste",
        "error_message"      => "Smoke test — ignore. Disparado manualmente pra validar a entrega."
      }
    )
    puts "Notificação sync_failed (smoke) emitida no workspace '#{ws.name}'. " \
         "Confira o sininho no app E a mensagem no grupo."
  end
end
