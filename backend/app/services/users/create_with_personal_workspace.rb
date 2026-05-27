module Users
  # Ponto único onde o login OAuth vira "user pronto pra usar o produto".
  # Idempotente: chamadas subsequentes do mesmo google_uid só atualizam
  # o perfil — não criam workspace nem membership extra.
  class CreateWithPersonalWorkspace
    def self.call(auth)
      new(auth).call
    end

    def initialize(auth)
      @auth = auth
    end

    def call
      ActiveRecord::Base.transaction do
        user = User.find_or_create_from_google(@auth)
        ensure_personal_workspace(user)
        user
      end
    end

    private

    def ensure_personal_workspace(user)
      return if user.workspaces.exists?

      workspace = Workspace.create!(
        name:            "#{user.name}'s workspace",
        created_by_user: user
      )
      WorkspaceMembership.create!(
        user:      user,
        workspace: workspace,
        role:      "editor",
        joined_at: Time.current
      )
    end
  end
end
