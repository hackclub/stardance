class ShopSuggestionVotePolicy < ApplicationPolicy
  def create?
    signed_in_any?
  end
end
