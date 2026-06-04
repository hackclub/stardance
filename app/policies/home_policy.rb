class HomePolicy < ApplicationPolicy
  def index?
    true
  end

  def feed?
    true
  end
end
