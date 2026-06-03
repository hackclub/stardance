class SearchPolicy < ApplicationPolicy
  def users?
    signed_in_any?
  end

  def projects?
    signed_in_any?
  end

  def global?
    signed_in_any?
  end
end
