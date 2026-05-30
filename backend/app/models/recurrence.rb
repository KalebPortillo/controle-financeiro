# Padrão recorrente detectado automaticamente (RF9.1) ou cadastrado manualmente
# (RF9.2). `descriptor_pattern` casa com a descrição das transações; quando uma
# transação esperada não chega no prazo, vira alerta (RF9.6).
class Recurrence < ApplicationRecord
  CADENCES = %w[weekly monthly yearly custom].freeze
  STATUSES = %w[active paused cancelled].freeze
  SOURCES  = %w[detected manual].freeze

  belongs_to :workspace
  belongs_to :account

  validates :descriptor_pattern, presence: true
  validates :cadence, inclusion: { in: CADENCES }
  validates :status,  inclusion: { in: STATUSES }
  validates :source,  inclusion: { in: SOURCES }
  validates :amount_tolerance_pct, presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validates :expected_amount_cents, numericality: { greater_than: 0 }, allow_nil: true
  validate :account_belongs_to_workspace

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  private

  def account_belongs_to_workspace
    return if account.nil? || workspace_id.nil?
    return if account.workspace_id == workspace_id

    errors.add(:account, "deve pertencer ao workspace")
  end
end
