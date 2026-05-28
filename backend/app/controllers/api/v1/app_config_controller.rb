class Api::V1::AppConfigController < ApplicationController
  # Config pública lida pelo frontend no boot. Decide comportamento por
  # AMBIENTE em runtime (RAILS_ENV), NÃO por build — staging e produção rodam
  # a mesma imagem, diferenciadas só pelo RAILS_ENV do container. Sandbox-vs-real
  # é configuração de ambiente, não código.
  SANDBOX_CONNECTOR_IDS = [ 2 ].freeze # Pluggy Bank (sandbox, user-ok/password-ok)

  # GET /api/v1/app_config
  def show
    render json: self.class.config_for(Rails.env)
  end

  # Lógica pura (env → config), extraída pra ser testável sem stubar Rails.env.
  def self.config_for(env)
    production = env.to_s == "production"
    {
      environment: env.to_s,
      pluggy: {
        include_sandbox: !production,
        connector_ids:   production ? nil : SANDBOX_CONNECTOR_IDS
      }
    }
  end
end
