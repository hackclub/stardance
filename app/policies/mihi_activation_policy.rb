class MihiActivationPolicy < ApplicationPolicy
  def create?
    user.present? && !user.banned? && Flipper.enabled?(:mihimode, user)
  end
end
