# frozen_string_literal: true

module DiscoverRail
  # rng: shows the viewer's own roll for today (or the roll button). The full
  # leaderboard lives on /rng. DailyRollsController streams the widget back
  # with context[:just_rolled] so the reveal animation only plays on a fresh roll.
  class DailyRollWidget < BaseWidget
    register_as :daily_roll

    def render?
      user.present? && Flipper.enabled?(:week_2_release, user)
    end

    def roll
      return @roll if defined?(@roll)
      @roll = DailyRoll.for_today(user)
    end

    def rolled?
      roll.present?
    end

    def just_rolled?
      rolled? && context[:just_rolled].present?
    end

    # Rolls are always positive, so the value is shown plainly.
    def formatted_value
      number_with_delimiter(roll.value)
    end
  end
end
