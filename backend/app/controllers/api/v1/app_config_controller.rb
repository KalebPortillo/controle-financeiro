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
  # Staging usa as MESMAS credenciais Pluggy de produção (secrets-common
  # compartilhado), então também conecta bancos REAIS — só dev/test ficam presos
  # ao conector sandbox.
  REAL_BANK_ENVS = %w[production staging].freeze

  def self.config_for(env)
    real_banks = REAL_BANK_ENVS.include?(env.to_s)
    {
      environment: env.to_s,
      pluggy: {
        include_sandbox: !real_banks,
        connector_ids:   real_banks ? nil : SANDBOX_CONNECTOR_IDS
      }
    }
  end
end
