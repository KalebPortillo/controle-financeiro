module Recurrences
  # Normalização de descritor de transação para casamento de recorrentes (RF9).
  # "NETFLIX.COM 4821" → "NETFLIX COM": tira dígitos e pontuação, normaliza
  # caixa e espaços — agrupa o mesmo estabelecimento apesar do ruído da fatura.
  # Compartilhado entre a detecção (RF9.1) e o casamento de "missed" (RF9.6).
  module Descriptor
    module_function

    def normalize(desc)
      desc.to_s.upcase.gsub(/\d+/, " ").gsub(/[^[:alpha:] ]/, " ").squish
    end
  end
end
