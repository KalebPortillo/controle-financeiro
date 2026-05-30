module Onboarding
  # Orquestra as transições do estado de onboarding (RF22).
  # Estado vive no campo jsonb `workspace.onboarding_state`.
  module Service
    InvalidTransition = Class.new(StandardError)

    # Ordem dos passos. nil = não aplicável (estados terminais ou iniciais).
    STEPS = {
      "not_started"   => "connecting",
      "connecting"    => "analyzing",
      "analyzing"     => "tagging",
      "tagging"       => "categorizing",
      "categorizing"  => "completed"
    }.freeze

    TERMINAL = %w[completed skipped].freeze

    module_function

    def start(workspace)
      state = workspace.onboarding_state || {}
      status = state["status"]
      return if status == "connecting"
      raise InvalidTransition, "cannot start from #{status}" if TERMINAL.include?(status)

      update_state(workspace, state.merge(
        "status"     => "connecting",
        "started_at" => Time.current.iso8601
      ))
    end

    def skip(workspace)
      state = workspace.onboarding_state || {}
      status = state["status"]
      return if status == "skipped"
      raise InvalidTransition, "cannot skip from #{status}" if status == "completed"

      update_state(workspace, state.merge("status" => "skipped"))
    end

    # Avança para o próximo step do fluxo. Se `to:` for fornecido, força
    # destino válido (deve estar em STEPS ou ser "completed").
    def advance(workspace, to: nil)
      state = workspace.onboarding_state || {}
      status = state["status"]
      return if status == "completed"

      destination = to || STEPS[status]
      raise InvalidTransition, "no next step from #{status}" if destination.nil?
      unless valid_destination?(destination)
        raise InvalidTransition, "invalid destination #{destination}"
      end

      new_state = state.merge("status" => destination)
      new_state["completed_at"] = Time.current.iso8601 if destination == "completed"
      update_state(workspace, new_state)
    end

    def valid_destination?(dest)
      STEPS.values.include?(dest) || dest == "completed"
    end

    def update_state(workspace, new_state)
      workspace.update!(onboarding_state: new_state)
    end
  end
end
