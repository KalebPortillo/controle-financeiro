require "test_helper"

class BankConnectionTest < ActiveSupport::TestCase
  test "factory builds a valid bank_connection" do
    assert build(:bank_connection).valid?
  end

  test "requires workspace, provider, external_connection_id, sync_history_since" do
    conn = BankConnection.new
    assert_not conn.valid?
    assert_includes conn.errors[:workspace],              "must exist"
    assert_includes conn.errors[:external_connection_id], "can't be blank"
    assert_includes conn.errors[:sync_history_since],     "can't be blank"
  end

  test "owner_membership is optional (nullified when member is removed)" do
    conn = build(:bank_connection, owner_membership: nil)
    conn.valid?
    assert_empty conn.errors[:owner_membership]
  end

  test "provider must be pluggy or manual" do
    conn = build(:bank_connection, provider: "bogus")
    assert_not conn.valid?
    assert_includes conn.errors[:provider], "is not included in the list"
  end

  test "status defaults to connected" do
    assert_equal "connected", BankConnection.new.status
  end

  test "status must be in the allowed set" do
    conn = build(:bank_connection, status: "bogus")
    assert_not conn.valid?
    assert_includes conn.errors[:status], "is not included in the list"
  end

  test "(provider, external_connection_id) is unique" do
    create(:bank_connection, provider: "pluggy", external_connection_id: "item-1")
    dup = build(:bank_connection, provider: "pluggy", external_connection_id: "item-1")
    assert_not dup.valid?
    assert_includes dup.errors[:external_connection_id], "has already been taken"
  end

  test "belongs to workspace + owner_membership; has many accounts" do
    conn = create(:bank_connection)
    a = create(:account, bank_connection: conn, workspace: conn.workspace)
    assert_equal conn.workspace, a.workspace
    assert_includes conn.accounts, a
  end

  test "status helpers" do
    assert build(:bank_connection, status: "connected").connected?
    assert build(:bank_connection, status: "error").error?
    assert build(:bank_connection, status: "syncing").syncing?
  end

  test "broadcasta no canal do workspace quando o status muda (RF21.3)" do
    conn = create(:bank_connection, status: "connected")
    stream = BankConnectionsChannel.broadcasting_for(conn.workspace)

    assert_broadcasts(stream, 1) do
      conn.update!(status: "syncing")
    end
  end

  test "broadcasta quando last_sync_at muda" do
    conn = create(:bank_connection)
    stream = BankConnectionsChannel.broadcasting_for(conn.workspace)

    assert_broadcasts(stream, 1) do
      conn.update!(last_sync_at: Time.current)
    end
  end

  test "não broadcasta quando muda um atributo irrelevante" do
    conn = create(:bank_connection)
    stream = BankConnectionsChannel.broadcasting_for(conn.workspace)

    assert_no_broadcasts(stream) do
      conn.update!(credentials_ref: "ref-novo")
    end
  end
end
