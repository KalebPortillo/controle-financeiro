namespace :pluggy do
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
