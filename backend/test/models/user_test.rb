require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "factory builds a valid user" do
    assert build(:user).valid?
  end

  test "requires email, google_uid and name" do
    user = User.new
    assert_not user.valid?
    assert_includes user.errors[:email],      "can't be blank"
    assert_includes user.errors[:google_uid], "can't be blank"
    assert_includes user.errors[:name],       "can't be blank"
  end

  test "email is unique case-insensitively" do
    create(:user, email: "ana@example.com")
    dup = build(:user, email: "ANA@example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "google_uid is unique" do
    create(:user, google_uid: "google-1")
    dup = build(:user, google_uid: "google-1")
    assert_not dup.valid?
    assert_includes dup.errors[:google_uid], "has already been taken"
  end

  test "email format is validated" do
    user = build(:user, email: "not-an-email")
    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  # --- .find_or_create_from_google ---------------------------------------

  def google_auth(overrides = {})
    OmniAuth::AuthHash.new({
      provider: "google_oauth2",
      uid: "google-123",
      info: {
        email: "kaleb@example.com",
        name:  "Kaleb",
        image: "https://lh3.googleusercontent.com/a/abc"
      }
    }.deep_merge(overrides))
  end

  test ".find_or_create_from_google creates a user from a fresh google auth" do
    assert_difference "User.count", 1 do
      user = User.find_or_create_from_google(google_auth)
      assert_equal "google-123",        user.google_uid
      assert_equal "kaleb@example.com", user.email
      assert_equal "Kaleb",             user.name
    end
  end

  test ".find_or_create_from_google finds existing user by google_uid" do
    existing = create(:user, google_uid: "google-123", email: "old@example.com")
    assert_no_difference "User.count" do
      user = User.find_or_create_from_google(google_auth)
      assert_equal existing.id, user.id
    end
  end

  test ".find_or_create_from_google updates name and avatar when google profile changes" do
    create(:user, google_uid: "google-123", name: "Old", avatar_url: nil)
    user = User.find_or_create_from_google(google_auth)
    assert_equal "Kaleb",                                  user.name
    assert_equal "https://lh3.googleusercontent.com/a/abc", user.avatar_url
  end
end
