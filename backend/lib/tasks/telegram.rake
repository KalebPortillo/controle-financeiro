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
end
