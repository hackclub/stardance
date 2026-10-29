require "test_helper"

class UserAgedOutTest < ActiveSupport::TestCase
  # 17 when they onboarded, 19 by the time these tests run.
  BIRTHDAY = Date.new(2007, 9, 1)

  setup do
    travel_to Time.zone.local(2026, 10, 16)
    @user = create_user(slack_id: "U_AGED", display_name: "aged", verified: true)
    @user.update!(age_attestation: "teen_13_18", onboarded_at: Time.zone.local(2025, 6, 1))
  end

  test "someone who onboarded as a teen and turned 19 gets the day they turned 19" do
    assert_equal Date.new(2026, 9, 1), @user.turned_19_on(BIRTHDAY)
  end

  test "someone who was already an adult when they onboarded didn't age out" do
    assert_nil @user.turned_19_on(Date.new(2000, 1, 1))
  end

  test "teens, missing birthdays and people who never onboarded didn't age out" do
    assert_nil @user.turned_19_on(Date.new(2010, 1, 1))
    assert_nil @user.turned_19_on(nil)
    @user.update!(onboarded_at: nil)
    assert_nil @user.turned_19_on(BIRTHDAY)
  end

  test "aged-out users can still ship and use the shop" do
    @user.update!(aged_out_on: Date.new(2026, 9, 1), ysws_eligible: false)

    assert @user.eligible_for_shop?
    refute @user.should_reject_orders?
    assert_equal Time.zone.local(2026, 9, 1), @user.time_logging_cutoff
  end

  test "a manual override of false still keeps aged-out users out of the shop" do
    @user.update!(aged_out_on: Date.new(2026, 9, 1), ysws_eligible: false, manual_ysws_override: false)

    refute @user.eligible_for_shop?
    assert @user.should_reject_orders?
  end

  test "a manual override of true lets aged-out users keep logging time" do
    @user.update!(aged_out_on: Date.new(2026, 9, 1), ysws_eligible: false, manual_ysws_override: true)

    refute @user.aged_out?
    assert_nil @user.time_logging_cutoff
    assert @user.eligible_for_shop?

    @user.update!(manual_ysws_override: nil)
    assert @user.aged_out?
    assert_equal Time.zone.local(2026, 9, 1), @user.time_logging_cutoff
  end

  test "an HCA refresh after turning 19 marks them aged out instead of rejecting orders" do
    @user.apply_hca_verification_payload!(
      { "verification_status" => "verified", "ysws_eligible" => false, "birthday" => BIRTHDAY.iso8601 }
    )

    assert_equal Date.new(2026, 9, 1), @user.reload.aged_out_on
    refute @user.should_reject_orders?
  end
end
