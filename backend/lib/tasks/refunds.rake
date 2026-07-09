namespace :refunds do
  # Backfill do auto-vínculo de estornos (RF10.6): varre todos os workspaces e
  # liga cada estorno ao gasto quando há match de código exato único. Idempotente
  # (pula créditos já vinculados). Uso: bin/rails refunds:autolink
  desc "Auto-vincula estornos ao gasto por código exato único (backfill)"
  task autolink: :environment do
    total = 0
    Workspace.find_each do |workspace|
      linked = Refunds::AutoLink.call(workspace: workspace)
      total += linked
      puts "[refunds:autolink] workspace=#{workspace.id} linked=#{linked}" if linked.positive?
    end
    puts "[refunds:autolink] total_linked=#{total}"
  end
end
