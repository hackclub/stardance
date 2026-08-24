require "test_helper"

class Admin::PayoutReviewPolicyTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "admins can view the index and individual reviews" do
    user = create_role_user("admin", :admin)
    policy = Admin::PayoutReviewPolicy.new(user, :payout_review)

    assert policy.index?
    assert policy.show?
  end

  test "NDA helpers can view individual reviews but not the index" do
    user = create_role_user("nda_helper", :nda_helper)
    policy = Admin::PayoutReviewPolicy.new(user, :payout_review)

    refute policy.index?
    assert policy.show?
  end

  test "other users cannot view payout reviews" do
    user = create_user(slack_id: "U_PAYOUT_POLICY_USER", display_name: "payout_policy_user")
    policy = Admin::PayoutReviewPolicy.new(user, :payout_review)

    refute policy.index?
    refute policy.show?
  end

  private

  def create_role_user(label, role)
    user = create_user(slack_id: "U_PAYOUT_POLICY_#{label.upcase}", display_name: "payout_policy_#{label}")
    user.grant_role!(role)
    user
  end
end
