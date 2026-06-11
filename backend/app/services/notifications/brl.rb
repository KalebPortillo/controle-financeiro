module Notifications
  # Formata centavos como dinheiro PT-BR plano: 123456 → "R$ 1.234,56".
  # Texto puro (a hard rule de monospace/tabular-nums é só na UI).
  module Brl
    module_function

    def format(cents)
      reais, centavos = cents.to_i.divmod(100)
      "R$ #{reais.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\\1.')},#{format_cents(centavos)}"
    end

    def format_cents(centavos)
      Kernel.format("%02d", centavos)
    end
  end
end
