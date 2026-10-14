# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end

  def view_deleted_devlogs?
    user&.admin? || user&.has_role?(:fraud_dept)
  end

  private

  # Hardware reviews (funding requests + ship certs) can be reviewed by the
  # global reviewer team, or by a reviewer of the project's hardware mission
  # (per-mission membership or the global mission_reviewer role).
  def can_review_hardware?
    user&.can_review? || hardware_mission_reviewer?
  end

  def hardware_mission_reviewer?
    return false unless record.respond_to?(:project)
    mission = record.project&.current_mission
    return false unless mission&.hardware?

    user&.mission_reviewer? || mission.memberships.exists?(user_id: user&.id)
  end

  def logged_in?
    user.present? && user.hca_linked?
  end

  def signed_in_any?
    user.present?
  end

  # True once the user has finished IDV. Used on actions that produce content
  # visible to other users — comments, etc. — to make sure unverified users
  # can't interact with the platform until verification is done.
  def verified?
    user.present? && user.identity_verified?
  end
end
