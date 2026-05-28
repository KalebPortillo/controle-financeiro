class BankConnection < ApplicationRecord
  PROVIDERS = %w[pluggy manual].freeze
  STATUSES  = %w[connected syncing expired error disconnected].freeze

  belongs_to :workspace
  belongs_to :owner_membership, class_name: "WorkspaceMembership"

  has_many :accounts, dependent: :nullify
  has_many :syncs, class_name: "BankConnectionSync", dependent: :delete_all

  validates :provider,               presence: true, inclusion: { in: PROVIDERS }
  validates :status,                 presence: true, inclusion: { in: STATUSES }
  validates :external_connection_id, presence: true, uniqueness: { scope: :provider }
  validates :sync_history_since,     presence: true

  attribute :provider, default: "pluggy"
  attribute :status,   default: "connected"

  # Empurra o estado novo pro painel de sync (RF21) sempre que o que a UI
  # mostra (status / horário da última sync) muda.
  after_update_commit :broadcast_update,
                      if: -> { saved_change_to_status? || saved_change_to_last_sync_at? }

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  private

  def broadcast_update
    BankConnectionsChannel.broadcast_to(
      workspace,
      event:           "connection_updated",
      bank_connection: BankConnections::Serializer.call(self)
    )
  end
end
