require "test_helper"

class Onboarding::ServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = create(:workspace)
  end

  # ---- start ----------------------------------------------------------------

  test "start moves not_started → connecting and records started_at" do
    Onboarding::Service.start(@workspace)

    state = @workspace.reload.onboarding_state
    assert_equal "connecting", state["status"]
    assert state["started_at"].present?
  end

  test "start is idempotent when already in connecting" do
    Onboarding::Service.start(@workspace)
    original_started = @workspace.reload.onboarding_state["started_at"]

    Onboarding::Service.start(@workspace)
    assert_equal "connecting", @workspace.reload.onboarding_state["status"]
    assert_equal original_started, @workspace.onboarding_state["started_at"]
  end

  test "start raises InvalidTransition when already completed" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    assert_raises(Onboarding::Service::InvalidTransition) do
      Onboarding::Service.start(@workspace)
    end
  end

  test "start raises InvalidTransition when already skipped" do
    @workspace.update!(onboarding_state: { "status" => "skipped" })
    assert_raises(Onboarding::Service::InvalidTransition) do
      Onboarding::Service.start(@workspace)
    end
  end

  # ---- skip -----------------------------------------------------------------

  test "skip moves any pre-terminal state to skipped" do
    %w[not_started connecting analyzing tagging].each do |status|
      ws = create(:workspace, onboarding_state: { "status" => status })
      Onboarding::Service.skip(ws)
      assert_equal "skipped", ws.reload.onboarding_state["status"]
    end
  end

  test "skip is idempotent on skipped" do
    @workspace.update!(onboarding_state: { "status" => "skipped" })
    assert_nothing_raised { Onboarding::Service.skip(@workspace) }
    assert_equal "skipped", @workspace.reload.onboarding_state["status"]
  end

  test "skip raises InvalidTransition on completed" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    assert_raises(Onboarding::Service::InvalidTransition) do
      Onboarding::Service.skip(@workspace)
    end
  end

  # ---- advance --------------------------------------------------------------

  test "advance from connecting goes to analyzing" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    Onboarding::Service.advance(@workspace)
    assert_equal "analyzing", @workspace.reload.onboarding_state["status"]
  end

  test "advance from analyzing goes to tagging" do
    @workspace.update!(onboarding_state: { "status" => "analyzing" })
    Onboarding::Service.advance(@workspace)
    assert_equal "tagging", @workspace.reload.onboarding_state["status"]
  end

  test "advance from tagging goes to completed and records completed_at" do
    @workspace.update!(onboarding_state: { "status" => "tagging" })
    Onboarding::Service.advance(@workspace)
    state = @workspace.reload.onboarding_state
    assert_equal "completed", state["status"]
    assert state["completed_at"].present?
  end

  test "advance with explicit to forces destination" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    Onboarding::Service.advance(@workspace, to: "completed")
    assert_equal "completed", @workspace.reload.onboarding_state["status"]
  end

  test "advance raises when destination is invalid" do
    @workspace.update!(onboarding_state: { "status" => "connecting" })
    assert_raises(Onboarding::Service::InvalidTransition) do
      Onboarding::Service.advance(@workspace, to: "not_started")
    end
  end

  test "advance is no-op when already completed" do
    @workspace.update!(onboarding_state: { "status" => "completed" })
    assert_nothing_raised { Onboarding::Service.advance(@workspace) }
    assert_equal "completed", @workspace.reload.onboarding_state["status"]
  end

  # ---- preserves other keys -------------------------------------------------

  test "transitions preserve previously stored suggestions" do
    @workspace.update!(onboarding_state: {
      "status" => "analyzing",
      "suggested_tags" => [ { "name" => "Mercado" } ]
    })
    Onboarding::Service.advance(@workspace)
    state = @workspace.reload.onboarding_state
    assert_equal "tagging", state["status"]
    assert_equal [ { "name" => "Mercado" } ], state["suggested_tags"]
  end
end
