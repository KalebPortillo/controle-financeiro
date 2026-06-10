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
        member do
          post "merge"
          post "suggest_tags" # gera sugestões de tag faltante (IA, on-demand)
          post "tag_suggestions/:tag_id/accept", action: :accept_tag_suggestion
          delete "tag_suggestions/:tag_id",      action: :dismiss_tag_suggestion
        end
      end

      # Transactions (RF2 inbox + RF4) — listagem/leitura + workflow da inbox.
      resources :transactions, only: [ :index, :create, :update, :destroy ] do
        member do
          post "consolidate"
          post "reject"
          get  "edits"
          get  "refund_candidates" # RF10.1
          post "link_refund"       # RF10.2
        end
        collection do
          post "reanalyze"
          get  "analysis_progress" # P4 — progresso real da análise IA
        end
      end

      # Estornos (RF10) — desfazer um vínculo. Criação é via transactions#link_refund.
      resources :transaction_refunds, only: [ :destroy ]

      # Transferências internas (RF11) — lista p/ reconciliação, marcar e desmarcar.
      resources :internal_transfers, only: [ :index, :create, :destroy ]

      # Importação por arquivo (RF20) — upload CSV/OFX → inbox. Processamento assíncrono.
      resources :imports, only: [ :index, :show, :create ]

      # AI learned rules (RF3.2) — ver e apagar regras aprendidas.
      resources :ai_learned_rules, only: [ :index, :destroy ]

      # Notificações in-app (RF17) — broadcast pro workspace + dirigidas.
      resources :notifications, only: [ :index ] do
        member     { post "mark_read" }
        collection { post "mark_all_read" }
      end

      # Tags sugeridas pela IA (RF3/RF22) — catálogo separado das tags reais.
      # accept promove a sugestão a Tag real (e opcionalmente aplica a uma
      # transação); destroy recusa (status dismissed).
      resources :suggested_tags, only: [ :index, :destroy ] do
        member { post "accept" }
      end

      # Categorias sugeridas pela IA (RF22, 2ª análise) — catálogo separado das
      # categorias reais. accept cria a Category e associa as tags; destroy recusa.
      resources :suggested_categories, only: [ :index, :destroy ] do
        member { post "accept" }
        collection { post "generate" } # gera sugestões on-demand via IA
      end

      # Recurrences (RF9) — recorrentes detectadas + cadastradas manualmente.
      resources :recurrences, only: [ :index, :create, :update, :destroy ] do
        collection { get "upcoming" }   # RF9.3 — vencimentos previstos
        member     { get "missed" }     # RF9.6 — não chegou no prazo
      end

      # Faturas do cartão (RF9.5) — derivadas, sem entidade física.
      resources :accounts, only: [] do
        resources :invoices, only: [ :index ]
      end

      # Onboarding (RF22) — fluxo guiado de primeira vez do dono do workspace.
      # As sugestões vêm dos endpoints suggested_tags/suggested_categories; aqui
      # ficam só as transições de fluxo. A IA é disparada nos advances.
      resource :onboarding, only: [ :show ], controller: "onboardings" do
        collection do
          post "start"
          post "skip"
          post "advance"
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
