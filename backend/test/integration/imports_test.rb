require "test_helper"

# RF20 — endpoints de importação: upload (202 + enfileira ProcessJob), limites,
# listagem e segurança. O processamento em si é coberto em
# test/services/imports/process_test.rb (evita o cleanup do AS de testes).
class ImportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user      = create(:user)
    sign_in_as(@user)
    @workspace = @user.workspace_memberships.first.workspace
  end

  def csv_upload(content)
    file = Tempfile.new([ "extrato", ".csv" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "extrato.csv")
  end

  VALID_CSV = "data,descricao,valor\n01/01/2026,MERCADO,-50.00\n".freeze

  test "POST creates the import (202), attaches the file and enqueues processing" do
    assert_enqueued_with(job: Imports::ProcessJob) do
      post "/api/v1/imports", params: { file: csv_upload(VALID_CSV), format: "csv" }
    end
    assert_response :accepted
    import = @workspace.imports.last
    assert_equal "pending", import.status
    assert_equal "extrato.csv", import.filename
    assert_equal "csv", import.format
  end

  test "file over 10 MB returns 413" do
    big = "data,descricao,valor\n" + ("01/01/2026,X,-1.00\n" * 600_000)
    assert_operator big.bytesize, :>, Import::MAX_BYTES
    post "/api/v1/imports", params: { file: csv_upload(big), format: "csv" }
    assert_response :payload_too_large
  end

  test "POST without a file → 422" do
    post "/api/v1/imports", params: { format: "csv" }
    assert_response :unprocessable_entity
  end

  test "GET index lists the workspace imports with counters" do
    create(:import, workspace: @workspace, uploaded_by_membership: @user.workspace_memberships.first,
           status: "completed", created_count: 3, duplicate_count: 1)
    get "/api/v1/imports"
    assert_response :ok
    body = JSON.parse(response.body)["imports"]
    assert_equal 1, body.size
    assert_equal 3, body.first["created_count"]
  end

  test "GET show 404 cross-workspace" do
    foreign = create(:import, workspace: create(:workspace),
                     uploaded_by_membership: create(:workspace_membership))
    get "/api/v1/imports/#{foreign.id}"
    assert_response :not_found
  end

  test "POST requires auth" do
    delete "/api/v1/sessions/current"
    post "/api/v1/imports", params: { file: csv_upload(VALID_CSV), format: "csv" }
    assert_response :unauthorized
  end
end
