module Api
  module V1
    # Onboarding (RF22) — fluxo guiado de 3 passos pro dono de um workspace
    # recém-criado. Estado vive em workspace.onboarding_state jsonb.
    class OnboardingsController < ApplicationController
      before_action :require_authentication!
      before_action :require_workspace_owner!

      PAGE_SIZE = 10

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

      # POST /api/v1/onboarding/tags
      # body: { accepted: [{ name: "Mercado" }, ...] }
      # Cria as tags (find_or_create_by por name), grava accepted_tag_ids
      # e transiciona pra "categorizing".
      def accept_tags
        ws = current_workspace
        accepted = Array(params[:accepted])
        tag_ids = []

        ActiveRecord::Base.transaction do
          accepted.each do |entry|
            name = entry[:name].to_s.strip.truncate(50)
            next if name.blank?
            tag = ws.tags.find_or_create_by!(name: name)
            tag_ids << tag.id
          end

          state = ws.onboarding_state || {}
          ws.update!(onboarding_state: state.merge(
            "status"           => "categorizing",
            "accepted_tag_ids" => tag_ids
          ))
        end

        render json: serialize(ws)
      end

      # POST /api/v1/onboarding/categories
      # body: { accepted: [{ name: "Alimentação", tag_ids: [uuid,...] }, ...] }
      # Cria categorias, associa às tags informadas (escopadas pro workspace),
      # transiciona pra "completed" e enfileira ReanalyzeJob.
      def accept_categories
        ws = current_workspace
        accepted = Array(params[:accepted])
        category_ids = []

        ActiveRecord::Base.transaction do
          accepted.each do |entry|
            name = entry[:name].to_s.strip.truncate(50)
            next if name.blank?

            category = ws.categories.find_or_create_by!(name: name)
            requested_ids = Array(entry[:tag_ids]).map(&:to_s)
            owned_tags = ws.tags.where(id: requested_ids)
            category.tags = owned_tags if owned_tags.any?
            category_ids << category.id
          end

          Onboarding::Service.advance(ws, to: "completed")
          state = ws.reload.onboarding_state
          ws.update!(onboarding_state: state.merge("accepted_category_ids" => category_ids))
        end

        AiSuggestion::ReanalyzeJob.perform_later(ws.id)
        render json: serialize(ws)
      end

      # GET /api/v1/onboarding/suggestions/tags?offset=N
      def suggestions_tags
        state = current_workspace.onboarding_state || {}
        render json: paginate(state["suggested_tags"] || [], key: :tags)
      end

      # GET /api/v1/onboarding/suggestions/categories?offset=N
      def suggestions_categories
        state = current_workspace.onboarding_state || {}
        render json: paginate(state["suggested_categories"] || [], key: :categories)
      end

      private

      def paginate(items, key:)
        offset = params[:offset].to_i.clamp(0, items.size)
        page = items[offset, PAGE_SIZE] || []
        { key => page, has_more: offset + page.size < items.size }
      end

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
        when "not_started", nil then 0
        when "connecting"       then 1
        when "analyzing"        then 2
        when "tagging"          then 3
        when "categorizing"     then 4
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
