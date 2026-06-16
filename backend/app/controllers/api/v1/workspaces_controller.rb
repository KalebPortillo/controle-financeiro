class Api::V1::WorkspacesController < ApplicationController
  before_action :require_authentication!
  before_action :set_workspace, only: [ :show, :update ]

  def index
    workspaces = current_user.workspaces.order(:created_at)
    render json: { workspaces: workspaces.map { |w| serialize(w) } }
  end

  def show
    render json: { workspace: serialize(@workspace) }
  end

  def create
    workspace = nil
    ActiveRecord::Base.transaction do
      workspace = Workspace.create!(
        name:            params[:name],
        created_by_user: current_user
      )
      WorkspaceMembership.create!(
        user:      current_user,
        workspace: workspace,
        role:      "editor",
        joined_at: Time.current
      )
    end

    render json: { workspace: serialize(workspace) }, status: :created
  end

  def update
    @workspace.update!(name: params[:name])
    render json: { workspace: serialize(@workspace) }
  end

  private

  # Lookup escopado pela membership do current_user — se o user não é membro,
  # ActiveRecord::RecordNotFound → 404 (default do Rails).
  def set_workspace
    @workspace = current_user.workspaces.find(params[:id])
  end

  def serialize(workspace)
    {
      id:         workspace.id,
      name:       workspace.name,
      created_at: workspace.created_at.iso8601
    }
  end
end
