module NotificationChannels
  # 4xx do canal: pedido rejeitado de forma permanente (chat não existe, bot
  # removido do grupo, payload inválido). Não adianta re-tentar.
  class ApiError < Error; end
end
