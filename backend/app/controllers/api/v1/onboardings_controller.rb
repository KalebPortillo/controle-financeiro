module Api
  module V1
    # Onboarding (RF22) — fluxo guiado de 3 passos pro dono de um workspace
    # recém-criado. Estado vive em workspace.onboarding_state jsonb.
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
      def advance
        Onboarding::Service.advance(current_workspace, to: params[:to])
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
          status:                 state["status"],
          current_step:           current_step_for(state["status"]),
          started_at:             state["started_at"],
          completed_at:           state["completed_at"],
          suggested_tags:         state["suggested_tags"] || [],
          suggested_categories:   state["suggested_categories"] || [],
          accepted_tag_ids:       state["accepted_tag_ids"] || [],
          accepted_category_ids:  state["accepted_category_ids"] || []
        }
      end

      def current_step_for(status)
        case status
        when "not_started", nil           then 0
        when "connecting", "analyzing"    then 1
        when "tagging"                    then 2
        when "categorizing"               then 3
        else                                   nil
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
