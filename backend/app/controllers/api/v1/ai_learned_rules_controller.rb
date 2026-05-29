module Api
  module V1
    class AiLearnedRulesController < ApplicationController
      before_action :require_authentication!

      def index
        rules = current_workspace.ai_learned_rules.recent
        render json: { ai_learned_rules: rules.map { |r| serialize(r) } }
      end

      def destroy
        rule = current_workspace.ai_learned_rules.find(params[:id])
        rule.destroy!
        head :no_content
      end

      private

      def serialize(rule)
        {
          id:                 rule.id,
          descriptor_pattern: rule.descriptor_pattern,
          improved_title:     rule.improved_title,
          tag_ids:            rule.tag_ids,
          match_count:        rule.match_count,
          last_seen_at:       rule.last_seen_at.iso8601
        }
      end
    end
  end
end
