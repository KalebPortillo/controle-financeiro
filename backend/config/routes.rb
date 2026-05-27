Rails.application.routes.draw do
  # Rails built-in health probe (200 se a app boota sem exceções).
  get "up" => "rails/health#show", as: :rails_health_check

  # API namespace v1.
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      # Sentry probe: rota só existe fora de produção para evitar spam de quota.
      get "test_error", to: "errors#trigger" unless Rails.env.production?

      # E2E auth bypass — só em non-production. Permite Playwright pular o
      # handshake Google e logar direto via `Users::CreateWithPersonalWorkspace`
      # (mesmo caminho do callback OAuth real).
      post "auth/test_sign_in", to: "sessions#test_sign_in" unless Rails.env.production?

      # Auth (Google OAuth via OmniAuth). O `auth/:provider` (request-phase)
      # é montado pelo middleware OmniAuth::Builder; aqui declaramos o
      # callback e a rota de failure.
      get "auth/:provider/callback", to: "sessions#create"
      get "auth/failure",            to: "sessions#failure"

      # Sessão "current": user atual + logout + troca de workspace ativo.
      get    "sessions/current",                  to: "sessions#show"
      delete "sessions/current",                  to: "sessions#destroy"
      post   "sessions/current/select_workspace", to: "sessions#select_workspace"

      # Workspaces (RF16.2–RF16.5).
      resources :workspaces, only: [ :index, :show, :create, :update ] do
        resources :memberships, only: [ :index, :create, :destroy ]
      end
    end
  end

  # Catch-all: serve o index.html do frontend para qualquer rota não-API
  # (assets estáticos são servidos antes via public_file_server middleware).
  root to: "static#index"
  get "*path", to: "static#index", constraints: ->(req) { !req.xhr? && req.format.html? }
end
