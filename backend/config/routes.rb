Rails.application.routes.draw do
  # Rails built-in health probe (200 se a app boota sem exceções).
  get "up" => "rails/health#show", as: :rails_health_check

  # Action Cable — painel de sync (RF21) ouve aqui. Autentica via cookie de
  # sessão (ApplicationCable::Connection). Frontend conecta em /cable.
  mount ActionCable.server => "/cable"

  # API namespace v1.
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      # Config pública (runtime) lida pelo frontend no boot — ex.: sandbox do
      # Pluggy ligado fora de produção. Decisão por RAILS_ENV, não por build.
      get "app_config", to: "app_config#show"
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

      # Webhook do Pluggy (máquina→máquina; valida header secreto, sem sessão).
      post "webhooks/pluggy", to: "webhooks#pluggy"

      # Tags (RF5) — etiquetas livres aplicáveis a transações.
      resources :tags, only: [ :index, :create, :update, :destroy ] do
        member { post "merge" }
      end

      # Categorias (RF6) — agregam tags pra relatórios/orçamentos.
      resources :categories, only: [ :index, :create, :update, :destroy ] do
        member { post "merge" }
      end

      # Transactions (RF2 inbox + RF4) — listagem/leitura + workflow da inbox.
      resources :transactions, only: [ :index, :create, :update, :destroy ] do
        member do
          post "consolidate"
          post "reject"
          get  "edits"
        end
        collection do
          post "reanalyze"
        end
      end

      # AI learned rules (RF3.2) — ver e apagar regras aprendidas.
      resources :ai_learned_rules, only: [ :index, :destroy ]

      # Recurrences (RF9) — recorrentes detectadas + cadastradas manualmente.
      resources :recurrences, only: [ :index, :create, :update, :destroy ] do
        collection { get "upcoming" }   # RF9.3 — vencimentos previstos
        member     { get "missed" }     # RF9.6 — não chegou no prazo
      end

      # Onboarding (RF22) — fluxo guiado de primeira vez do dono do workspace.
      resource :onboarding, only: [ :show ], controller: "onboardings" do
        collection do
          post "start"
          post "skip"
          post "advance"
          post "tags",       to: "onboardings#accept_tags"
          post "categories", to: "onboardings#accept_categories"
          get  "suggestions/tags",       to: "onboardings#suggestions_tags"
          get  "suggestions/categories", to: "onboardings#suggestions_categories"
        end
      end

      # Reports (RF13) — analytics / dashboards.
      scope "/reports" do
        get "overview",          to: "reports#overview"
        get "by_tag",            to: "reports#by_tag"
        get "by_category",       to: "reports#by_category"
        get "monthly_evolution", to: "reports#monthly_evolution"
      end

      # Bank connections (RF1 + RF21) — conexão via Pluggy.
      resources :bank_connections, only: [ :index, :show, :create, :destroy ] do
        collection do
          post "connect_token"
          post "sync_all"
        end
        member do
          post "sync"
          post "reconnect"
          get  "sync_history"
        end
      end
    end
  end

  # Catch-all: serve o index.html do frontend para qualquer rota não-API
  # (assets estáticos são servidos antes via public_file_server middleware).
  root to: "static#index"
  get "*path", to: "static#index", constraints: ->(req) { !req.xhr? && req.format.html? }
end
