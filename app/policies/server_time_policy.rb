class ServerTimePolicy < ApplicationPolicy
  # Public timestamps only; no account or event participation information.
  def show? = true
end
