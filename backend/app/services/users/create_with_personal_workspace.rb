module Users
  # Ponto único onde o login OAuth vira "user pronto pra usar o produto".
  # Idempotente: chamadas subsequentes do mesmo google_uid só atualizam
  # o perfil — não criam workspace nem membership extra.
  #
  # Encapsula tanto o upsert do User a partir do OmniAuth::AuthHash quanto
  # a criação do workspace pessoal. O model `User` fica livre de saber sobre
  # OmniAuth (Camadas no doc técnico: "Models simples + Services orquestram").
  class CreateWithPersonalWorkspace
    def self.call(auth)
      new(auth).call
    end

    def initialize(auth)
      @auth = auth
    end

    def call
      ActiveRecord::Base.transaction do
        user = upsert_user
        ensure_personal_workspace(user)
        user
      end
    end

    private

    def upsert_user
      user = User.find_or_initialize_by(google_uid: @auth.uid)
      user.email      = @auth.info.email
      user.name       = @auth.info.name
      user.avatar_url = @auth.info.image
      user.save!
      user
    end

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
