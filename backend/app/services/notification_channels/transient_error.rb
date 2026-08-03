module NotificationChannels
  # Falha de rede ao falar com o canal (timeout de conexão/leitura, conexão
  # derrubada, DNS). Transitório e sem resposta da API: não dá pra saber se a
  # mensagem chegou, mas o custo de não re-tentar é o gasto nunca aparecer no
  # Telegram. Quem re-tenta precisa ser idempotente — ver TelegramInboxButtons,
  # que carimba `telegram_notified_at` a cada envio.
  class TransientError < Error; end
end
