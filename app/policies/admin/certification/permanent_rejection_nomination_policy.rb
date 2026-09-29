class Admin::Certification::PermanentRejectionNominationPolicy < ApplicationPolicy
  def index? = user&.admin?
  def show? = index?

  def create?
    review = record.reviewable
    return false unless user && record.project&.hardware? && review&.pending?
    return false if record.project.hardware_review_blocked?
    return false unless review.claim_held_by?(user)

    policy = review.is_a?(::Certification::FundingRequest) ?
      Admin::Certification::FundingRequestPolicy : Admin::Certification::ShipPolicy
    policy.new(user, review).update?
  end

  def approve?
    user&.admin? && !record.project.memberships.exists?(user_id: user.id)
  end

  def deny? = approve?
end
