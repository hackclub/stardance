class Post::DevlogPolicy < ApplicationPolicy
    def show?
        true
    end

    def new?
        create?
    end

    def create?
        logged_in? && project_member?
    end

    def edit?
        owns?
    end

    def update?
        owns?
    end

    def destroy?
        owns? || user&.admin? || user&.has_role?(:fraud_dept)
    end

    def force_destroy?
        user&.admin? || user&.has_role?(:fraud_dept)
    end

    def versions?
        owns?
    end

    def hackatime_breakdown?
        user&.admin?
    end

    private

    def owns?
        return false unless user && record

        post = record.post
        return false unless post

        # Compare by foreign key rather than loading the association: in feed
        # rendering this runs once per card, and `post.user` would issue a
        # SELECT per post even though the post is already loaded.
        post.user_id == user.id
    end

    def project_member?
        return false unless user && record&.post&.project
        record.post.project.users.exists?(user.id)
    end
end
