require "test_helper"

# People who signed up at 13-18 and have since turned 19 keep their account so
# they can ship what they built and spend their stardust. Only time coded after
# their 19th birthday stops counting.
class SessionsControllerAgedOutTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @uid = "ident!#{SecureRandom.hex(4)}"
    @slack_id = "U_#{SecureRandom.hex(4).upcase}"
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:hack_club] = nil
  end

  test "someone who signed up at 18 and is now 19 can still sign in" do
    user = onboarded_user(signed_up: 1.year.ago, age_attestation: "teen_13_18")
    birthday = 19.years.ago.to_date - 1.day

    hca_sign_in(birthday: birthday)

    assert_equal user.id, session[:user_id]
    user.reload
    assert user.age_attestation_teen_13_18?
    assert_equal birthday + 19.years, user.aged_out_on
    assert user.ysws_eligible?, "projects built before turning 19 still count"
    assert_not_equal onboarding_age_gate_path, URI(response.location).path
  end

  test "someone already flipped to ineligible after aging out gets access back" do
    user = onboarded_user(signed_up: 1.year.ago, age_attestation: "ineligible")

    hca_sign_in(birthday: 19.years.ago.to_date - 1.day)

    assert_equal user.id, session[:user_id]
    assert user.reload.age_attestation_teen_13_18?
    assert user.aged_out?
  end

  test "someone who was already 19 at signup is still blocked" do
    user = onboarded_user(signed_up: 1.year.ago, age_attestation: "teen_13_18")

    hca_sign_in(birthday: 20.years.ago.to_date - 1.day)

    assert_nil session[:user_id]
    assert user.reload.age_attestation_ineligible?
    assert_not user.aged_out?
    assert_redirected_to onboarding_age_gate_path
  end

  test "someone who is still a teen isn't marked as aged out" do
    user = onboarded_user(signed_up: 1.year.ago, age_attestation: "teen_13_18")

    hca_sign_in(birthday: 17.years.ago.to_date)

    assert_equal user.id, session[:user_id]
    assert_not user.reload.aged_out?
  end

  test "an admin override skips the time cutoff" do
    user = onboarded_user(signed_up: 1.year.ago, age_attestation: "ineligible")
    user.update!(manual_ysws_override: true)
    birthday = 19.years.ago.to_date - 1.day

    hca_sign_in(birthday: birthday)

    assert_equal user.id, session[:user_id]
    user.reload
    assert_equal birthday + 19.years, user.aged_out_on
    assert_not user.aged_out?
    assert_nil user.time_logging_cutoff
  end

  private

  def onboarded_user(signed_up:, age_attestation:)
    @email = "agedout-#{SecureRandom.hex(4)}@example.com"
    user = User.create!(
      email:            @email,
      slack_id:         @slack_id,
      display_name:     "AgedOut#{SecureRandom.hex(3)}",
      age_attestation:  age_attestation,
      experience_level: "little",
      interests:        %w[web_dev],
      onboarded_at:     signed_up
    )
    user.identities.create!(provider: "hack_club", uid: @uid, access_token: "old-token")
    user.update_columns(created_at: signed_up)
    user
  end

  def hca_sign_in(birthday:)
    payload = {
      "id" => @uid,
      "verification_status" => "verified",
      "ysws_eligible" => false,
      "primary_email" => @email,
      "first_name" => "Test",
      "last_name" => "Teen",
      "slack_id" => @slack_id,
      "birthday" => birthday.iso8601,
      "address" => {}
    }
    original = HCAService.method(:identity)
    HCAService.define_singleton_method(:identity) { |_| payload }
    auth = OmniAuth::AuthHash.new(provider: :hack_club, uid: @uid, credentials: OmniAuth::AuthHash.new(token: "new-token"))
    OmniAuth.config.mock_auth[:hack_club] = auth
    Rails.application.env_config["omniauth.auth"] = auth
    get "/auth/hack_club/callback"
  ensure
    HCAService.define_singleton_method(:identity, original) if original
    Rails.application.env_config.delete("omniauth.auth")
  end
end
