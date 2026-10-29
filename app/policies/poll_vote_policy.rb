class PollVotePolicy < ApplicationPolicy
  def create?
    signed_in_any?
  end
end
