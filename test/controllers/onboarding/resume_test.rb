require "test_helper"

# Behavior for interrupted signup-wizard sessions: resuming a fresh guest,
# restarting a stale one, and expiring a stale guest who lands on /home.
class Onboarding::ResumeTest < ActionDispatch::IntegrationTest
  # A guest part-way through the wizard (no project, onboarded_at nil).
  def in_progress_guest(email: "resume_me@example.com", **attrs)
    User.create!(email: email, display_name: User.placeholder_display_name_from_email(email), **attrs)
  end

  test "placeholder display name is derived from the email plus a number" do
    post onboarding_start_path, params: { email: "ada.lovelace@example.com" }

    user = User.find_by(email: "ada.lovelace@example.com")
    assert_match(/\Aada_lovelace_\d+\z/, user.display_name)
  end

  test "submitting email for a fresh in-progress guest resumes at the next unanswered step" do
    guest = in_progress_guest(age_attestation: "teen_13_18") # answered birthday only

    post onboarding_start_path, params: { email: guest.email }

    assert_redirected_to onboarding_experience_path
    assert_equal guest.id, session[:user_id]
  end

  test "fresh guest with no answers resumes at the birthday step" do
    guest = in_progress_guest

    post onboarding_start_path, params: { email: guest.email }

    assert_redirected_to onboarding_birthday_path
  end

  test "submitting email for a stale in-progress guest restarts the wizard" do
    guest = in_progress_guest(age_attestation: "teen_13_18", experience_level: "some", interests: %w[web_dev])
    guest.update_column(:created_at, 8.days.ago)

    post onboarding_start_path, params: { email: guest.email }

    assert_redirected_to onboarding_welcome_path
    guest.reload
    assert_nil guest.age_attestation
    assert_nil guest.experience_level
    assert_empty guest.interests
    assert_nil guest.onboarded_at
  end

  test "fresh in-progress guest visiting /home is sent back to where they left off" do
    guest = in_progress_guest(age_attestation: "teen_13_18", experience_level: "some")
    sign_in guest

    get home_path

    assert_redirected_to onboarding_interests_path
  end

  test "stale in-progress guest visiting /home is logged out and sent to the landing page" do
    guest = in_progress_guest(age_attestation: "teen_13_18")
    guest.update_column(:created_at, 8.days.ago)
    sign_in guest

    get home_path

    assert_redirected_to root_path
    assert_nil session[:user_id]
  end

  test "a guest who finished the wizard is not pulled back into onboarding from /home" do
    guest = in_progress_guest(age_attestation: "teen_13_18", onboarded_at: Time.current)
    sign_in guest

    get home_path

    assert_response :success
  end
end
