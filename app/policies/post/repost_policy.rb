class Post::RepostPolicy < ApplicationPolicy
  def create?
    logged_in? && record.original_post&.user_id != user.id
  end

  def destroy?
    owns?
  end

  private
    def owns?
      user.present? && record.user == user
    end
end
