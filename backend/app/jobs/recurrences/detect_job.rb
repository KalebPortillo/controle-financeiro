module Recurrences
  # Wrapper assíncrono (Solid Queue) sobre Recurrences::Detect. Disparado ao
  # fim do sync fora do onboarding (RF9.1).
  class DetectJob < ApplicationJob
    queue_as :default

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return unless workspace

      Recurrences::Detect.call(workspace: workspace)
    end
  end
end
