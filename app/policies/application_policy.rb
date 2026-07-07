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
