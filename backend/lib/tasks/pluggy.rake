namespace :pluggy do
  # Registra (idempotente) os webhooks do Pluggy apontando pro nosso endpoint.
  # Sem isso o Pluggy nunca empurra eventos e o inbox só atualiza no sync
  # manual/periódico. Rodar uma vez por ambiente e pós-deploy.
  #
  # Uso: source ~/.config/controle-financeiro/secrets.env && \
  #      APP_HOST=wallet-staging.portilho.cc bin/rails pluggy:ensure_webhook
  desc "Registra (idempotente) os webhooks do Pluggy apontando pro endpoint do app"
  task ensure_webhook: :environment do
    host   = ENV.fetch("APP_HOST")
    secret = ENV.fetch("PLUGGY_WEBHOOK_SECRET")
    url    = "https://#{host}/api/v1/webhooks/pluggy"

    created = BankConnections::EnsureWebhook.call(url: url, secret: secret)

    if created.any?
      puts "✓ webhooks Pluggy registrados (#{url}): #{created.join(', ')}"
    else
      puts "✓ webhooks Pluggy já registrados em #{url} — nada a fazer."
    end
  end

  # Força o Pluggy a re-buscar no banco (PATCH /items) as conexões conectadas —
  # útil pra "puxar agora" sem esperar a cadência de auto-update do Pluggy. O
  # resultado (gastos novos) chega depois via webhook → sync → notificação.
  #
  # Uso: bin/rails pluggy:refresh_items
  desc "Dispara uma re-sincronização no Pluggy (PATCH /items) das conexões conectadas"
  task refresh_items: :environment do
    provider = BankAggregators::Pluggy.new(
      client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
      client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
    )

    conns = BankConnection.where(provider: "pluggy", status: "connected")
    conns.find_each do |c|
      result = provider.update_item(item_id: c.external_connection_id)
      puts "item #{c.external_connection_id[0, 8]}… → #{result[:status]}"
    rescue BankAggregators::Error => e
      puts "item #{c.external_connection_id[0, 8]}… ERRO: #{e.message}"
    end
    puts "[pluggy:refresh_items] disparados=#{conns.count}"
  end

  # Cria um item sandbox novo no Pluggy (connector 2 + user-ok/password-ok)
  # e imprime os IDs (item, accounts) pra atualizar a constante
  # `SANDBOX_ITEM_ID` em test/services/bank_aggregators/pluggy_test.rb e
  # re-gravar cassettes (`VCR_RECORD=all bin/rails test test/services/bank_aggregators/pluggy_test.rb`).
  #
  # Usado quando o item caduca (30 dias sem update no Pluggy sandbox).
  #
  # Uso: source ~/.config/controle-financeiro/secrets.env && bin/rails pluggy:bootstrap_sandbox
  desc "Cria um item sandbox no Pluggy e imprime IDs pra atualizar fixtures"
  task bootstrap_sandbox: :environment do
    raise "PLUGGY_CLIENT_ID/SECRET ausentes no env" if ENV["PLUGGY_CLIENT_ID"].blank?

    provider = BankAggregators::Pluggy.new(
      client_id:     ENV["PLUGGY_CLIENT_ID"],
      client_secret: ENV["PLUGGY_CLIENT_SECRET"]
    )

    require "net/http"
    require "json"
    uri = URI("https://api.pluggy.ai/items")
    req = Net::HTTP::Post.new(uri)
    req["X-API-KEY"]    = provider.api_key
    req["Content-Type"] = "application/json"
    req.body = {
      connectorId: BankAggregators::Pluggy::CONNECTORS[:sandbox_basic],
      parameters:  { user: "user-ok", password: "password-ok" }
    }.to_json

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
    payload = JSON.parse(res.body)
    raise "Pluggy /items HTTP #{res.code}: #{res.body}" unless res.code.start_with?("2")

    item_id = payload.fetch("id")
    puts "✓ item criado: #{item_id} (status #{payload['status']})"
    puts "  aguardando sync…"

    # Polling até status UPDATED ou timeout
    Timeout.timeout(60) do
      loop do
        status = JSON.parse(Net::HTTP.get(
          URI("https://api.pluggy.ai/items/#{item_id}"),
          "X-API-KEY" => provider.api_key
        ))["status"]
        break if status == "UPDATED"
        sleep 3
      end
    end

    accounts = provider.list_accounts(item_id: item_id)
    puts
    puts "Atualize em test/services/bank_aggregators/pluggy_test.rb:"
    puts "  SANDBOX_ITEM_ID         = #{item_id.inspect}.freeze"
    bank = accounts.find { |a| a[:type] == "BANK" }
    puts "  SANDBOX_BANK_ACCOUNT_ID = #{bank[:id].inspect}.freeze" if bank
    puts
    puts "E re-grave cassettes:"
    puts "  rm -rf test/vcr_cassettes/bank_aggregators/pluggy/"
    puts "  VCR_RECORD=once bin/rails test test/services/bank_aggregators/pluggy_test.rb"
  end
end
