class Api::V1::MembershipsController < ApplicationController
  before_action :require_authentication!
  before_action :set_workspace
  before_action :set_membership, only: [ :destroy ]

  def index
    memberships = @workspace.memberships.includes(:user).order(:joined_at)
    render json: { memberships: memberships.map { |m| serialize(m) } }
  end

  # RF16.3 — convite por email cadastrado.
  # Se email não existe na base, 404 com code "user_not_found" — não criamos
  # user lazily, o convidado precisa fazer signup primeiro.
  def create
    invitee = User.find_by(email: params[:email])
    return render_user_not_found unless invitee

    existing = @workspace.memberships.find_by(user_id: invitee.id)
    if existing
      render json: { membership: serialize(existing) }, status: :ok
      return
    end

    membership = @workspace.memberships.create!(
      user:      invitee,
      role:      "editor",
      joined_at: Time.current
    )
    render json: { membership: serialize(membership) }, status: :created
  end

  def destroy
    @membership.destroy!
    head :no_content
  end

  private

  # Lookup escopado pela membership do current_user — não-membro nem
  # vê a existência do workspace (404).
  def set_workspace
    @workspace = current_user.workspaces.find(params[:workspace_id])
  end

  def set_membership
    @membership = @workspace.memberships.find(params[:id])
  end

  def serialize(membership)
    {
      id:        membership.id,
      role:      membership.role,
      joined_at: membership.joined_at.iso8601,
      user: {
        id:         membership.user.id,
        email:      membership.user.email,
        name:       membership.user.name,
        avatar_url: membership.user.avatar_url
      }
    }
  end

  def render_user_not_found
    render json: {
      error: { code: "user_not_found", message: "No user is registered with that email." }
    }, status: :not_found
  end
end
