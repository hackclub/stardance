class ProjectMentionPolicy < ApplicationPolicy
  def new?
    logged_in?
  end

  def create?
    logged_in?
  end
end
