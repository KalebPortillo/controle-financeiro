# Notificação in-app (RF17). Criada exclusivamente via Notifications::Create
# (que faz broadcast + fan-out Telegram); `recipient_membership` NULL significa
# broadcast pro workspace inteiro. `read_at` é compartilhado: lida por um
# membro, lida pros dois (decisão do modelo de dados pro caso "casal").
class Notification < ApplicationRecord
  KINDS = %w[inbox_new budget_warning budget_exceeded
             recurrent_missed sync_failed import_completed].freeze

  belongs_to :workspace
  belongs_to :recipient_membership, class_name: "WorkspaceMembership", optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  # Broadcast (recipient NULL) + as dirigidas à membership.
  scope :visible_to, ->(membership) { where(recipient_membership_id: [ nil, membership.id ]) }

  KINDS.each do |k|
    define_method("#{k}?") { kind == k }
  end

  def mark_read!
    return if read_at.present?

    update!(read_at: Time.current)
  end
end
