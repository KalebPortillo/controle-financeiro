class AiLearnedRule < ApplicationRecord
  belongs_to :workspace

  validates :descriptor_pattern, presence: true,
            uniqueness: { scope: :workspace_id, case_sensitive: false }
  validates :match_count, numericality: { greater_than: 0 }

  scope :for_workspace, ->(ws_id) { where(workspace_id: ws_id) }
  scope :recent, -> { order(last_seen_at: :desc) }

  def self.lookup(workspace_id:, descriptor:)
    where(workspace_id: workspace_id)
      .find_by(descriptor_pattern: descriptor)
  end
end
