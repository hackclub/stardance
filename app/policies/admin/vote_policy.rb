class Admin::VotePolicy < ApplicationPolicy
  # Deliberately narrower than Admin::UserPolicy#view_votes?: NDA helpers read
  # the ratings a user cast, but throwing one out reverses a vote credit and
  # notifies the voter, so it stays with admins.
  def discard?
    user&.admin?
  end
end
