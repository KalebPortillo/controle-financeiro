module InternalTransfers
  # Wrapper assíncrono (Solid Queue) sobre InternalTransfers::Detect. Disparado
  # ao fim do sync fora do onboarding (RF11.1), junto da detecção de recorrentes.
  class DetectJob < ApplicationJob
    queue_as :default

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return unless workspace

      InternalTransfers::Detect.call(workspace: workspace)
    end
  end
end
