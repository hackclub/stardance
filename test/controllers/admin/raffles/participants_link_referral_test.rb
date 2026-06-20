require "test_helper"

class Admin::Raffles::ParticipantsLinkReferralTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:tongyu)
    @referred = users(:referral_referred_one)
    @referrer_participant = raffle_participants(:referrer)
  end

  test "admin can link a user as referred by a participant" do
    sign_in @admin

    assert_difference "Raffle::Referral.count", 1 do
      post link_referral_admin_raffles_participant_path(@referrer_participant),
           params: { user_id: @referred.id }
    end

    assert_redirected_to admin_raffles_participant_path(@referrer_participant)
    referral = Raffle::Referral.find_by(referred_user_id: @referred.id)
    assert referral
    assert_equal @referrer_participant.id, referral.participant_id
  end

  test "non-admin cannot link a referral" do
    sign_in users(:one)

    post link_referral_admin_raffles_participant_path(@referrer_participant),
         params: { user_id: @referred.id }
    assert_response :not_found
  end

  test "rejects self-referral" do
    sign_in @admin

    post link_referral_admin_raffles_participant_path(@referrer_participant),
         params: { user_id: @referrer_participant.user_id }

    assert_redirected_to admin_raffles_participant_path(@referrer_participant)
    assert_match(/themselves/i, flash[:alert])
  end

  test "rejects if referral already exists" do
    sign_in @admin
    Raffle::Referral.create!(
      participant: @referrer_participant,
      referred_user: @referred,
      channel: :web,
      raw_ref: "test",
      status: :pending
    )

    post link_referral_admin_raffles_participant_path(@referrer_participant),
         params: { user_id: @referred.id }

    assert_redirected_to admin_raffles_participant_path(@referrer_participant)
    assert_match(/already has a referral/i, flash[:alert])
  end
end
