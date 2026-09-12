require "test_helper"

class Sessions::HCALoginServiceTest < ActiveSupport::TestCase
  setup do
    @service = Sessions::HCALoginService.new(auth: nil, current_user: nil)
  end

  test "hca_age_attestation returns teen for user who was 18 at signup and is now 19" do
    user = users(:one)
    signup_date = Date.current - 1.year
    birthday = Date.current - 19.years

    user.update_columns(age_attestation: "teen_13_18", created_at: signup_date.to_time)

    result = @service.send(:hca_age_attestation, user, { ysws_eligible: false, birthday: birthday })

    assert_equal :teen, result, "user who was 18 at signup should not be blocked after turning 19"
  end

  test "hca_age_attestation returns ineligible for user who was always over 18 at signup" do
    user = users(:one)
    birthday = Date.current - 26.years

    user.update_columns(age_attestation: "teen_13_18", created_at: Time.current)

    result = @service.send(:hca_age_attestation, user, { ysws_eligible: false, birthday: birthday })

    assert_equal :ineligible, result
  end

  test "hca_age_attestation returns teen when ysws_eligible is true regardless of age" do
    user = users(:one)
    birthday = Date.current - 26.years

    result = @service.send(:hca_age_attestation, user, { ysws_eligible: true, birthday: birthday })

    assert_equal :teen, result
  end

  test "hca_age_attestation returns ineligible for new user with birthday over 18" do
    user = User.new

    birthday = Date.current - 26.years
    result = @service.send(:hca_age_attestation, user, { ysws_eligible: false, birthday: birthday })

    assert_equal :ineligible, result
  end
end
