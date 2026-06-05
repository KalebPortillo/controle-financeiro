require "csv"

module Imports
  # RF20 — parser CSV por heurística: detecta o delimitador e identifica as
  # colunas data/descrição/valor pelo cabeçalho (+ formato do conteúdo). Cobre os
  # extratos comuns (Nubank, Inter, Itaú) sem o usuário configurar nada.
  #
  # Retorna { rows: [{ date:, description:, amount_cents:, raw: }], errors:
  # [{ row:, message: }] }. Linha inválida vira erro, não aborta o lote.
  # Implementa a mesma interface que Imports::OfxParser usará (call/content:).
  class CsvParser
    DELIMITERS = [ ",", ";", "\t" ].freeze
    DATE_HEADERS   = /\b(data|date|dt)\b/i
    DESC_HEADERS   = /(desc|histó?rico|history|lan[çc]amento|title|t[íi]tulo|memo)/i
    AMOUNT_HEADERS = /(valor|amount|value|montante|quantia)/i

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(content:)
      @content = content.to_s
    end

    def call
      delimiter = detect_delimiter
      table = CSV.parse(@content, col_sep: delimiter, skip_blanks: true)
      return header_error("arquivo vazio") if table.empty?

      header = table.shift.map { |h| h.to_s.strip }
      cols = locate_columns(header)
      missing = %i[date description amount].select { |k| cols[k].nil? }
      return header_error("coluna #{missing.join(', ')} não encontrada") if missing.any?

      rows = []
      errors = []
      table.each_with_index do |fields, i|
        line = i + 2 # 1-based, +1 do header
        begin
          rows << parse_row(fields, cols)
        rescue StandardError => e
          errors << { row: line, message: e.message }
        end
      end
      { rows: rows, errors: errors }
    rescue CSV::MalformedCSVError => e
      header_error("CSV inválido: #{e.message}")
    end

    private

    def detect_delimiter
      first_line = @content.lines.first.to_s
      DELIMITERS.max_by { |d| first_line.count(d) }
    end

    # Acha o índice de cada coluna pelo cabeçalho.
    def locate_columns(header)
      {
        date:        header.index { |h| h.match?(DATE_HEADERS) },
        description: header.index { |h| h.match?(DESC_HEADERS) },
        amount:      header.index { |h| h.match?(AMOUNT_HEADERS) }
      }
    end

    def parse_row(fields, cols)
      date = parse_date(fields[cols[:date]].to_s.strip)
      desc = fields[cols[:description]].to_s.strip
      amount = parse_amount_cents(fields[cols[:amount]].to_s.strip)
      raise "descrição vazia" if desc.empty?

      { date: date, description: desc, amount_cents: amount,
        raw: { "data" => fields[cols[:date]], "valor" => fields[cols[:amount]], "desc" => desc } }
    end

    def parse_date(str)
      if str =~ %r{\A(\d{2})/(\d{2})/(\d{4})\z}
        Date.new(Regexp.last_match(3).to_i, Regexp.last_match(2).to_i, Regexp.last_match(1).to_i)
      elsif str =~ /\A\d{4}-\d{2}-\d{2}\z/
        Date.iso8601(str)
      else
        raise "data inválida: #{str.inspect}"
      end
    end

    # Aceita "-123,45", "2.500,00" (BR) e "-25.50", "1,234.56" (US). Sinal mantido.
    def parse_amount_cents(str)
      raise "valor vazio" if str.empty?

      normalized = normalize_amount(str)
      raise "valor inválido: #{str.inspect}" unless normalized =~ /\A-?\d+\.\d{2}\z/

      (normalized.to_f * 100).round
    end

    def normalize_amount(str)
      s = str.gsub(/[^\d,.\-]/, "")
      if s.include?(",") && s.include?(".")
        # o separador decimal é o que aparece por último
        s.rindex(",") > s.rindex(".") ? s.delete(".").tr(",", ".") : s.delete(",")
      elsif s.include?(",")
        s.tr(",", ".") # vírgula é decimal (BR)
      else
        s
      end
    end

    def header_error(message)
      { rows: [], errors: [ { row: 1, message: message } ] }
    end
  end
end
