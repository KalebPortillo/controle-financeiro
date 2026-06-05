require "test_helper"

class Imports::CsvParserTest < ActiveSupport::TestCase
  def parse(content)
    Imports::CsvParser.call(content: content)
  end

  test "parses a comma-delimited CSV with BR date and dot decimal" do
    csv = <<~CSV
      data,descrição,valor
      05/01/2026,MERCADO EXTRA,-123.45
      06/01/2026,SALARIO,2500.00
    CSV
    result = parse(csv)
    assert_empty result[:errors]
    assert_equal 2, result[:rows].size
    first = result[:rows].first
    assert_equal Date.new(2026, 1, 5), first[:date]
    assert_equal "MERCADO EXTRA", first[:description]
    assert_equal(-12_345, first[:amount_cents])
    assert_equal 250_000, result[:rows].last[:amount_cents]
  end

  # Extratos BR com vírgula decimal vêm com delimitador ; (o comum no Brasil).
  test "detects semicolon delimiter with BR decimal comma" do
    csv = "Data;Histórico;Valor\n10/02/2026;PADARIA;-9,90\n06/01/2026;SALARIO;2.500,00\n"
    result = parse(csv)
    assert_empty result[:errors]
    assert_equal "PADARIA", result[:rows].first[:description]
    assert_equal(-990, result[:rows].first[:amount_cents])
    assert_equal 250_000, result[:rows].last[:amount_cents]
  end

  test "detects tab delimiter and ISO dates with dot decimal" do
    csv = "date\tdescription\tamount\n2026-03-01\tUBER\t-25.50\n"
    result = parse(csv)
    assert_empty result[:errors]
    assert_equal Date.new(2026, 3, 1), result[:rows].first[:date]
    assert_equal(-2_550, result[:rows].first[:amount_cents])
  end

  test "positive value is a credit, negative is a debit (sign preserved)" do
    csv = "data,descricao,valor\n01/01/2026,A,-100.00\n02/01/2026,B,100.00\n"
    rows = parse(csv)[:rows]
    assert_equal(-10_000, rows[0][:amount_cents])
    assert_equal 10_000, rows[1][:amount_cents]
  end

  test "malformed row is reported, not fatal" do
    csv = "data,descricao,valor\n01/01/2026,OK,-10.00\nzzz,BAD,abc\n"
    result = parse(csv)
    assert_equal 1, result[:rows].size
    assert_equal 1, result[:errors].size
    assert_equal 3, result[:errors].first[:row] # 1-based incl. header
  end

  test "missing required column raises a header error" do
    csv = "foo,bar\n1,2\n"
    result = parse(csv)
    assert_empty result[:rows]
    assert_equal 1, result[:errors].size
    assert_match(/coluna/i, result[:errors].first[:message])
  end

  test "blank lines are skipped" do
    csv = "data,descricao,valor\n01/01/2026,A,-10.00\n\n02/01/2026,B,-20.00\n"
    assert_equal 2, parse(csv)[:rows].size
  end
end
