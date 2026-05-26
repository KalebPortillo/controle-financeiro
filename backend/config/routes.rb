Rails.application.routes.draw do
  # Rails built-in health probe (200 se a app boota sem exceções).
  get "up" => "rails/health#show", as: :rails_health_check

  # API namespace v1.
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"
      get "test_error", to: "errors#trigger"
    end
  end

  # Catch-all: serve o index.html do frontend para qualquer rota não-API
  # (assets estáticos são servidos antes via public_file_server middleware).
  root to: "static#index"
  get "*path", to: "static#index", constraints: ->(req) { !req.xhr? && req.format.html? }
end
