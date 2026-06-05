class Api::V1::ImportsController < ApplicationController
  before_action :require_authentication!
  before_action :set_import, only: [ :show ]

  # GET /api/v1/imports — histórico de importações do workspace (RF20).
  def index
    imports = current_workspace.imports.recent
    render json: { imports: imports.map { |i| serialize(i) } }
  end

  # GET /api/v1/imports/:id — status + contadores + error_log.
  def show
    render json: { import: serialize(@import) }
  end

  # POST /api/v1/imports — multipart { file, format, account_id? }. Cria o Import,
  # anexa o arquivo e enfileira o processamento (202). 413 se passar de 10 MB.
  def create
    file = params.require(:file)
    return render_too_large if file.size > Import::MAX_BYTES

    import = current_workspace.imports.new(
      uploaded_by_membership: current_membership,
      filename:        file.original_filename,
      format:          params.require(:format),
      file_size_bytes: file.size,
      account:         resolve_account
    )
    import.file.attach(file)
    import.save!
    Imports::ProcessJob.perform_later(import.id)
    render json: { import: serialize(import) }, status: :accepted
  rescue ActionController::ParameterMissing => e
    render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: { code: "validation_failed", message: e.message } }, status: :unprocessable_entity
  end

  private

  def set_import
    @import = current_workspace.imports.find(params[:id])
  end

  # account_id é opcional e buscado escopado (nunca mass-assignment).
  def resolve_account
    return nil if params[:account_id].blank?

    current_workspace.accounts.find(params[:account_id])
  end

  def render_too_large
    render json: {
      error: { code: "payload_too_large", message: "Arquivo acima de 10 MB." }
    }, status: :content_too_large
  end

  def serialize(import)
    {
      id:              import.id,
      filename:        import.filename,
      format:          import.format,
      status:          import.status,
      created_count:   import.created_count,
      duplicate_count: import.duplicate_count,
      error_count:     import.error_count,
      error_log:       import.error_log || [],
      created_at:      import.created_at.iso8601,
      completed_at:    import.completed_at&.iso8601
    }
  end
end
