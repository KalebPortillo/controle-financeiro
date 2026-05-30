# Padrão recorrente detectado automaticamente (RF9.1) ou cadastrado manualmente
# (RF9.2). `descriptor_pattern` casa com a descrição das transações; quando uma
# transação esperada não chega no prazo, vira alerta (RF9.6).
class Recurrence < ApplicationRecord
  CADENCES = %w[weekly monthly yearly custom].freeze
  STATUSES = %w[active paused cancelled].freeze
  SOURCES  = %w[detected manual].freeze

  # Dias de tolerância antes de considerar uma recorrente "atrasada" (RF9.6) —
  # cobranças raramente caem no dia exato previsto.
  GRACE_DAYS = 3

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

  # Última vez que uma transação consolidada casando o padrão foi vista (RF9.6).
  # Casamento por descritor normalizado — o mesmo critério da detecção (RF9.1).
  def last_seen_at
    matching_transactions.map(&:occurred_at).max
  end

  # True quando ativa, com vencimento previsto já passado (além do grace) e
  # sem transação correspondente desde então — "a recorrente não chegou" (RF9.6).
  def missed?(today: Date.current)
    return false unless active?
    return false if next_expected_at.nil?
    return false if today <= next_expected_at + GRACE_DAYS

    seen = last_seen_at
    seen.nil? || seen < next_expected_at
  end

  def days_overdue(today: Date.current)
    return 0 if next_expected_at.nil? || today <= next_expected_at

    (today - next_expected_at).to_i
  end

  private

  # Débitos consolidados desta conta cujo descritor normalizado bate com o
  # padrão. Filtro em Ruby (volume pessoal) — normalização não é trivial em SQL.
  def matching_transactions
    account.transactions.consolidated.where(direction: "debit").select do |t|
      Recurrences::Descriptor.normalize(t.original_description) == descriptor_pattern
    end
  end

  def account_belongs_to_workspace
    return if account.nil? || workspace_id.nil?
    return if account.workspace_id == workspace_id

    errors.add(:account, "deve pertencer ao workspace")
  end
end
