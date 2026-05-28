module BankAggregators
  # Item/conexão com problema do lado do banco (token expirado, MFA
  # pendente, conta desconectada). UI traduz pro usuário "reconectar".
  class ItemError < Error; end
end
