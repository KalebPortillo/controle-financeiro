class Api::V1::HealthController < ApplicationController
  # GET /api/v1/health
  # Smoke test endpoint — confirms Rails + DB are up.
  def show
    db_ok = ActiveRecord::Base.connection.execute("SELECT 1").any?
    render json: {
      status: db_ok ? "ok" : "degraded",
      version: ENV.fetch("APP_VERSION", "dev"),
      ruby: RUBY_VERSION,
      rails: Rails::VERSION::STRING,
      time: Time.current.iso8601
    }
  end
end
