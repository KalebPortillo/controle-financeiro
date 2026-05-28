module BankAggregators
  # Credenciais (client_id/secret) inválidas. Fatal — não tem retry possível
  # sem o usuário gerar nova app no provider.
  class AuthenticationError < Error; end
end
