require "test_helper"

# RF20 — registro de cada upload de arquivo (CSV/OFX) p/ importar transações.
class ImportTest < ActiveSupport::TestCase
  setup do
    @workspace  = create(:workspace)
    @membership = create(:workspace_membership, workspace: @workspace)
  end

  test "valid factory" do
    assert build(:import, workspace: @workspace, uploaded_by_membership: @membership).valid?
  end

  test "requires filename and format" do
    imp = build(:import, workspace: @workspace, uploaded_by_membership: @membership, filename: nil, format: nil)
    assert_not imp.valid?
    assert_includes imp.errors[:filename], "can't be blank"
  end

  test "rejects invalid format" do
    assert_not build(:import, workspace: @workspace, uploaded_by_membership: @membership, format: "xls").valid?
  end

  test "rejects invalid status" do
    assert_not build(:import, workspace: @workspace, uploaded_by_membership: @membership, status: "bogus").valid?
  end

  test "status defaults to pending" do
    assert_equal "pending", create(:import, workspace: @workspace, uploaded_by_membership: @membership).status
  end

  test "processing! marks started_at and status" do
    imp = create(:import, workspace: @workspace, uploaded_by_membership: @membership)
    imp.processing!
    assert_equal "processing", imp.status
    assert imp.started_at.present?
  end

  test "complete! records counts and completed_at" do
    imp = create(:import, workspace: @workspace, uploaded_by_membership: @membership)
    imp.complete!(created: 3, duplicate: 2, errors: [ { "row" => 5, "message" => "x" } ])
    assert_equal "completed", imp.status
    assert_equal 3, imp.created_count
    assert_equal 2, imp.duplicate_count
    assert_equal 1, imp.error_count
    assert_equal 5, imp.error_log.first["row"]
    assert imp.completed_at.present?
  end

  test "fail! records the failure" do
    imp = create(:import, workspace: @workspace, uploaded_by_membership: @membership)
    imp.fail!("boom")
    assert_equal "failed", imp.status
    assert_equal [ { "row" => nil, "message" => "boom" } ], imp.error_log
  end

  test "can attach a file" do
    imp = create(:import, workspace: @workspace, uploaded_by_membership: @membership)
    imp.file.attach(io: StringIO.new("data,desc,valor\n"), filename: "x.csv", content_type: "text/csv")
    assert imp.file.attached?
  end
end
