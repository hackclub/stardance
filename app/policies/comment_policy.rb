class CommentPolicy < ApplicationPolicy
  def create?
    logged_in? && verified?
  end

  def destroy?
    logged_in? && (record.user == user || user.admin?)
  end
end
