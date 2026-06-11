require "test_helper"

class ReferralAchievementsTest < ActiveSupport::TestCase
  setup do
    @tag = SecureRandom.hex(4)
    @referrer = create_user(slack_id: "U_REF_#{@tag}", display_name: "ref#{@tag}")
    @participant = @referrer.raffle_participant || Raffle::Participant.find_or_enroll!(@referrer)
    @week = Raffle::Week.create!(number: 16, status: :active)
    Flipper.enable(:week_2_release)
  end

  # -- helpers --

  def create_verified_referral(n)
    referred = create_user(slack_id: "U_REF_#{n}_#{SecureRandom.hex(4)}", display_name: "referred#{n}_#{SecureRandom.hex(4)}")
    Raffle::Referral.create!(
      participant: @participant,
      referred_user: referred,
      status: :verified,
      credited_week: @week,
      verified_at: Time.current
    )
  end

  def create_pending_referral(n)
    referred = create_user(slack_id: "U_PEND_#{n}_#{SecureRandom.hex(4)}", display_name: "pending#{n}_#{SecureRandom.hex(4)}")
    Raffle::Referral.create!(
      participant: @participant,
      referred_user: referred,
      status: :pending
    )
  end

  # -- verified_referral_count --

  test "verified_referral_count is 0 with no referrals" do
    assert_equal 0, @referrer.verified_referral_count
  end

  test "verified_referral_count only counts verified status" do
    create_verified_referral(1)
    create_pending_referral(2)
    assert_equal 1, @referrer.reload.verified_referral_count
  end

  test "verified_referral_count is 0 when user has no raffle participant" do
    user = create_user(slack_id: "U_NO_PART", display_name: "noparticipant")
    assert_equal 0, user.verified_referral_count
  end

  # -- granting: 0 referrals --

  test "sync with 0 referrals grants nothing" do
    @referrer.sync_referral_achievements!
    assert_not @referrer.earned_achievement?(:referral_2)
    assert_not @referrer.earned_achievement?(:referral_5)
  end

  # -- granting: 1 referral --

  test "sync with 1 referral grants nothing" do
    create_verified_referral(1)
    @referrer.sync_referral_achievements!
    assert_not @referrer.earned_achievement?(:referral_2)
  end

  test "progress shows 1/2 with 1 referral" do
    create_verified_referral(1)
    achievement = Achievement.find(:referral_2)
    progress = achievement.progress_for(@referrer)
    assert_equal({ current: 1, target: 2 }, progress)
  end

  # -- granting: 2 referrals --

  test "sync with 2 referrals grants referral_2 only" do
    2.times { |i| create_verified_referral(i) }
    @referrer.sync_referral_achievements!
    assert @referrer.earned_achievement?(:referral_2)
    assert_not @referrer.earned_achievement?(:referral_5)
  end

  # -- granting: 5 referrals --

  test "sync with 5 referrals grants both achievements" do
    5.times { |i| create_verified_referral(i) }
    @referrer.sync_referral_achievements!
    assert @referrer.earned_achievement?(:referral_2)
    assert @referrer.earned_achievement?(:referral_5)
  end

  # -- revoking: drop below 2 --

  test "rejecting referrals below 2 revokes referral_2" do
    refs = 2.times.map { |i| create_verified_referral(i) }
    @referrer.sync_referral_achievements!
    assert @referrer.earned_achievement?(:referral_2)

    refs.first.update!(status: :rejected, credited_week: nil)
    @referrer.sync_referral_achievements!
    assert_not @referrer.earned_achievement?(:referral_2)
  end

  # -- revoking: drop below 5 but stay above 2 --

  test "dropping to 3 referrals revokes referral_5 but keeps referral_2" do
    refs = 5.times.map { |i| create_verified_referral(i) }
    @referrer.sync_referral_achievements!
    assert @referrer.earned_achievement?(:referral_2)
    assert @referrer.earned_achievement?(:referral_5)

    refs[0].update!(status: :rejected, credited_week: nil)
    refs[1].update!(status: :rejected, credited_week: nil)
    @referrer.sync_referral_achievements!
    assert @referrer.earned_achievement?(:referral_2), "should still have referral_2 with 3 verified"
    assert_not @referrer.earned_achievement?(:referral_5), "should lose referral_5 with only 3 verified"
  end

  # -- revoking: no-op when not earned --

  test "revoking an unearned achievement is a no-op" do
    result = @referrer.revoke_achievement!(:referral_2)
    assert_nil result
  end

  # -- idempotency --

  test "syncing twice does not create duplicate achievements" do
    2.times { |i| create_verified_referral(i) }
    @referrer.sync_referral_achievements!
    @referrer.sync_referral_achievements!
    assert_equal 1, @referrer.achievements.where(achievement_slug: "referral_2").count
  end

  test "revoke then re-earn works cleanly" do
    refs = 2.times.map { |i| create_verified_referral(i) }
    @referrer.sync_referral_achievements!
    assert @referrer.earned_achievement?(:referral_2)

    refs.first.update!(status: :rejected, credited_week: nil)
    @referrer.sync_referral_achievements!
    assert_not @referrer.earned_achievement?(:referral_2)

    refs.first.update!(status: :verified, credited_week: @week, verified_at: Time.current)
    @referrer.sync_referral_achievements!
    assert @referrer.earned_achievement?(:referral_2)
  end

  # -- feature flag --

  test "sync is a no-op when week_2_release flag is disabled" do
    Flipper.disable(:week_2_release)
    2.times { |i| create_verified_referral(i) }
    @referrer.sync_referral_achievements!
    assert_not @referrer.earned_achievement?(:referral_2)
  end

  # -- integration: Credit service triggers sync --

  test "Credit service triggers achievement sync on referrer" do
    create_verified_referral(0)

    referred = create_user(slack_id: "U_CREDIT_TARGET", display_name: "credittarget")
    Raffle::Referral.create!(
      participant: @participant,
      referred_user: referred,
      status: :pending
    )

    Raffle::Referrals::Credit.run_safely(referred)

    @referrer.reload
    assert @referrer.earned_achievement?(:referral_2), "should earn referral_2 after credit brings count to 2"
  end
end
