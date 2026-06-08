require "time"

# Lógica pura (sem Rails, sem rede) de triagem do Sentry: normaliza o JSON de
# issues da API, prioriza e formata um digest legível. O HTTP fica no
# `bin/sentry-triage`; aqui só transformação — pra ser testável com fixture.
module SentryTriage
  module_function

  # Normaliza uma issue crua da API do Sentry num hash enxuto.
  def normalize(issue, project:)
    meta = issue["metadata"] || {}
    {
      project:    project,
      short_id:   issue["shortId"],
      title:      (issue["title"] || [ meta["type"], meta["value"] ].compact.join(": ")).to_s.strip,
      culprit:    issue["culprit"].to_s,
      count:      issue["count"].to_i,
      users:      issue["userCount"].to_i,
      level:      issue["level"].to_s,
      first_seen: issue["firstSeen"],
      last_seen:  issue["lastSeen"],
      permalink:  issue["permalink"]
    }
  end

  def normalize_all(issues, project:)
    Array(issues).map { |i| normalize(i, project: project) }
  end

  # Mais eventos primeiro; empate desempata por visto mais recente.
  def prioritize(rows)
    rows.sort_by { |r| [ -r[:count], -(Time.parse(r[:last_seen].to_s).to_i rescue 0) ] }
  end

  # `since` (Time/ISO) marca como NOVO as issues vistas pela 1ª vez depois dele
  # (ex.: novas desde o último deploy).
  def new_since?(row, since)
    return false unless since && row[:first_seen]

    Time.parse(row[:first_seen].to_s) >= (since.is_a?(Time) ? since : Time.parse(since.to_s))
  rescue ArgumentError
    false
  end

  # Digest legível (texto) das issues já priorizadas.
  def format(rows, since: nil)
    return "Nenhuma issue não-resolvida. 🎉" if rows.empty?

    lines = [ "#{rows.size} issue(s) não-resolvida(s), por frequência:\n" ]
    prioritize(rows).each_with_index do |r, i|
      novo = new_since?(r, since) ? " · NOVO" : ""
      lines << "#{i + 1}. [#{r[:project]}] #{r[:short_id]} · #{r[:count]} ev · " \
               "#{r[:users]} usr · #{r[:level]}#{novo}"
      lines << "   #{r[:title]}"
      lines << "   culprit: #{r[:culprit]}" unless r[:culprit].empty?
      lines << "   visto: #{r[:first_seen]} → #{r[:last_seen]}"
      lines << "   #{r[:permalink]}" if r[:permalink]
      lines << ""
    end
    lines.join("\n")
  end
end
