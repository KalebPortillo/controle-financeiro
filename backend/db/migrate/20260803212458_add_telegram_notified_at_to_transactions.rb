class AddTelegramNotifiedAtToTransactions < ActiveRecord::Migration[8.1]
  # Quando o gasto já recebeu mensagem com botões no Telegram. Serve de
  # checkpoint: o envio é 1 request por gasto e um timeout no meio do lote
  # abortava o resto sem retry. Com o carimbo, a re-execução manda só o que
  # faltou, em vez de duplicar o que já chegou.
  #
  # Transações antigas ficam NULL. Só o fluxo do sync (TelegramInboxButtons.call)
  # filtra por essa coluna, e ele só olha os ids do lote recém-sincronizado —
  # então nada retroativo é reenviado.
  def change
    add_column :transactions, :telegram_notified_at, :datetime
  end
end
