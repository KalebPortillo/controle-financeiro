class Api::V1::BankConnectionsController < ApplicationController
  before_action :require_authentication!
  before_action :set_connection, only: [ :show, :sync, :reconnect, :destroy ]

  INSTITUTION_LABELS = {
    "nubank" => "Nubank", "inter" => "Inter", "itau" => "Itaú",
    "santander" => "Santander", "bb" => "Banco do Brasil",
    "sandbox" => "Sandbox", "manual" => "Manual"
  }.freeze

  # GET /api/v1/bank_connections — lista + summary agregado (RF21).
  def index
    connections = current_workspace.bank_connections.includes(:accounts).order(:created_at)
    render json: {
      connections: connections.map { |c| serialize(c) },
      summary:     summary(connections)
    }
  end

  # GET /api/v1/bank_connections/:id
  def show
    render json: { bank_connection: serialize(@connection) }
  end

  # POST /api/v1/bank_connections/:id/sync — força sync agora (RF21.3). 202.
  def sync
    @connection.update!(status: "syncing")
    BankConnections::SyncJob.perform_later(@connection.id)
    render json: { bank_connection: serialize(@connection) }, status: :accepted
  end

  # POST /api/v1/bank_connections/sync_all — RF21.4. 202.
  def sync_all
    connections = current_workspace.bank_connections
    connections.update_all(status: "syncing", updated_at: Time.current)
    connections.pluck(:id).each { |id| BankConnections::SyncJob.perform_later(id) }
    render json: { enqueued: connections.size }, status: :accepted
  end

  # POST /api/v1/bank_connections/:id/reconnect — token de reconexão (RF21.8).
  def reconnect
    token = provider.create_connect_token(itemId: @connection.external_connection_id)
    render json: { connect_token: token }
  end

  # DELETE /api/v1/bank_connections/:id
  def destroy
    @connection.destroy!
    head :no_content
  end

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
    # Sync inicial assíncrono (RF1.4) — puxa as transações pra inbox.
    BankConnections::SyncJob.perform_later(connection.id)
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

  # Escopado por workspace — conexão de outro workspace dá 404 (RecordNotFound).
  def set_connection
    @connection = current_workspace.bank_connections.find(params[:id])
  end

  def summary(connections)
    by_status = connections.group_by(&:status).transform_values(&:size)
    {
      total:     connections.size,
      connected: by_status["connected"].to_i,
      syncing:   by_status["syncing"].to_i,
      error:     by_status["error"].to_i + by_status["expired"].to_i
    }
  end

  def provider
    @provider ||= BankAggregators::Pluggy.new(
      client_id:     ENV.fetch("PLUGGY_CLIENT_ID"),
      client_secret: ENV.fetch("PLUGGY_CLIENT_SECRET")
    )
  end

  def serialize(connection)
    {
      id:                 connection.id,
      provider:           connection.provider,
      status:             connection.status,
      error_message:      connection.error_message,
      sync_history_since: connection.sync_history_since.iso8601,
      last_sync_at:       connection.last_sync_at&.iso8601,
      next_sync_at:       connection.next_sync_at&.iso8601,
      last_sync_created_count:    connection.last_sync_created_count,
      last_sync_duplicate_count:  connection.last_sync_duplicate_count,
      last_sync_error_count:      connection.last_sync_error_count,
      last_sync_duration_seconds: connection.last_sync_duration_seconds,
      accounts: connection.accounts.sort_by(&:created_at).map { |a|
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
