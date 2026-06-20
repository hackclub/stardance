class ProjectPolicy < ApplicationPolicy
    def show?
        true
    end

    def new?
        logged_in?
    end

    def create?
        logged_in?
    end

    def edit?
        owns? || user&.admin?
    end

    def update?
        owns? || user&.admin?
    end

    def destroy?
        owns? || user&.admin? || user&.has_role?(:fraud_dept)
    end

    def force_destroy?
        user&.admin? || user&.has_role?(:fraud_dept)
    end

    def ship?
        member?
    end

    def submit_ship?
        member? && user&.eligible_for_shop?
    end

    def request_recertification?
        (member? || user&.can_review?) && record.needs_changes?
    end

    def follow?
        signed_in_any? && show?
    end

    def view_deleted_devlogs?
        user&.can_see_deleted_devlogs?
    end

    def see_votes?
        member? || user.admin?
    end

    # well, we shoudn't be doing this. but i think i goofed up a lil and authorize @devlog won't work without passing @project and Post::Devlog does not have @project
    def create_devlog?
        member?
    end

    def add_test_time?
        member?
    end

    private

    def member?
        return false unless user && record
        user.memberships.exists?(project: record)
    end

    def owns?
        return false unless user && record
        user.memberships.exists?(project: record, role: "owner")
    end
end
