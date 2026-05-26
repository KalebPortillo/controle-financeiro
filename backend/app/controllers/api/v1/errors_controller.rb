class Api::V1::ErrorsController < ApplicationController
  # GET /api/v1/test_error
  # Disparado para validar integração com Sentry. NÃO usar em produção.
  def trigger
    raise StandardError, "Test error — Sentry integration probe (#{Time.current.iso8601})"
  end
end
