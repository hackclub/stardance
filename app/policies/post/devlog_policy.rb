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

    private

    def owns?
        return false unless user && record

        post = record.post
        return false unless post

        post.user == user
    end

    def project_member?
        return false unless user && record&.post&.project
        record.post.project.users.exists?(user.id)
    end
end
