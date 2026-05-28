class Api::V1::BankConnectionsController < ApplicationController
  before_action :require_authentication!

  INSTITUTION_LABELS = {
    "nubank" => "Nubank", "inter" => "Inter", "itau" => "Itaú",
    "santander" => "Santander", "bb" => "Banco do Brasil",
    "sandbox" => "Sandbox", "manual" => "Manual"
  }.freeze

  # POST /api/v1/bank_connections/connect_token
  # Gera o token curto-prazo que o widget Pluggy Connect usa no frontend.
  def connect_token
    token = provider.create_connect_token
    render json: { connect_token: token }
  end

  # POST /api/v1/bank_connections { item_id, history_since }
  # Persiste a conexão criada pelo widget + popula accounts.
  def create
    connection = BankConnections::Create.call(
      workspace:        current_workspace,
      owner_membership: current_membership,
      item_id:          params.require(:item_id),
      history_since:    Date.parse(params.require(:history_since)),
      provider:         provider
    )
    render json: { bank_connection: serialize(connection) }, status: :created
  rescue ActionController::ParameterMissing => e
    render json: { error: { code: "validation_failed", message: e.message } },
           status: :unprocessable_entity
  rescue BankAggregators::Error => e
    render json: { error: { code: "provider_error", message: e.message } },
           status: :bad_gateway
  end

  private

  # Workspace ativo da sessão (ou o primeiro do user). Espelha a lógica do
  # SessionsController#active_workspace_id — quando RF tiver multi-workspace
  # pesado, extrair pra um CurrentWorkspace concern.
  def current_workspace
    selected = session[:active_workspace_id]
    workspaces = current_user.workspaces
    (selected && workspaces.find_by(id: selected)) || workspaces.order(:created_at).first
  end

  def current_membership
    current_user.workspace_memberships.find_by(workspace: current_workspace)
  end

  def provider
    @provider ||= BankAggregators::Pluggy.new(
      client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
      client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
    )
  end

  def serialize(connection)
    {
      id:                connection.id,
      provider:          connection.provider,
      status:            connection.status,
      sync_history_since: connection.sync_history_since.iso8601,
      last_sync_at:      connection.last_sync_at&.iso8601,
      accounts: connection.accounts.order(:created_at).map { |a|
        {
          id:                a.id,
          name:              a.name,
          kind:              a.kind,
          institution:       a.institution,
          institution_label: INSTITUTION_LABELS[a.institution],
          currency:          a.currency
        }
      }
    }
  end
end
