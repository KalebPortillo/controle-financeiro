class Workspace < ApplicationRecord
  belongs_to :created_by_user, class_name: "User"

  # Ordem importa: dependent: :destroy roda na ordem de declaração. transactions
  # referenciam accounts (FK), então vão ANTES de accounts. bank_connections e
  # accounts referenciam workspace_memberships via owner_membership_id, então vão
  # ANTES das memberships, senão a FK estoura ao apagar o workspace.
  # internal_transfers referencia transactions (FK) → destrói ANTES delas.
  # notifications referenciam memberships via recipient_membership_id → ANTES delas.
  has_many :notifications, dependent: :destroy
  has_many :internal_transfers, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :recurrences, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :suggested_tags, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :suggested_categories, dependent: :destroy
  has_many :bank_connections, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :ai_learned_rules, dependent: :destroy
  has_many :imports, dependent: :destroy
  has_many :memberships, class_name: "WorkspaceMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user

  validates :name, presence: true

  # --- Canal de erro de IA (camada de feedback) ---
  # Guarda o último erro não-recuperável de IA pra UI exibir (card no onboarding,
  # banner na inbox). Sempre via AiProviders::ApiError pra ter reason + mensagem
  # amigável. detail (técnico) só pra diagnóstico; a UI usa reason + message.

  def record_ai_error!(api_error)
    update_column(:ai_last_error, api_error.to_h.merge(at: Time.current.iso8601).stringify_keys)
  end

  def clear_ai_error!
    return if ai_last_error.nil?

    update_column(:ai_last_error, nil)
  end

  # { reason:, message:, at: } com chaves símbolo pra serialização; nil se limpo.
  def ai_error_payload
    return nil if ai_last_error.blank?

    { reason: ai_last_error["reason"], message: ai_last_error["message"], at: ai_last_error["at"] }
  end
end
