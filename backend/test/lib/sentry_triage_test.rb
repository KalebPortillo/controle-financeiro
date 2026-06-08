require "test_helper"
require Rails.root.join("lib/sentry_triage")

# Lógica pura da triagem do Sentry (normalizar JSON → priorizar → formatar).
# O HTTP fica no bin/sentry-triage; aqui só a transformação, com fixture.
class SentryTriageTest < ActiveSupport::TestCase
  def issue(over = {})
    {
      "shortId" => "BACK-1", "title" => "RuntimeError: boom", "culprit" => "app/x.rb in y",
      "count" => "10", "userCount" => 2, "level" => "error",
      "firstSeen" => "2026-06-01T00:00:00Z", "lastSeen" => "2026-06-07T00:00:00Z",
      "permalink" => "https://sentry.io/i/1"
    }.merge(over)
  end

  test "normalize extracts the relevant fields and casts counts" do
    r = SentryTriage.normalize(issue, project: "backend")
    assert_equal "backend", r[:project]
    assert_equal "BACK-1", r[:short_id]
    assert_equal 10, r[:count]
    assert_equal 2, r[:users]
    assert_equal "error", r[:level]
  end

  test "title falls back to metadata type: value when title is absent" do
    r = SentryTriage.normalize(issue("title" => nil, "metadata" => { "type" => "TypeError", "value" => "x is nil" }), project: "f")
    assert_equal "TypeError: x is nil", r[:title]
  end

  test "prioritize orders by event count desc" do
    rows = [ SentryTriage.normalize(issue("shortId" => "A", "count" => "3"), project: "b"),
             SentryTriage.normalize(issue("shortId" => "B", "count" => "50"), project: "b") ]
    assert_equal %w[B A], SentryTriage.prioritize(rows).map { |r| r[:short_id] }
  end

  test "new_since? flags issues first seen after the cutoff" do
    recent = SentryTriage.normalize(issue("firstSeen" => "2026-06-07T10:00:00Z"), project: "b")
    old    = SentryTriage.normalize(issue("firstSeen" => "2026-05-01T00:00:00Z"), project: "b")
    cutoff = "2026-06-07T00:00:00Z"
    assert SentryTriage.new_since?(recent, cutoff)
    refute SentryTriage.new_since?(old, cutoff)
    refute SentryTriage.new_since?(recent, nil)
  end

  test "format produces a readable digest and marks NOVO" do
    rows = [ SentryTriage.normalize(issue("shortId" => "BACK-9", "firstSeen" => "2026-06-07T10:00:00Z"), project: "backend") ]
    out = SentryTriage.format(rows, since: "2026-06-07T00:00:00Z")
    assert_match(/BACK-9/, out)
    assert_match(/NOVO/, out)
    assert_match(%r{app/x\.rb}, out)
  end

  test "format handles the empty case" do
    assert_match(/Nenhuma issue/, SentryTriage.format([]))
  end
end
