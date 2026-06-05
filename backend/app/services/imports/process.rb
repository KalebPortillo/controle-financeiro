require "digest"

module Imports
  # RF20 — processa um Import: lê o arquivo anexado, roda o parser do formato e
  # cria cada linha como transação pending na inbox (mesmo pipeline da sync,
  # RF20.2). Dedup determinístico por (conta, data, valor, descritor) via id
  # sintético em source_metadata['id'] — reaproveita o índice unique de
  # external_transaction_id. Grava contadores + error_log no Import.
  class Process
    PARSERS = { "csv" => Imports::CsvParser }.freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(import:)
      @import    = import
      @workspace = import.workspace
    end

    def call
      parser = PARSERS[@import.format]
      return @import.fail!("formato não suportado: #{@import.format}") unless parser

      content = @import.file.download
      result  = parser.call(content: content)

      created = 0
      duplicated = 0
      row_errors = result[:errors].dup
      result[:rows].each_with_index do |row, i|
        case import_row(row)
        when :created    then created += 1
        when :duplicated then duplicated += 1
        when :errored    then row_errors << { row: i + 2, message: "linha inválida" }
        end
      end

      @import.complete!(created: created, duplicate: duplicated, errors: row_errors)
    rescue StandardError => e
      @import.fail!(e.message)
      raise
    end

    private

    def import_row(row)
      tx = Transaction.create!(
        workspace:            @workspace,
        account:             account,
        direction:            row[:amount_cents].negative? ? "debit" : "credit",
        amount_cents:         row[:amount_cents].abs,
        currency:             "BRL",
        occurred_at:          row[:date],
        original_description: row[:description],
        status:               "pending",
        source:               "manual_import",
        source_metadata:      row[:raw].merge("id" => synthetic_id(row))
      )
      AiSuggestion::SuggestJob.perform_later(tx.id)
      :created
    rescue ActiveRecord::RecordNotUnique
      :duplicated
    rescue ActiveRecord::RecordInvalid, ArgumentError
      :errored
    end

    # Conta destino: a do import, ou a conta manual do workspace (RF12).
    def account
      @account ||= @import.account || manual_account
    end

    def manual_account
      @workspace.accounts.find_or_create_by!(institution: "manual", name: "Dinheiro / Externo") do |a|
        a.kind = "checking"
        a.owner_membership = @import.uploaded_by_membership
      end
    end

    # Dedup: mesma compra importada 2x (ou já vinda da sync) colide de propósito.
    def synthetic_id(row)
      key = [ account.id, row[:date], row[:amount_cents], row[:description] ].join("|")
      "import-#{Digest::SHA256.hexdigest(key)[0, 24]}"
    end
  end
end
