require "test_helper"

class SessionsControllerGuestUpgradeTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @access_token = "fake-access-token-#{SecureRandom.hex(4)}"
    @uid = "ident!#{SecureRandom.hex(4)}"
    @slack_id = "U_#{SecureRandom.hex(4).upcase}"
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:hack_club] = nil
  end

  test "guest with no HCA identity gets identity attached on first sign-in" do
    guest = User.create!(
      email:            "newteen@example.com",
      display_name:     "WizardName",
      age_attestation:  "teen_13_18",
      experience_level: "little",
      interests:        %w[web_dev],
      onboarded_at:     Time.current
    )

    open_session.tap do |sess|
      sess.send(:process, :get, dev_login_path(guest.id))
    end

    with_stubbed_hca_identity(birthday: "2010-06-15") do
      with_omniauth_mock(@access_token) do
        sign_in_as_guest(guest)
        get "/auth/hack_club/callback"
      end
    end

    guest.reload
    assert_equal 1, guest.identities.where(provider: "hack_club").count
    assert guest.hca_linked?, "expected guest to now be HCA-linked"
    assert_equal "WizardName", guest.display_name, "wizard display_name should be preserved"
  end

  test "direct HCA sign-in links an existing unlinked user with matching email" do
    guest = User.create!(
      email:            "honest@example.com",
      display_name:     "ExistingGuest",
      age_attestation:  "teen_13_18",
      experience_level: "little",
      interests:        %w[web_dev],
      onboarded_at:     Time.current
    )

    with_stubbed_hca_identity(birthday: "2010-06-15", email: "HONEST@example.com") do
      with_omniauth_mock(@access_token) do
        get "/auth/hack_club/callback"
      end
    end

    assert_equal guest.id, session[:user_id]
    assert_equal 1, guest.reload.identities.where(provider: "hack_club", uid: @uid).count
    assert_equal "honest@example.com", guest.email
    assert_equal "ExistingGuest", guest.display_name
  end

  test "direct HCA sign-in updates existing linked user found by matching email" do
    existing = User.create!(
      email:        "honest@example.com",
      display_name: "ExistingLinkedUser",
      slack_id:     "U_OLD_SLACK"
    )
    identity = existing.identities.create!(
      provider:     "hack_club",
      uid:          "old-hca-uid-#{SecureRandom.hex(4)}",
      access_token: "existing-token"
    )

    with_stubbed_hca_identity(birthday: "2010-06-15", email: "HONEST@example.com") do
      with_omniauth_mock(@access_token) do
        get "/auth/hack_club/callback"
      end
    end

    assert_equal existing.id, session[:user_id]
    assert_equal @uid, identity.reload.uid
    assert_equal @slack_id, existing.reload.slack_id
    assert_equal 1, existing.identities.where(provider: "hack_club").count
  end

  test "HCA birthday under 13 flags guest as ineligible and signs out" do
    guest = User.create!(
      email:            "tooyoung@example.com",
      display_name:     "YoungLiar",
      age_attestation:  "teen_13_18",
      experience_level: "none",
      interests:        [],
      onboarded_at:     Time.current
    )

    with_stubbed_hca_identity(birthday: "2018-01-01") do
      with_omniauth_mock(@access_token) do
        sign_in_as_guest(guest)
        get "/auth/hack_club/callback"
      end
    end

    assert_redirected_to onboarding_age_gate_path
    guest.reload
    assert_equal "ineligible", guest.age_attestation
    assert_equal 0, guest.identities.where(provider: "hack_club").count
  end

  test "HCA birthday over 18 also flags as ineligible" do
    guest = User.create!(
      email:            "tooold@example.com",
      display_name:     "OldLiar",
      age_attestation:  "teen_13_18",
      experience_level: "experienced",
      interests:        %w[hardware],
      onboarded_at:     Time.current
    )

    with_stubbed_hca_identity(birthday: "2000-01-01") do
      with_omniauth_mock(@access_token) do
        sign_in_as_guest(guest)
        get "/auth/hack_club/callback"
      end
    end

    assert_redirected_to onboarding_age_gate_path
    assert_equal "ineligible", guest.reload.age_attestation
  end

  test "OAuth resolving to a different existing user resets the guest session and signs in as that user" do
    guest = User.create!(
      email:            "collision-guest@example.com",
      display_name:     "CollisionGuest",
      age_attestation:  "teen_13_18",
      experience_level: "some",
      interests:        [],
      onboarded_at:     Time.current
    )

    # A different HCA-linked user already exists with the slack_id that HCA will return.
    existing = User.create!(
      slack_id:     @slack_id,
      display_name: "ExistingHCAUser",
      email:        "existing-hca@example.com"
    )
    existing.identities.create!(
      provider:     "hack_club",
      uid:          "older-uid-#{SecureRandom.hex(4)}",
      access_token: "existing-token"
    )

    with_stubbed_hca_identity(birthday: "2009-08-20") do
      with_omniauth_mock(@access_token) do
        sign_in_as_guest(guest)
        assert_equal guest.id, session[:user_id], "precondition: signed in as the guest before OAuth"

        get "/auth/hack_club/callback"
      end
    end

    # The signed-in user is the existing account, NOT the guest.
    assert_equal existing.id, session[:user_id]
    refute_equal guest.id, session[:user_id]

    # The guest row is left intact (we don't delete on collision).
    assert User.exists?(guest.id)

    # The guest never gets an HCA identity attached.
    assert_equal 0, guest.reload.identities.where(provider: "hack_club").count
  end

  test "HCA birthday in 13-18 range is accepted" do
    guest = User.create!(
      email:            "honest@example.com",
      display_name:     "HonestTeen",
      age_attestation:  "teen_13_18",
      experience_level: "some",
      interests:        %w[app_dev],
      onboarded_at:     Time.current
    )

    with_stubbed_hca_identity(birthday: "2009-08-20") do
      with_omniauth_mock(@access_token) do
        sign_in_as_guest(guest)
        get "/auth/hack_club/callback"
      end
    end

    assert guest.reload.hca_linked?
    assert_equal "teen_13_18", guest.age_attestation
  end

  private

  def with_stubbed_hca_identity(birthday:, email: "honest@example.com")
    payload = identity_payload(birthday: birthday, email: email)
    original = HCAService.method(:identity)
    HCAService.define_singleton_method(:identity) { |_| payload }
    yield
  ensure
    HCAService.define_singleton_method(:identity, original) if original
  end

  def identity_payload(birthday:, email:)
    {
      "id" => @uid,
      "verification_status" => "verified",
      "ysws_eligible" => true,
      "primary_email" => email,
      "first_name" => "Test",
      "last_name" => "Teen",
      "slack_id" => @slack_id,
      "birthday" => birthday,
      "address" => {}
    }
  end

  def with_omniauth_mock(token)
    auth = OmniAuth::AuthHash.new(
      provider: :hack_club,
      uid: @uid,
      credentials: OmniAuth::AuthHash.new(token: token)
    )
    OmniAuth.config.mock_auth[:hack_club] = auth
    Rails.application.env_config["omniauth.auth"] = auth
    yield
  ensure
    Rails.application.env_config.delete("omniauth.auth")
  end

  def sign_in_as_guest(guest)
    post onboarding_start_path, params: { email: guest.email }
  end
end
