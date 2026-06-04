class VotePolicy < ApplicationPolicy
  def index?
    user_can_vote?
  end

  def new?
    true
  end

  def create?
    user_can_vote?
  end

  private

  def user_can_vote?
    return true if user&.admin?
    raise Pundit::NotAuthorizedError, "You are not authorized to perform this action." unless user&.verification_verified?

    raise Pundit::NotAuthorizedError, "Your voting has been locked temporarily. Please contact @Fraud Squad for more information." if Flipper.enabled?(:voting_locked, user)
    raise Pundit::NotAuthorizedError, "You must have shipped at least one project to vote." unless user.shipped_projects.exists?
    raise Pundit::NotAuthorizedError, "You've used all available votes for now. Ship again to unlock more votes." unless user.vote_balance < 0
    raise Pundit::NotAuthorizedError, "Voting is currently disabled." unless Flipper.enabled?(:voting, user)

    true
  end
end
