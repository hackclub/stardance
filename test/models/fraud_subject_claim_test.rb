require "test_helper"

# Holding a person for one reviewer, so two of them do not work the same queue.

# == Schema Information
#
# Table name: fraud_subject_claims
#
#  id          :bigint           not null, primary key
#  claimed_at  :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  reviewer_id :bigint           not null
#  subject_id  :bigint           not null
#
# Indexes
#
#  index_fraud_subject_claims_on_reviewer_id  (reviewer_id)
#  index_fraud_subject_claims_on_subject_id   (subject_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (reviewer_id => users.id)
#  fk_rails_...  (subject_id => users.id)
#
class FraudSubjectClaimTest < ActiveSupport::TestCase
  include UserFactory

  setup do
    @subject = create_user(slack_id: "u-claim-subject", display_name: "claimsubject")
    @first = create_user(slack_id: "u-claim-first", display_name: "claimfirst")
    @second = create_user(slack_id: "u-claim-second", display_name: "claimsecond")
  end

  test "the first reviewer through takes the person" do
    claim = FraudSubjectClaim.claim(@subject, @first)

    assert_equal @first.id, claim.reviewer_id
    assert_predicate claim, :active?
  end

  test "a second reviewer is turned away while the claim is live" do
    FraudSubjectClaim.claim(@subject, @first)

    assert_nil FraudSubjectClaim.claim(@subject, @second)
    assert FraudSubjectClaim.held_by_other?(@subject, @second)
    assert_not FraudSubjectClaim.held_by_other?(@subject, @first)
  end

  test "reopening refreshes the holder's own claim rather than blocking them" do
    first = FraudSubjectClaim.claim(@subject, @first)
    first.update!(claimed_at: 50.minutes.ago)

    again = FraudSubjectClaim.claim(@subject, @first)

    assert_equal first.id, again.id
    assert_operator again.claimed_at, :>, 1.minute.ago
    assert_equal 1, FraudSubjectClaim.count
  end

  test "a claim older than an hour lapses and the next reviewer takes it" do
    FraudSubjectClaim.claim(@subject, @first).update!(claimed_at: (FraudSubjectClaim::CLAIM_TTL + 1.minute).ago)

    claim = FraudSubjectClaim.claim(@subject, @second)

    assert_equal @second.id, claim.reviewer_id
    assert_not FraudSubjectClaim.held_by_other?(@subject, @second)
    assert_equal 1, FraudSubjectClaim.count, "the lapsed row is taken over, not duplicated"
  end

  test "releasing hands the person back" do
    FraudSubjectClaim.claim(@subject, @first)
    FraudSubjectClaim.release(@subject, @first)

    assert_equal @second.id, FraudSubjectClaim.claim(@subject, @second).reviewer_id
  end

  test "one person can only ever have one claim row" do
    FraudSubjectClaim.claim(@subject, @first)

    assert_raises ActiveRecord::RecordNotUnique do
      FraudSubjectClaim.create!(subject: @subject, reviewer: @second, claimed_at: Time.current)
    end
  end
end
