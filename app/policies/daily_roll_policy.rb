# frozen_string_literal: true

class DailyRollPolicy < ApplicationPolicy
  # Anyone can roll: signed-in rolls save to the account, logged-out rolls go
  # to a cookie (cleared on sign-in so they re-roll fresh).
  def create?
    true
  end

  def leaderboard?
    true
  end

  # Spending the earned reroll requires an account; the controller re-checks
  # the unlock condition (coding time today) server-side.
  def reroll?
    signed_in_any?
  end

  # History is per-account, so it's signed-in only.
  def history?
    signed_in_any?
  end
end
