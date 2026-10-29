class Finality::RafflePolicy < ApplicationPolicy
  def show?
    Finality.raffle_enabled?
  end
end
