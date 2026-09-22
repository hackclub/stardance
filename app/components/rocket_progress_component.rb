# frozen_string_literal: true

# Pinned strip at the top of the home feed: how many approved hours the program
# has banked toward repairing Vega's rocket. Same story as the :bukux2 intro
# dialogue, so it hides with that flag and the home page is untouched without
# it.
#
# The figure comes from RocketProgress, which derives it from approved YSWS
# submissions whose ship landed inside the campaign window — nothing here
# writes anything.
class RocketProgressComponent < ViewComponent::Base
  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def render? = Flipper.enabled?(:bukux2, user)

  def progress = @progress ||= RocketProgress.snapshot(user: user)

  def hours = progress.hours
  def goal = progress.goal_hours
  def remaining = progress.remaining_hours
  def complete? = progress.complete?

  def contribution? = progress.user_hours.positive?
  def fill_percent = [ hours / goal.to_f * 100, 100 ].min.round(4)
  def contribution_percent = hours.positive? ? (progress.user_hours.to_f / hours * 100).clamp(0, 100).round(4) : 0
  def display_contribution = helpers.number_with_precision(progress.user_hours, precision: 2, strip_insignificant_zeros: true, delimiter: ",")

  def progress_label
    label = "#{display_hours} of #{display_goal} hours logged toward fixing the rocket"
    contribution? ? "#{label}, including #{display_contribution} hours from you" : label
  end

  # Whole hours read better on a 5000-hour goal; the exact figure still goes to
  # the progress bar's aria-valuenow.
  def display_hours = helpers.number_with_delimiter(hours.round)
  def display_goal = helpers.number_with_delimiter(goal)
  def display_remaining = helpers.number_with_delimiter(remaining.ceil)
end
