module Api
  module V1
    # Onboarding (RF22) — fluxo guiado de 4 passos pro dono de um workspace
    # recém-criado. O estado de FLUXO vive em workspace.onboarding_state jsonb;
    # as SUGESTÕES de tags/categorias vivem nos catálogos suggested_tags/
    # suggested_categories (não mais no jsonb). Tags e categorias reais são
    # criadas incrementalmente via os endpoints /tags, /categories e /suggested_*.
    class OnboardingsController < ApplicationController
      before_action :require_authentication!
      before_action :require_workspace_owner!

      # GET /api/v1/onboarding
      def show
        render json: serialize(current_workspace)
      end

      # POST /api/v1/onboarding/start
      def start
        Onboarding::Service.start(current_workspace)
        render json: serialize(current_workspace)
      rescue Onboarding::Service::InvalidTransition => e
        render_invalid_transition(e)
      end

      # POST /api/v1/onboarding/skip
      def skip
        Onboarding::Service.skip(current_workspace)
        render json: serialize(current_workspace)
      rescue Onboarding::Service::InvalidTransition => e
        render_invalid_transition(e)
      end

      # POST /api/v1/onboarding/advance { to?: "..." }
      # Dispara a IA conforme o passo em que entra:
      # - "analyzing" → 1ª análise (tags) via AnalyzeJob (F2, user-triggered)
      # - "completed" → reanalisa a inbox c/ tags já criadas (RF22.6)
      # (Categorias saíram do onboarding — sugestão é on-demand na tela de Categorias.)
      def advance
        Onboarding::Service.advance(current_workspace, to: params[:to])
        case current_workspace.onboarding_state["status"]
        when "analyzing"
          current_workspace.clear_ai_error! # nova análise → limpa erro anterior
          Onboarding::AnalyzeJob.perform_later(current_workspace.id)
        when "completed"
          AiSuggestion::ReanalyzeJob.perform_later(current_workspace.id)
        end
        render json: serialize(current_workspace)
      rescue Onboarding::Service::InvalidTransition => e
        render_invalid_transition(e)
      end

      private

      # Só o dono do workspace passa pelo fluxo (RF22.2). Membros convidados
      # veem o app direto.
      def require_workspace_owner!
        return if current_workspace.created_by_user_id == current_user.id

        render json: {
          error: { code: "forbidden", message: "Onboarding is only available for the workspace owner." }
        }, status: :forbidden
      end

      def serialize(workspace)
        state = workspace.onboarding_state || {}
        {
          status:         state["status"],
          current_step:   current_step_for(state["status"]),
          started_at:     state["started_at"],
          completed_at:   state["completed_at"],
          analysis_error: workspace.ai_error_payload # {reason, message, at} | null
        }
      end

      def current_step_for(status)
        case status
        when "not_started", nil then 0
        when "connecting"       then 1
        when "analyzing"        then 2
        when "tagging"          then 3
        else                         nil
        end
      end

      def render_invalid_transition(err)
        render json: {
          error: { code: "invalid_onboarding_transition", message: err.message }
        }, status: :unprocessable_entity
      end
    end
  end
end
