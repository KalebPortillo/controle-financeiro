module BankAggregators
  # Base de todos os erros levantados pelos providers de agregador bancário.
  # Subclasses específicas vivem em arquivos próprios (convenção Zeitwerk
  # de uma constante por arquivo): authentication_error.rb, upstream_error.rb,
  # item_error.rb.
  class Error < StandardError; end
end
